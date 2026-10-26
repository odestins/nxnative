import XCTest
#if os(macOS)
@testable import SwitchMacApp
#else
@testable import iSwitch
#endif

private final class GuestHTTPFixture: @unchecked Sendable {
    private let lock = NSLock()
    private var status = 200
    private var body = Data()
    private var requests: [URLRequest] = []
    func set(_ status: Int, _ body: Data) { lock.withLock { self.status = status; self.body = body; requests = [] } }
    func response(_ request: URLRequest) -> (Int, Data) { lock.withLock { requests.append(request); return (status, body) } }
    var lastRequest: URLRequest? { lock.withLock { requests.last } }
}

private final class GuestHTTPProtocol: URLProtocol, @unchecked Sendable {
    static let fixture = GuestHTTPFixture()
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "guest.test.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body) = Self.fixture.response(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class GuestChatClientTests: XCTestCase {
    @MainActor private func client() -> GuestChatClient {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [GuestHTTPProtocol.self]
        return GuestChatClient(configuration: .init(applicationID: "123", redirectURI: "discord-123:/authorize/callback",
            guestEndpoint: "https://guest.test.invalid/v1/guest-token"), session: URLSession(configuration: config))
    }
    @MainActor func testClientSendsOnlyInstallationIdentityAndAcceptsBoundedAccess() async throws {
        GuestHTTPProtocol.fixture.set(200, Data(#"{"applicationID":"123","accessToken":"fixture-access","expiresIn":3600}"#.utf8))
        let identity = try GuestChatIdentity.create(name: "Player")
        let token = try await client().authorize(identity)
        XCTAssertEqual(token.accessToken, "fixture-access"); XCTAssertEqual(token.refreshToken, "")
        XCTAssertEqual(GuestHTTPProtocol.fixture.lastRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer " + identity.credential)
        XCTAssertEqual(GuestHTTPProtocol.fixture.lastRequest?.httpMethod, "POST")
    }
    @MainActor func testClientRejectsWrongApplicationOversizedAndMalformedReplies() async throws {
        let identity = try GuestChatIdentity.create(name: "Player")
        for reply in [#"{"applicationID":"456","accessToken":"fixture","expiresIn":3600}"#,
                      #"{"applicationID":"123","accessToken":"fixture","expiresIn":0}"#,
                      #"{"applicationID":"123","accessToken":"fixture","expiresIn":604801}"#,
                      "not JSON", String(repeating: "x", count: 32_769)] {
            GuestHTTPProtocol.fixture.set(200, Data(reply.utf8))
            do { _ = try await client().authorize(identity); XCTFail("Invalid broker response was accepted") } catch {}
        }
    }
    @MainActor func testClientShowsSafeLinkedRateLimitAndServiceErrors() async throws {
        let identity = try GuestChatIdentity.create(name: "Player")
        for (status, expected) in [(409, "linked to Discord"), (429, "Wait a minute"), (503, "temporarily unavailable")] {
            GuestHTTPProtocol.fixture.set(status, Data(#"{"error":"sensitive upstream details"}"#.utf8))
            do { _ = try await client().authorize(identity); XCTFail("HTTP error was accepted") }
            catch { XCTAssertTrue(error.localizedDescription.contains(expected)); XCTAssertFalse(error.localizedDescription.contains("sensitive")) }
        }
    }
}
