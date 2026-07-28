import XCTest
@testable import HomeHub

final class HubAddressTests: XCTestCase {
    func testAddsHTTPSSchemeAndKeepsPort() throws {
        let url = try HubAddress.normalize("192.168.1.25:8787")
        XCTAssertEqual(url.absoluteString, "http://192.168.1.25:8787/")
    }

    func testNormalizesToServerRoot() throws {
        let url = try HubAddress.normalize(" HTTPS://HomeHub.local:9443/tasks?show=all ")
        XCTAssertEqual(url.absoluteString, "https://HomeHub.local:9443/")
    }

    func testRejectsUnsupportedScheme() {
        XCTAssertThrowsError(try HubAddress.normalize("ftp://homehub.local")) { error in
            XCTAssertEqual(error as? HubAddressError, .unsupportedScheme)
        }
    }

    func testRejectsCredentials() {
        XCTAssertThrowsError(try HubAddress.normalize("http://user:secret@homehub.local")) { error in
            XCTAssertEqual(error as? HubAddressError, .credentialsNotAllowed)
        }
    }

    func testBuildsNestedEndpoint() throws {
        let base = try HubAddress.normalize("http://192.168.1.25:8787")
        XCTAssertEqual(
            HubAddress.endpoint("/api/security/events", relativeTo: base).absoluteString,
            "http://192.168.1.25:8787/api/security/events"
        )
    }

    func testMapsWebRoutesToNativeTabs() {
        XCTAssertEqual(HubTab.route(for: "/"), .home)
        XCTAssertEqual(HubTab.route(for: "/tasks/"), .board)
        XCTAssertEqual(HubTab.route(for: "/pantry"), .pantry)
        XCTAssertEqual(HubTab.route(for: "/scan"), .scan)
        XCTAssertEqual(HubTab.route(for: "/security"), .guard)
        XCTAssertNil(HubTab.route(for: "/api/status"))
    }
}
