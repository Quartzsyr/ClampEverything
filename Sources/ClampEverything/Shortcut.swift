import AppKit
import Carbon
import ClampCore

@MainActor final class ShortcutManager {
    static let shared = ShortcutManager()
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var action: (() -> Void)?
    private var current: Shortcut?
    func unregister() { if let reference { UnregisterEventHotKey(reference) }; reference = nil; action = nil; current = nil }
    func register(_ shortcut: Shortcut, action: @escaping () -> Void) -> String? {
        if shortcut == current { self.action = action; return nil }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
                guard let context else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated { Unmanaged<ShortcutManager>.fromOpaque(context).takeUnretainedValue().action?() }
                return noErr
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
            if status != noErr { return "快捷键监听未能启动（\(status)）。" }
        }
        var newReference: EventHotKeyRef?
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x434C4D50, id: 1), GetApplicationEventTarget(), 0, &newReference)
        guard status == noErr else { return "此快捷键无法注册，可能已被占用（\(status)）。" }
        unregister(); reference = newReference; self.action = action; current = shortcut; return nil
    }
}
