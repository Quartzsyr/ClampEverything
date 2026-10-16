import AppKit
import SwiftUI
import Testing
@testable import ClampEverything

@Suite(.serialized) @MainActor struct CodeReadingTests {
    @Test func sourceFitsThePaperAndLongLinesWrapWithoutDroppingCharacters() throws {
        _ = NSApplication.shared
        let view = CodeReadingScrollView(frame: CGRect(x: 0, y: 0, width: 296, height: 220))
        let source = "TY  - JOUR\nTI  - Advances in chiral analysis: " + String(repeating: "完整标题 very long source ", count: 200)
            + "\nAU  - Penasa, Roberto\n\tlet unicode = \"你好\"\n"
        view.setSource(source)
        for width: CGFloat in [192, 296, 533] {
            view.setFrameSize(CGSize(width: width, height: 220)); view.layoutSubtreeIfNeeded()
            view.paper.arrange(in: view.contentSize)
            let paper = view.paper, text = paper.text
            #expect(text.string == source)
            #expect(paper.frame.width <= width && text.frame.maxX <= width - 11)
            #expect(paper.fontSize >= 7)
            #expect(!view.hasHorizontalScroller)
            let manager = try #require(text.layoutManager), container = try #require(text.textContainer)
            let glyphs = manager.glyphRange(for: container)
            var fragments = 0
            manager.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in
                fragments += 1
                #expect(used.maxX <= container.containerSize.width + 1)
            }
            #expect(fragments > source.components(separatedBy: "\n").count)
            #expect(paper.frame.height > view.contentSize.height)
        }
    }
    @Test func resizingScalesShortCodeAndKeepsTheOriginalSyntaxColors() throws {
        _ = NSApplication.shared
        let view = CodeReadingScrollView(frame: CGRect(x: 0, y: 0, width: 192, height: 220))
        view.setSource("let 文字 = \"hello\"\nreturn 42")
        view.paper.arrange(in: view.contentSize)
        let small = view.paper.fontSize
        view.setFrameSize(CGSize(width: 533, height: 220)); view.layoutSubtreeIfNeeded()
        view.paper.arrange(in: view.contentSize)
        #expect(view.paper.fontSize > small)
        let storage = try #require(view.paper.text.textStorage)
        let font = try #require(storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        #expect(font.pointSize == view.paper.fontSize)
        #expect(storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .systemPurple)
        #expect(storage.string == "let 文字 = \"hello\"\nreturn 42")
    }
}
