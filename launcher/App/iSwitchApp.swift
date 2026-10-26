import SwiftUI
import iSwitchCore

@main
struct iSwitchApp: App {
    @StateObject private var model = LibraryModel()
    @StateObject private var chat = GameChatService.forLaunch()
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("appearance") private var appearance = "dark"
    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(model)
                .environmentObject(chat)
                .preferredColorScheme(appearance == "system" ? nil : appearance == "light" ? .light : .dark)
                .tint(Palette.accent)
                .task {
                    model.setControllersActive(scenePhase == .active)
                    model.didOpenGame = { chat.setActivity("Playing \($0)") }
                    if !model.loaded { await model.load() }; await chat.restore()
                }
                .onChange(of: scenePhase) { _, phase in
                    model.setControllersActive(phase == .active)
                    chat.setActive(phase == .active)
                    if phase == .active { chat.setActivity("In reSwitch") }
                }
                .onOpenURL { url in
                    if let code = GameChatRules.inviteURL(url.absoluteString) { chat.pendingInvite = code; if !model.importingSource { model.panel = .gameChat } }
                    else if url.scheme == "discord-\(GameChatConfiguration.load()?.applicationID ?? "")", !model.importingSource { model.panel = .gameChat }
                    else if url.isFileURL { model.openFile(url) }
                }
        }
    }
}

enum Palette {
    // The red pixels in the supplied logo are sRGB #E60012.
    static let accent = Color(.sRGB, red: 230.0 / 255, green: 0, blue: 18.0 / 255, opacity: 1)
    static let coral = Color(red: 1, green: 0.36, blue: 0.34)
    static let orange = Color(red: 1, green: 0.69, blue: 0.27)
    static let green = Color(red: 0.52, green: 0.85, blue: 0.57)
    static let background = Color(uiColor: .systemBackground)
    static let surface = Color(uiColor: .secondarySystemBackground)
}

struct ConsoleMark: View {
    var body: some View {
        HStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 4).fill(Palette.accent).frame(width: 9, height: 23)
                .overlay(Circle().fill(.black.opacity(0.65)).frame(width: 4).offset(y: -4))
            RoundedRectangle(cornerRadius: 4).fill(Palette.accent).frame(width: 9, height: 23)
                .overlay(Circle().fill(.black.opacity(0.65)).frame(width: 4).offset(y: 4))
        }.accessibilityHidden(true)
    }
}
