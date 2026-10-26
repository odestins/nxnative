import Foundation
import iSwitchCore

@MainActor protocol GameChatTransport: AnyObject {
    var available: Bool { get }
    var onEvent: ((String, String) -> Void)? { get set }
    var snapshot: [String: Any] { get }
    func tick()
    func request(_ action: String, _ parameters: [String: Any], timeout: Double) async throws -> [String: Any]
    func cancel()
    func cancelAuthorization() -> Bool
}

extension GameChatTransport {
    func cancelAuthorization() -> Bool { true }
    func request(_ action: String, _ parameters: [String: Any] = [:]) async throws -> [String: Any] {
        try await request(action, parameters, timeout: 30)
    }
}

/// Same official SDK boundary as ArcStation. Constructed lazily, pumped on the
/// main actor, with exactly one completion per request and bounded deadlines.
@MainActor final class DiscordGameChatTransport: GameChatTransport {
    var onEvent: ((String, String) -> Void)?
    private var bridge: ASDiscordBridge?
    private let configuration = GameChatConfiguration.load()
    private var pending: [UUID: CheckedContinuation<Data, Error>] = [:]
    private var deadlines: [UUID: Task<Void, Never>] = [:]
    var available: Bool { ASDiscordBridge.compiledAvailable() && configuration != nil }
    var snapshot: [String: Any] { bridge?.snapshot() ?? [:] }

    private func prepare() throws -> ASDiscordBridge {
        if let bridge { return bridge }
        guard available, let configuration, let id = UInt64(configuration.applicationID) else {
            throw LibraryError.invalid("Discord is unavailable in this build. Install an updated copy of reSwitch.")
        }
        let value = ASDiscordBridge(applicationID: id)
        value.eventHandler = { [weak self] event, value in
            Task { @MainActor in self?.onEvent?(event, value) }
        }
        bridge = value
        return value
    }
    func tick() { bridge?.tick() }

    func request(_ action: String, _ parameters: [String: Any], timeout: Double) async throws -> [String: Any] {
        let bridge = try prepare(), id = UUID()
        let payload: Data = try await withCheckedThrowingContinuation { continuation in
            pending[id] = continuation
            deadlines[id] = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(timeout)) } catch { return }
                // OAuth can be cancelled before its token exchange. Once an
                // irreversible guest merge starts, keep its completion alive
                // so the resulting refresh token can be saved by the service.
                if action == "authorize" {
                    while !bridge.cancelAuthorization() {
                        do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    }
                }
                guard let self, let continuation = pending.removeValue(forKey: id) else { return }
                deadlines[id] = nil
                if ["connect", "join"].contains(action) {
                    bridge.perform("disconnect", parameters: [:]) { _, _ in }
                }
                continuation.resume(throwing: LibraryError.invalid(action == "send" || action == "partySend" ? "Could not confirm delivery. Refresh the conversation before trying again." : "Discord took too long to respond. Please try again."))
            }
            bridge.perform(action, parameters: parameters) { [weak self] result, error in
                // Transfer immutable bytes, not SDK-owned Objective-C containers,
                // across the callback's executor boundary.
                let payload = try? JSONSerialization.data(withJSONObject: result ?? [:])
                Task { @MainActor in
                    guard let self, let continuation = self.pending.removeValue(forKey: id) else { return }
                    self.deadlines.removeValue(forKey: id)?.cancel()
                    if let error { continuation.resume(throwing: LibraryError.invalid(error.isEmpty ? "Discord could not complete that request." : error)) }
                    else if let payload { continuation.resume(returning: payload) }
                    else { continuation.resume(throwing: LibraryError.invalid("Discord returned an unreadable response.")) }
                }
            }
        }
        guard let result = try JSONSerialization.jsonObject(with: payload) as? [String: Any] else {
            throw LibraryError.invalid("Discord returned an unreadable response.")
        }
        return result
    }

    func cancel() {
        bridge?.perform("disconnect", parameters: [:]) { _, _ in }
        deadlines.values.forEach { $0.cancel() }; deadlines.removeAll()
        let waiting = Array(pending.values); pending.removeAll()
        waiting.forEach { $0.resume(throwing: CancellationError()) }
    }

    func cancelAuthorization() -> Bool { bridge?.cancelAuthorization() ?? true }
}
