import Carbon.HIToolbox
import Foundation

/// A process-wide hotkey registered through Carbon's `RegisterEventHotKey`.
///
/// Carbon hotkeys are deliberate here: an `NSEvent` global monitor would work too, but it
/// requires the Accessibility (input monitoring) permission. This API does not, so the app
/// only ever asks for Screen Recording.
final class HotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let id: UInt32

    /// The registry deliberately stores the *action*, not the `HotKey` itself: holding the
    /// object here would keep it alive forever and `deinit` would never run, leaking the
    /// Carbon registration every time the shortcut is rebound.
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1

    /// Returns nil when the combination is already claimed by another application.
    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        id = HotKey.nextID
        HotKey.nextID += 1
        HotKey.actions[id] = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, _ in
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return status }
            HotKey.actions[hotKeyID.id]?()
            return noErr
        }

        var handlerRef: EventHandlerRef?
        guard InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType, nil, &handlerRef) == noErr else {
            HotKey.actions[id] = nil
            return nil
        }
        handler = handlerRef

        let hotKeyID = EventHotKeyID(signature: OSType(0x51524b45), id: id) // 'QRKE'
        var hotKeyRef: EventHotKeyRef?
        guard RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
            RemoveEventHandler(handlerRef)
            HotKey.actions[id] = nil
            return nil
        }
        ref = hotKeyRef
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        HotKey.actions[id] = nil
    }
}
