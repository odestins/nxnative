import SwiftUI
import iSwitchCore

#if os(iOS)
struct PanelDoneToolbar: ToolbarContent {
    @EnvironmentObject private var model: LibraryModel
    var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { model.panel = nil }.tint(.primary).disabled(model.importingSource).accessibilityIdentifier("closePanel")
        }
    }
}

#endif

struct GameChatView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @EnvironmentObject private var chat: GameChatService
    @AppStorage("discordAgeRequirementConfirmed") private var ageConfirmed = false
    @AppStorage("playerName") private var playerName = "Player"
    @State private var showingParty = false
    @State private var joining = false
    @State private var joinCode = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(spacing: 12) {
                    if let account = chat.account { ChatAvatar(person: account, size: 48) }
                    else { Image(systemName: "person.2.wave.2.fill").font(.system(size: 25)).foregroundStyle(Palette.orange).frame(width: 48, height: 48).background(Palette.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14)) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(chat.account?.name ?? "Chat while you play").font(.title3.bold())
                        if chat.account != nil { ChatConnectionBadge() }
                        else { Text("Text and voice, together.").font(.subheadline).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                    if chat.account != nil {
                        NavigationLink { GameChatSettingsView() } label: {
                            Image(systemName: "gearshape").font(.system(size: 20)).foregroundStyle(.primary)
                                .frame(width: 44, height: 44).background(Palette.surface, in: RoundedRectangle(cornerRadius: 13))
                        }.buttonStyle(.plain).accessibilityLabel("Chat settings").accessibilityIdentifier("chatSettings")
                    }
                }
                if chat.linked || chat.account != nil || chat.inParty {
                    if !chat.linked {
                        HStack {
                            Label(chat.reconnecting ? "Reconnecting…" : "You’re offline", systemImage: "wifi.exclamationmark").font(.subheadline)
                            Spacer()
                            if !chat.reconnecting { Button("Reconnect") { Task { await chat.reconnect() } } }
                        }.padding(14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                    }
                    if chat.inParty {
                        Button { showingParty = true } label: {
                            VStack(alignment: .leading, spacing: 16) {
                                HStack { Label("Your Chat", systemImage: "person.2.wave.2.fill").font(.headline); Spacer(); Image(systemName: "arrow.up.right") }
                                HStack(spacing: -8) {
                                    ForEach(Array(chat.members.prefix(5))) { ChatAvatar(person: $0, size: 44) }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("\(chat.members.count) in chat").font(.subheadline.weight(.medium))
                                        Text(chat.hasCall ? chat.voiceStatus : "Text chat · Mic off").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Text("Return to conversation").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.accent)
                            }.padding(18).background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                        }.buttonStyle(.plain).accessibilityIdentifier("createChat")
                    } else {
                        chatActions
                    }
                    if !chat.invitations.isEmpty || chat.pendingInvite != nil { invitations }
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text(chat.isGuest && chat.friends.isEmpty ? "Bring your friends" : "Friends").font(.title3.bold())
                            if !chat.friends.isEmpty { Text("\(chat.friends.filter { $0.status != "Offline" }.count) online").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if !chat.friends.isEmpty { NavigationLink("See all") { FriendsChatView() }.font(.subheadline).tint(.primary).accessibilityIdentifier("gameChatList") }
                        }
                        if chat.friends.isEmpty {
                            ChatSection(title: chat.isGuest ? "Everyone is welcome" : "Your friends will appear here", symbol: "person.2") {
                                Text(chat.isGuest ? "Start a chat and share its invitation code. Your friends can join as guests, too." : "Connect with friends on Discord to see them here.")
                                    .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                                if chat.isGuest { NavigationLink { GameChatSettingsView() } label: { Label("Connect Discord · Optional", systemImage: "arrow.up.right") }.font(.subheadline).tint(.primary) }
                            }
                        }
                        else {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(chat.friends.prefix(8))) { person in
                                    NavigationLink { ChatConversationView(target: .friend(person.id)) } label: {
                                        HStack(spacing: 12) {
                                            ChatAvatar(person: person).overlay(alignment: .bottomTrailing) { Circle().fill(person.status == "Offline" ? Color.gray : Palette.green).frame(width: 12, height: 12).overlay(Circle().stroke(Palette.surface, lineWidth: 2)) }
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(person.name).font(.body.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                                Text(chat.preview(for: person)).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                                            }
                                            Spacer(minLength: 8)
                                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                        }.padding(.vertical, 14).contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityIdentifier("chatFriend-\(person.id)")
                                    if person.id != chat.friends.prefix(8).last?.id { Divider().padding(.leading, 56) }
                                }
                            }.padding(.horizontal, 14).background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
                        }
                    }
                } else {
                    VStack(spacing: 20) {
                        Text("Your next session starts here.").font(.title2.bold()).multilineTextAlignment(.center)
                        Text("Join with an invitation code, or connect Discord to find your friends. Guest text and voice chat need no Discord login.").font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        if chat.pendingInvite != nil { Label("Your invitation is ready", systemImage: "envelope.badge").font(.subheadline) }
                        Toggle("I meet Discord’s minimum age requirement", isOn: $ageConfirmed).font(.subheadline).tint(Palette.green).accessibilityIdentifier("gameChatAge")
                        if chat.linking || chat.reconnecting {
                            ProgressView(chat.linking ? "Waiting for Discord…" : chat.isGuest ? "Connecting to Chat…" : "Reconnecting…")
                            if chat.linking { Button("Cancel sign-in") { chat.cancelLink() }.accessibilityIdentifier("cancelDiscordLink") }
                        } else {
                            Button { Task { await chat.continueAsGuest(name: playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Player" : playerName) } } label: {
                                Label("Continue as Guest", systemImage: "person.crop.circle").frame(maxWidth: .infinity, minHeight: 36)
                            }.buttonStyle(.borderedProminent).disabled(!ageConfirmed || !chat.guestAvailable).accessibilityIdentifier("continueGuest")
                            Button { Task { await chat.link() } } label: { Label("Connect Discord", systemImage: "person.crop.circle.badge.checkmark").frame(maxWidth: .infinity, minHeight: 36) }
                                .buttonStyle(.bordered).tint(.primary).disabled(!ageConfirmed || !chat.available).accessibilityIdentifier("connectDiscord")
                        }
                        Text(chat.guestAvailable ? "Guest chat uses your reSwitch profile name. Your sign-in stays on this \(DevicePresentation.name). Powered by Discord." : "Guest Chat is not enabled in this build yet. Discord sign-in is available.").font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(24).background(Palette.surface, in: RoundedRectangle(cornerRadius: 24))
                }
            }.frame(maxWidth: 760).padding(20).frame(maxWidth: .infinity)
        }.background(Palette.background)
            .navigationDestination(isPresented: $showingParty) { PartyChatView() }
            .alert("Join Chat", isPresented: $joining) {
                TextField("Invitation code", text: $joinCode).chatInvitationInput()
                Button("Cancel", role: .cancel) {}
                Button("Join") { if let code = GameChatRules.invitation(joinCode) { Task { await chat.joinParty(code); showingParty = chat.inParty } } else { chat.notice = "Enter the complete invitation code shared by your friend." } }
            } message: { Text("Paste the invitation shared by your friend.") }
            .onAppear { chat.clearConversation() }
    }
    private var chatActions: some View {
        let layout = textSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Button { Task { await chat.createParty(); showingParty = chat.inParty } } label: {
                Label(chat.busy ? "Starting…" : "Start Chat", systemImage: "person.2.wave.2.fill")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }.buttonStyle(.borderedProminent).disabled(chat.busy || !chat.linked).accessibilityIdentifier("createChat")
            Button { joining = true } label: {
                Text("Join").fontWeight(.semibold)
                    .frame(minWidth: 70, maxWidth: textSize.isAccessibilitySize ? .infinity : nil, minHeight: 36)
            }.buttonStyle(.bordered).tint(.primary).disabled(chat.busy || !chat.linked)
                .accessibilityHint("Enter an invitation code to join a chat").accessibilityIdentifier("joinChat")
        }
    }

    private var invitations: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Invitations").font(.headline)
            ForEach(chat.invitations) { invitation in
                HStack {
                    Label(invitation.name, systemImage: "envelope.badge").lineLimit(1); Spacer()
                    Button { Task { await chat.dismiss(invitation) } } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel("Dismiss invitation from \(invitation.name)")
                    Button("Join") { Task { await chat.accept(invitation); showingParty = chat.inParty } }.buttonStyle(.borderedProminent).disabled(chat.inParty || chat.busy)
                }
            }
            if let invitation = chat.pendingInvite {
                HStack {
                    Text("A friend invited you to Chat").font(.subheadline); Spacer()
                    Button("Dismiss") { chat.pendingInvite = nil }
                    Button("Join") { Task { await chat.joinParty(invitation); showingParty = chat.inParty } }.disabled(chat.inParty || chat.busy)
                }
            }
        }.padding(16).background(Palette.surface, in: RoundedRectangle(cornerRadius: 18))
    }
}

struct ChatAvatar: View {
    let person: ChatPerson
    var size: CGFloat = 44
    var body: some View {
        AsyncImage(url: GameChatRules.avatar(person.avatar)) { image in image.resizable().scaledToFill() } placeholder: {
            Text(String(person.name.prefix(1)).uppercased()).font(.system(size: size * 0.42, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity).background(Palette.accent.opacity(0.16))
        }.frame(width: size, height: size).clipShape(Circle())
            .overlay(Circle().strokeBorder(person.speaking ? Palette.green : .primary.opacity(0.08), lineWidth: person.speaking ? 3 : 1))
            .accessibilityHidden(true)
    }
}

struct FriendsChatView: View {
    @EnvironmentObject private var chat: GameChatService
    @State private var search = ""
    @State private var blocking: ChatPerson?
    var inviting = false
    var filtered: [ChatPerson] { chat.friends.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            if chat.inParty {
                Section { NavigationLink { PartyChatView() } label: { Label("Current Chat", systemImage: "person.2.wave.2.fill") } }
            }
            Section("\(chat.isGuest ? "Chat friends" : "Discord friends") · \(chat.friends.count)") {
                ForEach(filtered) { friend in
                    HStack {
                    NavigationLink { ChatConversationView(target: .friend(friend.id)) } label: {
                        HStack(spacing: 12) {
                            ChatAvatar(person: friend)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(friend.name).font(.headline)
                                Text(chat.preview(for: friend)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Circle().fill(friend.status == "Offline" ? Color.secondary : Palette.green).frame(width: 8, height: 8).accessibilityLabel(friend.status)
                        }.padding(.vertical, 5)
                    }
                    if chat.inParty {
                        Button { Task { await chat.invite(friend) } } label: {
                            if chat.invitingIDs.contains(friend.id) { ProgressView().frame(width: 44, height: 44) }
                            else { Image(systemName: chat.invitedIDs.contains(friend.id) ? "checkmark.circle.fill" : "person.badge.plus").frame(width: 44, height: 44) }
                        }.buttonStyle(.borderless).disabled(!chat.linked || chat.invitedIDs.contains(friend.id) || chat.invitingIDs.contains(friend.id))
                            .accessibilityLabel(chat.invitedIDs.contains(friend.id) ? "Invited \(friend.name)" : "Invite \(friend.name)")
                    }
                    }.contextMenu {
                        if chat.inParty { Button(chat.invitedIDs.contains(friend.id) ? "Invitation sent" : "Invite to chat", systemImage: "person.badge.plus") { Task { await chat.invite(friend) } }.disabled(chat.invitedIDs.contains(friend.id) || chat.invitingIDs.contains(friend.id)) }
                        Button("Block", systemImage: "hand.raised", role: .destructive) { blocking = friend }
                    }.accessibilityIdentifier("chatFriend-\(friend.id)")
                }
            }
        }
        .overlay { if filtered.isEmpty { ContentUnavailableView(search.isEmpty ? "No friends yet" : "No matching friends", systemImage: "person.2", description: Text(search.isEmpty ? (chat.isGuest ? "Share a Chat invitation or join with a friend’s code." : "Your Discord friends will appear here when connected.") : "Try a different name.")) } }
        .searchable(text: $search, prompt: "Find a friend")
        .navigationTitle(inviting ? "Invite friends" : "Friends")
        .toolbar { if !inviting { PanelDoneToolbar() } }

        .onAppear { chat.clearConversation() }
        .confirmationDialog("Block \(blocking?.name ?? "this person") on Discord?", isPresented: Binding(get: { blocking != nil }, set: { if !$0 { blocking = nil } }), titleVisibility: .visible) {
            Button("Block", role: .destructive) { if let person = blocking { Task { await chat.block(person) } }; blocking = nil }
        }
    }
}

struct PartyChatView: View {
    @EnvironmentObject private var chat: GameChatService
    #if os(iOS)
    @Environment(\.verticalSizeClass) private var verticalSize
    private var compactVoiceLayout: Bool { verticalSize == .compact }
    #else
    private var compactVoiceLayout: Bool { true }
    #endif
    @State private var leaving = false
    @State private var people = false
    @State private var audioSettings = false
    private var leavePlacement: ToolbarItemPlacement {
        #if os(macOS)
        .cancellationAction
        #else
        .primaryAction
        #endif
    }
    var body: some View {
        Group {
            if let id = chat.lobbyID {
                VStack(spacing: 0) {
                    if compactVoiceLayout {
                        HStack(spacing: 20) {
                            participants.frame(maxWidth: .infinity)
                            voiceControls.frame(maxWidth: .infinity)
                        }.padding(.horizontal, 16).padding(.vertical, 6)
                    } else {
                        participants.padding(.horizontal, 16).padding(.vertical, 6)
                        voiceControls.padding(.horizontal, 16).padding(.bottom, 10)
                    }
                    Divider()
                    ChatConversationView(target: .party(id), embedded: true)
                }
            } else { ContentUnavailableView("Chat ended", systemImage: "bubble.left", description: Text("Go back to create or join another chat.")) }
        }.navigationTitle("Your chat").chatInlineTitle()
            .toolbar {
                PanelDoneToolbar()
                ToolbarItem(placement: leavePlacement) { Button("Leave Chat", role: .destructive) { leaving = true }.disabled(chat.busy || !chat.inParty) }
            }
            .navigationDestination(isPresented: $audioSettings) { GameChatSettingsView() }
            .sheet(isPresented: $people) {
                NavigationStack {
                    List {
                        Section("In this chat") {
                            ForEach(chat.members) { person in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 12) {
                                        ChatAvatar(person: person)
                                        VStack(alignment: .leading) { Text(person.id == chat.account?.id ? "You" : person.name).font(.headline); Text(person.speaking ? "Speaking" : person.inVoice ? "In voice" : "Text only").font(.caption).foregroundStyle(.secondary) }
                                        Spacer()
                                        if person.id != chat.account?.id && chat.hasCall { Button(person.localMute ? "Unmute" : "Mute") { Task { await chat.adjust(person, muted: !person.localMute) } }.buttonStyle(.bordered).disabled(chat.changingControls) }
                                    }
                                    if person.id != chat.account?.id && chat.hasCall {
                                        HStack { Text("Volume").font(.caption); Spacer(); Button("−") { Task { await chat.adjust(person, volume: person.volume - 20) } }; Text("\(Int(person.volume))%").font(.caption.monospacedDigit()); Button("+") { Task { await chat.adjust(person, volume: person.volume + 20) } } }.buttonStyle(.bordered).disabled(chat.changingControls)
                                    }
                                }.padding(.vertical, 5)
                            }
                        }
                        Section {
                            NavigationLink { FriendsChatView(inviting: true) } label: { Label("Invite friends", systemImage: "person.badge.plus") }
                            if !chat.partyCode.isEmpty { ShareLink(item: chat.partyCode) { Label("Share invitation code", systemImage: "square.and.arrow.up") } }
                        }
                        Section { LabeledContent("Audio output", value: chat.routeName) }
                    }.navigationTitle("People & invites").chatInlineTitle()
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { people = false } } }
                }.chatSheetSizes()
            }
            .confirmationDialog("Leave this chat?", isPresented: $leaving, titleVisibility: .visible) { Button("Leave chat", role: .destructive) { Task { await chat.leaveParty() } } }
    }
    private var participants: some View {
        HStack(spacing: 10) {
                        HStack(spacing: -8) { ForEach(Array(chat.members.prefix(3))) { ChatAvatar(person: $0, size: 32) } }
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(chat.members.count) in chat").font(.subheadline.weight(.semibold))
                            Text(chat.hasCall ? chat.voiceStatus : "Text chat · Mic off").font(.caption).foregroundStyle(chat.hasCall ? Palette.green : .secondary)
                        }
                        Spacer()
                        Button { people = true } label: { Image(systemName: "person.badge.plus").frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel("People and invitations")
                    }
    }
    private var voiceControls: some View {
        HStack(spacing: 8) {
                        if chat.hasCall {
                            control(chat.muted ? "Unmute" : "Mic on", icon: chat.muted ? "mic.slash.fill" : "mic.fill", active: chat.muted) { Task { await chat.toggleMute() } }.accessibilityIdentifier("chatMute")
                            control(chat.deafened ? "Listen" : "Sound on", icon: chat.deafened ? "speaker.slash.fill" : "speaker.wave.2.fill", active: chat.deafened) { Task { await chat.toggleDeafen() } }
                            Menu {
                                #if os(iOS)
                                Button(chat.speaker ? "Use default audio route" : "Use speaker") { chat.toggleSpeaker() }
                                #else
                                Button("Audio devices") { audioSettings = true }
                                #endif
                                Button("Leave voice", role: .destructive) { Task { await chat.stopVoice() } }
                            } label: { Image(systemName: "ellipsis").frame(width: 44, height: 44).background(Palette.surface, in: RoundedRectangle(cornerRadius: 12)) }.chatVoiceMenuStyle().accessibilityLabel("Voice options")
                        } else {
                            Button { Task { await chat.startVoice() } } label: { Label(chat.changingVoice ? "Connecting…" : "Join voice", systemImage: "mic.fill").frame(maxWidth: .infinity, minHeight: 32) }
                                .buttonStyle(.borderedProminent).disabled(chat.changingVoice || !chat.linked).accessibilityIdentifier("joinChatVoice")
                        }
                    }
    }
    private func control(_ title: String, icon: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { Label(title, systemImage: icon).font(.subheadline.weight(.medium)).frame(maxWidth: .infinity, minHeight: 44).background(active ? Palette.accent.opacity(0.15) : Palette.surface, in: RoundedRectangle(cornerRadius: 12)) }
            .buttonStyle(.plain).foregroundStyle(active ? Palette.accent : .primary).disabled(chat.changingControls || chat.changingVoice)
    }
}

struct ChatConversationView: View {
    @EnvironmentObject private var chat: GameChatService
    let target: ChatConversation
    var embedded = false
    @FocusState private var composing: Bool
    @State private var wasAtBottom = true

    var body: some View {
        VStack(spacing: 0) {
            if !chat.linked {
                HStack(spacing: 12) {
                    Label(chat.reconnecting ? "Reconnecting to Chat…" : "You’re offline. Your draft is saved.", systemImage: "wifi.exclamationmark")
                    Spacer(minLength: 0)
                    if !chat.reconnecting {
                        Button("Reconnect") { Task { await chat.reconnect() } }
                            .disabled(chat.linking).accessibilityIdentifier("chatConversationReconnect")
                    }
                }.font(.caption).padding(12)
            }
            if let error = chat.messageError {
                VStack(spacing: 6) { Text(error).font(.caption).foregroundStyle(.secondary); Button("Try again") { Task { await chat.reloadMessages() } } }.padding(12)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if chat.loadingMessages && chat.messages.isEmpty { ProgressView().frame(maxWidth: .infinity).padding() }
                        if !chat.loadingMessages && chat.messages.isEmpty && chat.messageError == nil {
                            Text("Say hello to start the conversation.").font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 30)
                        }
                        ForEach(chat.messages) { message in
                            HStack(alignment: .bottom) {
                                let mine = message.authorID == chat.account?.id
                                if mine { Spacer(minLength: 30) }
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack { Text(mine ? "You" : message.author).fontWeight(.semibold); Spacer(minLength: 8); Text(message.sentAt, style: .time) }.font(.caption2).foregroundStyle(.secondary)
                                    Text(verbatim: message.text).font(.body).textSelection(.enabled)
                                }.padding(12).background(mine ? Palette.accent.opacity(0.13) : Palette.surface, in: RoundedRectangle(cornerRadius: 14))
                                if !mine { Spacer(minLength: 30) }
                            }.id(message.id)
                        }
                        Color.clear.frame(height: 1).id("latestMessage")

                    }.padding(12)
                }.defaultScrollAnchor(.bottom, for: .initialOffset).defaultScrollAnchor(.bottom, for: .sizeChanges).chatKeyboardDismiss()
                .onScrollGeometryChange(for: Bool.self) { $0.contentSize.height - $0.contentOffset.y - $0.containerSize.height < 70 } action: { _, value in wasAtBottom = value }
                .onChange(of: chat.messages.last?.id) { _, _ in if wasAtBottom || chat.messages.last?.authorID == chat.account?.id { proxy.scrollTo("latestMessage", anchor: .bottom) } }
            }
        }.safeAreaInset(edge: .bottom, spacing: 0) { composer }
        .navigationTitle(embedded ? "Your chat" : chat.conversationTitle)
        .chatInlineTitle()
        .toolbar { if !embedded { PanelDoneToolbar() } }

        .task(id: target) { await chat.select(target) }
        .onDisappear { composing = false }
    }
    private var composer: some View {
            VStack(alignment: .leading, spacing: 8) {
                if let error = chat.sendError { Label(error, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Palette.coral).accessibilityIdentifier("chatSendError") }
                HStack(alignment: .bottom, spacing: 10) {
                    TextField("Message", text: Binding(get: { chat.draft }, set: { chat.draft = $0 }), axis: .vertical)
                        .textFieldStyle(.plain)
                        .lineLimit(1...4).padding(12).background(Palette.surface, in: RoundedRectangle(cornerRadius: 14)).focused($composing).accessibilityIdentifier("chatMessageDraft")
                    Button { Task { await chat.send() } } label: {
                        if chat.isSending { ProgressView().frame(width: 44, height: 44) }
                        else { Image(systemName: "arrow.up.circle.fill").font(.system(size: 36)).frame(width: 44, height: 44) }
                    }.buttonStyle(.plain).disabled(!chat.linked || chat.isSending || GameChatRules.message(chat.draft) == nil).accessibilityLabel("Send message").accessibilityIdentifier("sendChatMessage")
                }
                if chat.draft.utf16.count > 1800 { Text("\(chat.draft.utf16.count)/2000").font(.caption2).foregroundStyle(chat.draft.utf16.count > 2000 ? Palette.accent : .secondary).frame(maxWidth: .infinity, alignment: .trailing) }
            }.padding(12).background(.bar)

    }
}

struct GameChatSettingsView: View {
    @EnvironmentObject private var chat: GameChatService
    @State private var disconnecting = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    if let account = chat.account { ChatAvatar(person: account, size: 56) }
                    VStack(alignment: .leading, spacing: 5) {
                        Text(chat.account?.name ?? "Chat account").font(.title3.bold())
                        Text(chat.isGuest ? "Guest profile" : "Discord account").font(.subheadline).foregroundStyle(.secondary)
                        ChatConnectionBadge()
                    }
                    Spacer(minLength: 0)
                }.padding(.vertical, 4)

                ChatSection(title: "Account & connection", symbol: "person.crop.circle") {
                    if chat.isGuest {
                        Text("Connect Discord to find your friends. Your guest profile will be linked to your Discord account.")
                            .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if chat.linking {
                            ProgressView("Connecting Discord…")
                            Button("Cancel sign-in") { chat.cancelLink() }.buttonStyle(.bordered)
                        } else {
                            Button { Task { await chat.link() } } label: {
                                Label("Connect Discord · Optional", systemImage: "person.badge.plus").frame(maxWidth: .infinity, minHeight: 30)
                            }.buttonStyle(.bordered).disabled(chat.inParty || chat.reconnecting).accessibilityIdentifier("linkGuestDiscord")
                        }
                        if chat.inParty { Label("Leave your current chat before linking an account.", systemImage: "info.circle").font(.caption).foregroundStyle(.secondary) }
                        Divider()
                    }
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Connection").font(.subheadline.weight(.medium))
                            Text(chat.reconnecting ? "Reconnecting…" : chat.linked ? "Ready to chat" : "Reconnect to continue")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Reconnect") { Task { await chat.reconnect() } }.buttonStyle(.bordered)
                            .disabled(chat.reconnecting || chat.linking).accessibilityIdentifier("chatReconnect")
                    }
                }

                ChatSection(title: "Voice & audio", symbol: "waveform") {
                    ChatDetailRow(title: "Voice", value: chat.hasCall ? chat.voiceStatus : "Not in a voice chat")
                    if chat.hasCall {
                        Toggle("Microphone", isOn: Binding(get: { !chat.muted }, set: { _ in Task { await chat.toggleMute() } }))
                            .disabled(chat.changingControls || chat.changingVoice).accessibilityIdentifier("chatSettingsMicrophone")
                        Toggle("Hear others", isOn: Binding(get: { !chat.deafened }, set: { _ in Task { await chat.toggleDeafen() } }))
                            .disabled(chat.changingControls || chat.changingVoice).accessibilityIdentifier("chatSettingsListening")
                        Divider()
                    }
                    #if os(iOS)
                    ChatDetailRow(title: "Output", value: chat.routeName.isEmpty ? "System default" : chat.routeName)
                    if chat.hasCall {
                        Toggle("Use speaker", isOn: Binding(get: { chat.speaker }, set: { _ in chat.toggleSpeaker() }))
                    }
                    #else
                    Picker("Microphone", selection: Binding(get: { chat.inputDevice }, set: { id in Task { await chat.selectAudioDevice(id, input: true) } })) {
                        if !chat.audioInputs.contains(where: { $0.id == chat.inputDevice }) { Text("System default").tag(chat.inputDevice) }
                        ForEach(chat.audioInputs) { Text($0.name).tag($0.id) }
                    }.disabled(chat.updatingDevices || !chat.linked).accessibilityIdentifier("chatAudioInput")
                    Picker("Speakers / headphones", selection: Binding(get: { chat.outputDevice }, set: { id in Task { await chat.selectAudioDevice(id, input: false) } })) {
                        if !chat.audioOutputs.contains(where: { $0.id == chat.outputDevice }) { Text("System default").tag(chat.outputDevice) }
                        ForEach(chat.audioOutputs) { Text($0.name).tag($0.id) }
                    }.disabled(chat.updatingDevices || !chat.linked).accessibilityIdentifier("chatAudioOutput")
                    Button { Task { await chat.refreshAudioDevices() } } label: { Label(chat.updatingDevices ? "Refreshing…" : "Refresh devices", systemImage: "arrow.clockwise") }
                        .buttonStyle(.bordered).disabled(chat.updatingDevices || !chat.linked)
                    #endif
                    Text("Voice stays connected when you return HOME or open a game.").font(.caption).foregroundStyle(.secondary)
                }.tint(Palette.green)

                ChatSection(title: "Privacy & permissions", symbol: "lock.shield") {
                    Button { ChatPlatform.openMicrophoneSettings() } label: {
                        HStack { Label("Microphone permissions", systemImage: "mic"); Spacer(); Image(systemName: "arrow.up.right") }
                            .frame(minHeight: 30).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("chatMicrophonePermissions")
                    Text("Allow microphone access in \(DevicePresentation.name) Settings to use voice. Text chat works without it.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Divider()
                    Button("Disconnect on this \(DevicePresentation.name)", role: .destructive) { disconnecting = true }
                        .buttonStyle(.bordered).tint(Palette.coral).disabled(chat.linking).accessibilityIdentifier("chatDisconnect")
                    Text("Disconnecting clears this device’s recent chat history and drafts. Your other devices stay connected.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text("Powered by Discord · Discord sign-in is optional. Only recent messages are available here.")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity).multilineTextAlignment(.center)
            }.frame(maxWidth: 720).padding(20).frame(maxWidth: .infinity)
        }.background(Palette.background).tint(.primary).navigationTitle("Chat Settings").chatInlineTitle()
            .toolbar { PanelDoneToolbar() }
            #if os(macOS)
            .task { await chat.refreshAudioDevices() }
            #endif
            .confirmationDialog("Disconnect Chat on this \(DevicePresentation.name)?", isPresented: $disconnecting, titleVisibility: .visible) {
                Button("Disconnect", role: .destructive) { Task { await chat.unlink() } }
            } message: { Text("Your local chat history and drafts will be cleared. You can connect again later.") }
    }
}

#if os(iOS)
struct GameChatMiniBar: View {
    @EnvironmentObject private var chat: GameChatService
    @EnvironmentObject private var model: LibraryModel
    var body: some View {
        if chat.inParty {
            HStack(spacing: 14) {
                Button { model.panel = .gameChat } label: { Label("Chat · \(chat.members.count)", systemImage: "person.2.wave.2.fill").lineLimit(1) }
                Spacer()
                if chat.hasCall { Button { Task { await chat.toggleMute() } } label: { Image(systemName: chat.muted ? "mic.slash.fill" : "mic.fill").frame(width: 44, height: 44) }.accessibilityLabel(chat.muted ? "Unmute microphone" : "Mute microphone").disabled(chat.changingControls || chat.changingVoice) }
            }.font(.subheadline).padding(.horizontal, 18).background(.regularMaterial, in: Capsule()).padding(.horizontal, 24).padding(.bottom, 6)
        }
    }
}

#endif
