import Foundation

@main
enum CheckChatKeyboardReserve {
    static func main() {
        var assertions = 0
        func expect(_ condition: @autoclosure () -> Bool) {
            precondition(condition())
            assertions += 1
        }
        let window = CGRect(x: 0, y: 0, width: 810, height: 1080)

        // The iPad (9th generation) portrait keyboard measured on device,
        // including the 完成 toolbar, docks across the bottom edge.
        let docked = CGRect(x: 0, y: 815, width: 810, height: 265)
        expect(ChatKeyboardReserve.isDocked(docked, in: window))
        expect(ChatKeyboardReserve.height(viewBottom: 1080, keyboardTop: docked.minY) == 265)
        // A view that already ends above the keyboard reserves nothing.
        expect(ChatKeyboardReserve.height(viewBottom: 700, keyboardTop: docked.minY) == 0)

        // A hardware keyboard's shortcut bar is still a docked input panel.
        let bar = CGRect(x: 0, y: 1025, width: 810, height: 55)
        expect(ChatKeyboardReserve.isDocked(bar, in: window))
        expect(ChatKeyboardReserve.height(viewBottom: 1080, keyboardTop: bar.minY) == 55)

        // Floating, undocked or split keyboards and a keyboard moved off the
        // bottom edge never lift the composer.
        expect(!ChatKeyboardReserve.isDocked(CGRect(x: 200, y: 500, width: 320, height: 250), in: window))
        expect(!ChatKeyboardReserve.isDocked(CGRect(x: 0, y: 600, width: 810, height: 265), in: window))
        expect(!ChatKeyboardReserve.isDocked(CGRect(x: 0, y: 1080, width: 810, height: 265), in: window))

        // A screen-wide keyboard over a narrower Split View window still docks.
        let narrow = CGRect(x: 0, y: 0, width: 507, height: 1080)
        expect(ChatKeyboardReserve.isDocked(CGRect(x: -2, y: 815, width: 1620, height: 265), in: narrow))

        // Empty, null and non-finite input reserves nothing.
        expect(!ChatKeyboardReserve.isDocked(.zero, in: window))
        expect(!ChatKeyboardReserve.isDocked(.null, in: window))
        expect(!ChatKeyboardReserve.isDocked(docked, in: .zero))
        expect(ChatKeyboardReserve.height(viewBottom: .infinity, keyboardTop: 815) == 0)
        expect(ChatKeyboardReserve.height(viewBottom: 1080, keyboardTop: .nan) == 0)

        print("{\"assertions\":\(assertions)}")
    }
}
