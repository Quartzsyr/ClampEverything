import AppKit

/// Own exactly one hide call, balanced on every exit path.
@MainActor final class CursorVisibilityLease {
    private(set) var acquired = false
    private let hide: () -> Bool
    private let show: () -> Void
    init(hide: @escaping () -> Bool = { CGDisplayHideCursor(CGMainDisplayID()) == .success },
         show: @escaping () -> Void = { _ = CGDisplayShowCursor(CGMainDisplayID()) }) {
        self.hide = hide; self.show = show
    }
    @discardableResult func acquire() -> Bool {
        if acquired { return true }
        acquired = hide(); return acquired
    }
    func release() { guard acquired else { return }; show(); acquired = false }
}
