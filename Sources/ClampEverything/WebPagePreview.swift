import AppKit
import SwiftUI
import WebKit

@MainActor enum WebPagePreviewCache {
    struct Entry { let image: NSImage; let title: String; let date: Date }
    private static var entries: [URL: Entry] = [:]
    static func entry(_ url: URL, now: Date = Date()) -> Entry? {
        guard let entry = entries[url], now.timeIntervalSince(entry.date) < 600 else { entries[url] = nil; return nil }
        return entry
    }
    static func invalidate(_ url: URL) { entries[url] = nil }
    static func insert(image: NSImage, title: String, for url: URL, now: Date = Date()) {
        entries[url] = Entry(image: image, title: title, date: now)
        while entries.count > 8, let oldest = entries.min(by: { $0.value.date < $1.value.date })?.key { entries[oldest] = nil }
    }
}

/// Snapshot mode serves the guide; live mode keeps the page available for wheel scrolling.
@MainActor final class WebPagePreviewModel: NSObject, ObservableObject, WKNavigationDelegate {
    @Published private(set) var image: NSImage?
    @Published private(set) var title = ""
    @Published private(set) var loading = true
    @Published private(set) var failed = false
    @Published private(set) var revision = 0
    @Published private(set) var scrolling = false
    @Published private(set) var scrollBend: CGFloat = 0
    var onScrollPosition: (CGPoint) -> Void = { _ in }
    private var live = false
    private var initialPosition = CGPoint.zero
    private var idleScroll: Task<Void, Never>?
    private var pendingScroll: Task<Void, Never>?
    private var delta = CGSize.zero
    private var pointer = CGPoint(x: 0.5, y: 0.5)
    private weak var webView: WKWebView?
    private var url: URL?
    private var generation = 0
    private var settling: Task<Void, Never>?
    private var timeout: Task<Void, Never>?
    private var html: String?

    func attach(_ view: WKWebView, url: URL, html: String? = nil, live: Bool = false, initialPosition: CGPoint = .zero) {
        cancel(); self.url = url; self.html = html; self.live = live; self.initialPosition = initialPosition; webView = view
        failed = false; loading = true
        (view as? ThumbnailWebView)?.resetPageFit()
        let token = generation
        if html == nil, let cached = WebPagePreviewCache.entry(url) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == token else { return }
                self.image = cached.image; self.title = cached.title; if !live { self.loading = false }
            }
            if !live { return }
        }
        view.navigationDelegate = self
        if let html { view.loadHTMLString(html, baseURL: url) }
        else { view.load(URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 15)) }
        timeout = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard !Task.isCancelled, let self, self.generation == token, (self.image == nil || self.live) else { return }
            self.fail()
        }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.webView === webView else { return }
        let token = generation
        settling?.cancel()
        settling = Task { @MainActor [weak self, weak webView] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let self, let webView, self.generation == token else { return }
            await (webView as? ThumbnailWebView)?.fitPageContent()
            guard self.generation == token, !Task.isCancelled else { return }
            self.title = webView.title ?? self.url?.host ?? "网页"
            let config = WKSnapshotConfiguration()
            config.rect = webView.bounds; config.snapshotWidth = 800
            config.afterScreenUpdates = false
            webView.takeSnapshot(with: config) { [weak self] image, _ in
                guard let self, self.generation == token else { return }
                guard let image, image.size.width > 0, image.size.height > 0 else {
                    if self.live { self.loading = false; self.timeout?.cancel(); self.restorePosition() } else { self.fail() }; return
                }
                self.image = image; self.loading = false; self.failed = false
                self.timeout?.cancel()
                if let url = self.url { WebPagePreviewCache.insert(image: image, title: self.title, for: url) }
                if self.live { self.restorePosition() } else { webView.stopLoading() }
            }
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { if self.webView === webView, (image == nil || live), (error as NSError).code != NSURLErrorCancelled { fail() } }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { if self.webView === webView, (image == nil || live), (error as NSError).code != NSURLErrorCancelled { fail() } }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { if self.webView === webView, (image == nil || live) { fail() } }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let scheme = navigationAction.request.url?.scheme?.lowercased()
        decisionHandler(["https", "http", "about"].contains(scheme ?? "") && navigationAction.targetFrame != nil ? .allow : .cancel)
    }
    private func fail() {
        settling?.cancel(); timeout?.cancel(); webView?.stopLoading()
        failed = true; loading = false
    }
    private func restorePosition() {
        guard live, initialPosition != .zero else { return }
        let point = initialPosition; initialPosition = .zero
        guard point.x.isFinite, point.y.isFinite else { return }
        webView?.evaluateJavaScript("window.scrollTo(\(point.x), \(point.y));")
    }
    func scroll(_ event: PreviewScroll, animated: Bool = true) {
        guard live, !failed, let webView, event.delta.width.isFinite, event.delta.height.isFinite else { return }
        let multiplier: CGFloat = event.precise ? 1 : 14
        delta.width -= event.delta.width * multiplier
        delta.height -= event.delta.height * multiplier
        pointer = event.location; scrolling = true
        if animated { withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.85)) { scrollBend = max(-0.5, min(0.5, event.delta.height / 100)) } }
        idleScroll?.cancel()
        idleScroll = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 300_000_000) } catch { return }
            guard let self else { return }
            self.scrolling = false
            withAnimation(animated ? .spring(response: 0.4, dampingFraction: 0.75) : nil) { self.scrollBend = 0 }
        }
        guard pendingScroll == nil else { return }
        let token = generation
        pendingScroll = Task { @MainActor [weak self, weak webView] in
            do { try await Task.sleep(nanoseconds: 8_000_000) } catch { return }
            guard let self, let webView, self.generation == token else { return }
            let zoom = max(WebPageFit.minimumScale, (webView as? ThumbnailWebView)?.previewScale ?? 1)
            let x = self.pointer.x * webView.bounds.width, y = self.pointer.y * webView.bounds.height
            let dx = self.delta.width / zoom, dy = self.delta.height / zoom
            self.delta = .zero; self.pendingScroll = nil
            let script = """
            (() => {
              let e = document.elementFromPoint(\(x), \(y));
              while (e && e !== document.body && e !== document.documentElement) {
                const s = getComputedStyle(e);
                if ((/(auto|scroll)/.test(s.overflowY) && e.scrollHeight > e.clientHeight + 1) ||
                    (/(auto|scroll)/.test(s.overflowX) && e.scrollWidth > e.clientWidth + 1)) break;
                e = e.parentElement;
              }
              const target = (!e || e === document.body || e === document.documentElement) ? document.scrollingElement : e;
              if (target) { const old = target.style.scrollBehavior; target.style.scrollBehavior = 'auto'; target.scrollBy(\(dx), \(dy)); target.style.scrollBehavior = old; }
              return [window.scrollX, window.scrollY];
            })()
            """
            webView.evaluateJavaScript(script) { [weak self] result, _ in
                guard let self, self.generation == token, let xy = result as? [Double], xy.count == 2 else { return }
                self.onScrollPosition(CGPoint(x: xy[0], y: xy[1]))
            }
        }
    }
    func retry() {
        if let url { WebPagePreviewCache.invalidate(url) }
        cancel(); image = nil; title = ""; failed = false; loading = true; revision += 1
    }
    func detach(_ view: WKWebView) {
        view.navigationDelegate = nil; view.stopLoading()
        if webView === view { cancel() }
    }
    func cancel() {
        generation += 1; settling?.cancel(); timeout?.cancel()
        idleScroll?.cancel(); pendingScroll?.cancel(); pendingScroll = nil; delta = .zero
        scrolling = false; scrollBend = 0
        (webView as? ThumbnailWebView)?.stopPageFit()
        webView?.navigationDelegate = nil; webView?.stopLoading(); webView = nil
    }
}

struct WebPageSnapshotView: NSViewRepresentable {
    @ObservedObject var model: WebPagePreviewModel
    let url: URL
    var html: String? = nil
    var live = false
    var initialPosition = CGPoint.zero
    func makeNSView(context: Context) -> WebPageViewportView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        let view = WebPageViewportView(frame: CGRect(x: 0, y: 0, width: 280, height: 160), configuration: configuration)
        model.attach(view.webView, url: url, html: html, live: live, initialPosition: initialPosition)
        return view
    }
    func updateNSView(_ view: WebPageViewportView, context: Context) { view.arrangePage() }
    static func dismantleNSView(_ view: WebPageViewportView, coordinator: ()) {
        let web = view.webView
        (web.navigationDelegate as? WebPagePreviewModel)?.detach(web)
        web.navigationDelegate = nil; web.stopLoading()
    }
}
