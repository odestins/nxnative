import XCTest
@testable import SwitchMacApp

@MainActor private final class AudioTransport: GameChatTransport {
    let available = true
    var onEvent: ((String, String) -> Void)?
    var ready = false
    var input = "default", output = "default"
    var selected: [String] = []
    var holdInputs = false
    var inputsGate: CheckedContinuation<Void, Never>?
    var inputRequests = 0, outputRequests = 0
    var snapshot: [String: Any] {
        ["status": ready ? "Ready" : "Disconnected", "account": ["id": "101", "name": "Test"], "hasCall": false]
    }
    func tick() {}
    func cancel() { ready = false }
    func request(_ action: String, _ parameters: [String: Any], timeout: Double) async throws -> [String: Any] {
        switch action {
        case "authorize": return ["accessToken": "fixture", "refreshToken": "fixture", "expiresIn": 3600]
        case "connect": ready = true
        case "audioInputs":
            inputRequests += 1
            if holdInputs { await withCheckedContinuation { inputsGate = $0 } }
            return ["devices": [["id": "default", "name": "System default"], ["id": "mic", "name": "USB microphone"]], "currentID": input]
        case "audioOutputs":
            outputRequests += 1
            return ["devices": [["id": "default", "name": "System default"], ["id": "speakers", "name": "Speakers"]], "currentID": output]
        case "audioInputDevice": input = parameters["id"] as! String; selected.append(action)
        case "audioOutputDevice": output = parameters["id"] as! String; selected.append(action)
        default: break
        }
        return [:]
    }
}

final class ChatAudioTests: XCTestCase {
    @MainActor private func makeChat(_ transport: AudioTransport) async -> GameChatService {
        let credentials = GameChatCredentialStore(read: { .init(accessToken: "fixture", refreshToken: "fixture", expiresAt: .distantFuture) }, save: { _ in }, delete: {})
        let chat = GameChatService(transport: transport, credentials: credentials, guestStore: .init(read: { nil }, save: { _ in }), managesAudio: false)
        await chat.restore()
        return chat
    }

    @MainActor func testAudioSelectionUsesListedDevicesAndCorrectDirection() async {
        let transport = AudioTransport(), chat = await makeChat(transport)
        defer { chat.shutdown() }
        await chat.refreshAudioDevices()
        XCTAssertEqual(chat.audioInputs.map(\.id), ["default", "mic"])
        await chat.selectAudioDevice("missing", input: true)
        XCTAssertTrue(transport.selected.isEmpty)
        await chat.selectAudioDevice("mic", input: true)
        await chat.selectAudioDevice("speakers", input: false)
        XCTAssertEqual(transport.selected, ["audioInputDevice", "audioOutputDevice"])
        XCTAssertEqual(chat.inputDevice, "mic")
        XCTAssertEqual(chat.outputDevice, "speakers")
        XCTAssertEqual(chat.routeName, "Speakers")
    }

    @MainActor func testDisconnectRejectsLateAudioDeviceResponse() async {
        let transport = AudioTransport(), chat = await makeChat(transport)
        defer { chat.shutdown() }
        transport.holdInputs = true
        let refresh = Task { await chat.refreshAudioDevices() }
        for _ in 0..<100 {
            if transport.inputsGate != nil { break }
            await Task.yield()
        }
        XCTAssertNotNil(transport.inputsGate)
        await chat.unlink()
        transport.inputsGate?.resume()
        await refresh.value
        XCTAssertTrue(chat.audioInputs.isEmpty)
        XCTAssertTrue(chat.audioOutputs.isEmpty)
        XCTAssertFalse(chat.updatingDevices)
        XCTAssertEqual(transport.outputRequests, 0, "A cancelled session must not start the next SDK request")
    }

    @MainActor func testOldAudioRefreshCannotBlockOrUnlockNewSessionRefresh() async {
        let transport = AudioTransport(), chat = await makeChat(transport)
        defer { chat.shutdown() }
        transport.holdInputs = true
        let oldRefresh = Task { await chat.refreshAudioDevices() }
        for _ in 0..<100 { if transport.inputsGate != nil { break }; await Task.yield() }
        let oldGate = transport.inputsGate
        XCTAssertNotNil(oldGate)
        await chat.unlink()
        XCTAssertFalse(chat.updatingDevices)
        await chat.link()
        XCTAssertTrue(chat.linked)
        let newRefresh = Task { await chat.refreshAudioDevices() }
        for _ in 0..<100 { if transport.inputRequests == 2 { break }; await Task.yield() }
        XCTAssertEqual(transport.inputRequests, 2)
        guard transport.inputRequests == 2 else {
            oldGate?.resume(); await oldRefresh.value; await newRefresh.value
            return
        }
        let newGate = transport.inputsGate
        oldGate?.resume(); await oldRefresh.value
        XCTAssertTrue(chat.updatingDevices, "The old session cannot clear a new refresh's loading state")
        XCTAssertEqual(transport.outputRequests, 0)
        newGate?.resume(); await newRefresh.value
        XCTAssertFalse(chat.updatingDevices)
        XCTAssertEqual(transport.outputRequests, 1)
        XCTAssertEqual(chat.audioInputs.map(\.id), ["default", "mic"])
    }
}
