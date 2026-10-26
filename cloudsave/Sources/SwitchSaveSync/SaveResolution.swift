import Foundation

public enum SaveResolution {
    case local, adopt(SaveManifest), restore(CloudSaveRecord), choose([CloudSaveRecord])

    /// Device clocks determine ancestry. Wall-clock dates are display-only: a
    /// phone with an incorrect clock must never win over different progress.
    public static func decide(records: [CloudSaveRecord], state: SaveLocalState,
                              localHash: String, localExists: Bool, version: String) -> Self {
        let heads = SaveManifest.heads(records.map(\.manifest))
        guard !heads.isEmpty else { return .local }
        if heads.count == 1, let head = heads.first, let record = records.first(where: { $0.id == head.id }) {
            if localHash == head.contentHash { return .adopt(head) }
            if head.version == version && (!localExists || (head.clock != state.clock && head.clock.dominates(state.clock) && localHash == state.contentHash)) { return .restore(record) }
            if !localExists || !state.clock.dominates(head.clock) { return .choose([record]) }
            return .local
        }
        if localExists && heads.allSatisfy({ state.clock != $0.clock && state.clock.dominates($0.clock) }) { return .local }
        return .choose(records.filter { record in heads.contains { $0.id == record.id } })
    }
}
