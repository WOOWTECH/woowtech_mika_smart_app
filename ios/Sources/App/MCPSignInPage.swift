#if os(iOS)
import AuthenticationServices
import UIKit

/// An MCP server's OAuth sign-in page, shown the way ChatGPT's is (ModelAccountSignIn):
/// ASWebAuthenticationSession with Safari's sign-ins, while the App stays in front.
/// The page comes back to the server's loopback listener (MCPSession.signIn), so its
/// callback scheme is never used. One page at a time; no address is logged.
@MainActor
final class MCPSignInPage: MCPSignInBrowsing {
    static let shared = MCPSignInPage()

    private var session: ASWebAuthenticationSession?
    private var closed: (@MainActor () -> Void)?
    private let presentation = ModelAccountPresentationAnchor()

    func open(_ url: URL, closed: @escaping @MainActor () -> Void) {
        close()
        let handler: ASWebAuthenticationSession.CompletionHandler = { [weak self] _, error in
            // The loopback callback finishes a sign-in; this only ends one the person closed first.
            Task { @MainActor in self?.pageClosed(error) }
        }
        let page: ASWebAuthenticationSession
        if #available(iOS 17.4, *) {
            page = ASWebAuthenticationSession(url: url, callback: .customScheme(ModelAccountSignIn.unusedCallbackScheme),
                                              completionHandler: handler)
        } else {
            page = ASWebAuthenticationSession(url: url, callbackURLScheme: ModelAccountSignIn.unusedCallbackScheme,
                                              completionHandler: handler)
        }
        page.presentationContextProvider = presentation
        // Like a browser: someone already signed in to the service in Safari need not type it again.
        page.prefersEphemeralWebBrowserSession = false
        session = page
        self.closed = closed
        if !page.start() {
            session = nil
            self.closed = nil
            closed()
        }
    }

    func close() {
        let page = session
        session = nil
        closed = nil
        page?.cancel()
    }

    /// The person closed the page before the sign-in finished; closing it here says nothing.
    private func pageClosed(_ error: Error?) {
        guard session != nil, let closed else { return }
        session = nil
        self.closed = nil
        if error != nil { closed() }
    }
}
#endif
