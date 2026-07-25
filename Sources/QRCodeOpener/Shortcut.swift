import AppKit
import Carbon.HIToolbox

/// A key combination, stored in Carbon terms because that is what `RegisterEventHotKey` takes.
struct Shortcut: Equatable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = Shortcut(
        keyCode: UInt32(kVK_ANSI_7),
        carbonModifiers: UInt32(cmdKey | shiftKey)
    )

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    init(keyCode: UInt32, cocoaModifiers: NSEvent.ModifierFlags) {
        var carbon: UInt32 = 0
        if cocoaModifiers.contains(.command) { carbon |= UInt32(cmdKey) }
        if cocoaModifiers.contains(.shift) { carbon |= UInt32(shiftKey) }
        if cocoaModifiers.contains(.option) { carbon |= UInt32(optionKey) }
        if cocoaModifiers.contains(.control) { carbon |= UInt32(controlKey) }
        self.init(keyCode: keyCode, carbonModifiers: carbon)
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbonModifiers & UInt32(cmdKey) != 0 { flags.insert(.command) }
        if carbonModifiers & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbonModifiers & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbonModifiers & UInt32(controlKey) != 0 { flags.insert(.control) }
        return flags
    }

    /// Shift alone is rejected: a global ⇧-only hotkey would swallow ordinary typing
    /// system-wide. At least one of ⌘/⌃/⌥ is required.
    var hasRequiredModifier: Bool {
        carbonModifiers & UInt32(cmdKey | controlKey | optionKey) != 0
    }

    /// e.g. "⌘⇧7". Modifiers use the standard macOS display order ⌃⌥⇧⌘.
    var displayString: String {
        Shortcut.modifierGlyphs(cocoaModifiers) + Shortcut.keyName(for: keyCode)
    }

    /// Just the modifier glyphs, for previewing a chord that has no key yet.
    static func modifierGlyphs(_ flags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option) { result += "⌥" }
        if flags.contains(.shift) { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result
    }

    /// The character for an `NSMenuItem` key equivalent, when the key has a plain one.
    var menuKeyEquivalent: String {
        guard Shortcut.specialKeyNames[keyCode] == nil else { return "" }
        return Shortcut.characterForKeyCode(keyCode)?.lowercased() ?? ""
    }

    // MARK: - Persistence

    private static let keyCodeDefault = "shortcut.keyCode"
    private static let modifiersDefault = "shortcut.carbonModifiers"

    static func load() -> Shortcut {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: keyCodeDefault) != nil else { return .default }
        return Shortcut(
            keyCode: UInt32(defaults.integer(forKey: keyCodeDefault)),
            carbonModifiers: UInt32(defaults.integer(forKey: modifiersDefault))
        )
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(Int(keyCode), forKey: Shortcut.keyCodeDefault)
        defaults.set(Int(carbonModifiers), forKey: Shortcut.modifiersDefault)
    }

    static func resetToDefault() {
        UserDefaults.standard.removeObject(forKey: keyCodeDefault)
        UserDefaults.standard.removeObject(forKey: modifiersDefault)
    }

    // MARK: - Key naming

    private static let specialKeyNames: [UInt32: String] = [
        UInt32(kVK_Return): "↩",
        UInt32(kVK_Tab): "⇥",
        UInt32(kVK_Space): "Space",
        UInt32(kVK_Delete): "⌫",
        UInt32(kVK_ForwardDelete): "⌦",
        UInt32(kVK_Escape): "⎋",
        UInt32(kVK_Home): "↖",
        UInt32(kVK_End): "↘",
        UInt32(kVK_PageUp): "⇞",
        UInt32(kVK_PageDown): "⇟",
        UInt32(kVK_LeftArrow): "←",
        UInt32(kVK_RightArrow): "→",
        UInt32(kVK_UpArrow): "↑",
        UInt32(kVK_DownArrow): "↓",
        UInt32(kVK_ANSI_KeypadEnter): "⌤",
        UInt32(kVK_F1): "F1", UInt32(kVK_F2): "F2", UInt32(kVK_F3): "F3",
        UInt32(kVK_F4): "F4", UInt32(kVK_F5): "F5", UInt32(kVK_F6): "F6",
        UInt32(kVK_F7): "F7", UInt32(kVK_F8): "F8", UInt32(kVK_F9): "F9",
        UInt32(kVK_F10): "F10", UInt32(kVK_F11): "F11", UInt32(kVK_F12): "F12",
    ]

    static func keyName(for keyCode: UInt32) -> String {
        if let special = specialKeyNames[keyCode] { return special }
        return characterForKeyCode(keyCode)?.uppercased() ?? "Key \(keyCode)"
    }

    /// Asks the active keyboard layout what the key produces, so an AZERTY or ABNT2 layout
    /// shows the character actually printed on the user's keycap.
    private static func characterForKeyCode(_ keyCode: UInt32) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        let layoutData = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        let layout = unsafeBitCast(CFDataGetBytePtr(layoutData), to: UnsafePointer<UCKeyboardLayout>.self)

        var deadKeyState: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0

        let status = UCKeyTranslate(
            layout,
            UInt16(keyCode),
            UInt16(kUCKeyActionDisplay),
            0, // no modifiers: we want the bare key legend
            UInt32(LMGetKbdType()),
            OptionBits(kUCKeyTranslateNoDeadKeysBit),
            &deadKeyState,
            characters.count,
            &length,
            &characters
        )

        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: characters, count: length)
    }
}
