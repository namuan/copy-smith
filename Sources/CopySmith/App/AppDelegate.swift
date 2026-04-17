import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: PopupWindow?
    private var viewModel: MainViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let vm = MainViewModel()
        viewModel = vm

        let vc = MainViewController(viewModel: vm)

        let win = PopupWindow(
            contentRect: NSRect(x: 0, y: 0,
                                width: Styles.windowWidth, height: Styles.windowHeight),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        win.title = "Popup"
        win.contentViewController = vc
        win.isMovableByWindowBackground = true
        win.backgroundColor = .clear
        win.isOpaque = false
        win.hasShadow = true
        win.center()
        win.makeKeyAndOrderFront(nil)

        window = win
    }

    func applicationWillTerminate(_ notification: Notification) {
        viewModel?.cancelAll()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

// MARK: - Custom borderless window

final class PopupWindow: NSWindow {
    /// Required for borderless windows to receive keyboard events.
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}
