import AppKit
import Testing
@testable import ClampEverything

struct TargetGlowGeometryTests {
    @Test func convertsNegativeDisplayAndClipsToVisibleObject() throws {
        let screen = CGRect(x: -1440, y: 0, width: 1440, height: 900)
        let frame = try #require(TargetGlowGeometry.frame(rect: CGRect(x: -1500, y: 100, width: 300, height: 200), screen: screen, desktopTop: 900))
        #expect(frame == CGRect(x: -1454, y: 586, width: 268, height: 228))
    }
    @Test func rejectsMissingOrNonfiniteBounds() {
        let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
        for rect in [CGRect.zero, CGRect(x: 2000, y: 0, width: 100, height: 100), CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 80)] {
            #expect(TargetGlowGeometry.frame(rect: rect, screen: screen, desktopTop: 800) == nil)
        }
    }
    @Test func selectedTextUsesSelectionBoundsInsteadOfParentLink() throws {
        let selection = CGRect(x: 30, y: 70, width: 120, height: 22)
        let target = try PointCapture.resolve([
            PointCandidate(role: "AXStaticText", selectedText: "selected", rect: CGRect(x: 0, y: 0, width: 700, height: 500), selectionRect: selection),
            PointCandidate(role: "AXLink", url: URL(string: "https://example.com"), rect: CGRect(x: 0, y: 0, width: 700, height: 500))
        ])
        #expect(target.bounds == selection)
    }
}

@MainActor struct TargetAimTests {
    @Test(.timeLimit(.minutes(1))) func movementDiscardsEvenAnUncooperativeOldRead() async throws {
        let (events, continuation) = AsyncStream<String>.makeStream()
        defer { continuation.finish() }
        let aim = TargetAimController(dwell: 5_000_000, hintDelay: 5_000_000, read: { point in
            if point.x == 1 {
                continuation.yield("old-started")
                // This read deliberately completes even after cancellation.
                await withCheckedContinuation { done in
                    DispatchQueue.global().asyncAfter(deadline: .now() + 0.12) { done.resume() }
                }
                continuation.yield("old-finished")
            }
            return PointTarget(payload: .text("text"), title: "\(Int(point.x))")
        })
        defer { aim.cancel() }
        var titles: [String] = []
        aim.onTarget = { if let target = $0 { titles.append(target.title); continuation.yield("target-" + target.title) } }
        var iterator = events.makeAsyncIterator()
        aim.update(at: CGPoint(x: 1, y: 0))
        #expect(await iterator.next() == "old-started")
        aim.update(at: CGPoint(x: 2, y: 0))
        var completed: Set<String> = []
        while !completed.contains("old-finished") || !completed.contains("target-2") {
            if let event = await iterator.next() { completed.insert(event) }
        }
        #expect(titles == ["2"])
    }
    @Test func cancelBeforeDwellSuppressesTargetAndHint() async throws {
        let aim = TargetAimController(dwell: 40_000_000, hintDelay: 5_000_000, read: { _ in PointTarget(payload: .text("x"), title: "x") })
        var shown = false
        aim.onTarget = { if $0 != nil { shown = true } }
        aim.onHint = { if $0 { shown = true } }
        aim.update(at: .zero); aim.cancel()
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(!shown)
    }
    @Test(.timeLimit(.minutes(1))) func hintWaitsAfterGlowAndMovementHidesBothImmediately() async throws {
        let aim = TargetAimController(dwell: 5_000_000, hintDelay: 100_000_000, read: { _ in PointTarget(payload: .text("x"), title: "x") })
        defer { aim.cancel() }
        var targetVisible = false, hintVisible = false
        let (events, continuation) = AsyncStream<String>.makeStream()
        defer { continuation.finish() }
        aim.onTarget = {
            targetVisible = $0 != nil
            if targetVisible { continuation.yield("target") }
        }
        aim.onHint = {
            hintVisible = $0
            if $0 { continuation.yield("hint") }
        }
        var iterator = events.makeAsyncIterator()
        aim.update(at: .zero)
        #expect(await iterator.next() == "target")
        aim.update(at: .zero) // Watchdog re-sampling must not restart the dwell.
        #expect(await iterator.next() == "hint")
        aim.update(at: CGPoint(x: 20, y: 30))
        #expect(!targetVisible && !hintVisible)
    }
}

struct TypedTargetGlowTests {
    @Test func targetPayloadSelectsDistinctStyles() {
        let rect = CGRect(x: 20, y: 30, width: 100, height: 40)
        #expect(TargetGlowStyle.forTarget(PointTarget(payload: .text("x"), title: "x")) == .text)
        #expect(TargetGlowStyle.forTarget(PointTarget(payload: .image(rect), title: "image")) == .image)
        #expect(TargetGlowStyle.forTarget(PointTarget(payload: .link(URL(string: "https://example.com")!), title: "link")) == .link)
        #expect(TargetGlowStyle.forTarget(PointTarget(payload: .file(URL(fileURLWithPath: "/tmp/folder", isDirectory: true)), title: "folder")) == .folder)
        #expect(TargetGlowStyle.forTarget(PointTarget(payload: .file(URL(fileURLWithPath: "/tmp/image.png")), title: "image", fileKind: .image)) == .image)
        #expect(TargetGlowStyle.forTarget(PointTarget(payload: .file(URL(fileURLWithPath: "/tmp/report.pdf")), title: "file")) == .file)
    }
    @Test func multilineTextKeepsSeparateLocalContoursAndNativeRegions() throws {
        let lines = [CGRect(x: 100, y: 100, width: 240, height: 20), CGRect(x: 100, y: 126, width: 130, height: 20)]
        let target = try PointCapture.resolve([PointCandidate(role: "AXStaticText", text: "first\nsecond", rect: CGRect(x: 100, y: 100, width: 300, height: 100), textRegions: lines)])
        #expect(target.regions == lines)
        let layout = try #require(TargetGlowLayout.make(regions: target.regions, screen: CGRect(x: 0, y: 0, width: 1000, height: 800), desktopTop: 800))
        #expect(layout.regions == [CGRect(x: 14, y: 14, width: 240, height: 20), CGRect(x: 14, y: 40, width: 130, height: 20)])
        #expect(layout.frame.size == CGSize(width: 268, height: 74))
    }
    @Test func sameBoundaryDoesNotMakeFileAndImageUseSameContour() {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 70)
        let file = TargetGlowContour(regions: [bounds], style: .file).path(in: bounds)
        let image = TargetGlowContour(regions: [bounds], style: .image).path(in: bounds)
        let link = TargetGlowContour(regions: [bounds], style: .link).path(in: bounds)
        #expect(file != image)
        #expect(link.boundingRect.height == 0)
        #expect(image.boundingRect.height > 70)
    }
}

@MainActor struct MovingTargetGlowTests {
    @Test(.timeLimit(.minutes(1))) func movementInsideTargetDimsAndLeavingTargetClears() async throws {
        let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let aim = TargetAimController(dwell: 5_000_000, hintDelay: 50_000_000, read: { _ in
            PointTarget(payload: .text("text"), title: "text", bounds: bounds)
        })
        defer { aim.cancel() }
        let (events, continuation) = AsyncStream<Bool>.makeStream()
        defer { continuation.finish() }
        var visible = false, moving = false
        aim.onTarget = { visible = $0 != nil; if visible { continuation.yield(true) } }
        aim.onMotion = { moving = $0 }
        var iterator = events.makeAsyncIterator()
        aim.update(at: CGPoint(x: 10, y: 10))
        _ = await iterator.next()
        aim.update(at: CGPoint(x: 20, y: 20))
        #expect(visible && moving)
        _ = await iterator.next()
        aim.update(at: CGPoint(x: 200, y: 200))
        #expect(!visible && !moving)
    }
}
