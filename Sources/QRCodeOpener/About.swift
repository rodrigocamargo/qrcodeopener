import AppKit

/// Company and product identity. Everything user-visible is read from `Info.plist` where
/// possible so the About box can never drift from what was actually shipped.
enum About {
    static let companyName = "Robots Drinking Tea LLC"
    static let supportURL = URL(string: "https://robotsdrinkingtea.com/qrcodeopener/support")!

    static var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "QR Code Opener"
    }

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    static var copyright: String {
        Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String
            ?? "Copyright © 2026 \(companyName)"
    }

    @MainActor
    static func showPanel() {
        NSApp.activate(ignoringOtherApps: true)

        let credits = NSMutableAttributedString()
        credits.append(NSAttributedString(
            string: "Scan every QR code on screen and copy its link — without reaching for your phone.\n\n",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.labelColor,
            ]
        ))
        credits.append(NSAttributedString(
            string: "Created by \(companyName)",
            attributes: [
                .font: NSFont.systemFont(ofSize: 11, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor,
            ]
        ))

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: appName,
            .applicationVersion: version,
            .version: "(\(build))",
            .credits: credits,
            NSApplication.AboutPanelOptionKey(rawValue: "Copyright"): copyright,
        ])
    }
}
