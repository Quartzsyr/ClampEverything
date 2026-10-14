import Foundation

/// CGEvent/NSEvent device-independent modifiers, without lock/device bits.
public struct HoldShortcut: Codable, Equatable, Sendable {
    public static let modifierMask: UInt64 = (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20) | (1 << 23)
    public var keyCode: UInt16?
    public var modifiers: UInt64
    public var label: String
    public init(keyCode: UInt16? = nil, modifiers: UInt64, label: String) {
        self.keyCode = keyCode; self.modifiers = modifiers & Self.modifierMask; self.label = label
    }
    public static let option = HoldShortcut(modifiers: 1 << 19, label: "⌥ Option")
    public func conflicts(with shortcut: Shortcut) -> Bool {
        guard keyCode.map(UInt32.init) == shortcut.keyCode else { return false }
        let carbon: UInt32 = ((modifiers & (1 << 20) != 0) ? 256 : 0)
            | ((modifiers & (1 << 17) != 0) ? 512 : 0)
            | ((modifiers & (1 << 19) != 0) ? 2048 : 0)
            | ((modifiers & (1 << 18) != 0) ? 4096 : 0)
        return carbon == shortcut.modifiers
    }
    public var isValid: Bool { (modifiers & ~Self.modifierMask == 0) && (keyCode != nil || modifiers != 0) && keyCode != 53 && (keyCode.map { $0 < 128 } ?? true) }
}

/// No key content is stored. Tracks only the configured physical key and modifiers.
public struct HoldGestureState {
    public private(set) var active = false
    private var keyHeld = false
    private var cancelled = false
    private var consumedKey: UInt16?
    public init() {}
    /// Returns whether this keyboard event belongs to the gesture and must be swallowed.
    public mutating func update(shortcut: HoldShortcut, flags: UInt64, key: UInt16? = nil, down: Bool? = nil, repeated: Bool = false) -> Bool {
        let modifiersMatch = flags & HoldShortcut.modifierMask == shortcut.modifiers
        var consume = false
        if key == 53 && down == true && active {
            cancelled = true; active = false; return true
        }
        // Modifier-only gestures must not interfere with normal Option/Command shortcuts.
        if shortcut.keyCode == nil, key != nil, down == true {
            cancelled = true; active = false; return false
        }
        if let key, let down, key == shortcut.keyCode {
            if down {
                if !repeated { keyHeld = true }
                if consumedKey == key || (!repeated && modifiersMatch) { consumedKey = key; consume = true }
            } else {
                consume = consumedKey == key; consumedKey = nil; keyHeld = false
            }
        }
        let held = shortcut.keyCode == nil ? modifiersMatch : (keyHeld && modifiersMatch && consumedKey != nil)
        if !held { cancelled = false }
        active = shortcut.isValid && held && !cancelled
        return consume
    }
    public mutating func cancel() { if active { cancelled = true }; active = false }
    public mutating func reset() { self = HoldGestureState() }
}
