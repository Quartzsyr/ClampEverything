import AppKit
import PDFKit
import WebKit
import SwiftUI
import Testing
import ClampCore
@testable import ClampEverything

struct PageScrollTests {
    @Test func aTrackpadStrokeAndItsMomentumOnlyTurnOnePage() {
        var gate = PageScrollGate()
        #expect(gate.direction(for: PreviewScroll(delta: CGSize(width: 0, height: -12), precise: true, phase: .began, time: 1)) == nil)
        #expect(gate.direction(for: PreviewScroll(delta: CGSize(width: 0, height: -15), precise: true, phase: .changed, time: 1.05)) == 1)
        #expect(gate.direction(for: PreviewScroll(delta: CGSize(width: 0, height: -90), precise: true, phase: .changed, time: 1.8)) == nil)
        #expect(gate.direction(for: PreviewScroll(delta: CGSize(width: 0, height: -90), precise: true, momentum: .changed, time: 2)) == nil)
        #expect(gate.direction(for: PreviewScroll(delta: CGSize(width: 0, height: 30), precise: true, phase: .began, time: 2.5)) == -1)
    }
    @Test func mouseWheelHasACooldownAndHorizontalSwipesWork() {
        var gate = PageScrollGate()
        #expect(gate.direction(for: PreviewScroll(delta: CGSize(width: 0, height: -1), time: 1)) == 1)
        #expect(gate.direction(for: PreviewScroll(delta: CGSize(width: 0, height: -1), time: 1.1)) == nil)
        #expect(gate.direction(for: PreviewScroll(delta: CGSize(width: 0, height: 1), time: 1.7)) == -1)
        #expect(gate.direction(for: PreviewScroll(delta: CGSize(width: -30, height: 0), precise: true, phase: .began, time: 2.5)) == 1)
    }
}

@Suite(.serialized) @MainActor struct DocumentReadingTests {
    private func pdf() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        let document = PDFDocument()
        for (index, color) in [NSColor.systemRed, .systemBlue, .systemGreen].enumerated() {
            let image = NSImage(size: CGSize(width: 240, height: 320)); image.lockFocus()
            color.setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: 240, height: 320)).fill()
            ("Page \(index + 1)" as NSString).draw(at: CGPoint(x: 20, y: 240), withAttributes: [.font: NSFont.systemFont(ofSize: 24)])
            image.unlockFocus(); document.insert(try #require(PDFPage(image: image)), at: index)
        }
        #expect(document.write(to: url)); return url
    }
    @Test func pdfPagesRenderDistinctOriginalPagesAndStopAtBounds() async throws {
        let url = try pdf(); defer { try? FileManager.default.removeItem(at: url) }
        let source = DocumentPages(url: url)
        #expect(try await source.pageCount() == 3)
        let red = try #require(try await source.image(at: 0)), blue = try #require(try await source.image(at: 1))
        let redData = try #require(red.tiffRepresentation), blueData = try #require(blue.tiffRepresentation)
        let a = try #require(NSBitmapImageRep(data: redData))
        let b = try #require(NSBitmapImageRep(data: blueData))
        let c1 = try #require(a.colorAt(x: a.pixelsWide / 2, y: a.pixelsHigh / 2)?.usingColorSpace(.sRGB))
        let c2 = try #require(b.colorAt(x: b.pixelsWide / 2, y: b.pixelsHigh / 2)?.usingColorSpace(.sRGB))
        #expect(c1.redComponent > c1.blueComponent && c2.blueComponent > c2.redComponent)
        #expect(try await source.image(at: -1) == nil)
        #expect(try await source.image(at: 3) == nil)
        let reader = DocumentReadingModel(); await reader.load(url, initialIndex: 1)
        #expect(reader.index == 1 && reader.count == 3)
        reader.move(-1, animated: false)
        for _ in 0..<30 { if !reader.busy { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(reader.index == 0 && reader.previous == nil)
        reader.move(-1, animated: false); #expect(reader.index == 0)
        reader.move(1, animated: true)
        for _ in 0..<30 { if reader.turning { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(reader.turning && reader.previous != nil)
        reader.cancel(); try await Task.sleep(nanoseconds: 550_000_000)
        #expect(!reader.turning && reader.previous == nil && !reader.loading)
    }
    @Test func wordAndRTFTextFlowAcrossRealPagesRatherThanRepeatingTheFirstPage() async throws {
        for (ext, type) in [("docx", NSAttributedString.DocumentType.officeOpenXML), ("rtf", .rtf)] {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            defer { try? FileManager.default.removeItem(at: url) }
            let text = (0..<120).map { "第 \($0 + 1) 段：The next page must contain different readable content.\n" }.joined()
            let source = NSMutableAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.black])
            source.addAttribute(.foregroundColor, value: NSColor.systemRed, range: (text as NSString).range(of: "第 1 段"))
            try source.data(from: NSRange(location: 0, length: source.length), documentAttributes: [.documentType: type]).write(to: url)
            let pages = DocumentPages(url: url)
            #expect(try await pages.pageCount() > 2)
            let first = try #require(try await pages.image(at: 0)), second = try #require(try await pages.image(at: 1))
            #expect(first.tiffRepresentation != second.tiffRepresentation)
            let data = try #require(first.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            var dark = 0
            for y in stride(from: 60, to: bitmap.pixelsHigh - 60, by: 8) {
                for x in stride(from: 60, to: bitmap.pixelsWide - 60, by: 8) {
                    if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.redComponent < 0.7 { dark += 1 }
                }
            }
            #expect(dark > 50)
            var headingPixels = 0
            for y in stride(from: 40, to: 140, by: 2) {
                for x in stride(from: 40, to: 250, by: 2) {
                    if let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.redComponent > c.greenComponent + 0.2 { headingPixels += 1 }
                }
            }
            #expect(headingPixels > 10) // the first paragraph must be at the TOP, not clipped away

        }
    }
    @Test func textAndCodeWheelEventsReachTheUnderlyingNativeReader() {
        let root = NSView(frame: CGRect(x: 0, y: 0, width: 400, height: 200))
        let scroll = NSScrollView(frame: CGRect(x: 0, y: 0, width: 180, height: 200))
        scroll.documentView = NSTextView(frame: CGRect(x: 0, y: 0, width: 180, height: 1200))
        let another = NSScrollView(frame: CGRect(x: 220, y: 0, width: 180, height: 200))
        let handle = ContentDragView(frame: scroll.frame)
        root.addSubview(scroll); root.addSubview(another); root.addSubview(handle)
        #expect(handle.readingScrollTarget(at: CGPoint(x: 50, y: 100)) === scroll)
        scroll.isHidden = true
        #expect(handle.readingScrollTarget(at: CGPoint(x: 50, y: 100)) == nil)
    }
    @Test func scrollingTheCopySurfaceDoesNotCopyOnMouseRelease() throws {
        let view = ContentDragView(frame: CGRect(x: 0, y: 0, width: 100, height: 150))
        var copied = 0, scrolled = 0
        view.copyAction = { copied += 1 }; view.scrollAction = { _ in scrolled += 1 }
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: -50, wheel2: 0, wheel3: 0))
        let wheel = try #require(NSEvent(cgEvent: cg))
        view.mouseDown(with: down); view.scrollWheel(with: wheel); view.mouseUp(with: down)
        #expect(scrolled == 1 && copied == 0)
        view.scrollAction = nil
        view.mouseDown(with: down); view.scrollWheel(with: wheel); view.mouseUp(with: down)
        #expect(copied == 0)
    }
    @Test func aZeroDeltaScrollEventDoesNotSwallowTheCopyClick() throws {
        let view = ContentDragView(frame: CGRect(x: 0, y: 0, width: 100, height: 150))
        var copied = 0
        view.copyAction = { copied += 1 }; view.scrollAction = { _ in }
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 0, wheel2: 0, wheel3: 0))
        let wheel = try #require(NSEvent(cgEvent: cg))
        view.mouseDown(with: down); view.scrollWheel(with: wheel); view.mouseUp(with: down)
        #expect(copied == 1)
    }
}

@Suite(.serialized) @MainActor struct LiveWebReadingTests {
    @Test func livePageScrollsBodyAndNestedContentAndRestoresPosition() async throws {
        _ = NSApplication.shared
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let viewport = WebPageViewportView(frame: CGRect(x: 0, y: 0, width: 320, height: 200), configuration: config)
        let view = viewport.webView
        let window = NSWindow(contentRect: viewport.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = viewport
        let page = WebPagePreviewModel()
        defer { page.cancel(); window.contentView = nil; window.close() }
        let html = "<html><head><title>Scrollable</title></head><body style='margin:0;height:5000px;background:linear-gradient(white,blue)'><div id='inner' style='position:fixed;right:0;top:0;width:200px;height:200px;overflow:auto'><div style='height:2000px'>Nested scrolling</div></div></body></html>"
        page.attach(view, url: URL(string: "https://reading.invalid/")!, html: html, live: true, initialPosition: CGPoint(x: 0, y: 180))
        for _ in 0..<100 { if !page.loading || page.failed { break }; try await Task.sleep(nanoseconds: 50_000_000) }
        #expect(!page.failed && page.image != nil)
        try await Task.sleep(nanoseconds: 100_000_000)
        let initial = try #require(try await view.evaluateJavaScript("window.scrollY") as? Double)
        #expect(initial >= 175)
        var saved = CGPoint.zero; page.onScrollPosition = { saved = $0 }
        page.scroll(PreviewScroll(delta: CGSize(width: 0, height: -70), location: CGPoint(x: 0.2, y: 0.5), precise: true, time: 1), animated: false)
        try await Task.sleep(nanoseconds: 180_000_000)
        let after = try #require(try await view.evaluateJavaScript("window.scrollY") as? Double)
        #expect(after > initial && saved.y > 180)
        page.scroll(PreviewScroll(delta: CGSize(width: 0, height: -70), location: CGPoint(x: 0.95, y: 0.1), precise: true, time: 2), animated: false)
        try await Task.sleep(nanoseconds: 180_000_000)
        #expect(try await view.evaluateJavaScript("document.getElementById('inner').scrollTop") as? Double ?? 0 > 0)
        page.cancel(); #expect(!page.scrolling && page.scrollBend == 0)
        let held = try #require(try await view.evaluateJavaScript("window.scrollY") as? Double)
        page.scroll(PreviewScroll(delta: CGSize(width: 0, height: -70), time: 3))
        try await Task.sleep(nanoseconds: 40_000_000)
        #expect(try await view.evaluateJavaScript("window.scrollY") as? Double == held)
    }
}
