import AppKit
import Testing
@testable import ClampEverything

@MainActor struct ClampFeedbackGeometryTests {
    @Test func nativeChineseAcknowledgementsFitOnOneLineInBothAppearances() {
        _ = NSApplication.shared
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            for message in ["已夹住", "已复制", "已放好", "Clip saved"] {
                let layout = ClampFeedbackLayout.make(message: message, at: .zero, screen: CGRect(x: 0, y: 0, width: 1440, height: 900))
                let view = ClampFeedbackContentView(message: message, kind: .success, size: layout.contentSize)
                view.appearance = NSAppearance(named: appearance); view.layoutSubtreeIfNeeded()
                let natural = view.label.cell?.cellSize ?? .zero
                #expect(view.label.maximumNumberOfLines == 1)
                #expect(view.label.cell?.usesSingleLineMode == true)
                #expect(view.label.frame.width >= natural.width)
                #expect(view.label.frame.height >= natural.height)
                #expect(view.bounds.contains(view.label.frame))
            }
        }
    }
    @Test func acknowledgementStaysCompactAndLongErrorsFitAtDisplayEdges() {
        for screen in [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: -300, width: 1920, height: 1080)] {
            for point in [screen.origin, CGPoint(x: screen.maxX, y: screen.maxY)] {
                let success = ClampFeedbackLayout.make(message: "已夹住", at: point, screen: screen)
                #expect(success.frame.width < 100 && success.frame.height < 42)
                #expect(screen.contains(success.frame))
                let error = ClampFeedbackLayout.make(message: "读取的文件已移动，请重新选择原文件后再试。", at: point, screen: screen)
                #expect(error.frame.width <= 260 && error.contentSize.height > 26)
                #expect(screen.contains(error.frame))
            }
        }
    }
}

@Suite(.serialized) @MainActor struct ClampFeedbackLifecycleTests {
    @Test func newFeedbackReplacesAnOldFadeAndSuccessClearsItself() async throws {
        _ = NSApplication.shared
        let presenter = ClampFeedbackPresenter()
        defer { presenter.dismiss() }
        let point = try #require(NSScreen.screens.first?.visibleFrame.origin)
        presenter.show("已夹住", kind: .success, at: point, animated: false)
        #expect(presenter.panel.isVisible && presenter.panel.ignoresMouseEvents)
        let firstHost = presenter.panel.contentView
        // Replace while the previous success is fading; its task cannot hide the new message.
        try await Task.sleep(nanoseconds: 900_000_000)
        presenter.show("原文件不可用", kind: .failure, at: point, animated: false)
        try await Task.sleep(nanoseconds: 300_000_000)
        #expect(presenter.panel.isVisible && presenter.panel.alphaValue == 1)
        #expect(presenter.panel.contentView !== firstHost)
        presenter.dismiss()
        #expect(!presenter.panel.isVisible && presenter.panel.contentView == nil)
        presenter.show("已夹住", kind: .success, at: point, animated: false)
        try await Task.sleep(nanoseconds: 1_150_000_000)
        #expect(!presenter.panel.isVisible && presenter.panel.contentView == nil)
    }
}
