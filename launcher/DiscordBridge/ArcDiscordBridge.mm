// Adapted from the owner's ArcStation Discord integration. Uses the same official SDK.
#import "ArcDiscordBridge.h"
#import <TargetConditionals.h>
static BOOL ASParseDiscordID(id value, uint64_t *result) {
    if (![value isKindOfClass:NSString.class]) return NO;
    NSString *text=value;
    if (text.length==0 || text.length>20 || [text characterAtIndex:0]=='0') return NO;
    uint64_t parsed=0;
    for (NSUInteger i=0;i<text.length;i++) {
        unichar c=[text characterAtIndex:i];
        if (c<'0' || c>'9') return NO;
        uint64_t digit=c-'0';
        if (parsed>(UINT64_MAX-digit)/10) return NO;
        parsed=parsed*10+digit;
    }
    *result=parsed; return YES;
}
#if __has_include(<discord_partner_sdk/discordpp.h>)
#define DISCORDPP_IMPLEMENTATION
#include <discord_partner_sdk/discordpp.h>
#include <memory>
#include <optional>
#include <unordered_set>
#include <map>
#include <cmath>
#include <algorithm>
using namespace discordpp;
static NSString *str(std::string const& value) { return [[NSString alloc] initWithBytes:value.data() length:value.size() encoding:NSUTF8StringEncoding] ?: @""; }
static std::string cpp(NSString *value) { return value ? std::string(value.UTF8String) : std::string(); }
static NSString *failure(ClientResult const& result) { return result.Successful() ? nil : str(result.Error()); }
static NSDictionary *messageJSON(MessageHandle const& m) {
    auto author=m.Author();
    return @{@"id": str(std::to_string(m.Id())), @"authorID": str(std::to_string(m.AuthorId())), @"author": author ? str(author->DisplayName()) : @"Discord user", @"text": str(m.Content()), @"channelID": str(std::to_string(m.ChannelId()))};
}
@implementation ASDiscordBridge {
    std::shared_ptr<Client> _client;
    std::optional<Call> _call;
    uint64_t _applicationID;
    uint64_t _lobbyID;
    uint64_t _generation;
    uint64_t _callGeneration;
    uint64_t _authorizationGeneration;
    bool _authorizationExchanging;
    std::unordered_set<uint64_t> _speaking;
    std::map<uint64_t,ActivityInvite> _invitations;
}
+ (BOOL)compiledAvailable { return YES; }
+ (NSNumber *)parseSnowflake:(NSString *)value { uint64_t parsed; return ASParseDiscordID(value,&parsed) ? @(parsed) : nil; }
- (instancetype)initWithApplicationID:(uint64_t)applicationID {
    self=[super init]; if (!self) return nil;
    _applicationID=applicationID; _client=std::make_shared<Client>();
    _client->SetApplicationId(applicationID);
    #if TARGET_OS_IPHONE
    _client->SetEngineManagedAudioSession(true);
    #endif
    __weak ASDiscordBridge *weakSelf=self;
    _client->SetStatusChangedCallback([weakSelf](Client::Status status, Client::Error error, int32_t detail) {
        ASDiscordBridge *strong=weakSelf;
        if(strong.eventHandler) strong.eventHandler(@"status", str(Client::StatusToString(status)));
    });
    _client->SetTokenExpirationCallback([weakSelf]() { ASDiscordBridge *strong=weakSelf; if(strong.eventHandler) strong.eventHandler(@"tokenExpired", @""); });
    auto changed=[weakSelf](uint64_t id) { ASDiscordBridge *strong=weakSelf; if(strong.eventHandler) strong.eventHandler(@"message", str(std::to_string(id))); };
    _client->SetMessageCreatedCallback(changed);
    _client->SetMessageUpdatedCallback(changed);
    _client->SetMessageDeletedCallback([changed](uint64_t message, uint64_t channel) { changed(message); });
    _client->SetActivityJoinCallback([weakSelf](std::string secret) { ASDiscordBridge *strong=weakSelf; if(strong.eventHandler) strong.eventHandler(@"joinRequested", str(secret)); });
    auto inviteChanged=[weakSelf](ActivityInvite invite) {
        ASDiscordBridge *s=weakSelf; if(!s || invite.ApplicationId()!=s->_applicationID || invite.Type()!=ActivityActionTypes::Join) return;
        if(invite.IsValid()) {
            s->_invitations.insert_or_assign(invite.MessageId(),invite);
            while(s->_invitations.size()>32) s->_invitations.erase(s->_invitations.begin());
        } else { s->_invitations.erase(invite.MessageId()); }
        if(s.eventHandler) s.eventHandler(@"invitations",@"");
    };
    _client->SetActivityInviteCreatedCallback(inviteChanged);
    _client->SetActivityInviteUpdatedCallback(inviteChanged);
    _client->SetDeviceChangeCallback([weakSelf](std::vector<AudioDevice>,std::vector<AudioDevice>) {
        ASDiscordBridge *strong=weakSelf;
        if(strong.eventHandler) strong.eventHandler(@"audioDevicesChanged", @"");
    });
    return self;
}
- (void)tick { RunCallbacks(); }
- (BOOL)cancelAuthorization {
    if (_authorizationExchanging) return NO;
    ++_authorizationGeneration; _client->AbortAuthorize(); return YES;
}
- (void)audioDevices:(BOOL)input completion:(ASDiscordCompletion)completion {
    __weak ASDiscordBridge *weakSelf=self;
    auto generation=_generation;
    auto devicesCallback=[weakSelf,generation,input,completion](std::vector<AudioDevice> devices) {
        ASDiscordBridge *strong=weakSelf;
        if(!strong || strong->_generation!=generation) { completion(nil,@"Discord audio request was cancelled."); return; }
        NSMutableArray *rows=[NSMutableArray array];
        std::unordered_set<std::string> seen;
        auto defaultID=Client::GetDefaultAudioDeviceId();
        if(!devices.empty() && !defaultID.empty()) {
            [rows addObject:@{@"id":str(defaultID),@"name":@"System default"}]; seen.insert(defaultID);
        }
        for(auto const& device:devices) if(seen.insert(device.Id()).second)
            [rows addObject:@{@"id":str(device.Id()),@"name":str(device.Name())}];
        auto currentCallback=[weakSelf,generation,input,completion,rows](AudioDevice current) {
            ASDiscordBridge *owner=weakSelf;
            if(!owner || owner->_generation!=generation) { completion(nil,@"Discord audio request was cancelled."); return; }
            completion(@{@"devices":rows,@"currentID":current ? str(current.Id()) : @"",
                @"volume":@(input ? owner->_client->GetInputVolume() : owner->_client->GetOutputVolume())},nil);
        };
        if(input) strong->_client->GetCurrentInputDevice(currentCallback);
        else strong->_client->GetCurrentOutputDevice(currentCallback);
    };
    if(input) _client->GetInputDevices(devicesCallback); else _client->GetOutputDevices(devicesCallback);
}
- (NSDictionary *)snapshot {
    NSMutableArray *friends=[NSMutableArray array];
    if (_client->GetStatus()==Client::Status::Ready) {
        for (auto const& relationship:_client->GetRelationships()) {
            if (relationship.DiscordRelationshipType()!=RelationshipType::Friend && relationship.GameRelationshipType()!=RelationshipType::Friend) continue;
            auto user=relationship.User(); if(!user) continue;
            auto activity=user->GameActivity();
            std::string detail=activity ? activity->Details().value_or("") : "";
            [friends addObject:@{@"id":str(std::to_string(user->Id())), @"name":str(user->DisplayName()), @"activity":detail.empty() ? str(EnumToString(user->Status())) : str(detail), @"status":str(EnumToString(user->Status())), @"avatar":str(user->AvatarUrl(UserHandle::AvatarType::Png,UserHandle::AvatarType::Png))}];
        }
    }
    NSMutableArray *members=[NSMutableArray array];
    auto lobby=_client->GetLobbyHandle(_lobbyID);
    auto participants=_call ? _call->GetParticipants() : std::vector<uint64_t>();
    if (lobby) for (auto const& member:lobby->LobbyMembers()) {
        auto user=member.User(); auto id=member.Id();
        [members addObject:@{@"id":str(std::to_string(id)), @"name":user ? str(user->DisplayName()) : @"Party member",
            @"avatar":user ? str(user->AvatarUrl(UserHandle::AvatarType::Png,UserHandle::AvatarType::Png)) : @"",
            @"speaking":@(_speaking.count(id)>0), @"inVoice":@(std::find(participants.begin(),participants.end(),id)!=participants.end()),
            @"localMute":@(_call && _call->GetLocalMute(id)), @"volume":@(_call ? _call->GetParticipantVolume(id) : 100)}];
    }
    auto me=_client->GetCurrentUserV2();
    NSMutableArray *invites=[NSMutableArray array];
    for(auto const& [id,invite]:_invitations) {
        auto sender=_client->GetUser(invite.SenderId());
        [invites addObject:@{@"id":str(std::to_string(id)),@"name":sender ? str(sender->DisplayName()) : @"A friend"}];
    }
    NSDictionary *account=me ? @{@"id":str(std::to_string(me->Id())), @"name":str(me->DisplayName()), @"avatar":str(me->AvatarUrl(UserHandle::AvatarType::Png,UserHandle::AvatarType::Png))} : @{};
    return @{@"status":str(Client::StatusToString(_client->GetStatus())), @"account":account, @"friends":friends, @"members":members, @"invitations":invites,
        @"lobbyID":str(std::to_string(_lobbyID)), @"voiceStatus":_call ? str(Call::StatusToString(_call->GetStatus())) : @"Disconnected",
        @"hasCall":@(_call.has_value()), @"muted":@(_client->GetSelfMuteAll()), @"deafened":@(_client->GetSelfDeafAll())};
}
- (void)perform:(NSString *)action parameters:(NSDictionary *)p completion:(ASDiscordCompletion)completion {
    if ([action hasPrefix:@"audio"] && _client->GetStatus()!=Client::Status::Ready) {
        completion(nil,@"Connect to Chat before changing party audio."); return;
    }
    uint64_t recipient=0;
    if ([action isEqualToString:@"send"] || [action isEqualToString:@"messages"] || [action isEqualToString:@"block"] || [action isEqualToString:@"invite"] || [action isEqualToString:@"participant"]) {
        if (!ASParseDiscordID(p[@"id"],&recipient)) { completion(nil,@"Discord returned an invalid account identifier."); return; }
        // Participant mute and volume are local call controls, just like self
        // mute. Keep them available while the gateway is reconnecting.
        if (![action isEqualToString:@"participant"] && _client->GetStatus()!=Client::Status::Ready) { completion(nil,@"Connect to Chat before opening a conversation."); return; }
    }
    if ([action isEqualToString:@"send"] || [action isEqualToString:@"partySend"]) {
        NSString *text=p[@"text"];
        if(![text isKindOfClass:NSString.class] || text.length==0 || text.length>2000) { completion(nil,@"Messages must contain 1–2000 characters."); return; }
    }
    __weak ASDiscordBridge *weakSelf=self;
    auto tokenGeneration=_generation;
    auto tokens=[weakSelf,completion,tokenGeneration](ClientResult result,std::string access,std::string refresh,AuthorizationTokenType type,int32_t expires,std::string scopes) {
        if(!result.Successful()) { completion(nil,failure(result)); return; }
        ASDiscordBridge *strong=weakSelf;
        if(!strong || strong->_generation!=tokenGeneration) {
            // Discard this device's late result. Revoking a shared application
            // grant here can unexpectedly disconnect the owner's desktop app.
            completion(nil,@"Discord sign-in was cancelled."); return;
        }
        completion(@{@"accessToken":str(access), @"refreshToken":str(refresh), @"expiresIn":@(expires), @"scopes":str(scopes)},nil);
    };
    auto done=[completion](ClientResult result) { completion(result.Successful() ? @{} : nil,failure(result)); };
    if ([action isEqualToString:@"authorize"]) {
        _authorizationExchanging=false;
        auto authorizationGeneration=++_authorizationGeneration;
        std::string guestToken=[p[@"guestAccessToken"] isKindOfClass:NSString.class] ? cpp(p[@"guestAccessToken"]) : "";
        auto verifier=_client->CreateAuthorizationCodeVerifier();
        AuthorizationArgs args; args.SetClientId(_applicationID); args.SetScopes(Client::GetDefaultCommunicationScopes()); args.SetCodeChallenge(verifier.Challenge());
        auto generation=_generation;
        _client->Authorize(args,[weakSelf,verifier,tokens,completion,generation,authorizationGeneration,guestToken](ClientResult result,std::string code,std::string redirect) {
            ASDiscordBridge *strong=weakSelf; if(!strong) { completion(nil,@"Discord closed."); return; }
            if(!result.Successful()) { completion(nil,failure(result)); return; }
            if(strong->_generation!=generation || strong->_authorizationGeneration!=authorizationGeneration) { completion(nil,@"Discord sign-in was cancelled."); return; }
            strong->_authorizationExchanging=true;
            auto exchanged=[weakSelf,tokens,authorizationGeneration](ClientResult result,std::string access,std::string refresh,AuthorizationTokenType type,int32_t expires,std::string scopes) {
                ASDiscordBridge *owner=weakSelf;
                // A successful result is delivered to Swift asynchronously.
                // Keep cancellation blocked until the service saves it and
                // leaves its linking state; the next authorization resets this.
                if(owner && owner->_authorizationGeneration==authorizationGeneration && !result.Successful()) owner->_authorizationExchanging=false;
                tokens(result,access,refresh,type,expires,scopes);
            };
            if(guestToken.empty()) strong->_client->GetToken(strong->_applicationID,code,verifier.Verifier(),redirect,exchanged);
            else strong->_client->GetTokenFromProvisionalMerge(strong->_applicationID,code,verifier.Verifier(),redirect,AuthenticationExternalAuthType::DiscordBotIssuedAccessToken,guestToken,exchanged);
        });
    } else if ([action isEqualToString:@"refresh"]) {
        _client->RefreshToken(_applicationID,cpp(p[@"refreshToken"]),tokens);
    } else if ([action isEqualToString:@"connect"] || [action isEqualToString:@"updateToken"]) {
        bool connect=[action isEqualToString:@"connect"];
        auto generation=_generation;
        _client->UpdateToken(AuthorizationTokenType::Bearer,cpp(p[@"accessToken"]),[weakSelf,completion,generation,connect](ClientResult result) {
            ASDiscordBridge *strong=weakSelf;
            if(!result.Successful() || !strong) { completion(nil,failure(result) ?: @"Discord closed."); return; }
            if(strong->_generation!=generation) { completion(nil,@"Discord connection was cancelled."); return; }
            if(connect) strong->_client->Connect(); completion(@{},nil);
        });
    } else if ([action isEqualToString:@"disconnect"]) {
        ++_generation;
        ++_callGeneration;
        ++_authorizationGeneration; _authorizationExchanging=false;
        _client->AbortAuthorize();
        _client->EndCalls([]() {});
        if(_lobbyID && _client->GetStatus()==Client::Status::Ready) _client->LeaveLobby(_lobbyID,[](ClientResult) {});
        _client->Disconnect(); _call.reset(); _lobbyID=0; _speaking.clear(); _invitations.clear(); completion(@{},nil);
    } else if ([action isEqualToString:@"revoke"]) {
        _client->RevokeToken(_applicationID,cpp(p[@"token"]),done);
    } else if ([action isEqualToString:@"join"]) {
        if(_lobbyID) { completion(nil,@"Leave the current party before joining another."); return; }
        auto generation=_generation;
        _client->CreateOrJoinLobby(cpp(p[@"secret"]),[weakSelf,completion,generation](ClientResult result,uint64_t lobby) {
            ASDiscordBridge *strong=weakSelf;
            if(!result.Successful() || !strong) { completion(nil,failure(result) ?: @"Discord closed."); return; }
            if(strong->_generation!=generation) {
                if(strong->_lobbyID!=lobby) strong->_client->LeaveLobby(lobby,[](ClientResult) {});
                completion(nil,@"Party join was cancelled."); return;
            }
            strong->_lobbyID=lobby;
            completion(@{@"lobbyID":str(std::to_string(lobby))},nil);
        });
    } else if ([action isEqualToString:@"voiceStart"]) {
        if (!_lobbyID || _client->GetStatus()!=Client::Status::Ready) { completion(nil,@"Join a chat before enabling voice."); return; }
        if (_call) { completion(@{},nil); return; }
        auto callGeneration=++_callGeneration;
        _call=_client->StartCall(_lobbyID);
        if(!*_call) { _call.reset(); completion(nil,@"Voice chat could not start. Please try again."); return; }
        _call->SetSpeakingStatusChangedCallback([weakSelf,callGeneration](uint64_t id,bool speaking) { ASDiscordBridge *s=weakSelf; if(s && s->_callGeneration==callGeneration) { if(speaking) s->_speaking.insert(id); else s->_speaking.erase(id); } });
        _call->SetStatusChangedCallback([weakSelf,callGeneration](Call::Status status,Call::Error error,int32_t detail) {
            ASDiscordBridge *s=weakSelf; if(!s || s->_callGeneration!=callGeneration) return;
            if(status==Call::Status::Disconnected) { s->_call.reset(); s->_speaking.clear(); }
            if(error!=Call::Error::None && s.eventHandler) s.eventHandler(@"error",@"Voice chat could not stay connected. Check your connection and try Join Voice again.");
            if(s.eventHandler) s.eventHandler(@"voice",str(Call::StatusToString(status)));
        });
        completion(@{},nil);
    } else if ([action isEqualToString:@"voiceStop"]) {
        auto callGeneration=++_callGeneration;
        auto generation=_generation;
        _client->EndCalls([weakSelf,completion,generation,callGeneration]() { ASDiscordBridge *s=weakSelf; if(s && s->_generation==generation && s->_callGeneration==callGeneration) { s->_call.reset(); s->_speaking.clear(); } completion(@{},nil); });
    } else if ([action isEqualToString:@"participant"]) {
        if(!_call) { completion(nil,@"Join voice chat first."); return; }
        if(p[@"mute"]) _call->SetLocalMute(recipient,[p[@"mute"] boolValue]);
        if(p[@"volume"]) { double value=[p[@"volume"] doubleValue]; if(!std::isfinite(value)||value<0||value>200) { completion(nil,@"Invalid volume."); return; } _call->SetParticipantVolume(recipient,value); }
        completion(@{},nil);
    } else if ([action isEqualToString:@"chatVisible"]) { _client->SetShowingChat([p[@"value"] boolValue]); completion(@{},nil);
    } else if ([action isEqualToString:@"invite"]) { _client->SendActivityInvite(recipient,"Join my reSwitch chat",done);
    } else if ([action isEqualToString:@"acceptInvite"] || [action isEqualToString:@"dismissInvite"]) {
        uint64_t id=0;
        if(!ASParseDiscordID(p[@"id"],&id) || !_invitations.count(id)) { completion(nil,@"This invitation has expired."); return; }
        if([action isEqualToString:@"dismissInvite"]) { _invitations.erase(id); completion(@{},nil); return; }
        if(_client->GetStatus()!=Client::Status::Ready || _lobbyID) { completion(nil,@"Connect Discord and leave your current chat before accepting an invitation."); return; }
        auto generation=_generation;
        _client->AcceptActivityInvite(_invitations.at(id),[weakSelf,generation,id,completion](ClientResult result,std::string secret) {
            ASDiscordBridge *s=weakSelf;
            if(!s || s->_generation!=generation) { completion(nil,@"Invitation was cancelled."); return; }
            if(result.Successful()) s->_invitations.erase(id);
            completion(result.Successful() ? @{@"secret":str(secret)} : nil,failure(result));
        });
    } else if ([action isEqualToString:@"partyMessages"]) {
        if(!_lobbyID) { completion(nil,@"Join a chat first."); return; }
        _client->GetLobbyMessagesWithLimit(_lobbyID,100,[completion](ClientResult result,std::vector<MessageHandle> messages) {
            if(!result.Successful()) { completion(nil,failure(result)); return; }
            NSMutableArray *rows=[NSMutableArray array]; for(auto const& m:messages) [rows addObject:messageJSON(m)]; completion(@{@"messages":rows},nil);
        });
    } else if ([action isEqualToString:@"partySend"]) {
        if(!_lobbyID) { completion(nil,@"Join a chat first."); return; }
        _client->SendLobbyMessage(_lobbyID,cpp(p[@"text"]),[completion](ClientResult result,uint64_t id) { completion(result.Successful() ? @{@"id":str(std::to_string(id))} : nil,failure(result)); });
    } else if ([action isEqualToString:@"leave"]) {
        if(!_lobbyID) { completion(@{},nil); return; }
        auto lobby=_lobbyID;
        ++_callGeneration;
        auto generation=_generation;
        _client->EndCalls([weakSelf,lobby,completion,generation]() {
            ASDiscordBridge *strong=weakSelf; if(!strong) { completion(nil,@"Discord closed."); return; }
            if(strong->_generation!=generation) { completion(nil,@"Party operation was cancelled."); return; }
            strong->_call.reset(); strong->_speaking.clear();
            strong->_client->LeaveLobby(lobby,[weakSelf,completion,generation](ClientResult result) { ASDiscordBridge *s=weakSelf; if(result.Successful() && s && s->_generation==generation) s->_lobbyID=0; completion(result.Successful() ? @{} : nil,failure(result)); });
        });
    } else if ([action isEqualToString:@"audioInputs"] || [action isEqualToString:@"audioOutputs"]) {
        [self audioDevices:[action isEqualToString:@"audioInputs"] completion:completion];
    } else if ([action isEqualToString:@"audioInputDevice"] || [action isEqualToString:@"audioOutputDevice"]) {
        NSString *device=p[@"id"];
        if(![device isKindOfClass:NSString.class] || device.length==0 || device.length>4096) { completion(nil,@"Choose an available Discord audio device."); return; }
        if([action isEqualToString:@"audioInputDevice"]) _client->SetInputDevice(cpp(device),done);
        else _client->SetOutputDevice(cpp(device),done);
    } else if ([action isEqualToString:@"audioInputVolume"] || [action isEqualToString:@"audioOutputVolume"]) {
        BOOL input=[action isEqualToString:@"audioInputVolume"];
        NSNumber *volume=p[@"value"];
        if(![volume isKindOfClass:NSNumber.class] || !std::isfinite(volume.doubleValue) || volume.doubleValue<0 || volume.doubleValue>(input ? 100 : 200)) {
            completion(nil,@"Choose a valid Discord audio volume."); return;
        }
        if(input) _client->SetInputVolume(volume.floatValue); else _client->SetOutputVolume(volume.floatValue);
        completion(@{},nil);
    } else if ([action isEqualToString:@"mute"]) { _client->SetSelfMuteAll([p[@"value"] boolValue]); completion(@{},nil);
    } else if ([action isEqualToString:@"deafen"]) { _client->SetSelfDeafAll([p[@"value"] boolValue]); completion(@{},nil);
    } else if ([action isEqualToString:@"send"]) {
        _client->SendUserMessage(recipient,cpp(p[@"text"]),[completion](ClientResult result,uint64_t id) { completion(result.Successful() ? @{@"id":str(std::to_string(id))} : nil,failure(result)); });
    } else if ([action isEqualToString:@"messages"]) {
        _client->GetUserMessagesWithLimit(recipient,50,[completion](ClientResult result,std::vector<MessageHandle> messages) {
            if(!result.Successful()) { completion(nil,failure(result)); return; }
            NSMutableArray *array=[NSMutableArray array]; for(auto const& message:messages) [array addObject:messageJSON(message)];
            completion(@{@"messages":array},nil);
        });
    } else if ([action isEqualToString:@"block"]) { _client->BlockUser(recipient,done);
    } else if ([action isEqualToString:@"presence"]) {
        Activity activity; activity.SetType(ActivityTypes::Playing);
        activity.SetSupportedPlatforms(static_cast<ActivityGamePlatforms>(static_cast<uint32_t>(ActivityGamePlatforms::Desktop) | static_cast<uint32_t>(ActivityGamePlatforms::IOS)));
        activity.SetDetails(cpp(p[@"title"]));
        NSString *secret=p[@"secret"];
        if(secret.length>0 && _lobbyID) { ActivitySecrets secrets; secrets.SetJoin(cpp(secret)); activity.SetSecrets(secrets); ActivityParty party; party.SetId(std::to_string(_lobbyID)); party.SetCurrentSize((int32_t)(_call ? _call->GetParticipants().size() : 1)); party.SetMaxSize(8); activity.SetParty(party); }
        _client->UpdateRichPresence(activity,done);
    } else { completion(nil,@"Unsupported Discord operation."); }
}
@end
#else
@implementation ASDiscordBridge
+ (BOOL)compiledAvailable { return NO; }
+ (NSNumber *)parseSnowflake:(NSString *)value { uint64_t parsed; return ASParseDiscordID(value,&parsed) ? @(parsed) : nil; }
- (instancetype)initWithApplicationID:(uint64_t)applicationID { return [super init]; }
- (void)tick {}
- (BOOL)cancelAuthorization { return YES; }
- (NSDictionary *)snapshot { return @{@"status":@"Unavailable"}; }
- (void)perform:(NSString *)action parameters:(NSDictionary *)parameters completion:(ASDiscordCompletion)completion { completion(nil,@"Official Discord Social SDK is not installed in this build."); }
@end
#endif
