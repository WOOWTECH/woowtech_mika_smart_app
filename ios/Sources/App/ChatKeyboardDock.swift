import CoreGraphics
import Foundation

/// Pure geometry for the chat composer's keyboard space.
enum ChatKeyboardReserve {
    /// A docked keyboard spans the window's width and reaches its bottom edge.
    /// Floating, split, undocked or off-window keyboards reserve nothing.
    static func isDocked(_ keyboard: CGRect, in window: CGRect) -> Bool {
        guard valid(keyboard), valid(window) else { return false }
        let visible = keyboard.intersection(window)
        return valid(visible) && visible.minX <= window.minX + 1
            && visible.maxX >= window.maxX - 1 && visible.maxY >= window.maxY - 1
    }

    /// Real docked keyboards, with their toolbar and prediction bar, stay well
    /// under this share of the window. A stale occlusion once reported ~890 of
    /// 1080 pt on an iPad; anything taller than this is ignored.
    static let maximumShare: CGFloat = 0.7

    static func isPlausible(_ keyboard: CGRect, in window: CGRect) -> Bool {
        guard isDocked(keyboard, in: window) else { return false }
        return keyboard.intersection(window).height <= window.height * maximumShare
    }

    /// Space to keep clear below a view whose bottom edge is `viewBottom`.
    static func height(viewBottom: CGFloat, keyboardTop: CGFloat) -> CGFloat {
        guard viewBottom.isFinite, keyboardTop.isFinite else { return 0 }
        return max(0, viewBottom - keyboardTop)
    }

    /// A real bottom container inset is the home indicator: 34 pt on an iPhone,
    /// 20 pt on an iPad, 0 with a Home button. On the physical iPad (9th
    /// generation) the system reported about 900 pt here, and not as keyboard
    /// space, so the transcript was 0 pt tall under the navigation bar. Anything
    /// taller than this is not a home indicator and is ignored.
    static let maximumContainerBottom: CGFloat = 50

    static func containerBottom(_ reported: CGFloat) -> CGFloat {
        guard reported.isFinite, reported > 0, reported <= maximumContainerBottom else { return 0 }
        return reported
    }

    /// The column reaches the bottom edge; a docked keyboard covers the home
    /// indicator, so the larger of the two is kept clear, never both.
    static func bottomPadding(keyboard: CGFloat, containerBottom: CGFloat) -> CGFloat {
        max(keyboard.isFinite ? keyboard : 0, containerBottom)
    }

    private static func valid(_ rect: CGRect) -> Bool {
        !rect.isNull && !rect.isInfinite && !rect.isEmpty
            && rect.origin.x.isFinite && rect.origin.y.isFinite
            && rect.width.isFinite && rect.height.isFinite
    }
}

#if os(iOS)
import SwiftUI
import UIKit

/// Chat opts out of SwiftUI's automatic keyboard safe area. On a physical
/// iPad the system kept a stale ~890 pt bottom occlusion across keyboard
/// show/hide, view rebuilds and app relaunches: chat got ~100 pt, the
/// transcript (and its setup hint) collapsed to zero and the composer sat
/// under the navigation bar. Only this app's own keyboard, docked across the
/// bottom edge and of plausible height, reserves space here, whichever field
/// owns it, like SwiftUI's own avoidance.
@MainActor
final class ChatKeyboardDock: NSObject, ObservableObject {
    /// The docked local keyboard in window coordinates, or nil.
    @Published private(set) var frameInWindow: CGRect?
    /// The keyboard's own animation length, so the composer moves with it.
    @Published private(set) var animationDuration = 0.25

    override init() {
        super.init()
        for name in [UIResponder.keyboardWillChangeFrameNotification,
                     UIResponder.keyboardDidChangeFrameNotification,
                     UIResponder.keyboardWillHideNotification,
                     UIResponder.keyboardDidHideNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(keyboardChanged(_:)), name: name, object: nil)
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    /// Space to keep clear below a view framed in window (`.global`) coordinates.
    func reserve(below view: CGRect) -> CGFloat {
        guard let frameInWindow else { return 0 }
        return ChatKeyboardReserve.height(viewBottom: view.maxY, keyboardTop: frameInWindow.minY)
    }

    @objc private func keyboardChanged(_ notification: Notification) {
        let hiding = notification.name == UIResponder.keyboardWillHideNotification
            || notification.name == UIResponder.keyboardDidHideNotification
        // Another app's keyboard (multitasking, out-of-process pickers) never
        // moves this composer.
        let local = (notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? NSNumber)?.boolValue ?? true
        if let duration = (notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? NSNumber)?.doubleValue,
           duration > 0, duration < 2, duration != animationDuration {
            animationDuration = duration
        }
        var docked: CGRect?
        if !hiding, local,
           let end = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue,
           let window = Self.window(for: notification.object as? UIScreen) {
            // Keyboard frames are in screen coordinates; a window may be smaller.
            let frame = window.convert(end, from: window.screen.coordinateSpace)
            if ChatKeyboardReserve.isPlausible(frame, in: window.bounds) { docked = frame }
        }
        if frameInWindow != docked { frameInWindow = docked }
    }

    private static func window(for screen: UIScreen?) -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .filter { screen == nil || $0.screen === screen }
        return scenes.first(where: { $0.activationState == .foregroundActive })?.keyWindow
            ?? scenes.first?.keyWindow
    }
}

/// Applied to the whole chat column: ignore SwiftUI's keyboard and bottom
/// container safe areas and pad the bottom itself, for this app's own docked
/// keyboard (moving with it, at its own animation duration) or else a plausible
/// home indicator (see ChatKeyboardReserve.containerBottom). A surface that
/// replaces the keyboard, such as the attachment panel, drops the keyboard space at once.
struct ChatKeyboardReserveModifier: ViewModifier {
    @ObservedObject var dock: ChatKeyboardDock
    let replaced: Bool
    @State private var frame = CGRect.zero
    /// The bottom container inset as the system reports it, before the check.
    @State private var reportedBottom: CGFloat = 0

    private var reserve: CGFloat { replaced ? 0 : dock.reserve(below: frame) }
    private var bottomPadding: CGFloat {
        ChatKeyboardReserve.bottomPadding(keyboard: reserve,
                                          containerBottom: ChatKeyboardReserve.containerBottom(reportedBottom))
    }

    func body(content: Content) -> some View {
        content
            .padding(.bottom, bottomPadding)
            .animation(.easeOut(duration: dock.animationDuration), value: reserve)
            .background {
                // The column's own frame does not depend on the padding above.
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { frame = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { _, value in frame = value }
                }
            }
            .overlay(alignment: .topLeading) {
                if ChatLayoutProbe.isEnabled {
                    ChatLayoutProbe(reportedBottom: reportedBottom, column: frame,
                                    keyboard: dock.frameInWindow, padding: bottomPadding)
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
            .ignoresSafeArea(.container, edges: .bottom)
            .background {
                // Outside the ignored regions this reads the inset the system reports.
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { reportedBottom = proxy.safeAreaInsets.bottom }
                        .onChange(of: proxy.safeAreaInsets.bottom) { _, value in reportedBottom = value }
                }
            }
    }
}

/// Diagnostic readout for the physical iPad's bottom inset (launch argument
/// -WoowLayoutProbe only): what SwiftUI and UIKit each report, so a wrong
/// inset can be traced to its layer. It shows numbers only.
struct ChatLayoutProbe: View {
    static let isEnabled = ProcessInfo.processInfo.arguments.contains("-WoowLayoutProbe")
    let reportedBottom: CGFloat
    let column: CGRect
    let keyboard: CGRect?
    let padding: CGFloat
    @State private var window = ""

    var body: some View {
        let text = "swiftUIBottom=\(Int(reportedBottom)) padding=\(Int(padding)) column=\(Self.rect(column)) "
            + "dockKeyboard=\(keyboard.map(Self.rect) ?? "nil") \(window)"
        Text(verbatim: text)
            .font(.system(size: 10, design: .monospaced))
            .padding(4)
            .background(Color.yellow.opacity(0.85))
            .background(ChatWindowInsetsReader { window = $0 }.frame(width: 1, height: 1))
            .accessibilityIdentifier("layout.probe")
            .allowsHitTesting(false)
    }

    static func rect(_ r: CGRect) -> String {
        "(\(Int(r.minX)),\(Int(r.minY)),\(Int(r.width)),\(Int(r.height)))"
    }
}

/// Reads the hosting window's UIKit insets and keyboard layout guide.
private struct ChatWindowInsetsReader: UIViewRepresentable {
    let report: (String) -> Void
    func makeUIView(context: Context) -> ReaderView { ReaderView(report: report) }
    func updateUIView(_ view: ReaderView, context: Context) { view.report = report; view.publish() }

    final class ReaderView: UIView {
        var report: (String) -> Void
        private var last = ""
        init(report: @escaping (String) -> Void) { self.report = report; super.init(frame: .zero) }
        required init?(coder: NSCoder) { nil }
        override func layoutSubviews() { super.layoutSubviews(); publish() }
        override func safeAreaInsetsDidChange() { super.safeAreaInsetsDidChange(); publish() }
        func publish() {
            guard let window else { return }
            let root = window.rootViewController
            func edges(_ i: UIEdgeInsets) -> String { "t\(Int(i.top))b\(Int(i.bottom))" }
            let text = "window=\(edges(window.safeAreaInsets)) root=\(root.map { edges($0.view.safeAreaInsets) } ?? "nil") "
                + "additional=\(root.map { edges($0.additionalSafeAreaInsets) } ?? "nil") "
                + "kbGuide=\(ChatLayoutProbe.rect(window.keyboardLayoutGuide.layoutFrame)) "
                + "bounds=\(ChatLayoutProbe.rect(window.bounds))"
            guard text != last else { return }
            last = text
            DispatchQueue.main.async { [report] in report(text) }
        }
    }
}

extension View {
    /// See ChatKeyboardReserveModifier. `replaced`: another bottom surface,
    /// such as the attachment panel, is taking the keyboard's place.
    func chatKeyboardReserve(_ dock: ChatKeyboardDock, replaced: Bool = false) -> some View {
        modifier(ChatKeyboardReserveModifier(dock: dock, replaced: replaced))
    }
}
#endif
