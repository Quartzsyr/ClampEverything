import AppKit
import SwiftUI

/// Fit ordinary source lines before soft-wrapping unusually long lines. The
/// floor prevents a single URL or minified line making the whole page illegible.
enum CodePreviewLayout {
    static func fontSize(width: CGFloat, sourceWidthAtEleven: CGFloat, digits: Int) -> CGFloat {
        let preferred = min(16, max(7, 11 * width / 296))
        let available = max(1, width - 24)
        let content = max(1, sourceWidthAtEleven + CGFloat(digits) * 6.7 + 10)
        return min(preferred, max(7, 11 * available / content))
    }
}

struct CodeReadingView: NSViewRepresentable {
    let source: String
    func makeNSView(context: Context) -> CodeReadingScrollView { CodeReadingScrollView() }
    func updateNSView(_ view: CodeReadingScrollView, context: Context) { view.setSource(source) }
}

final class CodeReadingScrollView: NSScrollView {
    let paper = CodeReadingPaper()
    override init(frame: NSRect) {
        super.init(frame: frame)
        drawsBackground = false; borderType = .noBorder
        hasVerticalScroller = true; hasHorizontalScroller = false
        autohidesScrollers = true; scrollerStyle = .overlay
        documentView = paper
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func setSource(_ source: String) {
        guard paper.source != source else { return }
        paper.setSource(source)
        paper.arrange(in: contentSize)
        contentView.scroll(to: .zero)
    }
    override func layout() { super.layout(); paper.arrange(in: contentSize) }
}

/// One TextKit layout owns text and logical line numbers, including soft wraps.
/// It has no horizontal overflow; the copy/drag overlay still exports the file.
final class CodeReadingPaper: NSView {
    let text = NSTextView(frame: .zero)
    private(set) var source = ""
    private var colored = NSAttributedString()
    private var starts: [Int] = [0]
    private var measuredWidth: CGFloat = 0
    private var lastSize = CGSize.zero
    private(set) var fontSize: CGFloat = 11
    private(set) var gutter: CGFloat = 24
    override var isFlipped: Bool { true }
    override init(frame: NSRect) {
        super.init(frame: frame)
        text.drawsBackground = false; text.isEditable = false
        text.isSelectable = true; text.isRichText = false
        text.isHorizontallyResizable = false; text.isVerticallyResizable = true
        text.minSize = .zero
        text.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = .zero
        text.textContainer?.lineFragmentPadding = 0
        text.textContainer?.widthTracksTextView = true
        text.textContainer?.heightTracksTextView = false
        addSubview(text)
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
    func setSource(_ source: String) {
        self.source = source; lastSize = .zero
        colored = NSAttributedString(CodeColoring.highlight(source))
        starts = [0]
        for (index, unit) in source.utf16.enumerated() where unit == 10 { starts.append(index + 1) }
        let font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        measuredWidth = source.components(separatedBy: "\n").map {
            ($0.replacingOccurrences(of: "\t", with: "    ") as NSString).size(withAttributes: [.font: font]).width
        }.max() ?? 0
    }
    func arrange(in viewport: CGSize) {
        guard viewport.width > 0, viewport.height > 0, viewport != lastSize else { return }
        lastSize = viewport
        fontSize = CodePreviewLayout.fontSize(width: viewport.width, sourceWidthAtEleven: measuredWidth, digits: String(starts.count).count)
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let numberWidth = (String(starts.count) as NSString).size(withAttributes: [.font: font]).width
        gutter = ceil(numberWidth) + 10
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = fontSize * 0.28
        paragraph.lineBreakMode = .byWordWrapping
        paragraph.tabStops = []; paragraph.defaultTabInterval = ("    " as NSString).size(withAttributes: [.font: font]).width
        let value = NSMutableAttributedString(attributedString: colored)
        value.addAttributes([.font: font, .paragraphStyle: paragraph], range: NSRange(location: 0, length: value.length))
        text.textStorage?.setAttributedString(value)
        let width = max(1, viewport.width - 24 - gutter)
        text.setFrameSize(CGSize(width: width, height: viewport.height))
        text.textContainer?.containerSize = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        guard let manager = text.layoutManager, let container = text.textContainer else { return }
        manager.ensureLayout(for: container)
        let height = ceil(max(manager.usedRect(for: container).maxY, manager.extraLineFragmentRect.maxY))
        text.frame = CGRect(x: 12 + gutter, y: 14, width: width, height: max(1, height))
        setFrameSize(CGSize(width: viewport.width, height: max(viewport.height, height + 28)))
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        guard let manager = text.layoutManager else { return }
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor.withAlphaComponent(0.6)]
        for (line, start) in starts.enumerated() {
            let rect: CGRect
            if start < colored.length {
                let glyph = manager.glyphIndexForCharacter(at: start)
                rect = manager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            } else { rect = manager.extraLineFragmentRect }
            let y = text.frame.minY + rect.minY
            guard y + rect.height >= dirtyRect.minY, y <= dirtyRect.maxY else { continue }
            let label = String(line + 1) as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: CGPoint(x: 12 + gutter - 10 - size.width, y: y), withAttributes: attributes)
        }
    }
}
