import AppKit
import PDFKit
import Testing
import ClampCore
@testable import ClampEverything

@Suite(.serialized) @MainActor struct DocumentCopyTests {
    @Test func pdfAndWordWindowClicksSurviveTrackpadTailsAndTurnWindowChanges() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClampDocumentCopy-" + UUID().uuidString)
        let board = NSPasteboard(name: .init("ClampDocumentCopy-" + UUID().uuidString))
        let store = ClipStore(root: root, copyPasteboard: board); store.hidden = false; store.state.preferences.hideInFullScreen = false
        let pdf = root.appendingPathComponent("PDF 资料.pdf"), word = root.appendingPathComponent("Word 资料.docx")
        let document = PDFDocument()
        let image = NSImage(size: CGSize(width: 240, height: 320)); image.lockFocus()
        NSColor.white.setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: 240, height: 320)).fill(); image.unlockFocus()
        for index in 0..<2 { document.insert(try #require(PDFPage(image: image)), at: index) }
        #expect(document.write(to: pdf))
        let text = NSAttributedString(string: String(repeating: "Word document paragraph.\n", count: 200), attributes: [.font: NSFont.systemFont(ofSize: 16)])
        try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]).write(to: word)
        store.state.items = [pdf, word].map { url in
            var item = ClipItem(kind: .file, title: url.lastPathComponent); item.originalPath = url.path; return item
        }
        let manager = WindowManager(store: store)
        defer { board.releaseGlobally(); manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        func find(_ v: NSView) -> ContentDragView? { (v as? ContentDragView) ?? v.subviews.compactMap(find).first }
        for item in store.state.items {
            let model = manager.model(item.id); model.present(animated: false)
            let host = try #require(model.panel.contentView)
            for _ in 0..<100 {
                try await Task.sleep(nanoseconds: 20_000_000)
                host.layoutSubtreeIfNeeded()
                if !model.busy, find(host) != nil { break }
            }
            for expand in [true, false] {
                let surface = try #require(find(host))
                surface.resetForReuse()
                let point = surface.convert(CGPoint(x: surface.bounds.midX, y: surface.bounds.midY), to: nil)
                let screenPoint = model.panel.convertPoint(toScreen: point)
                func event(_ type: NSEvent.EventType) throws -> NSEvent {
                    try #require(NSEvent.mouseEvent(with: type, location: model.panel.convertPoint(fromScreen: screenPoint), modifierFlags: [],
                        timestamp: 1, windowNumber: model.panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
                }
                let down = try event(.leftMouseDown)
                let target = try #require(host.hitTest(host.superview!.convert(down.locationInWindow, from: nil)) as? ContentDragView)
                #expect(target.acceptsFirstMouse(for: down))
                #expect(target.accessibilityLabel() != "已复制")
                model.panel.sendEvent(down)
                #expect(model.busy)
                // A trackpad can finish its finger-scroll with a small non-momentum
                // delta between the physical click's down and up events.
                let tail = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -2, wheel2: 0, wheel3: 0))
                tail.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(CGScrollPhase.ended.rawValue))
                let tailEvent = try #require(NSEvent(cgEvent: tail))
                #expect(tailEvent.momentumPhase.isEmpty && tailEvent.phase.contains(.ended))
                target.scrollWheel(with: tailEvent)
                #expect(model.busy)
                model.documentTurn(expand)
                try await Task.sleep(nanoseconds: 50_000_000); host.layoutSubtreeIfNeeded()
                let up = try event(.leftMouseUp)
                let current = try #require(host.hitTest(host.superview!.convert(up.locationInWindow, from: nil)) as? ContentDragView)
                #expect(current === target)
                #expect(current.prepareDrag(at: up.locationInWindow) == nil)
                // Run the actual configured copy callback against the store's private destination.
                board.clearContents()
                if !expand {
                    let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -3, wheel2: 0, wheel3: 0))
                    cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2)
                    let momentum = try #require(NSEvent(cgEvent: cg))
                    #expect(!momentum.momentumPhase.isEmpty)
                    current.scrollWheel(with: momentum)
                }
                model.panel.sendEvent(up)
                #expect(board.string(forType: .fileURL) == store.fileURL(item)?.absoluteString)
                let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]
                #expect(urls?.first == store.fileURL(item))
                #expect(current.accessibilityLabel() == "已复制")
                #expect(!model.busy)
            }
        }
    }
}
