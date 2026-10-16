import AppKit
import PDFKit
import WebKit
import Testing
import ClampCore
@testable import ClampEverything

struct ContentPreviewTests {
    @Test func routesDocumentsAndCodeWithoutDependingOnQuickLookPlugins() {
        for ext in ["pdf", "PDF"] { #expect(FilePreviewKind.forURL(URL(fileURLWithPath: "/tmp/sample." + ext)) == .pdf) }
        for ext in ["docx", "doc", "pages", "xlsx", "pptx"] { #expect(FilePreviewKind.forURL(URL(fileURLWithPath: "/tmp/sample." + ext)) == .document) }
        for name in ["sample.swift", "test.py", "index.tsx", "data.json", "index.html", "readme.md", "Dockerfile", ".gitignore"] {
            #expect(FilePreviewKind.forURL(URL(fileURLWithPath: "/tmp/" + name)) == .code)
        }
        #expect(FilePreviewKind.forURL(URL(fileURLWithPath: "/tmp/photo.png")) == .other)
    }
    @Test func boundedCodeReaderHandlesUnicodeAndRejectsBinary() throws {
        let root = URL(fileURLWithPath: "/private/tmp/ClampCodePreview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("test.swift")
        try "let 文字 = \"你好\"\r\nreturn 2".write(to: url, atomically: true, encoding: .utf8)
        let unicode = try CodeExcerpt.read(url)
        #expect(unicode.text == "let 文字 = \"你好\"\nreturn 2")
        #expect(unicode.lineCount == 2 && !unicode.truncated)
        try Array(repeating: "// line", count: 700).joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        let lines = try CodeExcerpt.read(url)
        #expect(lines.lineCount == 400 && lines.truncated)
        try Data(repeating: 65, count: 500_000).write(to: url)
        let bytes = try CodeExcerpt.read(url)
        #expect(bytes.text.utf8.count <= CodeExcerpt.byteLimit && bytes.truncated)
        try "UTF16 文本".data(using: .utf16)!.write(to: url)
        #expect(try CodeExcerpt.read(url).text == "UTF16 文本")
        for bytes in [Data([0, 1, 2, 3]), Data([0xff, 0xfd])] {
            try bytes.write(to: url)
            #expect(throws: (any Error).self) { try CodeExcerpt.read(url) }
        }
    }
    @Test func clippedUtf8ScalarDoesNotDiscardTheWholePreview() throws {
        let url = URL(fileURLWithPath: "/private/tmp/ClampUTF8-" + UUID().uuidString + ".txt")
        defer { try? FileManager.default.removeItem(at: url) }
        let text = String(repeating: "A", count: CodeExcerpt.byteLimit - 1) + "你好"
        try text.write(to: url, atomically: true, encoding: .utf8)
        let preview = try CodeExcerpt.read(url)
        #expect(preview.text.utf8.count == CodeExcerpt.byteLimit - 1)
        #expect(preview.truncated)
    }
    @Test func dragAndClampBlockHoverEvenWhenNoLocalCardIsMoving() {
        #expect(!HoverExpansionGate.blocks(mouseButtons: 0, materialMoving: false, pointClamping: false))
        #expect(HoverExpansionGate.blocks(mouseButtons: 1, materialMoving: false, pointClamping: false))
        #expect(HoverExpansionGate.blocks(mouseButtons: 0, materialMoving: true, pointClamping: false))
        #expect(HoverExpansionGate.blocks(mouseButtons: 0, materialMoving: false, pointClamping: true))
    }
}

@Suite(.serialized) @MainActor struct ContentPreviewNativeTests {
    @Test func pdfPreviewIsAThumbnailOfItsFirstPage() throws {
        let document = PDFDocument()
        for label in ["第一页", "第二页"] {
            let image = NSImage(size: CGSize(width: 240, height: 320))
            image.lockFocus(); NSColor.white.setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: 240, height: 320)).fill()
            (label as NSString).draw(at: CGPoint(x: 30, y: 160), withAttributes: [.font: NSFont.systemFont(ofSize: 20)])
            image.unlockFocus()
            document.insert(try #require(PDFPage(image: image)), at: document.pageCount)
        }
        let url = URL(fileURLWithPath: "/private/tmp/ClampPDFPreview-" + UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(document.write(to: url))
        let reloaded = try #require(PDFDocument(url: url))
        #expect(reloaded.pageCount == 2)
        let image = try #require(DocumentThumbnailRenderer.firstPage(url))
        #expect(image.size.width <= DocumentThumbnailRenderer.size.width)
        #expect(image.size.height <= DocumentThumbnailRenderer.size.height)
        #expect(ContentPreviewLayout.thumbnailHeight == 256)
    }
    @Test func wordPreviewProducesABoundedImage() async throws {
        _ = NSApplication.shared
        let source = NSAttributedString(string: "Word 文档预览测试", attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let data = try source.data(from: NSRange(location: 0, length: source.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
        let url = URL(fileURLWithPath: "/private/tmp/ClampWordPreview-" + UUID().uuidString + ".docx")
        defer { try? FileManager.default.removeItem(at: url) }
        try data.write(to: url)
        #expect(data.starts(with: [0x50, 0x4b]))
        let rendered = await Task.detached(priority: .utility) { DocumentThumbnailRenderer.firstPage(url) }.value
        let image = try #require(rendered)
        #expect(image.size == DocumentThumbnailRenderer.size)
    }
    @Test func highlightingPreservesTheOriginalSource() {
        let source = "let 文字 = \"hello\" // comment\nreturn 42"
        #expect(String(CodeColoring.highlight(source).characters) == source)
    }
    @Test func webPageImageCacheExpiresWithoutDependingOnCoverMetadata() throws {
        let url = try #require(URL(string: "https://example.com/" + UUID().uuidString))
        let now = Date()
        WebPagePreviewCache.insert(image: NSImage(size: CGSize(width: 800, height: 500)), title: "实际首屏", for: url, now: now)
        #expect(WebPagePreviewCache.entry(url, now: now)?.title == "实际首屏")
        #expect(WebPagePreviewCache.entry(url, now: now.addingTimeInterval(601)) == nil)
    }
    @Test func groupingOverlayDoesNotTurnDragReleaseIntoAnExpandClick() throws {
        _ = NSApplication.shared
        let view = LibraryDropView()
        var clicks = 0, begins = 0, ends = 0
        view.clickAction = { clicks += 1 }; view.beginMove = { begins += 1 }; view.endMove = { ends += 1 }
        func event(_ type: NSEvent.EventType, _ x: CGFloat) throws -> NSEvent {
            try #require(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 10), modifierFlags: [], timestamp: 0,
                windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        }
        view.mouseDown(with: try event(.leftMouseDown, 10))
        view.mouseDragged(with: try event(.leftMouseDragged, 40))
        view.mouseUp(with: try event(.leftMouseUp, 10))
        #expect(clicks == 0 && begins == 1 && ends == 1)
        view.mouseDown(with: try event(.leftMouseDown, 10))
        view.mouseUp(with: try event(.leftMouseUp, 11))
        #expect(clicks == 1)
        view.mouseUp(with: try event(.leftMouseUp, 11))
        #expect(clicks == 1)
    }
    @Test func compactClipOnlyUnfoldsAfterDroppingAwayFromTheEdge() throws {
        _ = NSApplication.shared
        let screen = try #require(NSScreen.screens.first)
        let root = URL(fileURLWithPath: "/private/tmp/ClampCompactDrag-" + UUID().uuidString)
        let store = ClipStore(root: root); store.hidden = true
        store.addTextOrLink("compact drag")
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        let id = store.active[0].id, card = manager.model(id)
        manager.dock(id)
        card.beginMove()
        #expect(!card.expanded && card.panel.frame.size == DockGeometry.compactSize)
        card.move(CGPoint(x: -10, y: 10))
        #expect(!card.expanded)
        card.moving = false; card.busy = false
        manager.finishMove(card, at: CGPoint(x: screen.frame.maxX - 8, y: screen.visibleFrame.midY))
        #expect(!card.expanded && store.item(id)?.placement.mode == .docked)
        card.beginMove()
        #expect(!card.expanded)
        card.moving = false; card.busy = false
        manager.finishMove(card, at: CGPoint(x: screen.frame.midX, y: screen.visibleFrame.midY))
        #expect(card.expanded && store.item(id)?.placement.mode == .floating)
    }
    @Test func hoveringAnotherClipDuringMaterialMoveNeverUnfoldsIt() async throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: "/private/tmp/ClampHoverDrag-" + UUID().uuidString)
        let store = ClipStore(root: root); store.hidden = true; store.state.preferences.hoverDelay = 0.01
        store.addTextOrLink("source"); store.addTextOrLink("target")
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        let source = manager.model(store.active[0].id), target = manager.model(store.active[1].id)
        source.moving = true
        target.hover(true)
        try await Task.sleep(nanoseconds: 60_000_000)
        #expect(!target.expanded && target.hoverSuppressed)
        source.moving = false
        target.hover(true)
        try await Task.sleep(nanoseconds: 60_000_000)
        #expect(!target.expanded)
        target.show()
        #expect(target.expanded)
    }
}
