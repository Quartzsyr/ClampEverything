import AppKit
import SwiftUI

extension NSPasteboard.PasteboardType {
    static let clampItemID = NSPasteboard.PasteboardType("local.quartz.ClampEverything.item-id")
}

struct LibraryDropZone: NSViewRepresentable {
    let destination: UUID
    @ObservedObject var store: ClipStore
    var highlighted: (Bool) -> Void = { _ in }
    var click: () -> Void = {}
    var beginMove: () -> Void = {}
    var move: (NSPoint) -> Void = { _ in }
    var endMove: () -> Void = {}
    func makeNSView(context: Context) -> LibraryDropView { let view = LibraryDropView(); configure(view); return view }
    func updateNSView(_ view: LibraryDropView, context: Context) { configure(view) }
    private func configure(_ view: LibraryDropView) {
        view.accepts = { store.canCombine($0, with: destination) }
        view.receive = { _ = store.combine($0, with: destination) }
        view.highlighted = highlighted; view.clickAction = click
        view.beginMove = beginMove; view.move = move; view.endMove = endMove
    }
}

final class LibraryDropView: NSView {
    var accepts: (UUID) -> Bool = { _ in false }
    var receive: (UUID) -> Void = { _ in }
    var highlighted: (Bool) -> Void = { _ in }
    var clickAction: () -> Void = {}
    var beginMove: () -> Void = {}
    var move: (NSPoint) -> Void = { _ in }
    var endMove: () -> Void = {}
    private func pointer(_ event: NSEvent) -> CGPoint { window?.convertPoint(toScreen: event.locationInWindow) ?? event.locationInWindow }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    private var pressPoint: CGPoint?
    private var mouseMoved = false
    override func mouseDown(with event: NSEvent) { pressPoint = pointer(event); mouseMoved = false }
    override func mouseDragged(with event: NSEvent) {
        guard let pressPoint else { return }
        let point = pointer(event)
        if !mouseMoved && hypot(point.x - pressPoint.x, point.y - pressPoint.y) > 4 { mouseMoved = true; beginMove() }
        if mouseMoved { move(NSPoint(x: point.x - pressPoint.x, y: point.y - pressPoint.y)) }
    }
    override func mouseUp(with event: NSEvent) {
        defer { pressPoint = nil; mouseMoved = false }
        guard let pressPoint else { return }
        if mouseMoved { endMove(); return }
        let point = pointer(event)
        if hypot(point.x - pressPoint.x, point.y - pressPoint.y) <= 4 { clickAction() }
    }
    private var candidate: UUID?
    private var ready = false
    private var dwell: DispatchWorkItem?
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect); registerForDraggedTypes([.clampItemID])
        setAccessibilityElement(true); setAccessibilityRole(.group)
        setAccessibilityLabel("拖入夹项并停留，松手夹成一组")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    private func identity(_ sender: NSDraggingInfo) -> UUID? {
        guard let text = sender.draggingPasteboard.string(forType: .clampItemID), let id = UUID(uuidString: text), accepts(id) else { return nil }
        return id
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard let id = identity(sender) else { return [] }
        candidate = id; ready = false; needsDisplay = true; highlighted(true)
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.candidate == id else { return }
            self.ready = true; self.needsDisplay = true
        }
        dwell?.cancel(); dwell = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { identity(sender) == candidate && candidate != nil ? .copy : [] }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { ready && identity(sender) == candidate && candidate != nil }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard ready, let id = identity(sender), id == candidate else { reset(); return false }
        reset(); receive(id); return true
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { reset() }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) { reset() }
    override func viewDidMoveToWindow() { if window == nil { reset() } }
    private func reset() { dwell?.cancel(); dwell = nil; candidate = nil; ready = false; highlighted(false); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        guard candidate != nil else { return }
        NSColor.controlAccentColor.withAlphaComponent(0.95).setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 7, yRadius: 7).fill()
        let title = (ready ? "松手夹成一组" : "停留以合并…") as NSString
        let style: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .medium), .foregroundColor: NSColor.white]
        let size = title.size(withAttributes: style)
        title.draw(at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2), withAttributes: style)
    }
}

@MainActor enum ContentDragPreview {
    static let size = NSSize(width: 220, height: 64)
    static func image(title: String, icon: NSImage?) -> NSImage {
        let preview = NSImage(size: size)
        preview.lockFocus()
        NSColor(calibratedWhite: 0.97, alpha: 0.96).setFill()
        NSBezierPath(roundedRect: NSRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1), xRadius: 10, yRadius: 10).fill()
        if let icon, icon.size.width > 0, icon.size.height > 0 {
            let scale = min(42 / icon.size.width, 42 / icon.size.height)
            let extent = NSSize(width: icon.size.width * scale, height: icon.size.height * scale)
            icon.draw(in: NSRect(x: 10 + (42 - extent.width) / 2, y: (size.height - extent.height) / 2, width: extent.width, height: extent.height))
        }
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingTail
        (title as NSString).draw(in: NSRect(x: 62, y: 32, width: 146, height: 18), withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.black, .paragraphStyle: paragraph])
        ("拖放到其他应用 · 保留原件" as NSString).draw(in: NSRect(x: 62, y: 14, width: 148, height: 15), withAttributes: [.font: NSFont.systemFont(ofSize: 9), .foregroundColor: NSColor.darkGray])
        preview.unlockFocus(); return preview
    }
}
