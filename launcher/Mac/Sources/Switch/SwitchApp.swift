import SwiftUI
import AppKit
import GameController
import SwitchMacRuntime
import iSwitchCore

let switchRed = Color(red: 230 / 255, green: 0, blue: 18 / 255)

@main
struct SwitchMacApp: App {
    @NSApplicationDelegateAdaptor(SwitchDelegate.self) var delegate
    @StateObject private var model = MacModel.shared
    @StateObject private var chat = GameChatService.forLaunch()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        Window("reSwitch", id: "home") {
            HomeView().environmentObject(model).environmentObject(chat)
                .preferredColorScheme(.dark).tint(switchRed)
                .frame(minWidth: 800, minHeight: 620)
                 .task { model.startControllers(); await chat.restore() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh(); chat.setActive(true) }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in chat.setActive(false) }
                .onChange(of: model.runningID) { _, _ in chat.setActivity(model.running.map { "Playing " + $0.manifest.name } ?? "In reSwitch") }
                .onChange(of: model.panel) { _, panel in chat.setVisible(panel == .chat) }
                .onOpenURL { url in
                    if let code = GameChatRules.inviteURL(url.absoluteString) { chat.pendingInvite = code; model.panel = .chat }
                }
        }
        .defaultSize(width: 1180, height: 780)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { Button("Add Prepared Game…", action: model.importPreparedGame).keyboardShortcut("o") }
            CommandGroup(replacing: .appSettings) { Button("Settings…") { model.panel = .settings }.keyboardShortcut(",") }
            CommandMenu("Game") {
                Button(model.runningID == model.selectedID ? "Return to Game" : "Start Game", action: model.launch)
                    .keyboardShortcut(.return, modifiers: .command).disabled(model.selected == nil)
                Button("Close Running Game…", action: model.stop).disabled(model.runningID == nil)
                Divider()
                Button("Controllers & Keyboard") { model.panel = .controllers }
                Button("Refresh Library") { model.refresh() }.keyboardShortcut("r")
            }
        }
    }
}

@MainActor
final class SwitchDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard MacModel.shared.runningID != nil else { return .terminateNow }
        let alert = NSAlert(); alert.messageText = "A game is still running"
        alert.informativeText = "Close the game from its window, or use Game → Close Running Game before quitting reSwitch."
        alert.addButton(withTitle: "Keep reSwitch Open"); alert.runModal()
        return .terminateCancel
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { sender.windows.first { $0.title == "reSwitch" }?.makeKeyAndOrderFront(nil) }
        return true
    }
}

struct HomeView: View {
    @EnvironmentObject private var model: MacModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var homeFocused: Bool
    @EnvironmentObject private var chat: GameChatService
    @AppStorage("playerName") private var playerName = "Player"
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.height < 740
            let cardSize = min(250.0, max(144.0, geometry.size.height * (compact ? 0.25 : 0.30)))
            VStack(spacing: 0) {
                header.padding(.horizontal, 38).padding(.top, compact ? 20 : 38)
                Spacer(minLength: compact ? 12 : 22)
                if model.isLoading && model.games.isEmpty {
                    ProgressView("Loading your library…").frame(maxWidth: .infinity, minHeight: cardSize + 150)
                } else {
                    VStack(alignment: .leading, spacing: compact ? 12 : 20) {
                        HStack {
                            Label(model.selected?.manifest.name ?? "Your games, ready to play", systemImage: ReSwitchBrand.controllerSymbol)
                                .font(.system(size: 26, weight: .semibold)).foregroundStyle(switchRed)
                                .lineLimit(1).minimumScaleFactor(0.75).accessibilityIdentifier("selectedGameName")
                            Spacer()
                            Text("\(model.games.count) games").font(.callout).foregroundStyle(.secondary)
                        }.padding(.horizontal, 40)
                        ScrollViewReader { proxy in
                            ScrollView(.horizontal) {
                                LazyHStack(spacing: 22) {
                                    ForEach(model.games) { game in
                                        GameCard(game: game, size: cardSize).id(game.id)
                                    }
                                    Button(action: model.importPreparedGame) {
                                        VStack(spacing: 12) { Image(systemName: "plus.circle").font(.system(size: 40, weight: .light)); Text("Add Game").font(.headline) }
                                            .foregroundStyle(.secondary).frame(width: cardSize, height: cardSize)
                                            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 18))
                                            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.white.opacity(0.12), style: StrokeStyle(lineWidth: 1, dash: [6])))
                                    }.buttonStyle(.plain).help("Add an already prepared Mac game")
                                }.padding(.horizontal, 40).padding(.vertical, 8)
                            }.scrollIndicators(.hidden).frame(height: cardSize + 24)
                            .onChange(of: model.selectedID) { _, id in
                                if let id { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) } }
                            }
                        }
                        HStack(alignment: .top, spacing: 18) {
                            if let game = model.selected {
                                VStack(alignment: .leading, spacing: 7) {
                                    HStack(spacing: 10) {
                                        Circle().fill(model.problems[game.id] == nil ? Color.green : Color.orange).frame(width: 7, height: 7)
                                        Text(model.runningID == game.id ? "Running" : model.problems[game.id] ?? "Ready on this Mac").fontWeight(.medium)
                                        Text("·  v\(game.manifest.version)").foregroundStyle(.secondary)
                                    }.font(.callout)
                                    Text(game.notes).font(.callout).foregroundStyle(.secondary).lineLimit(compact ? 1 : 3)
                                        .fixedSize(horizontal: false, vertical: true).help(game.notes)
                                }
                                Spacer(minLength: 10)
                                Button(action: model.launch) {
                                    Label(model.problems[game.id] != nil ? "Unavailable" : model.isLaunching ? "Starting…" : model.runningID == game.id ? "Return to Game" : "Start Game",
                                          systemImage: model.problems[game.id] != nil ? "exclamationmark.circle" : "play.fill")
                                        .font(.headline).padding(.horizontal, 18).padding(.vertical, 9)
                                }.buttonStyle(.borderedProminent).tint(model.problems[game.id] == nil ? switchRed : .gray)
                                    .disabled(model.problems[game.id] != nil || model.isLaunching)
                                    .accessibilityIdentifier("start-game")
                            }
                        }.frame(minHeight: compact ? 52 : 72, alignment: .topLeading).padding(.horizontal, 40)
                    }
                }
                Spacer(minLength: compact ? 12 : 22)
                dock(compact: compact)
                MacChatMiniBar()
                if let running = model.running {
                    HStack(spacing: 12) {
                        Circle().fill(.green).frame(width: 7, height: 7)
                        Text("Playing \(running.manifest.name)").lineLimit(1)
                        Button("Close Game…", action: model.stop).buttonStyle(.link).tint(.white)
                    }.font(.callout).padding(.top, compact ? 10 : 16)
                }
                footer.padding(.horizontal, 40).padding(.top, compact ? 16 : 28).padding(.bottom, compact ? 16 : 24)
            }
            .background(Color(white: 0.105))
        }
        .focusable().focusEffectDisabled().focused($homeFocused)
        .onAppear { homeFocused = true }
        .onChange(of: model.panel) { _, panel in if panel == nil { homeFocused = true } }
        .sheet(item: $model.panel) { panel in
            Group { if panel == .chat { MacChatPanel() } else { MacPanelView(panel: panel) } }
                .environmentObject(model).environmentObject(chat).preferredColorScheme(.dark).tint(switchRed)
        }
        .alert("reSwitch", isPresented: Binding(get: { model.message != nil }, set: { if !$0 { model.message = nil } })) {
            Button("OK", role: .cancel) { model.message = nil }
        } message: { Text(model.message ?? "") }
        .onKeyPress(.leftArrow) { move(.left) }
        .onKeyPress(.rightArrow) { move(.right) }
        .onKeyPress(.upArrow) { move(.up) }
        .onKeyPress(.downArrow) { move(.down) }
        .onKeyPress(.return) {
            guard model.panel == nil, model.message == nil, !model.isLaunching else { return .ignored }
            model.controllerConfirm(); return .handled
        }
        .onKeyPress(.escape) {
            guard model.panel == nil, model.focusedDock != nil else { return .ignored }
            model.controllerBack(); return .handled
        }
    }

    private func move(_ direction: ControllerNavigation.Direction) -> KeyPress.Result {
        guard model.panel == nil, model.message == nil, !model.isLaunching else { return .ignored }
        model.controllerMove(direction); return .handled
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { model.panel = .profile } label: {
                Group {
                    if let photo = model.photo { Image(nsImage: photo).resizable().scaledToFill() }
                    else { Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.white.opacity(0.7)) }
                }.frame(width: 48, height: 48).clipShape(Circle()).overlay(Circle().stroke(.white.opacity(0.16), lineWidth: 3))
            }.buttonStyle(.plain).help("Edit profile name and photo").accessibilityLabel("Your profile")
            VStack(alignment: .leading, spacing: 3) {
                Text(playerName).font(.system(size: 20, weight: .semibold)).lineLimit(1)
                Text("HOME").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(.secondary)
            }
            Spacer()
            TimelineView(.periodic(from: .now, by: 60)) { timeline in Text(timeline.date, format: .dateTime.hour().minute()).font(.system(size: 21, weight: .medium, design: .rounded)).monospacedDigit() }
            Image(systemName: "desktopcomputer").font(.title3).padding(.leading, 12).accessibilityLabel("Mac")
        }
    }

    private func dock(compact: Bool) -> some View {
        HStack(spacing: 22) {
            dockButton(0, "Chat", icon: "c.square", color: .orange) { model.panel = .chat }
            dockButton(1, "Store", icon: "bag", color: Color(red: 0.9, green: 0.3, blue: 0.27)) { model.panel = .store }
            dockButton(2, "Controllers", icon: ReSwitchBrand.controllerSymbol, color: Color(white: 0.75)) { model.panel = .controllers }
            dockButton(3, "Game Library", icon: ReSwitchBrand.librarySymbol, color: Color(white: 0.75)) { model.panel = .library }
            dockButton(4, "Settings", icon: "gearshape", color: Color(white: 0.75)) { model.panel = .settings }
            dockButton(5, "Quit reSwitch", icon: "power", color: Color(white: 0.75), action: model.quit)
        }
        .padding(.horizontal, 27).padding(.vertical, compact ? 10 : 16)
        .glassEffect(.regular, in: Capsule())
    }

    private func dockButton(_ index: Int, _ title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 30, weight: .regular)).foregroundStyle(color).frame(width: 54, height: 48).contentShape(Rectangle()) }
            .buttonStyle(.plain).help(title).accessibilityLabel(title)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(model.focusedDock == index ? switchRed : .clear, lineWidth: 2))
            .accessibilityValue(model.focusedDock == index ? "Selected" : "")
    }

    private var footer: some View {
        HStack {
            Label("Native on Apple silicon", systemImage: "cpu").foregroundStyle(.secondary)
            Spacer()
            Label("Browse", systemImage: "arrow.up.and.down.and.arrow.left.and.right").foregroundStyle(.secondary)
            Text("⌘ Return  Start").foregroundStyle(.secondary).padding(.leading, 16)
        }.font(.callout)
    }
}

private struct CoverRequestID: Equatable {
    let source: String?
    let visible: Bool
    let cached: Bool
}

struct GameCard: View {
    @EnvironmentObject var model: MacModel
    let game: PreparedGame
    let size: CGFloat
    var body: some View {
        Button { model.select(game) } label: {
            ZStack(alignment: .bottomLeading) {
                if let cover = model.covers[game.id] { Image(nsImage: cover).resizable().scaledToFill() }
                else { Rectangle().fill(.gray.opacity(0.2)).overlay(Text(game.manifest.name).font(.title2).padding()) }
                if !game.playable {
                    Text("NOT PLAYABLE YET").font(.system(size: 10, weight: .bold)).tracking(0.8)
                        .padding(10).frame(maxWidth: .infinity).background(.black.opacity(0.8))
                }
            }.frame(width: size, height: size).clipped().clipShape(RoundedRectangle(cornerRadius: 14))
                .padding(4).overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(model.selectedID == game.id ? switchRed : .clear, lineWidth: 3))
        }.buttonStyle(.plain).accessibilityLabel(game.manifest.name).accessibilityAddTraits(model.selectedID == game.id ? .isSelected : [])
        .task(id: CoverRequestID(source: game.manifest.artworkBase64, visible: model.panel == nil, cached: model.covers[game.id] != nil)) {
            guard model.panel == nil else { return }
            await model.loadCover(game)
        }
        .contextMenu {
            Button("Start Game") { model.select(game); model.launch() }.disabled(model.problems[game.id] != nil)
            Button("Show Game Folder") { NSWorkspace.shared.open(game.rootURL) }
            Button("Show Saves") { NSWorkspace.shared.open(game.playerDirectory) }
            Button("Relink Folder…") { model.relink(game) }
            Divider()
            Button("Remove Card…", role: .destructive) { model.remove(game) }
        }
    }
}

struct MacPanelView: View {
    @EnvironmentObject var model: MacModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("performanceHUD") private var hud = false
    @AppStorage("fullscreen") private var fullscreen = false
    @AppStorage("keyboardOwnPlayer") private var keyboardOwnPlayer = false
    @State private var search = ""
    let panel: MacPanel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(panel.rawValue).font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    switch panel {
                    case .settings: settings
                    case .controllers: controllers
                    case .library: library
                    case .chat: EmptyView()
                    case .store: StorePickerView()
                    case .profile: MacProfileEditor()
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
        }.frame(width: 660, height: 560).background(Color(white: 0.12))
    }

    private var settings: some View {
        Group {
            section("Game display") {
                Toggle("Show performance HUD", isOn: $hud)
                Toggle("Start games in full screen", isOn: $fullscreen)
                Text("Changes apply the next time you start a game. You can also use Control–Command–F in a game to enter or leave full screen.").font(.callout).foregroundStyle(.secondary)
            }
            section("Profile") { Button("Edit Name and Photo…") { model.panel = .profile }.tint(.white) }
            section("Saves on this Mac") {
                Text("Games save locally in their prepared folder under MacPlayer/save. These saves are separate from your iPhone and iPad; Mac iCloud save sync is not enabled.").foregroundStyle(.secondary)
                if let game = model.selected { Button("Show \(game.manifest.name) Save Folder") { NSWorkspace.shared.open(game.playerDirectory) }.tint(.white) }
            }
            section("Troubleshooting") {
                Button("Refresh Game Availability", action: model.refresh).tint(.white)
                if let log = model.latestLog { Button("Open Latest Game Log") { NSWorkspace.shared.open(log) }.tint(.white) }
                Button("Show Library Configuration") { NSWorkspace.shared.open(model.directory) }.tint(.white)
                Text("reSwitch keeps the last 10 launch logs for each game. Removing a card does not delete game data or saves.").font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private var controllers: some View {
        Group {
            section("Game controllers") {
                ForEach(Array(model.controllerNames.enumerated()), id: \.offset) { _, name in Label(name, systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                if model.controllerNames.isEmpty { Text("No controller connected").foregroundStyle(.secondary) }
                Text("HOME: use the D-pad or left stick to browse games. Down selects the menu; Up returns to games. On DualSense, Cross opens/starts, Circle goes back, and Options opens your library.").foregroundStyle(.secondary)
                Text("Connect a controller through Bluetooth or USB before starting a game. Controls use Nintendo button positions: right is A, bottom is B. A controller is recommended for games that need the right stick.").foregroundStyle(.secondary)
                Button("Open Bluetooth Settings") { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!) }.tint(.white)
                Toggle("Keep keyboard as a separate player", isOn: $keyboardOwnPlayer)
                Text("Off: keyboard and the first controller share player 1. On: controllers start at player 2. Local multiplayer still depends on the game.").font(.callout).foregroundStyle(.secondary)
            }
            section("Keyboard controls") {
                Grid(alignment: .leading, horizontalSpacing: 34, verticalSpacing: 12) {
                    mapping("Move", "W A S D")
                    mapping("D-pad", "Arrow keys")
                    mapping("A / B / X / Y", "J / K / U / I")
                    mapping("L / R · ZL / ZR", "Q / E · Z / C")
                    mapping("Press left / right stick", "F / G")
                    mapping("Plus / Minus", "Return / Tab")
                    mapping("Shake / Touch", "Space / Mouse click")
                }
            }
        }
    }

    private func mapping(_ label: String, _ keys: String) -> some View {
        GridRow { Text(label).foregroundStyle(.secondary); Text(keys).font(.system(.body, design: .monospaced)) }
    }

    private var library: some View {
        let entries = model.games.filter { search.isEmpty || $0.manifest.name.localizedCaseInsensitiveContains(search) }
        return Group {
            HStack {
                TextField("Search your games", text: $search).textFieldStyle(.roundedBorder)
                Button("Add Game…", action: model.importPreparedGame).tint(.white)
            }
            if entries.isEmpty {
                ContentUnavailableView(model.games.isEmpty ? "Your library is empty" : "No matching games", systemImage: "square.stack",
                    description: Text(model.games.isEmpty ? "Add a prepared Mac game to get started." : "Try a different title or clear your search."))
                if !search.isEmpty { Button("Clear Search") { search = "" }.tint(.white) }
            }
            LazyVStack(alignment: .leading, spacing: 14) {
                ForEach(entries) { game in
                    HStack(spacing: 14) {
                        Group {
                            if let cover = model.covers[game.id] { Image(nsImage: cover).resizable().scaledToFill() }
                            else { Rectangle().fill(.gray.opacity(0.2)).overlay(Image(systemName: "gamecontroller").foregroundStyle(.secondary)) }
                        }.frame(width: 54, height: 54).clipShape(RoundedRectangle(cornerRadius: 7)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(game.manifest.name).font(.headline)
                            Text(model.problems[game.id] ?? "Ready on this Mac").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Select") { model.select(game); dismiss() }.tint(.white)
                        Menu {
                            Button("Show Game Folder") { NSWorkspace.shared.open(game.rootURL) }
                            Button("Relink Folder…") { model.relink(game) }
                            Button("Remove Card…", role: .destructive) { model.remove(game) }
                        } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 26).accessibilityLabel("Options for \(game.manifest.name)")
                    }.task(id: CoverRequestID(source: game.manifest.artworkBase64, visible: model.panel == .library, cached: model.covers[game.id] != nil)) {
                        guard model.panel == .library else { return }
                        await model.loadCover(game)
                    }
                    Divider()
                }
            }
            Text("Add Game accepts prepared Mac packages. Adding an NSP or XCI alone cannot make an unsupported game playable.").font(.callout).foregroundStyle(.secondary)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) { Text(title).font(.headline); content() }
            .frame(maxWidth: .infinity, alignment: .leading).padding(18).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
    }
}
