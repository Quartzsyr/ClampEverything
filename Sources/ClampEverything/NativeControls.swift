import AppKit
import SwiftUI
import QuickLookUI
import ClampCore

struct MoveHandle: NSViewRepresentable {
    var begin: () -> Void
    var move: (NSPoint) -> Void
    var end: () -> Void
    var click: () -> Void = {}
    var label = "移动夹子，拖到屏幕边缘收起"
    func makeNSView(context: Context) -> HandleView { let view = HandleView(); configure(view); return view }
    func updateNSView(_ view: HandleView, context: Context) { configure(view) }
    private func configure(_ view: HandleView) { view.begin = begin; view.move = move; view.end = end; view.click = click; view.handleLabel = label }
}
final class HandleView: NSView {
    var begin: () -> Void = {}
    var move: (NSPoint) -> Void = { _ in }
    var click: () -> Void = {}
    var end: () -> Void = {}
    var handleLabel = "移动夹子，拖到屏幕边缘收起"
    private var start: NSPoint?
    private var dragged = false
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true); setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    private func screenPoint(_ event: NSEvent) -> NSPoint {
        if let cg = event.cgEvent {
            return NSPoint(x: cg.location.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - cg.location.y)
        }
        return window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }
    override func mouseDown(with event: NSEvent) { start = screenPoint(event); dragged = false }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = screenPoint(event)
        if !dragged && hypot(point.x - start.x, point.y - start.y) > 4 { dragged = true; begin(); NSCursor.closedHand.push() }
        if dragged { move(NSPoint(x: point.x - start.x, y: point.y - start.y)) }
    }
    override func mouseUp(with event: NSEvent) { if dragged { NSCursor.pop(); end() } else { click() }; dragged = false; start = nil }
    override func accessibilityLabel() -> String? { handleLabel }
    override func accessibilityPerformPress() -> Bool { click(); return true }
}

struct ContentDragHandle: NSViewRepresentable {
    let item: ClipItem
    @ObservedObject var store: ClipStore
    var interaction: (Bool) -> Void = { _ in }
    var showLabel = true
    var scroll: ((PreviewScroll) -> Void)? = nil
    var stabilizeWhilePressed = false
    func makeNSView(context: Context) -> ContentDragView { let view = ContentDragView(); configure(view); return view }
    func updateNSView(_ view: ContentDragView, context: Context) { configure(view) }
    private func configure(_ view: ContentDragView) {
        view.writer = { store.pasteboardItem(item) }
        view.preview = {
            let icon = store.images[item.id] ?? store.fileURL(item).map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: item.kind.symbol, accessibilityDescription: nil)
            return ContentDragPreview.image(title: item.title, icon: icon)
        }
        view.interaction = interaction
        view.copyAction = { [weak view] in view?.showCopyFeedback(success: store.copy(item)) }
        view.showLabel = showLabel; view.scrollAction = scroll
        view.stabilizeWhilePressed = stabilizeWhilePressed
    }
}
final class ContentDragView: NSView, NSDraggingSource {
    var writer: () -> NSPasteboardItem? = { nil }
    var preview: () -> NSImage? = { nil }
    var interaction: (Bool) -> Void = { _ in }
    var copyAction: () -> Void = {}
    var showLabel = true
    var scrollAction: ((PreviewScroll) -> Void)?
    private var start: NSPoint?
    private var dragged = false
    var stabilizeWhilePressed = false
    private var pressLocked = false
    private var discardsMomentum = false
    private var copyFeedback: Bool?
    private var copyFlash: DispatchWorkItem?
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    // Page turns resize the window between down and up; screen coordinates
    // distinguish real pointer movement from a change of window origin.
    private func screenPoint(_ windowPoint: CGPoint) -> CGPoint {
        window?.convertPoint(toScreen: windowPoint) ?? windowPoint
    }
    override func mouseDown(with event: NSEvent) {
        start = screenPoint(event.locationInWindow); dragged = false; discardsMomentum = true
        if stabilizeWhilePressed { pressLocked = true; interaction(true) }
    }
    private func unlockPress() {
        guard pressLocked else { return }; pressLocked = false; interaction(false)
    }
    func prepareDrag(at point: CGPoint) -> NSPasteboardItem? {
        let point = screenPoint(point)
        guard let start, !dragged, hypot(point.x - start.x, point.y - start.y) > 4, let item = writer() else { return nil }
        dragged = true; interaction(true)
        return item
    }
    override func mouseDragged(with event: NSEvent) {
        guard let writer = prepareDrag(at: event.locationInWindow) else { return }
        let draggingItem = NSDraggingItem(pasteboardWriter: writer)
        draggingItem.setDraggingFrame(NSRect(origin: convert(event.locationInWindow, from: nil), size: ContentDragPreview.size), contents: preview())
        beginDraggingSession(with: [draggingItem], event: event, source: self).animatesToStartingPositionsOnCancelOrFail = true
    }
    override func mouseUp(with event: NSEvent) {
        defer { self.start = nil; if !dragged { unlockPress() } }
        guard let start else { return }
        let point = screenPoint(event.locationInWindow)
        if !dragged && hypot(point.x - start.x, point.y - start.y) <= 4 {
            copyAction()
        }
    }
    override func scrollWheel(with event: NSEvent) {
        // A document press owns the gesture until up or drag. Trackpads can emit
        // non-momentum changed/ended deltas while clicking; these are not a new
        // reading gesture and must not erase the pending copy or turn a page.
        if stabilizeWhilePressed, start != nil { return }
        if stabilizeWhilePressed, discardsMomentum,
           !event.phase.intersection([.ended, .cancelled]).isEmpty { return }
        // A physical press stops the previous trackpad fling. Its queued momentum
        // must neither flip another page nor erase the new copy click.
        if !event.momentumPhase.isEmpty, start != nil || discardsMomentum {
            if event.momentumPhase.contains(.ended) || event.momentumPhase.contains(.cancelled) { discardsMomentum = false }
            return
        }
        // Genuine new scrolling still cancels the click; zero-delta end events do not.
        if abs(event.scrollingDeltaX) + abs(event.scrollingDeltaY) > 0.01 { discardsMomentum = false; start = nil; unlockPress() }
        guard let scrollAction else {
            if let target = readingScrollTarget(at: convert(event.locationInWindow, from: nil)) { target.scrollWheel(with: event) }
            else { super.scrollWheel(with: event) }
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        scrollAction(PreviewScroll(delta: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY),
            location: CGPoint(x: min(1, max(0, point.x / max(1, bounds.width))),
                              y: min(1, max(0, (isFlipped ? point.y : bounds.height - point.y) / max(1, bounds.height)))),
            precise: event.hasPreciseScrollingDeltas, phase: event.phase, momentum: event.momentumPhase, time: event.timestamp))
    }
    // The transparent copy/drag surface sits above text and code scroll views.
    // Forward wheel events to that native reader without changing click/drag.
    func readingScrollTarget(at point: CGPoint) -> NSScrollView? {
        if let enclosingScrollView { return enclosingScrollView }
        func find(_ root: NSView) -> NSScrollView? {
            guard root !== self, !root.isHidden, root.bounds.contains(root.convert(point, from: self)) else { return nil }
            if let scroll = root as? NSScrollView { return scroll }
            return root.subviews.lazy.compactMap(find).first
        }
        var ancestor = superview
        while let root = ancestor {
            if let target = find(root) { return target }
            ancestor = root.superview
        }
        return nil
    }
    func finishDrag() { dragged = false; start = nil; pressLocked = false; interaction(false) }
    func showCopyFeedback(success: Bool) {
        copyFeedback = success; needsDisplay = true; copyFlash?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.copyFeedback = nil; self?.needsDisplay = true }
        copyFlash = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (success ? 0.9 : 1.6), execute: work)
    }
    func resetForReuse() {
        start = nil; discardsMomentum = false; unlockPress(); copyFeedback = nil; copyFlash?.cancel(); copyFlash = nil; needsDisplay = true
    }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { finishDrag() }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        if let success = copyFeedback {
            let width = min(76, max(0, bounds.width - 4)), height = min(24, max(0, bounds.height - 4))
            let badge = CGRect(x: bounds.midX - width / 2, y: bounds.midY - height / 2, width: width, height: height)
            let ink = success ? NSColor(calibratedRed: 0.23, green: 0.40, blue: 0.39, alpha: 0.96) : NSColor.systemRed.withAlphaComponent(0.94)
            ink.setFill(); NSBezierPath(roundedRect: badge, xRadius: height / 2, yRadius: height / 2).fill()
            let label = (width >= 70 ? (success ? "✓ 已复制" : "未能复制") : (success ? "✓" : "!")) as NSString
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: height < 22 ? 9 : 10, weight: .medium), .foregroundColor: NSColor.white]
            let size = label.size(withAttributes: attributes)
            label.draw(at: CGPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2), withAttributes: attributes)
            return
        }
        guard showLabel else { return }
        let text = "拖出 · 轻点复制" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
    override func accessibilityLabel() -> String? { copyFeedback.map { $0 ? "已复制" : "未能复制" } ?? "拖出内容，或单击复制" }
}

struct DropZone: NSViewRepresentable {
    var label: String
    var fileOnly = false
    var receive: (NSPasteboard) -> Void
    var interaction: (Bool) -> Void = { _ in }
    var click: (() -> Void)? = nil
    func makeNSView(context: Context) -> DropTargetView { let view = DropTargetView(); configure(view); return view }
    func updateNSView(_ view: DropTargetView, context: Context) { configure(view) }
    private func configure(_ view: DropTargetView) {
        view.label = label; view.fileOnly = fileOnly; view.receive = receive; view.interaction = interaction; view.clickAction = click; view.needsDisplay = true
    }
}
final class DropTargetView: NSView {
    var label = "＋ 夹住"
    var fileOnly = false
    var receive: (NSPasteboard) -> Void = { _ in }
    var interaction: (Bool) -> Void = { _ in }
    var clickAction: (() -> Void)?
    private var highlighted = false
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect); registerForDraggedTypes([.fileURL, .png, .tiff, .string, .URL])
        setAccessibilityElement(true); setAccessibilityRole(.button)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseUp(with event: NSEvent) { clickAction?() }
    override func accessibilityPerformPress() -> Bool {
        guard let clickAction else { return false }
        clickAction(); return true
    }
    private func accepts(_ board: NSPasteboard) -> Bool {
        fileOnly ? board.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) : board.availableType(from: [.fileURL, .png, .tiff, .string, .URL]) != nil
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard accepts(sender.draggingPasteboard) else { return [] }
        highlighted = true; needsDisplay = true; interaction(true); return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { accepts(sender.draggingPasteboard) ? .copy : [] }
    override func draggingExited(_ sender: NSDraggingInfo?) { reset() }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { accepts(sender.draggingPasteboard) }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool { guard accepts(sender.draggingPasteboard) else { return false }; receive(sender.draggingPasteboard); reset(); return true }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { reset() }
    private func reset() { highlighted = false; needsDisplay = true; interaction(false) }
    override func draw(_ dirtyRect: NSRect) {
        guard !label.isEmpty else { return }
        (highlighted ? NSColor.controlAccentColor.withAlphaComponent(0.2) : NSColor.controlAccentColor.withAlphaComponent(0.06)).setFill()
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 8, yRadius: 8); path.fill()
        NSColor.controlAccentColor.withAlphaComponent(highlighted ? 0.8 : 0.25).setStroke(); path.setLineDash([4, 3], count: 2, phase: 0); path.stroke()
        let text = label as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.labelColor]
        let size = text.size(withAttributes: attributes)
        text.draw(in: NSRect(x: 6, y: max(4, (bounds.height - size.height) / 2), width: bounds.width - 12, height: size.height + 4), withAttributes: attributes)
    }
    override func accessibilityLabel() -> String? { label }
}

@MainActor final class PreviewController {
    static let shared = PreviewController()
    private var window: NSWindow?
    func show(_ url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            let alert = NSAlert(); alert.messageText = "无法预览原内容"; alert.informativeText = "文件不存在或设备未连接，请先重新关联位置。"; alert.runModal(); return
        }
        window?.close()
        let rect = NSRect(x: 0, y: 0, width: 720, height: 520)
        let previewWindow = NSWindow(contentRect: rect, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        previewWindow.isReleasedWhenClosed = false; previewWindow.title = "快速预览 · " + url.lastPathComponent
        guard let preview = QLPreviewView(frame: rect, style: .normal) else { return }
        preview.autostarts = false; preview.shouldCloseWithWindow = true; preview.previewItem = url as NSURL
        previewWindow.contentView = preview; previewWindow.center(); window = previewWindow
        NSApp.activate(ignoringOtherApps: true); previewWindow.makeKeyAndOrderFront(nil)
    }
}
