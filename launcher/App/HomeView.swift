import SwiftUI
import iSwitchCore

struct HomeView: View {
    @EnvironmentObject private var model: LibraryModel
    @EnvironmentObject private var chat: GameChatService
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage("playerName") private var playerName = "Player"
    @StateObject private var status = ConsoleStatus()
    @State private var importing = false

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width > geometry.size.height
            let height = geometry.size.height
            // Use the available window, so a narrow iPad window keeps the compact layout.
            let roomy = min(geometry.size.width, height) >= 600
            let landscapeDockHeight = max(44, min(46, max(36, height * 0.11))) + 14
            // Reserve full-size controls before sizing covers in a short landscape window.
            let landscapeTile = max(64, height - landscapeDockHeight - 180 - (chat.inParty ? 58 : 0))
            let tile = roomy ? min(250, max(180, min(height, geometry.size.width) * 0.26))
                : wide ? min(260, landscapeTile) : min(190, geometry.size.width * 0.44)
            VStack(spacing: 0) {
                header(wide: wide, roomy: roomy).padding(.top, roomy ? 32 : wide ? 6 : 20)
                Spacer(minLength: wide && !roomy ? 8 : 12)
                if let error = model.libraryError {
                    ContentUnavailableView {
                        Label("Library needs attention", systemImage: "externaldrive.badge.exclamationmark")
                    } description: { Text(error) } actions: {
                        Button("Open recovery settings") { model.panel = .settings }.buttonStyle(.borderedProminent)
                    }
                } else if !model.loaded {
                    ProgressView().frame(maxWidth: .infinity, minHeight: tile)
                } else {
                    gameRow(tile: tile, wide: wide, roomy: roomy)
                }
                Spacer(minLength: wide ? 8 : 28)
                VStack(spacing: roomy ? 18 : wide ? 8 : 14) {
                    dock(wide: wide, roomy: roomy, size: geometry.size)
                    if chat.inParty { GameChatMiniBar().frame(maxWidth: roomy ? 548 : .infinity) }
                }
                Spacer(minLength: wide ? 8 : 22)
                    // Keep spare height above the dock, not between it and the footer.
                    .frame(maxHeight: roomy ? 48 : wide ? 8 : 32)
                footer(wide: wide, roomy: roomy).padding(.bottom, roomy ? 24 : wide ? 8 : 20)
            }
            .background((scheme == .dark ? Color(white: 0.117) : Color(white: 0.925)).ignoresSafeArea())
        }
        .statusBarHidden()
        .sheet(item: $model.panel) { panel in
            NavigationStack {
                PanelView(panel: panel, importing: $importing)
                    .navigationTitle(panel.title).navigationBarTitleDisplayMode(.inline)
                    .toolbar { PanelDoneToolbar() }
            }
            .preferredColorScheme(appearance == "system" ? nil : appearance == "light" ? .light : .dark)
            .tint(panel == .settings ? Color.primary : Palette.accent)
            .alert(item: $model.notice) { notice in Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK"))) }
            .presentationDragIndicator(.visible).interactiveDismissDisabled(model.importingSource)
        }
        .onChange(of: model.panel) { _, panel in chat.setVisible(panel == .gameChat) }
        .onChange(of: chat.notice) { _, message in
            if let message { model.notice = AppNotice(title: "Chat", message: message); chat.notice = nil }
        }
        .alert(item: Binding(get: { model.panel == nil ? model.notice : nil }, set: { model.notice = $0 })) { notice in Alert(title: Text(notice.title), message: Text(notice.message), dismissButton: .default(Text("OK"))) }
        .overlay(alignment: .top) {
            if model.isBusy { HStack { ProgressView(); Text("Importing game cards…") }.font(.subheadline).padding(14).background(.regularMaterial, in: Capsule()).padding(.top, 20) }
        }
    }

    private func header(wide: Bool, roomy: Bool) -> some View {
        HStack {
            Button { model.panel = .profile } label: {
                Group {
                    if let photo = model.profilePhoto { Image(uiImage: photo).resizable().scaledToFill() }
                    else { Text(String(playerName.prefix(1)).uppercased()).font(.system(size: roomy ? 24 : wide ? 18 : 20, weight: .semibold)).foregroundStyle(.white) }
                }.frame(width: roomy ? 52 : wide ? 35 : 42, height: roomy ? 52 : wide ? 35 : 42)
                    .background(Palette.accent, in: Circle())
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.20), lineWidth: 3))
            }.frame(minWidth: 44, minHeight: 44).accessibilityLabel("Your profile")
            Spacer()
            TimelineView(.periodic(from: .now, by: 60)) { timeline in
                HStack(spacing: 11) {
                    Text(timeline.date, format: .dateTime.hour().minute()).monospacedDigit()
                    Image(systemName: status.networkSymbol).font(.system(size: roomy ? 20 : wide ? 14 : 16, weight: .semibold)).accessibilityLabel(status.networkLabel)
                    if status.battery >= 0 {
                        Text("\(Int(status.battery * 100))%").monospacedDigit()
                        Image(systemName: status.batterySymbol).font(.system(size: roomy ? 28 : wide ? 20 : 23))
                    }
                }.font(.system(size: roomy ? 24 : wide ? 17 : 19, weight: .medium)).foregroundStyle(.primary.opacity(0.85))
            }
        }.padding(.horizontal, roomy ? 44 : wide ? 26 : 24)
    }

    private func gameRow(tile: CGFloat, wide: Bool, roomy: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: ReSwitchBrand.controllerSymbol).font(.system(size: 20, weight: .bold)).accessibilityHidden(true)
                Text(model.selectedGame?.manifest.name ?? "Add software")
                    .font(.system(size: roomy ? 28 : wide ? 18 : 23, weight: .medium)).lineLimit(1).minimumScaleFactor(0.6)
                    .accessibilityIdentifier("selectedGameName")
                Spacer()
                if model.isPreview { Button("Exit preview") { model.togglePreview() }.font(.caption).accessibilityIdentifier("exitPreview") }
            }.foregroundStyle(Palette.accent).padding(.horizontal, roomy ? 48 : wide ? 48 : 26)
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: roomy ? 16 : 8) {
                        if model.visibleGames.isEmpty {
                            Button { model.panel = .add } label: {
                                VStack(spacing: 12) { Image(systemName: "plus").font(.system(size: 40, weight: .ultraLight)); Text("Add games").font(.headline) }
                                    .foregroundStyle(.primary.opacity(0.7)).frame(width: tile, height: tile)
                                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                                    .padding(4).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.accent, lineWidth: 2.5))
                            }.buttonStyle(.plain).accessibilityIdentifier("addGamesPrimary")
                            ForEach(0..<4) { _ in RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(0.025)).overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.055), lineWidth: 1.5)).frame(width: tile, height: tile).accessibilityHidden(true) }
                        } else {
                            ForEach(model.visibleGames) { game in gameTile(game, size: tile).id(game.id) }
                            Button { model.panel = .library } label: {
                                VStack(spacing: 12) { Image(systemName: "square.grid.3x3.fill").font(.system(size: 34)); Text("All Software").font(.subheadline) }
                                    .foregroundStyle(.primary.opacity(0.75)).frame(width: tile * 0.8, height: tile)
                            }.buttonStyle(.plain).accessibilityLabel("All software")
                        }
                    }.padding(.leading, roomy ? 44 : wide ? 48 : 22).padding(.trailing, 24).padding(.vertical, 4)
                }.scrollIndicators(.hidden).frame(height: tile + 16)
                .onChange(of: model.selectedID) { _, id in
                    if let id { withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(id, anchor: .center) } }
                }
            }
            if !wide && model.visibleGames.isEmpty {
                Text("Add games, keys, and firmware from Files on your \(DevicePresentation.name).")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 27).padding(.top, 10)
            }
        }
    }

    private func gameTile(_ game: LibraryGame, size: CGFloat) -> some View {
        let selected = model.selectedGame?.id == game.id
        return Button { if selected { model.launch(game) } else { model.select(game.id) } } label: {
            CoverArt(game: game, directory: model.artworkDirectory, preview: model.isPreview)
                .frame(width: size, height: size).clipShape(RoundedRectangle(cornerRadius: 10))
                .padding(4).overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? Palette.accent : .clear, lineWidth: 2.5))
        }.buttonStyle(.plain)
            .accessibilityLabel(game.manifest.name).accessibilityValue(selected ? "Selected. \(model.isPreview ? "Preview" : game.status)" : game.status)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityHint(selected ? "Opens this game." : "Selects this game. Activate it again to open.")
            .accessibilityIdentifier("game-\(game.id)")
            .contextMenu {
                Button("Game details", systemImage: "info.circle") { model.select(game.id); model.panel = .details }
                if !model.isPreview { Button(game.isFavorite ? "Unfavorite" : "Favorite", systemImage: game.isFavorite ? "star.slash" : "star") { model.favorite(game) } }
            }
    }

    private func dock(wide: Bool, roomy: Bool, size: CGSize) -> some View {
        let side = roomy ? 76 : wide ? min(46, max(36, size.height * 0.11)) : min(64, max(44, (size.width - 72) / 5))
        let verticalPadding = roomy ? 12.0 : wide ? 7.0 : 10.0
        let contents = HStack(spacing: roomy ? 16 : wide ? 10 : 4) {
                ForEach(ConsoleAction.allCases) { action in
                    Button { model.activateConsoleAction(action) } label: {
                        ConsoleSymbol(action: action).frame(width: side, height: side).frame(minWidth: 44, minHeight: 44)
                            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(model.focusedDock == action ? Palette.accent : .clear, lineWidth: 2))
                            .contentShape(Rectangle())
                    }
                        .buttonStyle(.plain).accessibilityLabel(action.title).accessibilityIdentifier(action.identifier)
                        .accessibilityAddTraits(model.focusedDock == action ? .isSelected : [])
                }
            }.padding(.horizontal, roomy ? 18 : wide ? 9 : 8).padding(.vertical, verticalPadding)
                .glassEffect(.regular.interactive(), in: Capsule())
                .padding(.horizontal, 16)
        return contents.frame(maxWidth: .infinity).frame(height: max(44, side) + verticalPadding * 2)
    }

    private func footer(wide: Bool, roomy: Bool) -> some View {
        HStack(spacing: 14) {
            Image(systemName: model.controllerNames.isEmpty ? DevicePresentation.icon : "gamecontroller.fill").font(.system(size: roomy ? 28 : 23)).foregroundStyle(.primary.opacity(0.75))
            if model.isPreview { Text("PREVIEW").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary) }
            Spacer()
            if let game = model.selectedGame {
                Button { model.panel = .details } label: { Label("Options", systemImage: "plus.circle.fill").frame(minHeight: 44).contentShape(Rectangle()) }.foregroundStyle(.primary.opacity(0.8))
                Button { model.launch(game) } label: { Label("Start", systemImage: "a.circle.fill").frame(minHeight: 44).contentShape(Rectangle()) }.foregroundStyle(.primary.opacity(0.9)).accessibilityIdentifier("startGame")
            } else {
                Button { model.togglePreview() } label: { Text("Preview").frame(minHeight: 44).contentShape(Rectangle()) }.foregroundStyle(.secondary).accessibilityIdentifier("previewLibrary")
                Button { model.panel = .add } label: { Label("Add software", systemImage: "a.circle.fill").frame(minHeight: 44).contentShape(Rectangle()) }.foregroundStyle(.primary)
            }
        }.font(.system(size: roomy ? 20 : wide ? 16 : 15)).padding(.horizontal, roomy ? 44 : wide ? 28 : 24)
    }

}
