import AssistantBrowser
import Foundation
import XCTest

final class BrowserManualLANAccessTests: XCTestCase {
    func testCandidateClassesAndAddressBoundaries() {
        let accepted = [
            "http://localhost/", "https://SUB.LOCALHOST/", "http://printer.local:8080/a?q=1#p",
            "https://router.home.arpa/", "http://router/", "http://127.0.0.1/",
            "http://127.255.255.255/", "http://10.0.0.1/", "http://172.16.0.1/",
            "http://172.31.255.255/", "http://192.168.1.1/", "http://169.254.1.1/",
            "http://[::1]/", "https://[fd00::1]:443/", "http://[fe80::1]/",
            "http://[::ffff:192.168.1.1]/", "http://[::ffff:7f00:1]/"
        ]
        for address in accepted {
            let state = BrowserManualLANAccess()
            let request = state.requestManualAccess(address: address)
            XCTAssertNotNil(request, address)
            XCTAssertEqual(state.status, .awaitingApproval, address)
            if let request {
                XCTAssertFalse(state.allowsNavigation(to: request.url), address)
                XCTAssertTrue(state.approve(request), address)
                XCTAssertTrue(state.allowsNavigation(to: request.url), address)
            }
        }

        let rejected = [
            "http://172.15.255.255/", "http://172.32.0.1/", "http://8.8.8.8/",
            "http://example.com/", "http://router.local.example/", "http://100.64.0.1/",
            "http://0.0.0.0/", "http://0.0.0.1/", "http://224.0.0.1/", "http://255.255.255.255/",
            "http://[::]/", "http://[ff02::1]/", "http://[fec0::1]/", "http://[::8.8.8.8]/",
            "http://[::ffff:8.8.8.8]/", "http://[fe80::1%25en0]/", "http://[2606:4700::1111]/"
        ]
        for address in rejected {
            let state = BrowserManualLANAccess()
            XCTAssertNil(state.requestManualAccess(address: address), address)
            XCTAssertEqual(state.status, .disabled, address)
        }
    }

    func testMalformedAuthoritiesAndPortsFailClosed() {
        let bad = [
            "http://127.1/", "http://2130706433/", "http://0177.0.0.1/", "http://0x7f000001/",
            "http://127.0.0.1:/", "http://127.0.0.1:0/", "http://127.0.0.1:65536/",
            "http://127.0.0.1:999999999999999999999/", "http://127.0.0.1:abc/",
            "http://user:password@127.0.0.1/", "http://@localhost/", "http://%6cocalhost/",
            "http://[::ffff:0177.0.0.1]/", "http://[::1]:80:90/", "file:///localhost", "localhost:8080",
            "http://bad..local/", "http://host_.local/", "http://127.0.0.1/" + String(repeating: "a", count: 8192)
        ]
        for address in bad {
            let state = BrowserManualLANAccess()
            XCTAssertNil(state.requestManualAccess(address: address), address)
            XCTAssertEqual(state.status, .disabled, address)
        }
        for address in ["http://localhost:1/", "http://localhost:65535/", "http://localhost:00080/"] {
            let state = BrowserManualLANAccess()
            XCTAssertNotNil(state.requestManualAccess(address: address), address)
        }
    }

    func testConfirmationShowsExactOriginWithoutPathOrQuery() throws {
        let state = BrowserManualLANAccess()
        let host = try XCTUnwrap(state.requestManualAccess(address: "HTTPS://printer.local:9443/path?q=fixture#section"))
        XCTAssertEqual(host.displayOrigin, "https://printer.local:9443")
        let ipv6 = try XCTUnwrap(state.requestManualAccess(address: "http://[::1]:8088/path?q=fixture"))
        XCTAssertEqual(ipv6.displayOrigin, "http://[::1]:8088")
        let defaultPort = try XCTUnwrap(state.requestManualAccess(address: "HTTPS://localhost/"))
        XCTAssertEqual(defaultPort.displayOrigin, "https://localhost:443")
    }

    func testEntire172RangeAndMappedIPv6UseTheSamePrivateBoundary() {
        for octet in 0...255 {
            for address in ["http://172.\(octet).1.1/", "http://[::ffff:172.\(octet).1.1]/"] {
                let state = BrowserManualLANAccess()
                let request = state.requestManualAccess(address: address)
                XCTAssertEqual(request != nil, (16...31).contains(octet), address)
            }
        }
    }

    func testExplicitApprovalRevocationAndStaleRequests() throws {
        let state = BrowserManualLANAccess()
        let url = try XCTUnwrap(URL(string: "http://localhost/a"))
        XCTAssertEqual(state.status, .disabled)
        XCTAssertFalse(state.allowsNavigation(to: url))
        let first = try XCTUnwrap(state.requestManualAccess(address: url.absoluteString))
        let second = try XCTUnwrap(state.requestManualAccess(address: url.absoluteString))
        XCTAssertFalse(state.approve(first))
        XCTAssertEqual(state.status, .awaitingApproval)
        XCTAssertTrue(state.approve(second))
        XCTAssertFalse(state.approve(second))
        XCTAssertEqual(state.status, .authorized)
        XCTAssertTrue(state.allowsNavigation(to: url))
        XCTAssertNil(state.requestManualAccess(address: "http://127.1/"))
        XCTAssertEqual(state.status, .disabled)
        XCTAssertFalse(state.allowsNavigation(to: url))
        let third = try XCTUnwrap(state.requestManualAccess(address: url.absoluteString))
        state.revoke()
        XCTAssertFalse(state.approve(third))
        XCTAssertFalse(state.allowsNavigation(to: url))
    }

    func testRevocationIsSharedWithAuthorizedAndPendingAliases() throws {
        let state = BrowserManualLANAccess()
        let url = try XCTUnwrap(URL(string: "http://localhost/a"))
        let request = try XCTUnwrap(state.requestManualAccess(address: url.absoluteString))
        XCTAssertTrue(state.approve(request))
        let authorizedAlias = state
        XCTAssertTrue(authorizedAlias.allowsNavigation(to: url))
        state.revoke()
        XCTAssertEqual(authorizedAlias.status, .disabled)
        XCTAssertFalse(authorizedAlias.allowsNavigation(to: url))
        XCTAssertFalse(authorizedAlias.approve(request))

        let pending = try XCTUnwrap(state.requestManualAccess(address: url.absoluteString))
        let pendingAlias = state
        state.revoke()
        XCTAssertEqual(pendingAlias.status, .disabled)
        XCTAssertFalse(pendingAlias.approve(pending))
        XCTAssertFalse(pendingAlias.allowsNavigation(to: url))
        XCTAssertEqual(state.status, .disabled)

        let anotherPending = try XCTUnwrap(state.requestManualAccess(address: url.absoluteString))
        pendingAlias.revoke()
        XCTAssertFalse(state.approve(anotherPending))
        XCTAssertEqual(state.status, .disabled)
        let anotherGrant = try XCTUnwrap(state.requestManualAccess(address: url.absoluteString))
        XCTAssertTrue(state.approve(anotherGrant))
        authorizedAlias.revoke()
        XCTAssertFalse(state.allowsNavigation(to: url))
        XCTAssertEqual(state.status, .disabled)

        // A separate session has an independent authority.
        let separate = BrowserManualLANAccess()
        let separateRequest = try XCTUnwrap(separate.requestManualAccess(address: url.absoluteString))
        XCTAssertTrue(separate.approve(separateRequest))
        state.revoke()
        XCTAssertTrue(separate.allowsNavigation(to: url))
    }

    func testTrailingDotHostsAreRejected() throws {
        let state = BrowserManualLANAccess()
        for address in ["http://localhost./", "http://printer.local./", "http://127.0.0.1./"] {
            XCTAssertNil(state.requestManualAccess(address: address), address)
        }
        let request = try XCTUnwrap(state.requestManualAccess(address: "http://printer.local/"))
        XCTAssertTrue(state.approve(request))
        XCTAssertFalse(state.allowsNavigation(to: try XCTUnwrap(URL(string: "http://printer.local./"))))
        XCTAssertTrue(state.allowsNavigation(to: try XCTUnwrap(URL(string: "http://PRINTER.LOCAL:80/"))))
    }

    func testConcurrentAliasesShareStateAndFinalRevocation() throws {
        let state = BrowserManualLANAccess()
        let alias = state
        let url = try XCTUnwrap(URL(string: "http://localhost/"))
        DispatchQueue.concurrentPerform(iterations: 400) { iteration in
            if iteration.isMultiple(of: 3) {
                alias.revoke()
            } else if let request = state.requestManualAccess(address: url.absoluteString) {
                _ = alias.approve(request)
                _ = state.allowsNavigation(to: url)
            }
        }
        alias.revoke()
        XCTAssertEqual(state.status, .disabled)
        XCTAssertFalse(state.allowsNavigation(to: url))
    }

    func testRedirectAndOriginComparison() throws {
        let state = BrowserManualLANAccess()
        let request = try XCTUnwrap(state.requestManualAccess(address: "http://Printer.Local:80/start"))
        XCTAssertTrue(state.approve(request))
        for target in ["http://printer.local/next", "http://PRINTER.LOCAL:80/path?q=1#x"] {
            XCTAssertTrue(state.allowsNavigation(to: try XCTUnwrap(URL(string: target))), target)
        }
        let relative = try XCTUnwrap(URL(string: "../next", relativeTo: request.url))
        XCTAssertTrue(state.allowsNavigation(to: relative))
        for target in ["https://printer.local/", "http://printer.local:81/", "http://other.local/",
                       "http://127.0.0.1/", "https://example.com/", "http://user@printer.local/"] {
            XCTAssertFalse(state.allowsNavigation(to: try XCTUnwrap(URL(string: target))), target)
        }
        let v6 = try XCTUnwrap(state.requestManualAccess(address: "https://[fd00::1]/"))
        XCTAssertTrue(state.approve(v6))
        XCTAssertTrue(state.allowsNavigation(to: try XCTUnwrap(URL(string: "https://[FD00:0:0:0:0:0:0:1]:443/a"))))
        XCTAssertFalse(state.allowsNavigation(to: try XCTUnwrap(URL(string: "https://[fd00::2]/"))))
        XCTAssertFalse(state.allowsNavigation(to: try XCTUnwrap(URL(string: "http://[fd00::1]/"))))
    }

    func testExistingManualAndResearchPoliciesStayRestricted() throws {
        for address in ["https://localhost/", "https://192.168.1.1/", "https://printer.local/", "https://[::1]/"] {
            let url = try XCTUnwrap(URL(string: address))
            let state = BrowserManualLANAccess()
            let request = try XCTUnwrap(state.requestManualAccess(address: address))
            XCTAssertTrue(state.approve(request))
            XCTAssertTrue(state.allowsNavigation(to: url))
            XCTAssertFalse(BrowserManualNavigationPolicy.allows(url))
            guard case .block = BrowserPolicy.evaluate(url) else { return XCTFail("Existing policy allowed \(address)") }
            XCTAssertThrowsError(try WebsiteOrigin(url: url))
        }
        XCTAssertTrue(BrowserManualNavigationPolicy.allows(try XCTUnwrap(URL(string: "https://example.com/"))))
    }
}
