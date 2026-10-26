import Foundation
import Combine
import AVFoundation
#if os(iOS)
import UIKit
#endif
import iSwitchCore

struct ChatPerson: Identifiable, Equatable {
    let id: String
    let name: String
    var avatar = ""
    var activity = ""
    var status = "Offline"
    var speaking = false
    var inVoice = false
    var localMute = false
    var volume = 100.0
    init?(_ row: [String: Any]) {
        guard let id = row["id"] as? String, GameChatRules.validID(id), let name = row["name"] as? String else { return nil }
        self.id = id; self.name = String(name.prefix(128))
        avatar = row["avatar"] as? String ?? ""; activity = String((row["activity"] as? String ?? "").prefix(256))
        status = row["status"] as? String ?? "Offline"; speaking = row["speaking"] as? Bool ?? false
        inVoice = row["inVoice"] as? Bool ?? false; localMute = row["localMute"] as? Bool ?? false
        volume = row["volume"] as? Double ?? 100
    }
}

struct ChatMessage: Identifiable, Equatable {
    let id: String
    let authorID: String
    let author: String
    let text: String
    var sentAt: Date { Date(timeIntervalSince1970: Double((UInt64(id) ?? 0) >> 22) / 1000 + 1_420_070_400) }
    init?(_ row: [String: Any]) {
        guard let id = row["id"] as? String, GameChatRules.validID(id),
              let authorID = row["authorID"] as? String, GameChatRules.validID(authorID),
              let author = row["author"] as? String, let text = row["text"] as? String else { return nil }
        self.id = id; self.authorID = authorID; self.author = String(author.prefix(128)); self.text = String(text.prefix(8000))
    }
}

enum ChatConversation: Hashable { case friend(String), party(String) }
struct ChatInvitation: Identifiable, Equatable { let id: String; let name: String }

@MainActor final class GameChatService: ObservableObject {
    @Published private(set) var linked = false
    @Published private(set) var isGuest = false
    @Published private(set) var linking = false
    @Published private(set) var reconnecting = false
    @Published private(set) var busy = false
    @Published private(set) var status = "Not connected"
    @Published private(set) var account: ChatPerson?
    @Published private(set) var friends: [ChatPerson] = []
    @Published private(set) var members: [ChatPerson] = []
    @Published private(set) var invitations: [ChatInvitation] = []
    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var conversation: ChatConversation?
    @Published private(set) var loadingMessages = false
    @Published private(set) var messageError: String?
    @Published private(set) var sendError: String?
    @Published private(set) var changingControls = false
    @Published private(set) var invitedIDs: Set<String> = []
    @Published private(set) var invitingIDs: Set<String> = []
    @Published private(set) var feedback: String?
    @Published private(set) var lobbyID: String?
    @Published private(set) var partyCode = ""
    @Published private(set) var hasCall = false
    @Published private(set) var changingVoice = false
    @Published private(set) var voiceStatus = "Disconnected"
    @Published private(set) var muted = false
    @Published private(set) var deafened = false
    @Published private(set) var speaker = false
    @Published private(set) var routeName = DevicePresentation.name
    #if os(macOS)
    @Published private(set) var audioInputs: [ChatAudioDevice] = []
    @Published private(set) var audioOutputs: [ChatAudioDevice] = []
    @Published private(set) var inputDevice = ""
    @Published private(set) var outputDevice = ""
    @Published private(set) var updatingDevices = false
    private var audioDeviceOperation: UUID?
    #endif
    @Published var pendingInvite: String?
    @Published var notice: String?
    @Published private var drafts: [ChatConversation: String] = [:]
    @Published private var sending: Set<ChatConversation> = []

    private let transport: any GameChatTransport
    private let credentials: GameChatCredentialStore
    private let guestAuthorizer: any GuestChatAuthorizing
    private let guestStore: GuestChatIdentityStore
    private var guestIdentity: GuestChatIdentity?
    private var linkPreviousTokens: GameChatTokens?
    private var linkWasGuest = false
    private let microphonePermission: () async -> Bool
    private let managesAudio: Bool
    private var tokens: GameChatTokens?
    private var credentialsNeedSave = false
    private var authorized = false
    private var authGeneration = 0
    private var conversationGeneration = 0
    private var voiceGeneration = 0
    private var pump: Timer?
    private var lastSnapshot = Date.distantPast
    private var restored = false
    private var refreshing = false
    private var visible = false
    private var active = true
    private var refreshTask: Task<Void, Never>?
    private var reloadTask: Task<Void, Never>?
    private var reloadAgain = false
    private var observers: [NSObjectProtocol] = []
    private var activity = "In reSwitch"
    private var prefersSpeaker = true
    private var cachedMessages: [ChatConversation: [ChatMessage]] = [:]
    private var recent: [ChatConversation] = []
    private var pumpInterval: TimeInterval = 0
    private var feedbackTask: Task<Void, Never>?

    var available: Bool { transport.available }
    var guestAvailable: Bool { available && guestAuthorizer.available }
    var connectionLabel: String { isGuest ? "Connected as Guest" : "Connected to Discord" }
    var inParty: Bool { lobbyID != nil }
    var isSending: Bool { conversation.map { sending.contains($0) } ?? false }
    var draft: String {
        get { conversation.flatMap { drafts[$0] } ?? "" }
        set { if let conversation { drafts[conversation] = String(newValue.prefix(4000)) } }
    }
    var conversationTitle: String {
        if case .friend(let id) = conversation { return friends.first { $0.id == id }?.name ?? "Conversation" }
        return "Party chat"
    }

    init(transport: (any GameChatTransport)? = nil, credentials: GameChatCredentialStore = .keychain(),
         guestAuthorizer: (any GuestChatAuthorizing)? = nil, guestStore: GuestChatIdentityStore = .keychain(),
         managesAudio: Bool = true, microphonePermission: @escaping () async -> Bool = { await ChatPlatform.requestMicrophone() }) {
        let transport = transport ?? DiscordGameChatTransport()
        self.transport = transport; self.credentials = credentials; self.managesAudio = managesAudio; self.microphonePermission = microphonePermission
        self.guestAuthorizer = guestAuthorizer ?? GuestChatClient(); self.guestStore = guestStore
        transport.onEvent = { [weak self] event, value in
            guard let self else { return }
            switch event {
            case "status", "voice", "invitations": self.updateSnapshot()
            #if os(macOS)
            case "audioDevicesChanged": Task { await self.refreshAudioDevices() }
            #endif
            case "tokenExpired": Task { await self.reconnect(forceRefresh: true) }
            case "message": self.scheduleMessageReload()
            case "joinRequested": self.pendingInvite = GameChatRules.invitation(value)
            case "error": self.notice = value
            default: break
            }
        }
        #if os(iOS)
        if managesAudio {
            observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updateRoute() }
            })
            observers.append(NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
                let began = (notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
                Task { @MainActor in
                    guard let self, self.hasCall else { return }
                    if began { self.notice = "Voice chat was interrupted by another call or audio app." }
                    else { do { try self.activateAudio() } catch { self.notice = error.localizedDescription } }
                }
            })
        }
        #endif
    }

    func restore() async {
        guard !restored else { return }; restored = true
        var guestError: Error?, discordError: Error?
        do { guestIdentity = try guestStore.read() } catch { guestError = error }
        do { tokens = try credentials.read() } catch { discordError = error }
        // Saving OAuth and updating the guest marker are separate Keychain
        // writes. A completed merge must survive an interrupted second write.
        if let identity = guestIdentity, identity.active, !identity.merged,
           tokens?.mergedGuestID != identity.fingerprint {
            isGuest = true; tokens = nil; await reconnect()
        } else if let identity = guestIdentity, !identity.active, !identity.merged, identity.prefersDiscord != true {
            // Disconnecting a guest must not silently switch back to an older
            // Discord account on the next launch.
            tokens = nil
        } else if let tokens {
            scheduleRefresh(tokens.expiresAt.timeIntervalSinceNow); await reconnect()
        } else if let error = guestError ?? discordError {
            restored = false; notice = error.localizedDescription
        }
    }

    func continueAsGuest(name: String) async {
        guard !linked, !linking, !reconnecting, guestAvailable else { return }
        do {
            var identity = try guestStore.read()
            if identity == nil || identity?.merged == true { identity = try GuestChatIdentity.create(name: name) }
            guard var identity else { return }
            identity.displayName = try GuestChatIdentity.validName(name); identity.active = true; identity.prefersDiscord = false
            try guestStore.save(identity)
            guestIdentity = identity; isGuest = true; tokens = nil; authGeneration += 1
            notice = nil
            await reconnect()
        } catch { notice = error.localizedDescription }
    }

    private func startPump() {
        // Voice keeps responsive speaking indicators; the idle HOME screen
        // needs two callback wakeups per second instead of twenty.
        let interval: TimeInterval = hasCall ? 0.05 : (visible || linking || reconnecting) ? 0.1 : 0.5
        guard pump == nil || pumpInterval != interval else { return }
        pump?.invalidate(); pumpInterval = interval
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.transport.tick()
                let interval = self.hasCall && self.visible ? 0.25 : self.visible ? 0.75 : 2.0
                if Date.now.timeIntervalSince(self.lastSnapshot) >= interval {
                    self.lastSnapshot = .now; self.updateSnapshot()
                }
            }
        }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common); pump = timer
    }

    func setActive(_ value: Bool) {
        active = value
        if value {
            if authorized || linking || reconnecting { startPump(); transport.tick(); updateSnapshot() }
            if let tokens, tokens.expiresAt.timeIntervalSinceNow < 60 { Task { await reconnect(forceRefresh: true) } }
            if visible { scheduleMessageReload() }
        } else if !hasCall && !linking { pump?.invalidate(); pump = nil }
    }

    func setVisible(_ value: Bool) {
        visible = value
        if active && (authorized || linking || reconnecting) { startPump() }
        if authorized { Task { _ = try? await transport.request("chatVisible", ["value": value]) } }
        if value { updateSnapshot(); scheduleMessageReload() }
        else { reloadTask?.cancel(); reloadTask = nil }
    }

    func link() async {
        guard !linking, !reconnecting else { return }
        guard !inParty else { notice = "Leave your current Chat before connecting Discord."; return }
        authGeneration += 1; let generation = authGeneration
        linkPreviousTokens = tokens; linkWasGuest = isGuest
        linking = true; status = "Connecting Discord…"; notice = nil; startPump()
        var exchanged = false
        defer { if generation == authGeneration { linking = false; if authorized && active { startPump() } } }
        do {
            var parameters: [String: Any] = [:]
            if isGuest, let identity = guestIdentity {
                if tokens == nil || tokens!.expiresAt.timeIntervalSinceNow < 300 {
                    let renewed = try await guestAuthorizer.authorize(identity)
                    guard generation == authGeneration else { return }
                    tokens = renewed; linkPreviousTokens = renewed
                }
                parameters["guestAccessToken"] = tokens?.accessToken
            }
            let response = try await transport.request("authorize", parameters, timeout: 180)
            guard generation == authGeneration else { return }
            exchanged = true; isGuest = false
            try saveTokens(response, mergedGuestID: linkWasGuest ? guestIdentity?.fingerprint : nil)
            if var identity = guestIdentity {
                identity.active = false; identity.merged = linkWasGuest || identity.merged; identity.prefersDiscord = true
                guestIdentity = identity
                // OAuth's merge marker is authoritative if this secondary write
                // fails. Never discard the new refresh token or the connection.
                try? guestStore.save(identity)
            }
            conversationGeneration += 1; conversation = nil; messages = []; cachedMessages = [:]; drafts = [:]; recent = []
            friends = []; account = nil; authorized = false; linked = false
            try await connect(generation)
            if credentialsNeedSave { notice = "Connected. Sign-in couldn’t be saved yet; keep reSwitch open while we retry." }
            linkPreviousTokens = nil
        } catch {
            guard generation == authGeneration else { return }
            if !exchanged && linkWasGuest {
                tokens = linkPreviousTokens; isGuest = true; authorized = tokens != nil
                updateSnapshot(); notice = error.localizedDescription; return
            }
            authorized = false; linked = false; status = "Not connected"; notice = error.localizedDescription
            transport.cancel(); pump?.invalidate(); pump = nil
        }
    }

    func cancelLink() {
        guard linking else { return }
        // Once Discord starts the irreversible account merge, let that short
        // exchange finish so its only refresh token is not discarded.
        guard transport.cancelAuthorization() else { notice = "Finishing secure sign-in. This will only take a moment."; return }
        if linkWasGuest {
            authGeneration += 1; linking = false; tokens = linkPreviousTokens; isGuest = true; authorized = tokens != nil
            updateSnapshot(); if active { startPump() }; return
        }
        authGeneration += 1; linking = false; authorized = false; linked = false; status = "Not connected"
        refreshTask?.cancel(); tokens = nil
        do { try credentials.delete() } catch { notice = error.localizedDescription }
        transport.cancel(); pump?.invalidate(); pump = nil
    }

    func reconnect(forceRefresh: Bool = false) async {
        guard !refreshing, !linking, tokens != nil || (isGuest && guestIdentity != nil) else { return }
        refreshing = true; reconnecting = true; let generation = authGeneration; startPump()
        defer { if generation == authGeneration { refreshing = false; reconnecting = false; if authorized && active { startPump() } } }
        do {
            if credentialsNeedSave, let tokens, !isGuest {
                do { try credentials.save(tokens); credentialsNeedSave = false } catch { /* Retain the only current refresh token in memory and retry. */ }
            }
            if isGuest, let identity = guestIdentity {
                if forceRefresh || tokens == nil || tokens!.expiresAt.timeIntervalSinceNow < 60 {
                    let value = try await guestAuthorizer.authorize(identity)
                    guard generation == authGeneration else { return }
                    tokens = value; scheduleRefresh(value.expiresAt.timeIntervalSinceNow)
                }
            } else if let previous = tokens, forceRefresh || previous.expiresAt.timeIntervalSinceNow < 60 {
                let response = try await transport.request("refresh", ["refreshToken": previous.refreshToken])
                guard generation == authGeneration else { return }
                try saveTokens(response, mergedGuestID: previous.mergedGuestID)
            }
            try await connect(generation)
            if credentialsNeedSave {
                notice = "Connected. Sign-in couldn’t be saved yet; keep reSwitch open while we retry."
                scheduleRefresh(180)
            }
        } catch {
            guard generation == authGeneration else { return }
            if authorized && linked {
                notice = "Couldn’t renew Chat access. Your call can continue; we’ll retry shortly."
                scheduleRefresh(180); return
            }
            authorized = false; linked = false; status = "Connection lost"
            notice = isGuest ? error.localizedDescription : "Couldn’t reconnect Discord. Try again, or connect your account again."
            transport.cancel(); updateSnapshot(); stopAudio(); pump?.invalidate(); pump = nil
        }
    }

    private func saveTokens(_ response: [String: Any], mergedGuestID: String?) throws {
        guard let access = response["accessToken"] as? String, !access.isEmpty, access.utf8.count < 16384,
              let refresh = response["refreshToken"] as? String, !refresh.isEmpty, refresh.utf8.count < 16384,
              let expires = response["expiresIn"] as? NSNumber, expires.doubleValue.isFinite, expires.doubleValue > 0 else {
            throw LibraryError.invalid("Discord returned incomplete authorization. Please connect again.")
        }
        let value = GameChatTokens(accessToken: access, refreshToken: refresh, expiresAt: Date.now.addingTimeInterval(expires.doubleValue), mergedGuestID: mergedGuestID)
        tokens = value
        do { try credentials.save(value); credentialsNeedSave = false }
        catch { credentialsNeedSave = true }
        scheduleRefresh(credentialsNeedSave ? 180 : expires.doubleValue)
    }

    private func scheduleRefresh(_ expiresIn: Double) {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(30, expiresIn - 120))) } catch { return }
            guard let self, self.active || self.hasCall else { return }
            await self.reconnect(forceRefresh: true)
        }
    }

    private func connect(_ generation: Int) async throws {
        guard let tokens, generation == authGeneration else { throw CancellationError() }
        if authorized && linked {
            _ = try await transport.request("updateToken", ["accessToken": tokens.accessToken])
            if generation == authGeneration { notice = nil; updateSnapshot() }
            return
        }
        authorized = true
        _ = try await transport.request("connect", ["accessToken": tokens.accessToken])
        let deadline = Date.now.addingTimeInterval(30)
        while generation == authGeneration && Date.now < deadline {
            updateSnapshot()
            if linked { notice = nil; publishActivity(); return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw LibraryError.invalid("Discord did not become ready. Check your connection and try again.")
    }

    func unlink() async {
        guard !linking else { notice = "Finish or cancel sign-in before disconnecting."; return }
        let leave = linked && inParty
        authGeneration += 1; conversationGeneration += 1
        refreshTask?.cancel(); reloadTask?.cancel()
        authorized = false; linked = false; linking = false; reconnecting = true; refreshing = false; busy = false; changingVoice = false
        tokens = nil; credentialsNeedSave = false; account = nil; friends = []; members = []; messages = []; conversation = nil; invitations = []
        drafts = [:]; sending = []; partyCode = ""; lobbyID = nil; hasCall = false; muted = false; deafened = false
        cachedMessages = [:]; recent = []; sendError = nil; invitedIDs = []; invitingIDs = []; changingControls = false; feedback = nil; feedbackTask?.cancel()
        pendingInvite = nil; voiceStatus = "Disconnected"; status = "Not connected"; loadingMessages = false
        #if os(macOS)
        audioInputs = []; audioOutputs = []; inputDevice = ""; outputDevice = ""; routeName = "System default"
        audioDeviceOperation = nil; updatingDevices = false
        #endif
        stopAudio()
        do {
            if !isGuest { try credentials.delete() }
            if var identity = guestIdentity { identity.active = false; try guestStore.save(identity); guestIdentity = identity }
        } catch { notice = error.localizedDescription }
        isGuest = false
        if leave { _ = try? await transport.request("leave", [:], timeout: 5) }
        transport.cancel(); reconnecting = false
        // Both apps share a Discord application. Disconnect only this device;
        // revoking the shared application grant could also sign ArcStation out.
        pump?.invalidate(); pump = nil
    }

    private func updateSnapshot() {
        let snapshot = transport.snapshot
        let rawStatus = snapshot["status"] as? String ?? "Not connected"
        let ready = authorized && rawStatus.lowercased() == "ready"
        let becameReady = ready && !linked
        if linked != ready { linked = ready }
        if status != rawStatus { status = rawStatus }
        let call = authorized && snapshot["hasCall"] as? Bool == true
        if hasCall != call { hasCall = call; if !call { stopAudio() }; if active || call { startPump() } }
        let voice = snapshot["voiceStatus"] as? String ?? "Disconnected"
        if voiceStatus != voice { voiceStatus = voice }
        let mute = snapshot["muted"] as? Bool ?? false, deaf = snapshot["deafened"] as? Bool ?? false
        if muted != mute { muted = mute }; if deafened != deaf { deafened = deaf }
        guard ready else {
            if !authorized {
                if !friends.isEmpty { friends = [] }; if !members.isEmpty { members = [] }
                if hasCall { hasCall = false; stopAudio() }
                if lobbyID != nil { lobbyID = nil; invalidateVoiceRequest() }
            }
            return
        }
        let me = (snapshot["account"] as? [String: Any]).flatMap(ChatPerson.init)
        if account != me { account = me }
        let list = (snapshot["friends"] as? [[String: Any]] ?? []).compactMap(ChatPerson.init).sorted {
            if ($0.status == "Offline") != ($1.status == "Offline") { return $0.status != "Offline" }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let people = (snapshot["members"] as? [[String: Any]] ?? []).compactMap(ChatPerson.init)
        let invites = (snapshot["invitations"] as? [[String: Any]] ?? []).compactMap { row -> ChatInvitation? in
            guard let id = row["id"] as? String, GameChatRules.validID(id), let name = row["name"] as? String else { return nil }
            return ChatInvitation(id: id, name: String(name.prefix(128)))
        }
        if invitations != invites { invitations = invites }
        if friends != list { friends = list }; if members != people { members = people }
        let id = snapshot["lobbyID"] as? String ?? "0", nextID = GameChatRules.validID(id) ? id : nil
        if lobbyID != nextID { lobbyID = nextID; invalidateVoiceRequest() }
        // Message events can be missed while the gateway is offline. Refresh
        // the visible conversation once on recovery rather than polling it.
        if becameReady { scheduleMessageReload() }
    }

    func createParty(voice: Bool = true) async { await joinParty(UUID().uuidString.lowercased(), voice: voice) }
    func accept(_ invitation: ChatInvitation) async {
        guard linked, !inParty, !busy else { return }
        let generation = authGeneration; busy = true
        do {
            let response = try await transport.request("acceptInvite", ["id": invitation.id])
            guard generation == authGeneration else { return }
            busy = false
            guard let secret = response["secret"] as? String, let code = GameChatRules.invitation(secret) else { throw LibraryError.invalid("This invitation is no longer available.") }
            await joinParty(code)
        } catch { if generation == authGeneration { busy = false; notice = error.localizedDescription } }
    }
    func dismiss(_ invitation: ChatInvitation) async {
        _ = try? await transport.request("dismissInvite", ["id": invitation.id]); updateSnapshot()
    }
    func joinParty(_ code: String, voice: Bool = true) async {
        guard linked, !inParty, !busy, let code = GameChatRules.invitation(code) else { return }
        let generation = authGeneration; busy = true
        var holdsBusy = true
        defer { if holdsBusy, generation == authGeneration { busy = false } }
        do {
            _ = try await transport.request("join", ["secret": code])
            guard generation == authGeneration, linked else { return }
            partyCode = code; pendingInvite = nil; updateSnapshot(); publishActivity()
            invitedIDs = []; invitingIDs = []
            if let lobbyID { await select(.party(lobbyID)) }
            guard generation == authGeneration else { return }
            holdsBusy = false; busy = false
            if voice { await startVoice() }
        } catch { if generation == authGeneration { notice = error.localizedDescription } }
    }

    func leaveParty() async {
        guard linked, !busy else { return }; let generation = authGeneration; busy = true
        invalidateVoiceRequest()
        defer { if generation == authGeneration { busy = false } }
        do {
            _ = try await transport.request("leave")
            guard generation == authGeneration else { return }
            partyCode = ""; stopAudio(); updateSnapshot(); publishActivity()
            if case .party = conversation { conversationGeneration += 1; conversation = nil; messages = []; loadingMessages = false }
        } catch { if generation == authGeneration { notice = error.localizedDescription; updateSnapshot() } }
    }

    func startVoice() async {
        guard linked, inParty, !busy, !hasCall, !changingVoice else { return }
        let generation = authGeneration, voiceRequest = voiceGeneration, requestedLobby = lobbyID
        changingVoice = true
        defer { if generation == authGeneration, voiceRequest == voiceGeneration { changingVoice = false } }
        let permitted = await microphonePermission()
        guard generation == authGeneration, voiceRequest == voiceGeneration, linked, lobbyID == requestedLobby else { return }
        guard permitted else { notice = "Text chat is ready. To use voice, allow Microphone access for reSwitch in \(DevicePresentation.name) Settings."; return }
        do {
            try activateAudio()
            _ = try await transport.request("voiceStart")
            guard generation == authGeneration, voiceRequest == voiceGeneration else { return }
            updateSnapshot(); startPump()
        } catch { if generation == authGeneration, voiceRequest == voiceGeneration { stopAudio(); notice = error.localizedDescription } }
    }

    func stopVoice() async {
        guard hasCall, !busy, !changingVoice else { return }
        let generation = authGeneration, voiceRequest = voiceGeneration
        changingVoice = true
        defer { if generation == authGeneration, voiceRequest == voiceGeneration { changingVoice = false } }
        do {
            _ = try await transport.request("voiceStop")
            guard generation == authGeneration, voiceRequest == voiceGeneration else { return }
            updateSnapshot(); stopAudio()
        } catch { if generation == authGeneration, voiceRequest == voiceGeneration { notice = error.localizedDescription } }
    }

    private func invalidateVoiceRequest() {
        // A lobby can be left and rejoined with the same ID. Its old microphone
        // prompt must not enable voice or reset a newer request's progress.
        voiceGeneration += 1; changingVoice = false
    }

    func toggleMute() async { await control("mute", ["value": !muted]) }
    func toggleDeafen() async { await control("deafen", ["value": !deafened]) }
    func adjust(_ member: ChatPerson, muted: Bool? = nil, volume: Double? = nil) async {
        var parameters: [String: Any] = ["id": member.id]
        if let muted { parameters["mute"] = muted }; if let volume { parameters["volume"] = min(200, max(0, volume)) }
        await control("participant", parameters)
    }
    private func control(_ action: String, _ parameters: [String: Any]) async {
        // These are local audio controls. A gateway reconnect must never
        // prevent the user from muting an otherwise live call.
        guard hasCall, !changingControls else { return }; let generation = authGeneration
        changingControls = true
        defer { if generation == authGeneration { changingControls = false } }
        do { _ = try await transport.request(action, parameters); if generation == authGeneration { updateSnapshot() } }
        catch { if generation == authGeneration { notice = error.localizedDescription } }
    }

    #if os(iOS)
    private func activateAudio() throws {
        guard managesAudio else { return }
        let session = AVAudioSession.sharedInstance()
        try configureAudioRoute(session)
        try session.setActive(true); updateRoute()
    }
    private func configureAudioRoute(_ session: AVAudioSession) throws {
        var options: AVAudioSession.CategoryOptions = [.mixWithOthers, .allowBluetoothHFP]
        if prefersSpeaker { options.insert(.defaultToSpeaker) }
        try session.setCategory(.playAndRecord, mode: .voiceChat, options: options)
    }
    private func stopAudio() {
        guard managesAudio else { return }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    func toggleSpeaker() {
        guard hasCall else { return }
        if !managesAudio { speaker.toggle(); return }
        let previous = prefersSpeaker
        prefersSpeaker = !speaker
        do {
            let session = AVAudioSession.sharedInstance()
            // Clearing an override alone cannot select the receiver while the
            // category still defaults to the speaker. Update both preferences.
            try configureAudioRoute(session)
            try session.overrideOutputAudioPort(prefersSpeaker ? .speaker : .none)
            updateRoute()
        } catch { prefersSpeaker = previous; notice = "The audio route couldn’t be changed. Check your connected headphones." }
    }
    private func updateRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let value = outputs.map(\.portName).joined(separator: ", ")
        if routeName != value { routeName = value }
        let output = outputs.contains { $0.portType == .builtInSpeaker }
        if speaker != output { speaker = output }
    }

    #else
    private func activateAudio() throws {
        guard managesAudio else { return }
        Task { await refreshAudioDevices() }
    }
    private func stopAudio() { }
    private func updateRoute() { }
    func refreshAudioDevices() async {
        guard linked, !updatingDevices else { return }
        let generation = authGeneration, operation = UUID()
        audioDeviceOperation = operation; updatingDevices = true
        defer { if audioDeviceOperation == operation { audioDeviceOperation = nil; updatingDevices = false } }
        do {
            let inputs = try await transport.request("audioInputs")
            guard generation == authGeneration, audioDeviceOperation == operation, linked else { return }
            let outputs = try await transport.request("audioOutputs")
            guard generation == authGeneration, audioDeviceOperation == operation, linked else { return }
            audioInputs = ChatAudioDevice.decode(inputs)
            audioOutputs = ChatAudioDevice.decode(outputs)
            inputDevice = inputs["currentID"] as? String ?? ""
            outputDevice = outputs["currentID"] as? String ?? ""
            routeName = audioOutputs.first { $0.id == outputDevice }?.name ?? "System default"
        } catch { if generation == authGeneration { notice = "Audio devices could not be refreshed. " + error.localizedDescription } }
    }
    func selectAudioDevice(_ id: String, input: Bool) async {
        guard linked, !updatingDevices, (input ? audioInputs : audioOutputs).contains(where: { $0.id == id }) else { return }
        let generation = authGeneration, operation = UUID()
        audioDeviceOperation = operation; updatingDevices = true
        defer { if audioDeviceOperation == operation { audioDeviceOperation = nil; updatingDevices = false } }
        do {
            _ = try await transport.request(input ? "audioInputDevice" : "audioOutputDevice", ["id": id])
            guard generation == authGeneration, audioDeviceOperation == operation, linked else { return }
            audioDeviceOperation = nil; updatingDevices = false
            await refreshAudioDevices()
        } catch { if generation == authGeneration { notice = error.localizedDescription } }
    }
    #endif

    func select(_ value: ChatConversation) async {
        if conversation != value {
            conversationGeneration += 1; conversation = value; messages = cachedMessages[value] ?? []; messageError = nil; sendError = nil; loadingMessages = false; reloadAgain = false
        }
        await reloadMessages()
    }
    func clearConversation() { conversationGeneration += 1; conversation = nil; messages = []; loadingMessages = false; messageError = nil; sendError = nil; reloadAgain = false }

    func preview(for person: ChatPerson) -> String {
        if let draft = drafts[.friend(person.id)], !draft.isEmpty { return "Draft: \(draft)" }
        return cachedMessages[.friend(person.id)]?.last?.text ?? (person.activity.isEmpty ? person.status : person.activity)
    }

    private func scheduleMessageReload() {
        guard linked, visible, conversation != nil else { return }
        guard reloadTask == nil else { return }
        reloadTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard let self else { return }; self.reloadTask = nil; await self.reloadMessages()
        }
    }

    func reloadMessages() async {
        guard linked, let selected = conversation else { return }
        guard !loadingMessages else { reloadAgain = true; return }
        let generation = authGeneration, selection = conversationGeneration
        loadingMessages = true; messageError = nil
        defer {
            if generation == authGeneration, selection == conversationGeneration {
                loadingMessages = false
                if reloadAgain { reloadAgain = false; scheduleMessageReload() }
            }
        }
        let action: String, parameters: [String: Any]
        switch selected {
        case .friend(let id): action = "messages"; parameters = ["id": id]
        case .party: action = "partyMessages"; parameters = [:]
        }
        do {
            let result = try await transport.request(action, parameters)
            guard generation == authGeneration, selection == conversationGeneration, conversation == selected, linked else { return }
            var seen = Set<String>()
            let rows = (result["messages"] as? [[String: Any]] ?? []).compactMap(ChatMessage.init).filter { seen.insert($0.id).inserted }
                .sorted { (UInt64($0.id) ?? 0) < (UInt64($1.id) ?? 0) }
            let bounded = Array(rows.suffix(100))
            cachedMessages[selected] = bounded
            recent.removeAll { $0 == selected }; recent.append(selected)
            while recent.count > 20 { cachedMessages.removeValue(forKey: recent.removeFirst()) }
            if messages != bounded { messages = bounded }
        } catch {
            if generation == authGeneration, selection == conversationGeneration, linked { messageError = error.localizedDescription }
        }
    }

    func send() async {
        guard linked, let selected = conversation, !sending.contains(selected), let text = GameChatRules.message(draft) else { return }
        let generation = authGeneration; sending.insert(selected); sendError = nil
        defer { if generation == authGeneration { sending.remove(selected) } }
        let action: String, parameters: [String: Any]
        switch selected {
        case .friend(let id): action = "send"; parameters = ["id": id, "text": text]
        case .party: action = "partySend"; parameters = ["text": text]
        }
        do {
            _ = try await transport.request(action, parameters)
            guard generation == authGeneration, linked else { return }
            if GameChatRules.message(drafts[selected] ?? "") == text { drafts[selected] = "" }
            if conversation == selected { await reloadMessages() }
        } catch { if generation == authGeneration, conversation == selected { sendError = error.localizedDescription } }
    }

    func invite(_ friend: ChatPerson) async {
        guard linked, let party = lobbyID, !invitingIDs.contains(friend.id), !invitedIDs.contains(friend.id) else { return }
        let generation = authGeneration
        invitingIDs.insert(friend.id)
        defer { if generation == authGeneration, lobbyID == party { invitingIDs.remove(friend.id) } }
        do {
            _ = try await transport.request("presence", ["title": activity, "secret": partyCode])
            guard generation == authGeneration, lobbyID == party else { return }
            _ = try await transport.request("invite", ["id": friend.id])
            if generation == authGeneration, lobbyID == party {
                invitedIDs.insert(friend.id); feedback = "Invited \(friend.name)"
                feedbackTask?.cancel(); feedbackTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(3)); guard !Task.isCancelled else { return }; self?.feedback = nil
                }
            }
        } catch { if generation == authGeneration { notice = error.localizedDescription } }
    }

    func block(_ friend: ChatPerson) async {
        guard linked else { return }; let generation = authGeneration
        do {
            _ = try await transport.request("block", ["id": friend.id])
            guard generation == authGeneration else { return }
            if conversation == .friend(friend.id) { clearConversation() }
            drafts.removeValue(forKey: .friend(friend.id)); cachedMessages.removeValue(forKey: .friend(friend.id)); recent.removeAll { $0 == .friend(friend.id) }; updateSnapshot()
        } catch { if generation == authGeneration { notice = error.localizedDescription } }
    }

    func setActivity(_ title: String) { let next = String(title.prefix(128)); guard next != activity else { return }; activity = next; publishActivity() }
    private func publishActivity() {
        guard linked else { return }
        let title = activity, code = partyCode
        Task { _ = try? await transport.request("presence", ["title": title, "secret": code]) }
    }

    func shutdown() {
        authGeneration += 1; refreshTask?.cancel(); reloadTask?.cancel(); feedbackTask?.cancel(); pump?.invalidate(); pump = nil
        observers.forEach(NotificationCenter.default.removeObserver); observers = []
        transport.onEvent = nil; transport.cancel(); stopAudio()
    }
}
