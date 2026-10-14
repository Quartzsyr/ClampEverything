import Foundation
import Testing
@testable import ClampCore

struct HoldShortcutTests {
    let option: UInt64 = 1 << 19
    let command: UInt64 = 1 << 20
    @Test func modifierOnlyHoldReleaseAndLockFlags() {
        var state = HoldGestureState()
        let result9 = !state.update(shortcut: .option, flags: option | (1 << 16))
        #expect(result9)
        #expect(state.active)
        _ = state.update(shortcut: .option, flags: 0)
        #expect(!state.active)
        _ = state.update(shortcut: .option, flags: option | command)
        #expect(!state.active)
    }
    @Test func singleKeyConsumesRepeatsAndRelease() {
        var state = HoldGestureState()
        let shortcut = HoldShortcut(keyCode: 2, modifiers: 0, label: "D")
        let result19 = state.update(shortcut: shortcut, flags: 0, key: 2, down: true)
        #expect(result19)
        #expect(state.active)
        let result21 = state.update(shortcut: shortcut, flags: 0, key: 2, down: true, repeated: true)
        #expect(result21)
        let result22 = state.update(shortcut: shortcut, flags: 0, key: 2, down: false)
        #expect(result22)
        #expect(!state.active)
        let result24 = !state.update(shortcut: shortcut, flags: 0, key: 1, down: true)
        #expect(result24)
    }
    @Test func releasingModifierBeforeKeyStillConsumesKeyUp() {
        var state = HoldGestureState()
        let shortcut = HoldShortcut(keyCode: 2, modifiers: option, label: "⌥D")
        let result29 = state.update(shortcut: shortcut, flags: option, key: 2, down: true)
        #expect(result29)
        #expect(state.active)
        _ = state.update(shortcut: shortcut, flags: 0)
        #expect(!state.active)
        let result33 = state.update(shortcut: shortcut, flags: 0, key: 2, down: false)
        #expect(result33)
    }
    @Test func escapeAndOtherShortcutsDoNotRearmUntilRelease() {
        var state = HoldGestureState()
        _ = state.update(shortcut: .option, flags: option)
        let result38 = state.update(shortcut: .option, flags: option, key: 53, down: true)
        #expect(result38)
        _ = state.update(shortcut: .option, flags: option)
        #expect(!state.active)
        _ = state.update(shortcut: .option, flags: 0)
        _ = state.update(shortcut: .option, flags: option)
        #expect(state.active)
        let result44 = !state.update(shortcut: .option, flags: option, key: 2, down: true)
        #expect(result44)
        #expect(!state.active)
        _ = state.update(shortcut: .option, flags: option, key: 2, down: false)
        #expect(!state.active)
    }
    @Test func keyHeldBeforeModifiersDoesNotStealExistingInput() {
        var state = HoldGestureState()
        let shortcut = HoldShortcut(keyCode: 2, modifiers: option, label: "⌥D")
        let result52 = !state.update(shortcut: shortcut, flags: 0, key: 2, down: true)
        #expect(result52)
        _ = state.update(shortcut: shortcut, flags: option)
        #expect(!state.active)
        let result55 = !state.update(shortcut: shortcut, flags: option, key: 2, down: true, repeated: true)
        #expect(result55)
        let result56 = !state.update(shortcut: shortcut, flags: option, key: 2, down: false)
        #expect(result56)
    }
    @Test func modifierChordAndConflictDetection() {
        let shortcut = HoldShortcut(keyCode: 2, modifiers: option | command, label: "⌘⌥D")
        #expect(shortcut.conflicts(with: Shortcut(keyCode: 2, modifiers: 256 | 2048, label: "same")))
        #expect(!shortcut.conflicts(with: Shortcut(keyCode: 2, modifiers: 2048, label: "different")))
        #expect(!HoldShortcut(keyCode: 53, modifiers: 0, label: "Esc").isValid)
        #expect(!HoldShortcut(modifiers: 0, label: "empty").isValid)
        var state = HoldGestureState()
        let chord = HoldShortcut(modifiers: option | command, label: "⌘⌥")
        _ = state.update(shortcut: chord, flags: option | command)
        #expect(state.active)
        _ = state.update(shortcut: chord, flags: option)
        #expect(!state.active)
    }
    @Test func completionAfterReleaseDoesNotBlockNextGesture() {
        var state = HoldGestureState()
        _ = state.update(shortcut: .option, flags: option)
        state.cancel()
        _ = state.update(shortcut: .option, flags: option)
        #expect(!state.active)
        _ = state.update(shortcut: .option, flags: 0)
        state.cancel() // An asynchronous capture finishes after the user released Option.
        _ = state.update(shortcut: .option, flags: option)
        #expect(state.active)
        state.cancel()
        _ = state.update(shortcut: .option, flags: 0)
        _ = state.update(shortcut: .option, flags: option)
        #expect(state.active)
    }
    @Test func existingPreferencesMigrateWithoutEnablingPermissions() throws {
        let old = Data(#"{"hideInFullScreen":false,"showHiddenFiles":true}"#.utf8)
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: old)
        #expect(!preferences.holdToClampEnabled)
        #expect(preferences.holdShortcut == .option)
        #expect(preferences.showHiddenFiles)
        #expect(!preferences.hideInFullScreen)
        var changed = preferences
        changed.holdToClampEnabled = true
        changed.holdShortcut = HoldShortcut(keyCode: 2, modifiers: option, label: "⌥D")
        #expect(try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(changed)) == changed)
    }
    @Test func optionJCaptureRequiresReleaseBeforeAnotherCapture() {
        var state = HoldGestureState()
        let shortcut = HoldShortcut(keyCode: 38, modifiers: option, label: "⌥J")
        _ = state.update(shortcut: shortcut, flags: option)
        #expect(!state.active)
        let press = state.update(shortcut: shortcut, flags: option, key: 38, down: true)
        #expect(press)
        #expect(state.active)
        state.cancel() // A click completes this capture, while J is still down.
        let repeatPress = state.update(shortcut: shortcut, flags: option, key: 38, down: true, repeated: true)
        #expect(repeatPress)
        #expect(!state.active)
        let release = state.update(shortcut: shortcut, flags: option, key: 38, down: false)
        #expect(release)
        #expect(!state.active)
        let nextPress = state.update(shortcut: shortcut, flags: option, key: 38, down: true)
        #expect(nextPress)
        #expect(state.active)
        _ = state.update(shortcut: shortcut, flags: 0) // Option is released first.
        #expect(!state.active)
        let finalRelease = state.update(shortcut: shortcut, flags: 0, key: 38, down: false)
        #expect(finalRelease)
    }
}
