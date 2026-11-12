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

/// Applied to the whole chat column: ignore SwiftUI's keyboard safe area and
/// pad the bottom for this app's own docked keyboard, moving with it (its own
/// animation duration). A surface that replaces the keyboard, such as the
/// attachment panel, drops the space at once.
struct ChatKeyboardReserveModifier: ViewModifier {
    @ObservedObject var dock: ChatKeyboardDock
    let replaced: Bool
    @State private var frame = CGRect.zero

    private var reserve: CGFloat { replaced ? 0 : dock.reserve(below: frame) }

    func body(content: Content) -> some View {
        content
            .padding(.bottom, reserve)
            .animation(.easeOut(duration: dock.animationDuration), value: reserve)
            .background {
                // The column's own frame does not depend on the padding above.
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { frame = proxy.frame(in: .global) }
                        .onChange(of: proxy.frame(in: .global)) { _, value in frame = value }
                }
            }
            .ignoresSafeArea(.keyboard, edges: .bottom)
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
