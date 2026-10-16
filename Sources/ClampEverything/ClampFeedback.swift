import AppKit
import SwiftUI
import QuartzCore

/// Small placement acknowledgement, separate from the cursor and the clipped object.
enum ClampFeedbackKind {
    case success, notice, failure
    var symbol: String {
        switch self { case .success: return "checkmark"; case .notice: return "info"; case .failure: return "exclamationmark" }
    }
    var holdDuration: Double { self == .success ? 0.85 : (self == .failure ? 2.8 : 1.6) }
}

struct ClampFeedbackLayout {
    let frame: CGRect
    let contentSize: CGSize
    static let font = NSFont.systemFont(ofSize: 11, weight: .medium)
    static func make(message: String, at point: CGPoint, screen: CGRect) -> Self {
        let text = (message as NSString).boundingRect(with: CGSize(width: 214, height: 50),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        let content = CGSize(width: max(62, min(250, ceil(text.width) + 42)), height: max(26, ceil(text.height) + 12))
        let size = CGSize(width: content.width + 10, height: content.height + 10)
        let x = max(screen.minX + 4, min(point.x + 12, screen.maxX - size.width - 4))
        let y = max(screen.minY + 4, min(point.y + 12, screen.maxY - size.height - 4))
        return Self(frame: CGRect(origin: CGPoint(x: x, y: y), size: size), contentSize: content)
    }
}

/// Measure and draw with the same native font; SwiftUI must not recompress CJK text.
final class ClampFeedbackContentView: NSView {
    let label = NSTextField(wrappingLabelWithString: "")
    private let icon = NSImageView()
    private var kind: ClampFeedbackKind = .success
    override var isFlipped: Bool { true }
    init(message: String, kind: ClampFeedbackKind, size: CGSize) {
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: size.width + 10, height: size.height + 10)))
        label.font = ClampFeedbackLayout.font
        label.isSelectable = false; label.textColor = .labelColor
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
        addSubview(icon); addSubview(label)
        configure(message, kind: kind)
        setAccessibilityElement(true); setAccessibilityRole(.staticText)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func configure(_ message: String, kind: ClampFeedbackKind) {
        self.kind = kind; label.stringValue = message
        label.maximumNumberOfLines = kind == .success ? 1 : 3
        label.cell?.usesSingleLineMode = kind == .success
        label.lineBreakMode = kind == .success ? .byClipping : .byWordWrapping
        icon.image = NSImage(systemSymbolName: kind.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        icon.contentTintColor = kind == .failure ? .systemOrange : (kind == .success ? NSColor(calibratedRed: 0.23, green: 0.40, blue: 0.39, alpha: 1) : .secondaryLabelColor)
        setAccessibilityLabel(message); needsLayout = true; needsDisplay = true
    }
    override func layout() {
        super.layout()
        let width = max(0, bounds.width - 46)
        label.preferredMaxLayoutWidth = width
        let measured = label.cell?.cellSize(forBounds: CGRect(x: 0, y: 0, width: width, height: 60)).height ?? 14
        let height = min(bounds.height - 10, max(14, measured))
        label.frame = CGRect(x: 31, y: (bounds.height - height) / 2, width: width, height: height)
        icon.frame = CGRect(x: 15, y: (bounds.height - 11) / 2, width: 10, height: 11)
    }
    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 5, dy: 5), xRadius: 7, yRadius: 7)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow(); shadow.shadowColor = NSColor.black.withAlphaComponent(0.10)
        shadow.shadowBlurRadius = 2; shadow.shadowOffset = CGSize(width: 0, height: 1); shadow.set()
        NSColor.controlBackgroundColor.withAlphaComponent(0.96).setFill(); path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.labelColor.withAlphaComponent(0.06).setStroke(); path.lineWidth = 0.5; path.stroke()
    }
}

struct ClampFeedbackView: NSViewRepresentable {
    let message: String
    let kind: ClampFeedbackKind
    let size: CGSize
    func makeNSView(context: Context) -> ClampFeedbackContentView { ClampFeedbackContentView(message: message, kind: kind, size: size) }
    func updateNSView(_ view: ClampFeedbackContentView, context: Context) { view.configure(message, kind: kind) }
}

@MainActor final class ClampFeedbackPresenter {
    let panel = FloatingPanel()
    private var task: Task<Void, Never>?
    private var generation = 0
    init() {
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
    }
    func show(_ message: String, kind: ClampFeedbackKind, at point: CGPoint, animated: Bool) {
        dismiss()
        let screen = NSScreen.screens.first { $0.frame.contains(point) }?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1000, height: 800)
        let layout = ClampFeedbackLayout.make(message: message, at: point, screen: screen)
        panel.contentView = ClampFeedbackContentView(message: message, kind: kind, size: layout.contentSize)
        panel.setFrame(layout.frame, display: true)
        panel.alphaValue = animated ? 0 : 1
        panel.orderFrontRegardless()
        if animated { fade(to: 1, duration: 0.14) }
        let token = generation
        task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(kind.holdDuration * 1_000_000_000))
                guard let self, self.generation == token else { return }
                self.fade(to: 0, duration: animated ? 0.22 : 0.12)
                try await Task.sleep(nanoseconds: animated ? 220_000_000 : 120_000_000)
                guard self.generation == token else { return }
                self.dismiss()
            } catch { return }
        }
    }
    private func fade(to alpha: CGFloat, duration: Double) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration; context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().alphaValue = alpha
        }
    }
    func dismiss() {
        generation += 1; task?.cancel(); task = nil
        // Removing the old host also prevents a replacement from retaining stale text.
        panel.orderOut(nil); panel.contentView = nil
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0; panel.animator().alphaValue = 1
        }
    }
}
