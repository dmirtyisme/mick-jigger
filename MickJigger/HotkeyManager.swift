import AppKit
import Carbon.HIToolbox

/// Registers ⌥⌘J (toggle active) and ⌥⌘M (toggle monitoring) as global
/// hotkeys via Carbon RegisterEventHotKey — App Store safe, survives sleep.
///
/// Carbon hotkey events arrive as NSEvent.systemDefined with subtype 6.
/// MickJiggerApp intercepts them in sendEvent(_:) and dispatches here.
final class HotkeyManager {

    var onToggle: (() -> Void)?
    var onToggleMonitor: (() -> Void)?

    // Referenced from MickJiggerApp.sendEvent — must outlive the hotkeys.
    static weak var current: HotkeyManager?

    private var toggleKey: EventHotKeyRef?
    private var monitorKey: EventHotKeyRef?

    private static let sig: OSType = 0x4D4B4A47  // "MKJG"
    static let toggleID:  UInt32 = 1
    static let monitorID: UInt32 = 2

    func register() {
        HotkeyManager.current = self
        let mods = UInt32(optionKey | cmdKey)
        var id1 = EventHotKeyID(signature: Self.sig, id: Self.toggleID)
        var id2 = EventHotKeyID(signature: Self.sig, id: Self.monitorID)
        RegisterEventHotKey(UInt32(kVK_ANSI_J), mods, id1,
                            GetApplicationEventTarget(), 0, &toggleKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_M), mods, id2,
                            GetApplicationEventTarget(), 0, &monitorKey)
    }

    deinit {
        if let ref = toggleKey  { UnregisterEventHotKey(ref) }
        if let ref = monitorKey { UnregisterEventHotKey(ref) }
    }
}

/// Custom NSApplication subclass that intercepts Carbon hotkey system events.
/// Set via NSPrincipalClass in Info.plist (handled in main.swift by using
/// MickJiggerApp.shared instead of NSApplication.shared).
final class MickJiggerApp: NSApplication {
    override func sendEvent(_ event: NSEvent) {
        // Carbon RegisterEventHotKey events arrive as systemDefined, subtype 6.
        if event.type == .systemDefined && event.subtype.rawValue == 6 {
            let keyCode = UInt32((event.data1 & 0xFFFF0000) >> 16)
            let keyDown  = ((event.data1 & 0xFF00) >> 8) == 0x0A
            if keyDown {
                switch keyCode {
                case HotkeyManager.toggleID:  HotkeyManager.current?.onToggle?()
                case HotkeyManager.monitorID: HotkeyManager.current?.onToggleMonitor?()
                default: break
                }
                return  // consumed; don't pass further
            }
        }
        super.sendEvent(event)
    }
}
