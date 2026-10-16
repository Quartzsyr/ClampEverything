import AppKit
import WebKit
import SwiftUI
import Testing
@testable import ClampEverything

struct WebPageFitGeometryTests {
    @Test func scalePreservesProportionsAndAllowsVeryWidePages() {
        #expect(WebPageFit.scale(viewWidth: 320, contentWidth: 1600) == 0.2)
        #expect(WebPageFit.scale(viewWidth: 192, contentWidth: 3200) == 0.06)
        #expect(WebPageFit.scale(viewWidth: 300, contentWidth: 800) == 300.0 / 1024)
        #expect(WebPageFit.scale(viewWidth: 2400, contentWidth: 1600) == 1)
        #expect(WebPageFit.scale(viewWidth: .nan, contentWidth: .infinity).isFinite)
    }
}

@Suite(.serialized) @MainActor struct WebPageFitNativeTests {
    @Test func hostedResponsivePagePreservesFontsAndFitsWithoutAZoomFeedbackLoop() async throws {
        _ = NSApplication.shared
        let page = WebPagePreviewModel()
        let html = """
        <html><head><meta name="viewport" content="width=device-width">
        <style>html {font-size:16px} body {margin:0} nav {display:flex;justify-content:space-between;font-size:1rem}
        nav span {padding:1rem} main {height:3000px;background:#eee}</style></head>
        <body><nav><span>Platform Solutions Resources</span><span id="right">Sign in · Sign up</span></nav><main>Source and README</main></body></html>
        """
        let host = NSHostingView(rootView: WebPageSnapshotView(model: page,
            url: URL(string: "https://responsive.invalid/" + UUID().uuidString)!, html: html, live: true)
            .frame(maxWidth: .infinity, maxHeight: .infinity))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 296, height: 185), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { page.cancel(); window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        for _ in 0..<120 { if !page.loading { break }; try await Task.sleep(nanoseconds: 50_000_000) }
        func find(_ root: NSView) -> WebPageViewportView? {
            (root as? WebPageViewportView) ?? root.subviews.compactMap(find).first
        }
        let viewport = try #require(find(host)), view = viewport.webView
        #expect(!page.failed && page.image != nil)
        // A nonzero minimum logical font used to enlarge rem layouts as zoom
        // decreased. Native surface scaling must keep CSS text at 16 pixels.
        for size in [CGSize(width: 296, height: 185), CGSize(width: 192, height: 320), CGSize(width: 533, height: 240)] {
            window.setContentSize(size); host.layoutSubtreeIfNeeded(); viewport.arrangePage()
            try await Task.sleep(nanoseconds: 150_000_000)
            #expect(view.pageZoom == 1)
            #expect(try await view.evaluateJavaScript("getComputedStyle(document.querySelector('nav')).fontSize") as? String == "16px")
            let right = try #require(try await view.evaluateJavaScript("document.getElementById('right').getBoundingClientRect().right") as? Double)
            #expect(right * view.previewScale <= size.width + 1)
            let edge = view.convert(CGPoint(x: view.bounds.width, y: 0), to: host)
            #expect(abs(edge.x - size.width) < 1)
            #expect(view.fittedContentWidth <= 1025)
        }
    }
    private func withPage(_ html: String, size: CGSize = CGSize(width: 320, height: 200),
                          check: (ThumbnailWebView, WebPagePreviewModel, NSWindow) async throws -> Void) async throws {
        _ = NSApplication.shared
        let config = WKWebViewConfiguration(); config.websiteDataStore = .nonPersistent()
        let viewport = WebPageViewportView(frame: CGRect(origin: .zero, size: size), configuration: config)
        let view = viewport.webView
        let window = NSWindow(contentRect: viewport.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = viewport
        let page = WebPagePreviewModel()
        defer { page.cancel(); window.contentView = nil; window.close() }
        page.attach(view, url: URL(string: "https://fit.invalid/" + UUID().uuidString)!, html: html, live: true)
        for _ in 0..<120 { if !page.loading || page.failed { break }; try await Task.sleep(nanoseconds: 50_000_000) }
        #expect(!page.loading && !page.failed && page.image != nil)
        try await check(view, page, window)
    }
    private func waitUntilFits(_ view: ThumbnailWebView) async throws {
        for _ in 0..<80 {
            let width = (try? await view.evaluateJavaScript(WebPageFit.measure) as? Double) ?? .infinity
            if width <= view.bounds.width + 1 { return }
            try await Task.sleep(nanoseconds: 30_000_000)
        }
        let width = try #require(try await view.evaluateJavaScript(WebPageFit.measure) as? Double)
        #expect(width <= view.bounds.width + 1)
    }
    @Test func widePageShowsBothEdgesInSnapshotsAndFitsDifferentPreviewRatios() async throws {
        let html = "<html><body style='margin:0'><main style='display:flex;width:1600px;height:1500px'><div style='width:200px;background:#0055ff'></div><div style='width:1200px;background:#eee'>A complete desktop page</div><div style='width:200px;background:#ff3300'></div></main></body></html>"
        try await withPage(html) { view, page, window in
            #expect(view.fittedContentWidth >= 1600)
            for size in [CGSize(width: 320, height: 200), CGSize(width: 192, height: 320), CGSize(width: 540, height: 180)] {
                window.setContentSize(size); (window.contentView as? WebPageViewportView)?.arrangePage()
                try await waitUntilFits(view)
                let width = try #require(try await view.evaluateJavaScript("document.querySelector('main').getBoundingClientRect().right") as? Double)
                #expect(width * view.previewScale <= size.width + 1)
                let config = WKSnapshotConfiguration(); config.rect = view.bounds; config.snapshotWidth = 800
                config.afterScreenUpdates = false
                let image = try await view.takeSnapshot(configuration: config)
                let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
                let bitmap = NSBitmapImageRep(cgImage: cg)
                let left = try #require(bitmap.colorAt(x: 20, y: 20)?.usingColorSpace(.sRGB))
                let right = try #require(bitmap.colorAt(x: bitmap.pixelsWide - 20, y: 20)?.usingColorSpace(.sRGB))
                #expect(left.blueComponent > left.redComponent + 0.4)
                #expect(right.redComponent > right.blueComponent + 0.4)
            }
            page.scroll(PreviewScroll(delta: CGSize(width: 0, height: -40), precise: true, time: 1), animated: false)
            try await Task.sleep(nanoseconds: 150_000_000)
            #expect(try await view.evaluateJavaScript("window.scrollY") as? Double ?? 0 > 0)
        }
    }
    @Test func lateWideContentAutomaticallyRefitsAndSmallScaleStillScrollsCorrectly() async throws {
        try await withPage("<html><body style='margin:0;height:8000px'><div id='article' style='height:500px'>Reading</div></body></html>", size: CGSize(width: 192, height: 200)) { view, page, _ in
            try await view.evaluateJavaScript("document.getElementById('article').style.width='3200px'")
            for _ in 0..<80 {
                if view.fittedContentWidth >= 3200 { break }
                try await Task.sleep(nanoseconds: 30_000_000)
            }
            try await waitUntilFits(view)
            #expect(view.previewScale < 0.1 && view.fittedContentWidth >= 3200)
            // WebKit can preserve a nonzero anchor when zooming. Start from a
            // known middle position and verify the movement, not an assumed origin.
            try await view.evaluateJavaScript("window.scrollTo(0, 1000)")
            try await Task.sleep(nanoseconds: 80_000_000)
            let before = try #require(try await view.evaluateJavaScript("window.scrollY") as? Double)
            page.scroll(PreviewScroll(delta: CGSize(width: 0, height: -30), precise: true, time: 1), animated: false)
            try await Task.sleep(nanoseconds: 150_000_000)
            let distance = try #require(try await view.evaluateJavaScript("window.scrollY") as? Double)
            #expect(abs((distance - before) * view.previewScale - 30) < 3)
            let zoom = view.previewScale
            page.cancel()
            try await view.evaluateJavaScript("document.getElementById('article').style.width='5000px'")
            try await Task.sleep(nanoseconds: 200_000_000)
            #expect(view.previewScale == zoom)
        }
    }
}
