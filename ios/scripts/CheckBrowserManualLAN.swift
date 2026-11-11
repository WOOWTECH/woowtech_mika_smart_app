import Foundation

/// Standalone CLT checks for the same production policy used by the XCTest suite.
/// This runner needs neither XCTest nor network access.
@main struct CheckBrowserManualLAN {
    struct Failure: Error { let label: String }

    static func main() throws {
        var count = 0
        func check(_ condition: @autoclosure () -> Bool, _ label: String) throws {
            count += 1
            if !condition() { throw Failure(label: label) }
        }
        let good = ["http://localhost/", "https://host.local/", "http://router/", "http://router.home.arpa/",
                    "http://127.0.0.1/", "http://10.1.2.3/", "http://192.168.1.1/", "http://169.254.1.1/",
                    "http://[::1]/", "http://[fd00::1]/", "http://[fe80::1]/", "http://[::ffff:192.168.1.1]/"]
        for address in good {
            let state = BrowserManualLANAccess()
            guard let url = URL(string: address) else { throw Failure(label: "fixture URL") }
            try check(state.status == .disabled && !state.allowsNavigation(to: url), "default denied")
            guard let request = state.requestManualAccess(address: address) else { throw Failure(label: "local candidate") }
            try check(state.status == .awaitingApproval && !state.allowsNavigation(to: url), "pending denied")
            try check(state.approve(request), "explicit approval")
            try check(state.status == .authorized && state.allowsNavigation(to: url), "same origin")
            state.revoke()
            try check(state.status == .disabled && !state.allowsNavigation(to: url), "revoke")
        }
        let bad = ["http://8.8.8.8/", "http://example.com/", "http://100.64.0.1/", "http://0.0.0.0/",
                   "http://224.0.0.1/", "http://255.255.255.255/", "http://[::]/", "http://[ff02::1]/",
                   "http://[fec0::1]/", "http://[::ffff:8.8.8.8]/", "http://[fe80::1%25en0]/",
                   "http://127.1/", "http://0177.0.0.1/", "http://0x7f000001/", "http://%6cocalhost/",
                   "http://127.0.0.1:/", "http://127.0.0.1:0/", "http://127.0.0.1:65536/",
                   "http://127.0.0.1:999999999999999999999/", "http://user:password@localhost/", "file:///localhost"]
        for address in bad {
            let state = BrowserManualLANAccess()
            try check(state.requestManualAccess(address: address) == nil && state.status == .disabled, "invalid candidate")
        }
        for octet in 0...255 {
            for address in ["http://172.\(octet).1.1/", "http://[::ffff:172.\(octet).1.1]/"] {
                let state = BrowserManualLANAccess()
                try check((state.requestManualAccess(address: address) != nil) == (16...31).contains(octet), "172 boundary")
            }
        }
        let state = BrowserManualLANAccess()
        guard let first = state.requestManualAccess(address: "http://Printer.Local:80/a"),
              let latest = state.requestManualAccess(address: "http://Printer.Local:80/a") else { throw Failure(label: "request") }
        try check(!state.approve(first) && state.status == .awaitingApproval, "stale request")
        try check(state.approve(latest), "latest request")
        guard let same = URL(string: "http://printer.local/next"),
              let port = URL(string: "http://printer.local:81/"),
              let scheme = URL(string: "https://printer.local/"),
              let host = URL(string: "http://other.local/"),
              let relative = URL(string: "../other", relativeTo: latest.url) else { throw Failure(label: "origin fixture") }
        try check(state.allowsNavigation(to: same) && state.allowsNavigation(to: relative), "same origin redirect")
        try check(!state.allowsNavigation(to: port) && !state.allowsNavigation(to: scheme) && !state.allowsNavigation(to: host), "cross origin redirect")
        try check(state.requestManualAccess(address: "http://127.1/") == nil && state.status == .disabled, "invalid replacement revokes")
        guard let v6 = state.requestManualAccess(address: "https://[fd00::1]/"),
              let v6Same = URL(string: "https://[FD00:0:0:0:0:0:0:1]:443/"),
              let v6Other = URL(string: "https://[fd00::2]/") else { throw Failure(label: "IPv6 fixture") }
        try check(state.approve(v6), "IPv6 approval")
        try check(state.allowsNavigation(to: v6Same) && !state.allowsNavigation(to: v6Other), "IPv6 origin")
        for address in ["https://localhost/", "https://192.168.1.1/", "https://printer.local/", "https://[::1]/"] {
            guard case .block = BrowserPolicy.evaluate(address: address) else { throw Failure(label: "existing policy") }
            count += 1
        }
        guard case .allow = BrowserPolicy.evaluate(address: "https://example.com/") else { throw Failure(label: "public policy") }
        count += 1
        guard case .allow = BrowserPolicy.evaluate(address: "https://example.com./") else { throw Failure(label: "public root dot policy") }
        count += 1
        let owner = BrowserManualLANAccess()
        guard let aliasURL = URL(string: "http://localhost/"),
              let approvedRequest = owner.requestManualAccess(address: aliasURL.absoluteString) else { throw Failure(label: "alias setup") }
        try check(owner.approve(approvedRequest), "alias approval")
        let approvedAlias = owner
        owner.revoke()
        try check(approvedAlias.status == .disabled && !approvedAlias.allowsNavigation(to: aliasURL), "authorized alias revoked")
        try check(!approvedAlias.approve(approvedRequest), "revoked grant cannot be reapproved")
        guard let pendingRequest = owner.requestManualAccess(address: aliasURL.absoluteString) else { throw Failure(label: "pending alias setup") }
        let pendingAlias = owner
        owner.revoke()
        try check(pendingAlias.status == .disabled && !pendingAlias.approve(pendingRequest), "pending alias revoked")
        try check(owner.status == .disabled, "alias cannot restore owner grant")
        guard let pendingAgain = owner.requestManualAccess(address: aliasURL.absoluteString) else { throw Failure(label: "reverse pending setup") }
        pendingAlias.revoke()
        try check(!owner.approve(pendingAgain) && owner.status == .disabled, "alias revokes pending owner")
        guard let grantAgain = owner.requestManualAccess(address: aliasURL.absoluteString) else { throw Failure(label: "reverse grant setup") }
        try check(owner.approve(grantAgain), "reverse grant approval")
        approvedAlias.revoke()
        try check(!owner.allowsNavigation(to: aliasURL) && owner.status == .disabled, "alias revokes authorized owner")
        let separate = BrowserManualLANAccess()
        guard let separateRequest = separate.requestManualAccess(address: aliasURL.absoluteString) else { throw Failure(label: "separate session setup") }
        try check(separate.approve(separateRequest), "separate session approval")
        owner.revoke()
        try check(separate.allowsNavigation(to: aliasURL), "separate session unaffected")
        guard let display = separate.requestManualAccess(address: "HTTPS://printer.local:9443/path?q=fixture#section"),
              let displayV6 = separate.requestManualAccess(address: "http://[::1]:8088/path?q=fixture"),
              let displayDefault = separate.requestManualAccess(address: "HTTPS://localhost/") else { throw Failure(label: "display origin setup") }
        try check(display.displayOrigin == "https://printer.local:9443", "display nonstandard origin")
        try check(displayV6.displayOrigin == "http://[::1]:8088", "display IPv6 origin")
        try check(displayDefault.displayOrigin == "https://localhost:443", "display default HTTPS port")
        for address in ["http://localhost./", "http://printer.local./", "http://127.0.0.1./"] {
            try check(owner.requestManualAccess(address: address) == nil, "trailing dot rejected")
        }
        guard let plain = owner.requestManualAccess(address: "http://printer.local/"),
              let dotted = URL(string: "http://printer.local./") else { throw Failure(label: "trailing dot navigation setup") }
        try check(owner.approve(plain), "plain host approval")
        try check(!owner.allowsNavigation(to: dotted), "trailing dot redirect rejected")
        DispatchQueue.concurrentPerform(iterations: 400) { iteration in
            if iteration.isMultiple(of: 3) {
                approvedAlias.revoke()
            } else if let request = owner.requestManualAccess(address: aliasURL.absoluteString) {
                _ = pendingAlias.approve(request)
                _ = approvedAlias.allowsNavigation(to: aliasURL)
            }
        }
        pendingAlias.revoke()
        try check(owner.status == .disabled && !approvedAlias.allowsNavigation(to: aliasURL), "concurrent aliases final revocation")
        print("PASS manual LAN policy: \(count) checks; pure Swift, no network")
    }
}
