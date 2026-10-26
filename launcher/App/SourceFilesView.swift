import SwiftUI
import UniformTypeIdentifiers
import iSwitchCore

extension Notification.Name { static let importSourceFile = Notification.Name("iSwitch.importSourceFile") }
private enum SourceImport: String { case game, keys, firmware }

struct SourceFilesView: View {
    @EnvironmentObject private var model: LibraryModel
    @State private var files: [SourceReference] = []
    @State private var keyCount: Int?
    @State private var missingFileIDs: Set<UUID> = []
    @State private var mode = SourceImport.game
    @State private var picking = false
    @State private var busy = false
    @State private var operation = ""
    @State private var manual: SourceReference?
    @State private var removing: SourceReference?
    @State private var removingKeys = false
    @State private var failure: String?

    var body: some View {
        List {
            Section {
                Label("Import directly on your \(DevicePresentation.name)", systemImage: DevicePresentation.icon)
                    .font(.headline).padding(.vertical, 4)
                Text("Choose files from On My \(DevicePresentation.name), Downloads, iCloud Drive, or a connected drive. No Mac is needed to add them here.")
                    .font(.subheadline).foregroundStyle(.secondary)
                if busy { HStack { ProgressView(); Text(operation).font(.subheadline) }.accessibilityIdentifier("sourceImportProgress") }
                if let failure { Text(failure).font(.footnote).foregroundStyle(Palette.orange) }
            }
            Section {
                importButton("Add game file", symbol: "plus.rectangle", mode: .game, id: "importGameFile")
                ForEach(files.filter { $0.kind == .game }) { file in fileRow(file) }
            } header: { Text("Games · NSP / XCI") } footer: {
                Text("Files are copied onto this \(DevicePresentation.name) for offline access. Add a title to HOME after importing. Newly imported games still need nxnative preparation on a Mac before they can run.")
            }
            Section {
                LabeledContent("prod.keys", value: keyCount.map { "\($0) entries stored" } ?? "Not added")
                    .accessibilityIdentifier("keyStatus")
                importButton(keyCount == nil ? "Add prod.keys" : "Replace prod.keys", symbol: "key", mode: .keys, id: "importProdKeys")
                if keyCount != nil { Button("Remove stored keys", role: .destructive) { removingKeys = true } }
            } header: { Text("Keys") } footer: {
                Text("Select the prod.keys text file. For a ZIP, tap it in Files first to extract it. Keys stay in this \(DevicePresentation.name)’s Keychain and are excluded from library exports.")
            }
            Section {
                importButton("Add firmware ZIP", symbol: "shippingbox", mode: .firmware, id: "importFirmware")
                ForEach(files.filter { $0.kind == .firmware }) { file in fileRow(file) }
            } header: { Text("Firmware") } footer: {
                Text("The ZIP’s file list is checked before importing. Stored firmware is not an installed operating system; nxnative uses selected system resources during game preparation.")
            }
        }
        .disabled(busy)
        .fileImporter(isPresented: $picking, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls): if let url = urls.first { importFile(url, as: mode) }
            case .failure(let error): model.show(error)
            }
        }
        .sheet(item: $manual, onDismiss: { Task { await refresh() } }) { source in
            NavigationStack { ManualGameView(source: source) { manual = nil }.navigationTitle("Add to HOME") }
        }
        .confirmationDialog("Remove the imported copy?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            if let removing {
                Button("Remove imported file", role: .destructive) { Task { do { try await model.sourceVault.remove(id: removing.id); await refresh() } catch { model.show(error) }; self.removing = nil } }
            }
        } message: { Text("The original in Files and any installed game app are kept.") }
        .confirmationDialog("Remove prod.keys from this \(DevicePresentation.name)?", isPresented: $removingKeys, titleVisibility: .visible) {
            Button("Remove keys", role: .destructive) { Task { do { try await model.sourceVault.removeKeys(); await refresh() } catch { model.show(error) } } }
        }
        .task {
            await refresh()
            if let url = model.pendingSourceURL { model.pendingSourceURL = nil; receive(url) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .importSourceFile)) { notification in
            if let url = notification.object as? URL { model.pendingSourceURL = nil; receive(url) }
        }
    }

    private func importButton(_ title: String, symbol: String, mode: SourceImport, id: String) -> some View {
        Button { self.mode = mode; picking = true } label: { Label(title, systemImage: symbol) }
            .accessibilityIdentifier(id)
    }

    private func fileRow(_ file: SourceReference) -> some View {
        let missing = missingFileIDs.contains(file.id)
        return VStack(alignment: .leading, spacing: 6) {
            Text(file.filename).font(.subheadline).lineLimit(2)
            Text(ByteCountFormatter.string(fromByteCount: file.bytes, countStyle: .file) + (file.archiveCount.map { " · \($0) NCA files" } ?? ""))
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Label(missing ? "Imported copy unavailable" : "Stored on this \(DevicePresentation.name)", systemImage: missing ? "exclamationmark.circle" : "checkmark.circle")
                    .font(.caption).foregroundStyle(missing ? Palette.orange : Palette.green)
                Spacer()
                if file.kind == .game { Button("Add to HOME") { manual = file }.font(.caption).buttonStyle(.borderless).disabled(missing) }
                Button(role: .destructive) { removing = file } label: { Image(systemName: "trash") }.buttonStyle(.borderless).accessibilityLabel("Remove \(file.filename)")
            }
            if missing { Text("Unlock this device if needed, then reopen this page. If the copy is still unavailable, add the original file again.").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 5)
    }

    private func refresh() async {
        do { let snapshot = try await model.sourceVault.snapshot(); files = snapshot.files; keyCount = snapshot.keyCount; failure = snapshot.keyError; missingFileIDs = snapshot.missingFileIDs }
        catch { failure = error.localizedDescription }
    }

    private func receive(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ["nsp", "xci"].contains(ext) { importFile(url, as: .game) }
        else if ext == "keys" { importFile(url, as: .keys) }
        else if ext == "zip" { importFile(url, as: .firmware) }
        else { model.notice = AppNotice(title: "Unsupported file", message: "Choose an NSP, XCI, prod.keys, firmware ZIP, or prepared .iswitch card.") }
    }

    private func importFile(_ url: URL, as mode: SourceImport) {
        guard !busy else { model.notice = AppNotice(title: "Import in progress", message: "Wait for this import to finish, then add the next file."); return }
        busy = true; operation = mode == .keys ? "Checking and storing keys…" : "Copying file to this \(DevicePresentation.name)…"
        model.importingSource = true
        Task {
            let taskID = UIApplication.shared.beginBackgroundTask(withName: "reSwitch file import")
            defer { if taskID != .invalid { UIApplication.shared.endBackgroundTask(taskID) }; busy = false; model.importingSource = false }
            do {
                if mode == .keys {
                    let count = try await model.sourceVault.importKeys(url)
                    model.notice = AppNotice(title: "Keys added", message: "Stored \(count) entries securely on this \(DevicePresentation.name).")
                } else {
                    let reference = try await model.sourceVault.add(url, kind: mode == .game ? .game : .firmware)
                    if mode == .game { manual = reference }
                    else { model.notice = AppNotice(title: "Firmware added", message: "Stored \(reference.archiveCount ?? 0) NCA files in the firmware ZIP on this \(DevicePresentation.name). Game preparation determines which resources nxnative can use.") }
                }
                await refresh()
            } catch { model.show(error) }
        }
    }
}

struct ManualGameView: View {
    let source: SourceReference?
    let finished: () -> Void
    @EnvironmentObject private var model: LibraryModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var titleID = ""
    @State private var saving = false
    @State private var error: String?
    var body: some View {
        Form {
            if let source { Section("Imported file") { Text(source.filename).font(.subheadline) } }
            Section("Game card") {
                TextField("Game name", text: $name).accessibilityIdentifier("manualGameName")
                TextField("16-character title ID", text: $titleID).textInputAutocapitalization(.characters).autocorrectionDisabled().font(.body.monospaced()).accessibilityIdentifier("manualTitleID")
                Menu("Choose an existing game profile") {
                    ForEach(model.catalog) { entry in Button(entry.name) { name = entry.name; titleID = entry.id } }
                }
            }
            Section {
                Text("This adds a card to HOME. It does not install or prepare a game. Import its prepared .iswitch card when its game app is ready.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let error { Text(error).font(.footnote).foregroundStyle(Palette.orange) }
                Button(saving ? "Adding…" : "Add to HOME") {
                    saving = true
                    Task {
                        do { try await model.addManual(titleID: titleID, name: name, source: source); finished(); dismiss() }
                        catch { self.error = error.localizedDescription }
                        saving = false
                    }
                }.disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || titleID.count != 16).accessibilityIdentifier("saveManualGame")
            }
        }
        .navigationTitle("Add a game")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { finished(); dismiss() } } }
        .onAppear {
            guard name.isEmpty else { return }
            if let id = source?.titleID {
                let base = UInt64(id, radix: 16).map { String(format: "%016llX", $0 & ~0xfff) } ?? id
                titleID = base
                name = model.catalog.first { $0.id == base }?.name ?? ""
            }
            if name.isEmpty { name = source.map { URL(fileURLWithPath: $0.filename).deletingPathExtension().lastPathComponent } ?? "" }
        }
    }
}
