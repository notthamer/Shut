import Carbon.HIToolbox
import Foundation

/// A global hot key via Carbon's RegisterEventHotKey. Unlike NSEvent global
/// monitors it needs no Accessibility permission, which is why this ancient API
/// is still the right tool.
public final class HotKey {
    public static let keyT: UInt32 = UInt32(kVK_ANSI_T)
    public static let controlOption: UInt32 = UInt32(controlKey | optionKey)

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static var registry: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1
    private let id: UInt32

    public init?(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        id = HotKey.nextID
        HotKey.nextID += 1

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            DispatchQueue.main.async { HotKey.registry[hotKeyID.id]?.action() }
            return noErr
        }, 1, &eventType, nil, &handler)
        guard status == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x544E5252) /* 'TNRR' */, id: id)
        guard RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr else {
            return nil
        }
        HotKey.registry[id] = self
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
        HotKey.registry[id] = nil
    }
}
