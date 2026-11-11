import Foundation

/// A single, explicit manual approval request. It contains no network capability.
public struct BrowserManualLANRequest: Equatable, Sendable {
    public let url: URL
    fileprivate let id: UUID
    fileprivate let origin: BrowserManualLANOrigin

    /// Display only the origin in the confirmation, not path, query or fragment.
    public var displayOrigin: String {
        let scheme = (url.scheme ?? "").lowercased()
        var host = url.host ?? ""
        if host.contains(":"), !host.hasPrefix("[") { host = "[" + host + "]" }
        return scheme + "://" + host + ":" + String(url.port ?? (scheme == "https" ? 443 : 80))
    }
}

/// Dormant first-stage policy; no WebKit, ATS, DNS or subresource enforcement.
/// Create one per manual browsing session. References share one locked state;
/// revoking through any reference invalidates the grant for every reference.
/// Requests and grants are in memory only.
public final class BrowserManualLANAccess: @unchecked Sendable {
    public enum Status: Equatable, Sendable { case disabled, awaitingApproval, authorized }

    private let lock = NSLock()
    private var pending: BrowserManualLANRequest?
    private var granted: BrowserManualLANOrigin?

    public init() {}

    /// Classify input without creating a request or granting access.
    public static func candidate(address: String) -> URL? {
        BrowserPolicy.manualLANCandidate(address: address)
    }

    public var status: Status {
        lock.lock(); defer { lock.unlock() }
        if pending != nil { return .awaitingApproval }
        return granted == nil ? .disabled : .authorized
    }

    /// A new request always revokes the previous grant and pending request,
    /// including when the new text is invalid. Call only from a manual flow.
    public func requestManualAccess(address: String) -> BrowserManualLANRequest? {
        lock.lock(); defer { lock.unlock() }
        pending = nil; granted = nil
        guard let url = BrowserPolicy.manualLANCandidate(address: address),
              let origin = BrowserManualLANOrigin(url: url) else { return nil }
        let request = BrowserManualLANRequest(url: url, id: UUID(), origin: origin)
        pending = request
        return request
    }

    /// A stale or unrelated request cannot approve or cancel a newer one.
    @discardableResult public func approve(_ request: BrowserManualLANRequest) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard pending == request else { return false }
        pending = nil
        granted = request.origin
        return true
    }

    public func revoke() {
        lock.lock(); defer { lock.unlock() }
        pending = nil; granted = nil
    }

    /// Policy decision for a proposed top-level URL, including a redirect.
    /// False includes cross-origin, invalid and unapproved destinations. This
    /// does not establish that a network request has not already been sent.
    public func allowsNavigation(to url: URL) -> Bool {
        guard let valid = BrowserPolicy.manualLANCandidate(address: url.absoluteURL.absoluteString),
              let origin = BrowserManualLANOrigin(url: valid) else { return false }
        lock.lock(); defer { lock.unlock() }
        guard let granted else { return false }
        return origin == granted
    }
}

fileprivate struct BrowserManualLANOrigin: Equatable, Sendable {
    private let scheme: String
    private let host: String
    private let port: Int

    init?(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              var host = components.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host = String(host.dropFirst().dropLast())
        }
        if host.contains(":") {
            guard let bytes = BrowserPolicy.ipv6Bytes(host) else { return nil }
            // Byte representation equates compressed and expanded IPv6 spellings.
            host = bytes.map { String(format: "%02x", $0) }.joined(separator: ":")
        }
        self.scheme = scheme
        self.host = host
        self.port = components.port ?? (scheme == "https" ? 443 : 80)
    }
}
