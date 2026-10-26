import SwiftUI

enum DevicePresentation { static let name = "Mac" }
enum Palette {
    static let accent = switchRed
    static let coral = Color(red: 1, green: 0.36, blue: 0.34)
    static let orange = Color(red: 1, green: 0.69, blue: 0.27)
    static let green = Color(red: 0.52, green: 0.85, blue: 0.57)
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
}

struct PanelDoneToolbar: ToolbarContent {
    @EnvironmentObject private var model: MacModel
    var body: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { model.panel = nil }.tint(.primary).accessibilityIdentifier("closePanel")
        }
    }
}

struct MacChatPanel: View {
    @EnvironmentObject private var chat: GameChatService
    var body: some View {
        NavigationStack {
            GameChatView().navigationTitle("Chat").toolbar { PanelDoneToolbar() }
        }.frame(minWidth: 660, idealWidth: 760, minHeight: 580, idealHeight: 700)
            .alert("Chat", isPresented: Binding(get: { chat.notice != nil }, set: { if !$0 { chat.notice = nil } })) {
                Button("OK", role: .cancel) { chat.notice = nil }
            } message: { Text(chat.notice ?? "") }
    }
}

struct MacChatMiniBar: View {
    @EnvironmentObject private var chat: GameChatService
    @EnvironmentObject private var model: MacModel
    var body: some View {
        if chat.inParty {
            HStack(spacing: 14) {
                Button { model.panel = .chat } label: { Label("Chat · \(chat.members.count)", systemImage: "person.2.wave.2.fill") }.buttonStyle(.plain)
                Text(chat.hasCall ? chat.voiceStatus : "Text chat").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if chat.hasCall {
                    Button { Task { await chat.toggleMute() } } label: { Image(systemName: chat.muted ? "mic.slash.fill" : "mic.fill").frame(width: 32, height: 32) }
                        .buttonStyle(.plain).accessibilityLabel(chat.muted ? "Unmute microphone" : "Mute microphone")
                        .disabled(chat.changingControls || chat.changingVoice)
                }
            }.padding(.horizontal, 18).padding(.vertical, 8).frame(maxWidth: 520)
                .background(.regularMaterial, in: Capsule()).padding(.top, 16)
        }
    }
}

struct MacProfileEditor: View {
    @EnvironmentObject private var model: MacModel
    @AppStorage("playerName") private var playerName = "Player"
    @State private var name = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 18) {
                if let photo = model.photo { Image(nsImage: photo).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(Circle()) }
                Button("Change Profile Photo…", action: model.choosePhoto)
            }
            TextField("Display name", text: $name).textFieldStyle(.roundedBorder).accessibilityIdentifier("profileName")
                .onSubmit(save)
            Text("Your name in reSwitch on this Mac. New guest Chat profiles use this name. Your Discord account name is managed in Discord.")
                .foregroundStyle(.secondary).font(.callout)
            if let error { Text(error).foregroundStyle(Palette.coral) }
            Button("Save Name", action: save).buttonStyle(.borderedProminent).accessibilityIdentifier("saveProfileName")
        }.onAppear { name = playerName }
    }
    private func save() {
        do { playerName = try GuestChatIdentity.validName(name); error = nil; model.panel = nil }
        catch { self.error = error.localizedDescription }
    }
}
