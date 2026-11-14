#if os(iOS)
import UIKit
import WebKit

/// Hosts the session's WKWebView inside the browser screen.
@MainActor
final class BrowserWebContainer: UIView {
    private let webView: WKWebView
    private let onDetach: () -> Void

    init(webView: WKWebView, onDetach: @escaping () -> Void) {
        self.webView = webView
        self.onDetach = onDetach
        super.init(frame: .zero)
        isAccessibilityElement = false
        accessibilityIdentifier = "browser.viewport"
        // The extended WebKit canvas must never cover browser chrome, receive
        // touches outside this viewport, or expose text drawn outside it.
        clipsToBounds = true
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) { return nil }

    func setCoveredByResearch(_ covered: Bool) {
        guard webView.superview === self else { return }
        // Preserve the existing modal accessibility boundary and mounted view.
        accessibilityElementsHidden = covered
        accessibilityElements = covered ? [] : [webView]
        automationElements = covered ? [] : [webView]
        webView.accessibilityElementsHidden = covered
        setNeedsLayout()
    }

    func detachWebView() {
        // A replacement wrapper may already own the cached WKWebView.
        guard webView.superview === self else { return }
        accessibilityElementsHidden = false
        accessibilityElements = nil
        automationElements = nil
        webView.accessibilityElementsHidden = false
        onDetach()
        webView.removeFromSuperview()
    }
}
#endif
