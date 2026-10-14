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
    override func mouseDown(with event: NSEvent) { start = NSEvent.mouseLocation; dragged = false }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = NSEvent.mouseLocation
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
    func makeNSView(context: Context) -> ContentDragView { let view = ContentDragView(); configure(view); return view }
    func updateNSView(_ view: ContentDragView, context: Context) { configure(view) }
    private func configure(_ view: ContentDragView) {
        view.writer = { store.pasteboardItem(item) }
        view.preview = {
            let icon = store.images[item.id] ?? store.fileURL(item).map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage(systemSymbolName: item.kind.symbol, accessibilityDescription: nil)
            return ContentDragPreview.image(title: item.title, icon: icon)
        }
        view.interaction = interaction; view.copyAction = { store.copy(item) }
        view.showLabel = showLabel
    }
}
final class ContentDragView: NSView, NSDraggingSource {
    var writer: () -> NSPasteboardItem? = { nil }
    var preview: () -> NSImage? = { nil }
    var interaction: (Bool) -> Void = { _ in }
    var copyAction: () -> Void = {}
    var showLabel = true
    private var start: NSPoint?
    private var dragged = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { start = event.locationInWindow; dragged = false }
    override func mouseDragged(with event: NSEvent) {
        guard let start, !dragged, hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y) > 4, let writer = writer() else { return }
        dragged = true; interaction(true)
        let draggingItem = NSDraggingItem(pasteboardWriter: writer)
        draggingItem.setDraggingFrame(NSRect(origin: convert(event.locationInWindow, from: nil), size: ContentDragPreview.size), contents: preview())
        beginDraggingSession(with: [draggingItem], event: event, source: self).animatesToStartingPositionsOnCancelOrFail = true
    }
    override func mouseUp(with event: NSEvent) { if !dragged { copyAction() }; start = nil }
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation { .copy }
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { dragged = false; start = nil; interaction(false) }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        guard showLabel else { return }
        let text = "拖出 · 轻点复制" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor]
        let size = text.size(withAttributes: attributes)
        text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: attributes)
    }
    override func accessibilityLabel() -> String? { "拖出内容，或单击复制" }
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
