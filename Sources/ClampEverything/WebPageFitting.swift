import AppKit
import WebKit

/// Fit the complete page width proportionally. Long pages remain scrollable.
enum WebPageFit {
    static let baselineWidth: CGFloat = 1024
    static let minimumScale: CGFloat = 0.01
    static func scale(viewWidth: CGFloat, contentWidth: CGFloat) -> CGFloat {
        guard viewWidth.isFinite, viewWidth > 0 else { return minimumScale }
        let width = contentWidth.isFinite ? max(baselineWidth, contentWidth) : baselineWidth
        return max(minimumScale, min(1, viewWidth / width))
    }
    static let measure = """
    (() => {
      const root = document.documentElement, body = document.body;
      return Math.max(1, root ? root.scrollWidth : 0, root ? root.clientWidth : 0,
        body ? body.scrollWidth : 0, body ? body.offsetWidth : 0);
    })()
    """
    static let observe = """
    (() => {
      let pending = false, last = 0;
      const measure = () => {
        pending = false;
        const root = document.documentElement, body = document.body;
        const width = Math.max(1, root ? root.scrollWidth : 0, root ? root.clientWidth : 0,
          body ? body.scrollWidth : 0, body ? body.offsetWidth : 0);
        if (Math.abs(width - last) > 1) {
          last = width;
          window.webkit.messageHandlers.clampViewport.postMessage(width);
        }
      };
      const schedule = () => { if (!pending) { pending = true; queueMicrotask(measure); } };
      const observer = new ResizeObserver(schedule);
      if (document.documentElement) observer.observe(document.documentElement);
      if (document.body) observer.observe(document.body);
      new MutationObserver(schedule).observe(document.documentElement, {
        subtree: true, childList: true, attributes: true,
        attributeFilter: ['style', 'class', 'width', 'height', 'src']
      });
      window.addEventListener('load', schedule, true);
      window.addEventListener('resize', schedule);
      if (document.fonts) document.fonts.ready.then(schedule);
      schedule();
    })()
    """
}

/// The content controller owns this handler, which holds only a weak view.
@MainActor private final class WebPageFitHandler: NSObject, WKScriptMessageHandler {
    weak var view: ThumbnailWebView?
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame else { return }
        view?.schedulePageFit()
    }
}

final class ThumbnailWebView: WKWebView {
    private(set) var fittedContentWidth = WebPageFit.baselineWidth
    private var fittingEnabled = true
    private var ready = false
    private var fitGeneration = 0
    private var fitTask: Task<Void, Never>?
    private var handler: WebPageFitHandler?

    /// The page lays out at desktop size and the containing native view scales
    /// the finished surface. pageZoom can enforce a logical minimum font even
    /// when minimumFontSize is zero, so it cannot produce faithful thumbnails.
    private(set) var previewScale: CGFloat = 1
    var fitWidthChanged: (() -> Void)?
    func setPreviewScale(_ scale: CGFloat) { previewScale = scale }

    override init(frame: NSRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        let handler = WebPageFitHandler(); handler.view = self; self.handler = handler
        self.configuration.userContentController.add(handler, name: "clampViewport")
        self.configuration.userContentController.addUserScript(WKUserScript(source: WebPageFit.observe, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        pageZoom = 1
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func resetPageFit() {
        stopPageFit(); fittingEnabled = true; ready = false
        fittedContentWidth = WebPageFit.baselineWidth
        fitWidthChanged?()
    }
    func resetViewportWidth() {
        fittedContentWidth = WebPageFit.baselineWidth
        schedulePageFit()
    }
    func stopPageFit() {
        fitGeneration += 1; fittingEnabled = false; ready = false
        fitTask?.cancel(); fitTask = nil
    }
    func schedulePageFit() {
        guard fittingEnabled, ready else { return }
        fitTask?.cancel()
        let token = fitGeneration
        fitTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: 60_000_000) } catch { return }
            guard let self, self.fitGeneration == token else { return }
            await self.fitPageContent()
        }
    }
    func fitPageContent() async {
        guard fittingEnabled else { return }
        ready = true; let token = fitGeneration
        for _ in 0..<3 {
            guard let number = try? await evaluateJavaScript(WebPageFit.measure) as? NSNumber,
                  token == fitGeneration, fittingEnabled, !Task.isCancelled else { return }
            let measured = CGFloat(number.doubleValue)
            guard measured.isFinite, measured > 0 else { return }
            let required = max(WebPageFit.baselineWidth, measured)
            guard required > fittedContentWidth + 1.5 else { return }
            fittedContentWidth = required
            fitWidthChanged?()
            do { try await Task.sleep(nanoseconds: 32_000_000) } catch { return }
        }
    }
}

/// Uniform native coordinate scaling keeps the web page at pageZoom == 1.
/// Its CSS viewport stays at desktop width, including text and rem dimensions.
final class WebPageViewportView: NSView {
    let webView: ThumbnailWebView
    private var displaySize = CGSize.zero
    private var arranging = false
    init(frame: CGRect, configuration: WKWebViewConfiguration) {
        webView = ThumbnailWebView(frame: CGRect(x: 0, y: 0, width: 1024, height: 640), configuration: configuration)
        super.init(frame: frame)
        addSubview(webView)
        webView.fitWidthChanged = { [weak self] in self?.arrangePage() }
        arrangePage()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    override var isFlipped: Bool { true }
    override func layout() { super.layout(); arrangePage() }
    override func setFrameSize(_ newSize: NSSize) { super.setFrameSize(newSize); arrangePage() }
    func arrangePage() {
        guard !arranging, frame.width > 0, frame.height > 0 else { return }
        arranging = true
        defer { arranging = false }
        if abs(frame.width - displaySize.width) > 0.5 { webView.resetViewportWidth() }
        displaySize = frame.size
        let scale = WebPageFit.scale(viewWidth: frame.width, contentWidth: webView.fittedContentWidth)
        let viewport = CGSize(width: frame.width / scale, height: frame.height / scale)
        webView.setPreviewScale(scale)
        if bounds.size != viewport { setBoundsSize(viewport) }
        if webView.frame.size != viewport { webView.setFrameSize(viewport) }
    }
}
