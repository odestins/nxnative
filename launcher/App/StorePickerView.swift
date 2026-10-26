import SwiftUI
import iSwitchCore

struct StorePickerView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Choose a website").font(.title2.bold())
            Text("Open either store in your browser.").foregroundStyle(.secondary)
            ForEach(StoreDestination.allCases) { store in
                Link(destination: store.url) {
                    HStack(spacing: 16) {
                        Image(systemName: "bag").font(.title2).foregroundStyle(.red)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.title).font(.headline)
                            Text(store.url.host ?? "").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                    }.foregroundStyle(.primary).padding(20)
                        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).accessibilityIdentifier("store-" + store.rawValue)
            }
        }.padding(24).frame(maxWidth: 620, alignment: .leading).frame(maxWidth: .infinity, alignment: .top)
    }
}
