import AppKit

struct PreviewScroll {
    var delta: CGSize
    var location = CGPoint(x: 0.5, y: 0.5) // normalized, top-left origin
    var precise = false
    var phase: NSEvent.Phase = []
    var momentum: NSEvent.Phase = []
    var time: TimeInterval
}

/// One trackpad stroke turns at most one page; momentum cannot turn more pages.
struct PageScrollGate {
    private var accumulated: CGFloat = 0
    private var consumed = false
    private var lastEvent: TimeInterval = -.infinity
    private var lastTurn: TimeInterval = -.infinity
    mutating func direction(for event: PreviewScroll) -> Int? {
        defer { lastEvent = event.time }
        if !event.momentum.isEmpty { return nil }
        if event.phase.contains(.began) || (event.phase.isEmpty && event.time - lastEvent > 0.3) { consumed = false; accumulated = 0 }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) { accumulated = 0; return nil }
        guard !consumed, event.time - lastTurn > 0.5 else { return nil }
        let delta = abs(event.delta.height) >= abs(event.delta.width) ? event.delta.height : event.delta.width
        accumulated += delta
        let threshold: CGFloat = event.precise ? 24 : 1
        guard abs(accumulated) >= threshold else { return nil }
        let direction = accumulated < 0 ? 1 : -1
        accumulated = 0; lastTurn = event.time
        if event.precise { consumed = true }
        return direction
    }
}
