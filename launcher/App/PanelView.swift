import SwiftUI
import iSwitchCore
import GameController

struct PanelView: View {
    let panel: Panel
    @Binding var importing: Bool
    @EnvironmentObject private var model: LibraryModel
    var body: some View {
        Group {
            switch panel {
            case .add: AddGamesView(importing: $importing)
            case .library: AllSoftwareView()
            case .setup: SetupView()
            case .controllers: ControllersView()
            case .settings: SettingsView(importing: $importing)
            case .profile: ProfileView()
            case .details: if let game = model.selectedGame { GameDetailsView(game: game) } else { Text("Select a game first.") }
            case .sources: SourceFilesView()
            case .gameChat: GameChatView()
            case .store: StorePickerView()
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.iswitchGame, .iswitchLibrary], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): model.importFiles(urls)
            case .failure(let error): model.show(error)
            }
        }
    }
}

struct AddGamesView: View {
    @EnvironmentObject private var model: LibraryModel
    @Binding var importing: Bool
    @State private var search = ""
    var filtered: [CatalogGame] { model.catalog.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.id.localizedCaseInsensitiveContains(search) } }
    var body: some View {
        List {
            if search.isEmpty {
                Section {
                    NavigationLink { SourceFilesView().navigationTitle("Games, keys & firmware") } label: {
                        Label("Import games, prod.keys or firmware", systemImage: "square.and.arrow.down")
                    }.accessibilityIdentifier("importFromIPhone")
                    NavigationLink { ManualGameView(source: nil) {} } label: { Label("Add a game manually", systemImage: "plus.rectangle") }
                    Button { importing = true } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.isBusy ? "Importing game cards…" : "Import game cards").font(.headline)
                                Text("Choose .iswitch files from Files or iCloud Drive.").font(.subheadline).foregroundStyle(.secondary)
                            }.padding(.vertical, 7)
                        } icon: { Image(systemName: "square.and.arrow.down.fill").font(.title2).foregroundStyle(Palette.accent) }
                    }.accessibilityIdentifier("importCards").disabled(model.isBusy)
                    Button { model.panel = .setup } label: { Label("Playing imported games", systemImage: "play.circle") }
                } footer: {
                    Text("Add files directly from your \(DevicePresentation.name) or iCloud Drive. nxnative still needs Mac preparation before a new raw NSP/XCI can play. A prepared .iswitch card opens its installed game app.")
                }
            }
            Section {
                ForEach(filtered) { game in
                    HStack(spacing: 14) {
                        Image(systemName: "gamecontroller").font(.title3).foregroundStyle(.secondary).frame(width: 30)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(game.name).font(.subheadline.weight(.medium))
                            Text("Profile versions: \(game.versions.joined(separator: ", "))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 4)
                        if model.games.contains(where: { $0.id == game.id }) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green).accessibilityLabel("In your library")
                        } else {
                            Button { model.add(game) } label: { Image(systemName: "plus.circle").font(.title2) }
                                .buttonStyle(.borderless).accessibilityLabel("Add \(game.name) to preparation list")
                        }
                    }.padding(.vertical, 4)
                }
                if filtered.isEmpty { Text("No matching game profiles.").foregroundStyle(.secondary) }
            } header: { Text("Plan your library · \(model.catalog.count) profiles") }
            footer: { Text("These profiles come from nxnative. Compatibility is reported by the upstream project and depends on the game version and device. Adding a title here does not download it.") }
        }
        .searchable(text: $search, prompt: "Search games or title IDs")
    }
}

struct AllSoftwareView: View {
    @EnvironmentObject private var model: LibraryModel
    @State private var search = ""
    @State private var sort = LibrarySort.recent
    @State private var favorites = false
    var entries: [LibraryGame] { sort.sorted(model.games, search: search, favoritesOnly: favorites) }
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack {
                    Picker("Sort games", selection: $sort) { ForEach(LibrarySort.allCases, id: \.self) { Text($0.rawValue).tag($0) } }.pickerStyle(.menu)
                    Spacer()
                    Toggle("Favorites", isOn: $favorites).toggleStyle(.button).font(.subheadline)
                }.padding(.horizontal, 22)
                if entries.isEmpty {
                    ContentUnavailableView(search.isEmpty && !favorites ? "A home for your games" : "No matching games", systemImage: "square.grid.2x2", description: Text(search.isEmpty && !favorites ? "Import a game card or add a title to your preparation list." : "Try another search or show all games."))
                    if search.isEmpty && !favorites {
                        Button("Add games") { model.panel = .add }.buttonStyle(.borderedProminent)
                    } else {
                        Button("Show all games") { search = ""; favorites = false }.buttonStyle(.borderedProminent)
                    }
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 20)], spacing: 24) {
                        ForEach(entries) { game in
                            Button {
                                model.isPreview = false; model.select(game.id); model.panel = .details
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    CoverArt(game: game, directory: model.artworkDirectory).aspectRatio(1, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 7))
                                    Text(game.manifest.name).font(.subheadline.weight(.semibold)).lineLimit(2).foregroundStyle(.primary)
                                    Text(game.status).font(.caption).foregroundStyle(.secondary)
                                    if game.isFavorite { Image(systemName: "star.fill").font(.caption).foregroundStyle(Palette.orange) }
                                }
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 22)
                }
            }.padding(.vertical, 20)
        }.searchable(text: $search, prompt: "Search your library")
    }
}

struct GameDetailsView: View {
    let game: LibraryGame
    @EnvironmentObject private var model: LibraryModel
    @State private var confirmingRemove = false
    var current: LibraryGame { model.games.first { $0.id == game.id } ?? game }
    var body: some View {
        List {
            Section {
                VStack(spacing: 14) {
                    CoverArt(game: current, directory: model.artworkDirectory, preview: model.isPreview)
                        .frame(width: 170, height: 170).clipShape(RoundedRectangle(cornerRadius: 8))
                    Text(current.manifest.name).font(.title2.bold()).multilineTextAlignment(.center)
                    Text(model.isPreview ? "Original sample artwork · Layout preview" : current.status).font(.subheadline).foregroundStyle(.secondary)
                    Button { model.launch(current) } label: {
                        Label(current.manifest.buildState == .planned ? "Prepare this game" : "Open game", systemImage: "play.fill").frame(maxWidth: .infinity).padding(.vertical, 7)
                    }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity).padding(.vertical, 14)
            }
            if !model.isPreview {
                Section {
                    Button { model.favorite(current) } label: { Label(current.isFavorite ? "Remove from favorites" : "Add to favorites", systemImage: current.isFavorite ? "star.fill" : "star") }
                    LabeledContent("Game version", value: current.manifest.version)
                    LabeledContent("iOS required", value: current.manifest.minimumOS + "+")
                    LabeledContent("Compatibility", value: current.manifest.compatibility == .profiled ? "Upstream profile" : "Experimental")
                    if let last = current.lastOpenedAt { LabeledContent("Last opened", value: last.formatted(date: .abbreviated, time: .shortened)) }
                } footer: {
                    Text(current.manifest.compatibility == .experimental ? "This game or version has no matching tested profile. A successful build does not establish that it will play correctly." : "Opening an installed app is recorded here. Game progress and playtime are managed by the game app.")
                }
                Section("Game data") {
                    Text("Graphics, language, and touch controls are configured in the game app. Use Files → On My \(DevicePresentation.name) → the game’s folder to back up its save folder and retrieve log.txt.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Rebuild with the same app identifier to retain its data. Back up saves before deleting or reinstalling a game app.").font(.subheadline).foregroundStyle(.secondary)
                    LabeledContent("Title ID", value: current.id).font(.caption.monospaced())
                }
                Section {
                    Button("Remove from library", role: .destructive) { confirmingRemove = true }
                } footer: { Text("Removes this card only. The installed game and its saves stay on your \(DevicePresentation.name).") }
            }
        }.confirmationDialog("Remove \(current.manifest.name) from your library?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove card", role: .destructive) { model.remove(current) }
        }
    }
}
