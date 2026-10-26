import SwiftUI

struct ChatSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(title, systemImage: symbol).font(.headline).foregroundStyle(.primary)
            content()
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.07)))
    }
}

struct ChatConnectionBadge: View {
    @EnvironmentObject private var chat: GameChatService
    var body: some View {
        HStack(spacing: 6) {
            if chat.reconnecting { ProgressView().controlSize(.mini) }
            else { Circle().fill(chat.linked ? Palette.green : .secondary).frame(width: 6, height: 6) }
            Text(chat.linked ? chat.connectionLabel : chat.reconnecting ? "Reconnecting…" : "Offline")
                .font(.caption.weight(.medium)).foregroundStyle(.secondary)
        }
    }
}

struct ChatDetailRow: View {
    let title: String
    let value: String
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value).multilineTextAlignment(.trailing)
        }.font(.subheadline)
    }
}
