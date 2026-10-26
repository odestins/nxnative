import SwiftUI
import SwitchSaveSync

struct CloudSavesView: View {
    @EnvironmentObject private var model: LibraryModel
    @StateObject private var cloud = CloudSaveCatalog()
    @State private var restoring: CloudSaveRecord?
    var body: some View {
        List {
            if !CloudSavePreferences.configured {
                Section {
                    Label("iCloud update pending", systemImage: "icloud.slash").font(.headline)
                    Text("This version keeps your saves on this \(DevicePresentation.name). Cloud backup will become available after the iCloud-enabled update is installed.").foregroundStyle(.secondary)
                }
            } else {
            Section {
                Toggle("iCloud saves", isOn: Binding(get: { cloud.enabled }, set: { cloud.setEnabled($0) })).tint(Palette.accent).accessibilityIdentifier("iCloudSavesToggle")
                Label(cloud.enabled ? cloud.status : "Automatic backups are paused", systemImage: cloud.available ? "icloud" : "icloud.slash").font(.subheadline).foregroundStyle(.secondary)
                    .accessibilityIdentifier("cloudSaveStatus").accessibilityValue(cloud.available ? "Available" : "Unavailable")
                if cloud.gathering { ProgressView("Checking saved progress…") }
            } footer: {
                Text("Completed game saves back up automatically. Games continue offline and retry on their next launch. Games must have the cloud-save update installed.")
            }
            ForEach(model.games) { game in
                let records = cloud.records.filter { $0.manifest.titleID == game.id }
                let heads = SaveManifest.heads(records.map(\.manifest))
                Section {
                    if records.isEmpty {
                        Label(cloud.available ? "No cloud save yet" : "Waiting for iCloud", systemImage: "icloud.and.arrow.up").foregroundStyle(.secondary)
                        Text("Play and reach a save checkpoint to create a backup.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        if heads.count > 1 { Label("Different progress found on multiple devices. Choose a save when opening this game.", systemImage: "exclamationmark.arrow.triangle.2.circlepath").font(.caption).foregroundStyle(Palette.orange) }
                        ForEach(Array(records.prefix(3))) { record in
                            VStack(alignment: .leading, spacing: 10) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.manifest.savedAt, format: .dateTime.month().day().hour().minute()).font(.subheadline.weight(.medium))
                                        Text("\(record.manifest.deviceName) · v\(record.manifest.version)").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: record.uploaded ? "checkmark.icloud" : "icloud.and.arrow.up").foregroundStyle(record.uploaded ? Palette.green : .secondary).accessibilityLabel(record.uploaded ? "Uploaded to iCloud" : "Upload pending")
                                }
                                HStack { Text(ByteCountFormatter.string(fromByteCount: Int64(record.manifest.bytes), countStyle: .file)).font(.caption).foregroundStyle(.secondary); Spacer(); Button("Restore…") { restoring = record }.font(.subheadline).disabled(!cloud.enabled) }
                            }.padding(.vertical, 4)
                        }
                    }
                } header: { Text(game.manifest.name) }
            }
            Section("How your progress is protected") {
                Label("Your current save stays on this \(DevicePresentation.name)", systemImage: DevicePresentation.icon)
                Label("Restores keep a local recovery copy", systemImage: "clock.arrow.circlepath")
                Label("Conflicting saves require your choice", systemImage: "arrow.triangle.branch")
                Text("Only save data goes to your private iCloud container. Game files, keys, firmware and your Discord account stay separate.").font(.caption).foregroundStyle(.secondary)
            }.font(.subheadline)
            }
        }.navigationTitle("iCloud saves").navigationBarTitleDisplayMode(.inline)
            .toolbar { PanelDoneToolbar() }
            .task { await cloud.start() }.onDisappear { cloud.stop() }
            .refreshable { await cloud.start() }
            .confirmationDialog("Restore this saved progress?", isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }), titleVisibility: .visible) {
                Button("Open game to restore") {
                    if let record = restoring, let game = model.games.first(where: { $0.id == record.manifest.titleID }) { model.launch(game, restoreSnapshot: record.id) }
                    restoring = nil
                }
            } message: { Text("The game restores before starting and keeps a recovery copy. If it is already running, close it from the app switcher and open it again.") }
    }
}
