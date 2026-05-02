import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: PopupWindow?
    private var viewModel: MainViewModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        log.info("App", "launched — version \(version), pid \(ProcessInfo.processInfo.processIdentifier)")

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
        log.info("App", "terminating")
        viewModel?.cancelAll()
        viewModel = nil

        // llama.cpp b8851 dispatches ggml_metal_rsets_init asynchronously and
        // the block sleeps 500 ms between retries.  llama_backend_free() does
        // not drain that dispatch block, so when exit() calls the C++ static
        // destructor chain, ggml_metal_rsets_free() fires GGML_ASSERT because
        // rsets->data is still populated.  _exit(0) skips C++ destructors
        // entirely — safe for this popup app which has no pending I/O.
        _exit(0)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}


final class PopupWindow: NSWindow {
    /// Required for borderless windows to receive keyboard events.
    override var canBecomeKey: Bool  { true }
    override var canBecomeMain: Bool { true }
}
