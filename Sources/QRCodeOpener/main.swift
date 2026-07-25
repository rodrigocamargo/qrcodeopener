import AppKit

// `NSApplication.delegate` is a weak reference, so the delegate is held here for the
// lifetime of the process.
private var appDelegate: AppDelegate?

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    appDelegate = delegate
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
