import SwiftUI
import iSwitchCore
import GameController
import PhotosUI

struct SetupView: View {
    @EnvironmentObject private var model: LibraryModel
    private let command = "python3 scripts/iswitch.py prepare \"/path/to/Game\" --keys \"/path/to/prod.keys\" --xcode"
    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Image(systemName: "desktopcomputer.and.arrow.down").font(.largeTitle).foregroundStyle(Palette.accent)
                    Text("Prepare once. Play from home.").font(.title2.bold())
                    Text("nxnative turns your game files into an \(DevicePresentation.name) app on your Mac. reSwitch keeps those apps together in one library.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 12)
            }
            Section("Your \(DevicePresentation.name)") {
                Label("\(DevicePresentation.systemName) \(UIDevice.current.systemVersion)", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.green)
                #if targetEnvironment(simulator)
                Label("Simulator: game execution is unavailable", systemImage: "desktopcomputer").foregroundStyle(.secondary)
                #else
                Label(model.supportsGameGraphics ? "Required texture support available" : "Required texture support unavailable", systemImage: model.supportsGameGraphics ? "checkmark.circle.fill" : "exclamationmark.triangle")
                    .foregroundStyle(model.supportsGameGraphics ? Palette.green : Palette.orange)
                #endif
                Text("Upstream targets iPhone 15 Pro or newer with an A17 Pro or later chip, or an M1 or newer iPad, and iOS or iPadOS 26+. Individual games still need device testing.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("1 · Prepare on your Mac") {
                Text("Keep one game’s base NSP or XCI, updates, and DLC in a folder outside the source repository. Keep your own prod.keys on the Mac.")
                Text("Open “reSwitch Prepare.command” in the repository’s scripts folder. It checks your tools, then lets you choose the game folder and key file.")
                DisclosureGroup("Terminal command") {
                    Text(command).font(.caption.monospaced()).textSelection(.enabled)
                    Button("Copy command") { UIPasteboard.general.string = command }
                }
                Text("The Mac needs Xcode with the Metal toolchain, XcodeGen, .NET SDK 10, zstd, SPIRV-Cross, glslang, and the Python packages listed by the preparation tool. Allow about twice the game files’ size plus 10 GB of free storage.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("2 · Install the game app") {
                Text("Open the generated NxNative workspace in Xcode. Select the game’s scheme, your development team, and your \(DevicePresentation.name), then Run in Release. Keep the Increased Memory Limit entitlement enabled.")
                Text("Alternatively, prepare an unsigned IPA and sign it using your sideloading tool. The launcher opens directly installed apps; container-specific launch routing is not configured.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("3 · Add it to reSwitch") {
                Text("Transfer the generated .iswitch card to your \(DevicePresentation.name) using AirDrop or iCloud Drive. Open it in reSwitch, or choose Add games → Import game cards.")
                Text("Tap the game’s tile, then Start. The game opens to its own settings and Play screen. Use the iOS app switcher to return to reSwitch.")
                Button { model.panel = .add } label: { Label("Add games", systemImage: "plus.circle.fill") }
            }
            Section("Your saves & settings") {
                Text("Each game keeps its saves separately. In Files, open On My \(DevicePresentation.name) → the game’s folder to copy its save folder before replacing or removing a game app. Game settings, touch controls, and performance options live inside that game.")
                    .font(.subheadline)
                Text("Import and keep games, prod.keys, and firmware directly on your \(DevicePresentation.name) through Game Cards or Settings. Preparing a newly added raw game into an executable nxnative app still requires a Mac. Switch 2 game compatibility is not added by the menu design.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

struct ControllersView: View {
    @EnvironmentObject private var model: LibraryModel
    var body: some View {
        List {
            Section {
                VStack(spacing: 15) {
                    Image(systemName: "gamecontroller.fill").font(.system(size: 70, weight: .light)).foregroundStyle(Palette.green)
                    Text(model.controllerNames.isEmpty ? "Bring your favorite controller." : "Ready to navigate.").font(.title2.bold()).multilineTextAlignment(.center)
                    Text(model.controllerNames.isEmpty ? "Pair a compatible controller in \(DevicePresentation.name) Settings → Bluetooth, then come back here." : "Use the D-pad or left stick to browse games. Press Down for the menu, and Up to return to your games.")
                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity).padding(.vertical, 24)
            }
            Section("Connected") {
                if model.controllerNames.isEmpty { Text("No controller connected").foregroundStyle(.secondary) }
                ForEach(Array(model.controllerNames.enumerated()), id: \.offset) { _, name in Label(name, systemImage: "checkmark.circle.fill").foregroundStyle(Palette.green) }
            }
            Section {
                LabeledContent("Left / right", value: "Browse games or menu")
                LabeledContent("Down / up", value: "Menu / games")
                LabeledContent("A / primary button", value: "Open selection")
                LabeledContent("Y / Menu button", value: "All software")
                LabeledContent("B / secondary button", value: "Back")
            } header: { Text("Home controls") } footer: { Text("Button labels follow Apple’s controller mapping. Lists and settings also support touch and iOS accessibility navigation. Inside a game, nxnative handles touch controls and the controller.") }
        }.onAppear { model.updateControllers() }
    }
}

struct ProfileView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @AppStorage("playerName") private var playerName = "Player"
    @EnvironmentObject private var model: LibraryModel
    @State private var selection: PhotosPickerItem?
    @State private var loadingPhoto = false
    @State private var photoError: String?
    var body: some View {
        let photoButtonTitle = model.profilePhoto == nil ? "Choose photo" : "Change photo"
        Form {
            Section("Profile photo") {
                let layout = textSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 18))
                    : AnyLayout(HStackLayout(spacing: 18))
                layout {
                    Group {
                        if let photo = model.profilePhoto { Image(uiImage: photo).resizable().scaledToFill() }
                        else { Text(String(playerName.prefix(1)).uppercased()).font(.system(size: 30, weight: .medium)).foregroundStyle(.white) }
                    }.frame(width: 80, height: 80).background(Palette.accent, in: Circle()).clipShape(Circle())
                    VStack(alignment: .leading, spacing: 10) {
                        PhotosPicker(selection: $selection, matching: .images) { Label(photoButtonTitle, systemImage: "photo") }
                            .accessibilityIdentifier("chooseProfilePhoto").disabled(loadingPhoto)
                        if loadingPhoto { ProgressView("Saving photo…") }
                        if model.profilePhoto != nil { Button("Remove photo", role: .destructive) { Task { await model.removeProfilePhoto() } }.font(.subheadline).disabled(loadingPhoto) }
                    }
                }.padding(.vertical, 8)
                if let photoError { Text(photoError).font(.footnote).foregroundStyle(Palette.orange) }
                Text("Your photo stays in reSwitch on this \(DevicePresentation.name). You can change or remove it at any time.").font(.footnote).foregroundStyle(.secondary)
            }
            Section {
                TextField("Display name", text: $playerName).textContentType(.nickname).submitLabel(.done)
                    .onChange(of: playerName) { _, new in if new.count > 30 { playerName = String(new.prefix(30)) } }
            } header: { Text("Make it yours") } footer: { Text("Your profile stays on this device. It is independent of each game’s player and save data.") }
            Section("Your collection") {
                LabeledContent("Games", value: "\(model.games.count)")
                LabeledContent("Favorites", value: "\(model.games.filter(\.isFavorite).count)")
                LabeledContent("Apps opened", value: "\(model.games.filter { $0.lastOpenedAt != nil }.count)")
            }
        }.onDisappear { if playerName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { playerName = "Player" } }
        .task(id: selection) {
            guard let selection else { return }
            loadingPhoto = true; photoError = nil
            defer { loadingPhoto = false }
            do {
                guard let selected = try await selection.loadTransferable(type: SelectedProfilePhoto.self) else { return }
                defer { try? FileManager.default.removeItem(at: selected.url) }
                try Task.checkCancellation()
                try await model.setProfilePhoto(selected.url)
            } catch is CancellationError {} catch { photoError = error.localizedDescription }
        }
    }
}

private struct ShareItems: Identifiable { let id = UUID(); let urls: [URL] }
struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: urls, applicationActivities: nil) }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

/// Keep navigation labels independent of the brand tint. Small red text on the
/// dark grouped-list surface does not have enough contrast for normal reading.
struct SettingsRow: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            if !textSize.isAccessibilitySize {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 36, height: 36)
                    .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body).foregroundStyle(.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }.fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct SettingsView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    @EnvironmentObject private var model: LibraryModel
    @Binding var importing: Bool
    @AppStorage("playerName") private var playerName = "Player"
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage("haptics") private var haptics = true
    @AppStorage("performanceHUD") private var performanceHUD = false

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    ProfileView().navigationTitle("Your profile").toolbar { PanelDoneToolbar() }
                } label: {
                    let layout = textSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                        : AnyLayout(HStackLayout(spacing: 14))
                    layout {
                        Group {
                            if let photo = model.profilePhoto { Image(uiImage: photo).resizable().scaledToFill() }
                            else { Text(String(playerName.prefix(1)).uppercased()).font(.system(size: 24, weight: .medium)).foregroundStyle(.white) }
                        }.frame(width: 52, height: 52).background(Palette.accent, in: Circle()).clipShape(Circle()).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(playerName).font(.headline).foregroundStyle(.primary)
                            Text("Profile photo and display name").font(.subheadline).foregroundStyle(.secondary)
                        }.fixedSize(horizontal: false, vertical: true)
                    }.padding(.vertical, 6)
                }.accessibilityIdentifier("settingsProfile")
            }
            Section("Gameplay") {
                if textSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 12) {
                        performanceLabel
                        Toggle("Performance HUD", isOn: $performanceHUD).labelsHidden()
                            .tint(Palette.accent).accessibilityIdentifier("performanceHUD")
                    }
                } else {
                    Toggle(isOn: $performanceHUD) { performanceLabel }
                        .tint(Palette.accent).accessibilityIdentifier("performanceHUD")
                }
                NavigationLink {
                    ControllersView().navigationTitle("Controllers").toolbar { PanelDoneToolbar() }
                } label: { SettingsRow(title: "Controllers", subtitle: "Connected controllers and button controls", symbol: "gamecontroller") }
                Button { model.panel = .gameChat } label: {
                    HStack {
                        SettingsRow(title: "Chat", subtitle: "Open your friends, text and voice chats", symbol: "person.2.wave.2")
                        Image(systemName: "arrow.up.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Games & saves") {
                NavigationLink {
                    SourceFilesView().navigationTitle("Files & imports").toolbar { PanelDoneToolbar() }
                } label: { SettingsRow(title: "Files & imports", subtitle: "Games, prod.keys and firmware", symbol: "folder") }
                    .accessibilityIdentifier("settingsImports")
                NavigationLink {
                    AddGamesView(importing: $importing).navigationTitle("Add games").toolbar { PanelDoneToolbar() }
                } label: { SettingsRow(title: "Add games to HOME", subtitle: "Game cards and installed game apps", symbol: "plus.rectangle") }.accessibilityIdentifier("settingsAddGames")
                NavigationLink { CloudSavesView() } label: {
                    SettingsRow(title: "iCloud saves", subtitle: "Back up and restore your progress", symbol: "icloud")
                }.accessibilityIdentifier("cloudSavesSettings")
                NavigationLink { LibrarySettingsView() } label: {
                    SettingsRow(title: "Manage library", subtitle: "Export cards, preview and recovery", symbol: "square.stack")
                }.accessibilityIdentifier("librarySettings")
            }
            Section("Appearance & feel") {
                Picker(selection: $appearance) {
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                    Text("System").tag("system")
                } label: { Label("Appearance", systemImage: "circle.lefthalf.filled").foregroundStyle(.primary) }
                    .accessibilityIdentifier("appearancePicker")
                Toggle(isOn: $haptics) { Label("Selection haptics", systemImage: "hand.tap").foregroundStyle(.primary) }
                    .tint(Palette.accent)
            }
            Section("Help & about") {
                NavigationLink {
                    SetupView().navigationTitle("Getting started").toolbar { PanelDoneToolbar() }
                } label: { SettingsRow(title: "Getting started", subtitle: "Game preparation and playing on \(DevicePresentation.name)", symbol: "questionmark.circle") }
                NavigationLink { AboutSwitchView() } label: {
                    SettingsRow(title: "About reSwitch", subtitle: AboutSwitchView.version, symbol: "info.circle")
                }
            }
        }.tint(.primary)
    }

    private var performanceLabel: some View {
        SettingsRow(title: "Performance HUD", subtitle: "Frame rate, GPU timing and memory. Applies when opening or resuming a game.", symbol: "gauge.with.dots.needle.67percent")
    }
}

private struct LibrarySettingsView: View {
    @EnvironmentObject private var model: LibraryModel
    @State private var sharing: ShareItems?
    @State private var resetting = false
    @State private var exporting = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Games in your library", value: "\(model.games.count)")
                Button {
                    exporting = true
                    Task {
                        await model.exportLibrary()
                        if let url = model.exportURL { sharing = ShareItems(urls: [url]) }
                        exporting = false
                    }
                } label: { Label(exporting ? "Preparing export…" : "Export game cards", systemImage: "square.and.arrow.up").foregroundStyle(.primary) }
                    .disabled(model.games.isEmpty || exporting)
            } header: { Text("Game cards") } footer: {
                Text("Export names, covers and launch links to share or keep a backup. Game files, keys, saves and favorites are stored separately.")
            }
            Section {
                Button { model.togglePreview(); model.panel = nil } label: {
                    Label(model.isPreview ? "Exit layout preview" : "Preview the home screen", systemImage: "rectangle.grid.1x2").foregroundStyle(.primary)
                }
            } footer: { Text("Try the HOME layout with sample cards. Your own library stays unchanged.") }
            Section {
                Button {
                    let urls = (try? FileManager.default.contentsOfDirectory(at: model.directory, includingPropertiesForKeys: nil))?.filter { $0.pathExtension == "json" } ?? []
                    if urls.isEmpty { model.notice = AppNotice(title: "No recovery files", message: "There are no library files to share yet.") }
                    else { sharing = ShareItems(urls: urls) }
                } label: { Label("Share recovery files", systemImage: "doc.badge.clock").foregroundStyle(.primary) }
                Button("Reset library…", role: .destructive) { resetting = true }
            } header: { Text("Recovery") } footer: {
                Text("A previous copy is kept when the library changes. Resetting keeps recovery files and leaves installed games and saves untouched.")
            }
        }
        .navigationTitle("Manage library").toolbar { PanelDoneToolbar() }
        .sheet(item: $sharing) { item in ShareSheet(urls: item.urls) }
        .confirmationDialog("Start a new empty library?", isPresented: $resetting, titleVisibility: .visible) {
            Button("Reset library", role: .destructive) { Task { await model.resetLibrary() } }
        } message: { Text("Existing library files will be kept for recovery. Installed game apps and saves are unaffected.") }
    }
}

private struct AboutSwitchView: View {
    static var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return "Version \(info["CFBundleShortVersionString"] as? String ?? "1.0") (\(info["CFBundleVersion"] as? String ?? "1"))"
    }

    var body: some View {
        Form {
            Section {
                Text("reSwitch").font(.title2.bold())
                Text(Self.version).foregroundStyle(.secondary)
                Text("A home for your nxnative game apps. Library browsing works offline.")
            }
            Section("Open source") {
                Link(destination: URL(string: "https://github.com/odestins/nxnative")!) {
                    Label("nxnative source fork", systemImage: "arrow.up.right.square").foregroundStyle(.primary)
                }
                NavigationLink("Open-source notices") { ScrollView { Text(licenses).font(.caption.monospaced()).textSelection(.enabled).padding() }.navigationTitle("Licenses").toolbar { PanelDoneToolbar() } }
                NavigationLink("Discord SDK notices") { ScrollView { Text(discordLicenses).font(.caption.monospaced()).textSelection(.enabled).padding() }.navigationTitle("Discord SDK").toolbar { PanelDoneToolbar() } }
            }
            Section {
                Text("Inspired by the Nintendo Switch home menu. An independent project, not affiliated with Nintendo. Nintendo Switch is a trademark of Nintendo.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }.navigationTitle("About reSwitch").toolbar { PanelDoneToolbar() }
    }

    private var licenses: String {
        guard let url = Bundle.main.url(forResource: "Notices", withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) else { return "nxnative is licensed under MIT. See the source repository for the full license and third-party notices." }
        return text
    }

    private var discordLicenses: String {
        guard let url = Bundle.main.url(forResource: "DiscordNotices", withExtension: "txt"), let text = try? String(contentsOf: url, encoding: .utf8) else { return "Discord Social SDK third-party notices are unavailable in this build." }
        return text
    }
}
