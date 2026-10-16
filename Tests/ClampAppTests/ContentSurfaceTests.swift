import AppKit
import WebKit
import Testing
import ClampCore
@testable import ClampEverything

@Suite(.serialized) @MainActor struct ContentSurfaceTests {
    @Test func documentPressOwnsTheGestureUntilReleaseThenScrollingResumes() throws {
        let view = ContentDragView(frame: CGRect(x: 0, y: 0, width: 120, height: 180))
        view.stabilizeWhilePressed = true
        var copied = 0, scrolled = 0, busy = false
        view.copyAction = { copied += 1 }; view.interaction = { busy = $0 }
        view.scrollAction = { _ in scrolled += 1 }
        func wheel(momentum: Bool) throws -> NSEvent {
            let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -4, wheel2: 0, wheel3: 0))
            if momentum { cg.setIntegerValueField(.scrollWheelEventMomentumPhase, value: 2) }
            return try #require(NSEvent(cgEvent: cg))
        }
        let down = try event(.leftMouseDown), up = try event(.leftMouseUp)
        view.mouseDown(with: down); #expect(busy)
        view.scrollWheel(with: try wheel(momentum: true))
        view.mouseUp(with: up)
        view.scrollWheel(with: try wheel(momentum: true))
        #expect(copied == 1 && scrolled == 0 && !busy)
        view.scrollWheel(with: try wheel(momentum: false))
        #expect(scrolled == 1)
        view.mouseDown(with: down)
        view.scrollWheel(with: try wheel(momentum: false)); view.mouseUp(with: up)
        #expect(scrolled == 1 && copied == 2 && !busy)
        view.scrollWheel(with: try wheel(momentum: false))
        #expect(scrolled == 2)
    }
    @Test func trackpadTailPhasesCannotCancelADocumentClickOrTurnItsPage() throws {
        let view = ContentDragView(frame: CGRect(x: 0, y: 0, width: 160, height: 220))
        view.stabilizeWhilePressed = true
        var copies = 0, scrolls = 0, locked = false
        view.copyAction = { copies += 1 }; view.scrollAction = { _ in scrolls += 1 }
        view.interaction = { locked = $0 }; view.writer = { NSPasteboardItem() }
        // CGScrollPhase and NSEvent.Phase use different bit values.
        let phases: [(CGScrollPhase?, NSEvent.Phase)] = [(.mayBegin, .mayBegin), (.began, .began), (.changed, .changed),
                                                       (.ended, .ended), (.cancelled, .cancelled), (nil, [])]
        for (cgPhase, phase) in phases {
            let down = try event(.leftMouseDown), up = try event(.leftMouseUp)
            view.mouseDown(with: down)
            let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -2, wheel2: 0, wheel3: 0))
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(cgPhase?.rawValue ?? 0))
            let wheel = try #require(NSEvent(cgEvent: cg))
            #expect(wheel.phase == phase)
            view.scrollWheel(with: wheel)
            #expect(locked)
            view.mouseUp(with: up)
            // Late finger-lift events also must not become a new page turn.
            cg.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(CGScrollPhase.ended.rawValue))
            view.scrollWheel(with: try #require(NSEvent(cgEvent: cg)))
            #expect(!locked)
        }
        #expect(copies == 6 && scrolls == 0)
        view.mouseDown(with: try event(.leftMouseDown))
        #expect(view.prepareDrag(at: CGPoint(x: 30, y: 10)) != nil)
        view.finishDrag(); view.mouseUp(with: try event(.leftMouseUp))
        #expect(copies == 6 && !locked)
    }
    @Test func resizingTheWindowDuringAPressDoesNotCancelCopyOrStartAFalseDrag() throws {
        _ = NSApplication.shared
        let view = ContentDragView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 100, height: 100), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.contentView = nil; window.close() }
        var copies = 0, drags = 0
        view.copyAction = { copies += 1 }; view.interaction = { if $0 { drags += 1 } }
        view.writer = { NSPasteboardItem() }
        func event(_ type: NSEvent.EventType, at point: CGPoint) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 1,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        let screenPoint = CGPoint(x: 150, y: 150)
        view.mouseDown(with: try event(.leftMouseDown, at: window.convertPoint(fromScreen: screenPoint)))
        // Document turns temporarily grow and then shrink the native window.
        window.setFrame(CGRect(x: 50, y: 50, width: 200, height: 200), display: false)
        let movedWindowPoint = window.convertPoint(fromScreen: screenPoint)
        #expect(view.prepareDrag(at: movedWindowPoint) == nil && drags == 0)
        view.mouseUp(with: try event(.leftMouseUp, at: movedWindowPoint))
        #expect(copies == 1)
        view.mouseDown(with: try event(.leftMouseDown, at: movedWindowPoint))
        #expect(view.prepareDrag(at: CGPoint(x: movedWindowPoint.x + 20, y: movedWindowPoint.y)) != nil)
        view.finishDrag(); view.mouseUp(with: try event(.leftMouseUp, at: movedWindowPoint))
        #expect(copies == 1 && drags == 1)
    }
    private func event(_ type: NSEvent.EventType, x: CGFloat = 10) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 10), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
    }
    @Test func primaryContentCopiesOnClickAndExportsTheOriginalOnDrag() throws {
        let root = URL(fileURLWithPath: "/private/tmp/ClampContentSurface-" + UUID().uuidString)
        let store = ClipStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("document.pdf")
        try Data("file fixture".utf8).write(to: file)
        for kind in [ClipKind.file, .folder, .text, .link] {
            var item = ClipItem(kind: kind, title: "test")
            switch kind {
            case .text: item.text = "原始文字"
            case .link: item.link = "https://example.com"
            case .folder: item.originalPath = root.path
            default: item.originalPath = file.path
            }
            let view = ContentDragView()
            var copied = 0; var active = false
            view.copyAction = { copied += 1 }; view.interaction = { active = $0 }
            view.writer = { store.pasteboardItem(item) }
            view.mouseUp(with: try event(.leftMouseUp)); #expect(copied == 0)
            view.mouseDown(with: try event(.leftMouseDown)); view.mouseUp(with: try event(.leftMouseUp))
            #expect(copied == 1)
            view.mouseDown(with: try event(.leftMouseDown))
            let writer = try #require(view.prepareDrag(at: CGPoint(x: 40, y: 10)))
            #expect(active)
            if kind == .text { #expect(writer.string(forType: .string) == item.text) }
            else if kind == .link { #expect(writer.string(forType: .URL) == item.link) }
            else { #expect(writer.string(forType: .fileURL) == store.fileURL(item)?.absoluteString) }
            view.finishDrag()
            view.mouseUp(with: try event(.leftMouseUp))
            #expect(copied == 1 && !active)
        }
    }
    @Test func folderDropAcceptsFileURLsAndRejectsWebLinks() async throws {
        let file = URL(fileURLWithPath: "/private/tmp/test file.docx")
        #expect(DroppedFileURLs.decode(file as NSURL) == file)
        #expect(DroppedFileURLs.decode(file.absoluteString as NSString) == file)
        #expect(DroppedFileURLs.decode(file.dataRepresentation as NSData) == file)
        #expect(DroppedFileURLs.decode("https://example.com" as NSString) == nil)
        let provider = NSItemProvider(item: file as NSURL, typeIdentifier: "public.file-url")
        let urls = await DroppedFileURLs.read([provider, provider])
        #expect(urls == [file])
    }
    @Test(.timeLimit(.minutes(1))) func webPreviewRendersActualHTMLWithoutAnOpenGraphCover() async throws {
        _ = NSApplication.shared
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let viewport = WebPageViewportView(frame: CGRect(x: 0, y: 0, width: 320, height: 200), configuration: config)
        let view = viewport.webView
        let window = NSWindow(contentRect: viewport.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = viewport
        let model = WebPagePreviewModel()
        defer { model.cancel(); window.contentView = nil; window.close() }
        let url = try #require(URL(string: "https://example.invalid/" + UUID().uuidString))
        model.attach(view, url: url, html: "<html><head><title>实际页面标题</title></head><body style='margin:0;background:#226699;color:white;font:48px sans-serif'><h1>Homepage preview</h1><p>No cover metadata</p></body></html>")
        let deadline = Date().addingTimeInterval(12)
        while model.image == nil && !model.failed && Date() < deadline { try await Task.sleep(nanoseconds: 50_000_000) }
        let image = try #require(model.image)
        #expect(model.title == "实际页面标题")
        #expect(image.size.width > 0 && image.size.height > 0)
        #expect(WebPagePreviewCache.entry(url)?.image != nil)
        let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cg)
        let color = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh * 3 / 4)?.usingColorSpace(.sRGB))
        #expect(color.blueComponent > color.redComponent + 0.15)
    }
}
