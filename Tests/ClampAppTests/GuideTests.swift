import AppKit
import SwiftUI
import Testing
import ClampCore
@testable import ClampEverything

@MainActor struct GuidePlaybackTests {
    @Test func tourCoversAllTypesAndCompletesAfterEveryStageExactlyOnce() {
        let tour = GuidePlayback()
        #expect(Set(GuidePlayback.kinds) == Set(PreviewSizeKind.allCases))
        var seen: [PreviewSizeKind: [GuideStage]] = [:]
        for _ in 0..<(GuidePlayback.kinds.count * GuideStage.allCases.count) {
            seen[tour.kind, default: []].append(tour.stage)
            tour.advance()
        }
        #expect(tour.finished && !tour.playing && tour.progress == 1)
        for kind in GuidePlayback.kinds { #expect(seen[kind] == GuideStage.allCases) }
        tour.advance(); #expect(tour.index == GuidePlayback.kinds.count - 1)
    }
    @Test func navigationResetsTheStageAndRestartDoesNotSkipExamples() {
        let tour = GuidePlayback()
        tour.advance(); tour.advance(); tour.next()
        #expect(tour.index == 1 && tour.stage == .aim)
        tour.previous(); #expect(tour.index == 0)
        tour.select(999); #expect(tour.index == 0)
        tour.select(GuidePlayback.kinds.count - 1); tour.next()
        #expect(tour.finished)
        tour.play(); #expect(tour.index == 0 && tour.stage == .aim && tour.playing)
        tour.pause(); #expect(!tour.playing)
    }
    @Test func pauseAndSelectionCancelTheOldClock() async throws {
        let tour = GuidePlayback()
        tour.play(); tour.select(2); tour.pause()
        try await Task.sleep(nanoseconds: 1_300_000_000)
        #expect(tour.index == 2 && tour.stage == .aim && !tour.playing)
        tour.replay(); #expect(tour.index == 2 && tour.stage == .aim && tour.playing)
        tour.pause()
    }
    @Test func exampleDocumentsAreReadableImagesAndEveryTypeHasConcreteContent() {
        _ = NSApplication.shared
        let samples = GuideExamples()
        #expect(samples.photo.size == CGSize(width: 800, height: 500))
        #expect(samples.pdf != nil && samples.document != nil)
        #expect(samples.pdf!.size.width > 100 && samples.document!.size.height > 100)
        for kind in GuidePlayback.kinds {
            #expect(!GuideExamples.filename(kind).isEmpty)
            #expect(!GuideExamples.explanation(kind).isEmpty)
        }
        #expect(GuideExamples.html.contains("田野手记"))
        #expect(GuideExamples.code.contains("struct LittleNote"))
    }
}

@Suite(.serialized) @MainActor struct GuideWindowTests {
    @Test func exampleWebpageRendersFromOfflineHTML() async throws {
        _ = NSApplication.shared
        let page = WebPagePreviewModel()
        let host = NSHostingView(rootView: WebPageSnapshotView(model: page,
            url: URL(string: "https://guide.clamp.invalid/")!, html: GuideExamples.html))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 240, height: 150), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = host
        defer { page.cancel(); window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        for _ in 0..<60 {
            if page.image != nil || page.failed { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(page.image != nil && !page.failed && !page.loading)
    }
    @Test func reopeningAndClosingStopsOldPlaybackAndDoesNotWriteExamplesToLibrary() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClampGuideTest-" + UUID().uuidString)
        let store = ClipStore(root: root); store.hidden = true
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        let before = store.state
        manager.showGuide()
        let first = try #require(manager.guidePlayback)
        #expect(manager.guidePanel.canBecomeKey && !manager.guidePanel.ignoresMouseEvents)
        #expect(first.playing && manager.guidePanel.contentView != nil)
        manager.showGuide()
        #expect(!first.playing)
        let second = try #require(manager.guidePlayback)
        manager.dismissGuide()
        #expect(!second.playing && !manager.guidePanel.isVisible)
        #expect(manager.guidePanel.contentView == nil && manager.guideExamples == nil)
        #expect(store.state == before)
        try await Task.sleep(nanoseconds: 1_300_000_000)
        #expect(first.stage == .aim && second.stage == .aim)
    }
}
