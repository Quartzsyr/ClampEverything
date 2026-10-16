import AppKit
import ApplicationServices
import Testing
import ClampCore
@testable import ClampEverything

enum SubjectFixture {
    static let rect = CGRect(x: -800, y: 120, width: 640, height: 480)
    static var target: PointTarget { PointTarget(payload: .image(rect), title: "打开的大图", bounds: rect, subjectImageBounds: rect) }
    static func image(changed: Bool = false) throws -> CGImage {
        let w = 512, h = 384
        var bytes = [UInt8](repeating: 255, count: w * h * 4)
        for y in 0..<h { for x in 0..<w {
            let i = (y * w + x) * 4
            bytes[i] = 245; bytes[i + 1] = 243; bytes[i + 2] = 235
            let r = hypot(Double(x - 130), Double(y - 150))
            if r <= 65 && r > 18 { bytes[i] = changed ? 30 : 220; bytes[i + 1] = changed ? 160 : 50; bytes[i + 2] = 36 }
            if x >= 310 && x < 450 && y >= 80 && y < 210 { bytes[i] = 35; bytes[i + 1] = 125; bytes[i + 2] = 210 }
        } }
        return try #require(SubjectRaster.image(bytes, width: w, height: h))
    }
    static func point(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height) }
    static func selection(right: Bool = false) throws -> ImageSubjectSelection {
        let result = try ImageSubjectAnalyzer.analyze(image(), point: right ? CGPoint(x: 0.75, y: 0.36) : CGPoint(x: 0.18, y: 0.38),
            source: target, rect: rect, useVision: false)
        return try #require(result)
    }
}

struct ImageSubjectEligibilityTests {
    @Test func openedImageOptsInButFilesIconsAndThumbnailsKeepTheirDefaultTarget() throws {
        let rect = CGRect(x: 20, y: 40, width: 640, height: 480)
        let image = PointCandidate(role: kAXImageRole, title: "photo", rect: rect)
        #expect(try PointCapture.resolve([image]).subjectImageBounds == rect)
        let file = URL(fileURLWithPath: "/tmp/photo.png")
        let opened = try PointCapture.resolve([PointCandidate(role: kAXImageRole, url: file, rect: rect, fileKind: .image)])
        if case .file(let original) = opened.payload { #expect(original == file) } else { Issue.record("Default lost the original file") }
        #expect(opened.subjectImageBounds == rect)
        for role in ["AXCell", "AXRow", "AXDockItem", "AXButton", "AXMenuItem"] {
            #expect(try PointCapture.resolve([image, PointCandidate(role: role)]).subjectImageBounds == nil)
        }
        #expect(try PointCapture.resolve([PointCandidate(role: kAXImageRole, rect: rect, thumbnail: true)]).subjectImageBounds == nil)
        #expect(try PointCapture.resolve([PointCandidate(role: kAXImageRole, rect: CGRect(x: 0, y: 0, width: 256, height: 256))]).subjectImageBounds == nil)
        #expect(ImageSubjectEligibility.isLarge(CGRect(x: 0, y: 0, width: 1000, height: 100)))
        #expect(!ImageSubjectEligibility.isThumbnail(role: "image", subrole: nil, description: "app-icon.png"))
        #expect(ImageSubjectEligibility.isThumbnail(role: "image", subrole: "AXThumbnail", description: nil))
        #expect(!ImageSubjectEligibility.isLarge(CGRect(x: 0, y: 0, width: CGFloat.infinity, height: 500)))
        let pdf = try PointCapture.resolve([image, PointCandidate(role: "AXCell", url: URL(fileURLWithPath: "/tmp/report.pdf"), fileKind: .file)])
        #expect(pdf.subjectImageBounds == nil)
    }
    @Test func selectedTextStillWinsAndLargeLinkedImageDefaultsToWholeImage() throws {
        let image = PointCandidate(role: kAXImageRole, rect: SubjectFixture.rect)
        let selected = try PointCapture.resolve([image, PointCandidate(role: "AXLink", url: URL(string: "https://example.com"), selectedText: "文字")])
        if case .text = selected.payload {} else { Issue.record("Text selection lost priority") }
        let whole = try PointCapture.resolve([image, PointCandidate(role: "AXLink", url: URL(string: "https://example.com"))])
        if case .image = whole.payload {} else { Issue.record("A large image became a page link") }
    }
}

struct ImageSubjectSegmentationTests {
    @Test func operatorsSeparateBothSubjectsPreserveHolesAndRejectBackground() throws {
        let image = try SubjectFixture.image(), left = try SubjectFixture.selection(), right = try SubjectFixture.selection(right: true)
        #expect(left.contains(SubjectFixture.point(0.18, 0.38)))
        #expect(!left.contains(SubjectFixture.point(0.75, 0.36)))
        #expect(right.contains(SubjectFixture.point(0.75, 0.36)))
        #expect(!right.contains(SubjectFixture.point(0.18, 0.38)))
        #expect(!left.contains(SubjectFixture.point(130.0 / 512, 150.0 / 384)))
        #expect(left.screenRect.maxX < right.screenRect.minX)
        #expect(left.screenRect.width < SubjectFixture.rect.width / 2)
        #expect(left.screenRect.midY < SubjectFixture.rect.midY) // Asymmetric fixture checks top-left Y mapping.
        let red = try SubjectRaster(left.image), blue = try SubjectRaster(right.image)
        let redPixel = (red.height / 2 * red.width + red.width / 5) * 4
        let bluePixel = (blue.height / 2 * blue.width + blue.width / 2) * 4
        #expect(red.rgba[redPixel] > red.rgba[redPixel + 2])
        #expect(blue.rgba[bluePixel + 2] > blue.rgba[bluePixel])
        #expect(red.rgba[3] == 0)
        #expect(red.rgba[(red.height / 2 * red.width + red.width / 2) * 4 + 3] == 0)
        #expect(try ContrastSubjectDetector.mask(image, at: CGPoint(x: 0.5, y: 0.9)) == nil)
    }
    @Test func semanticMaskDropsDisconnectedSpecksAndDoesNotAcceptTheWholeFrame() throws {
        var pixels = [UInt8](repeating: 0, count: 100 * 100)
        for y in 20..<70 { for x in 10..<50 { pixels[y * 100 + x] = 255 } }
        for y in 5..<10 { for x in 80..<85 { pixels[y * 100 + x] = 255 } }
        let chosen = try #require(try SubjectMask(width: 100, height: 100, values: pixels).connected(at: CGPoint(x: 0.3, y: 0.4)))
        #expect(chosen.contains(CGPoint(x: 0.3, y: 0.4)))
        #expect(!chosen.contains(CGPoint(x: 0.82, y: 0.07)))
        #expect(try SubjectMask(width: 100, height: 100, values: [UInt8](repeating: 255, count: 10000)).connected(at: CGPoint(x: 0.5, y: 0.5)) == nil)
    }
    @Test func contourFollowsTheSubjectInsteadOfItsBoundingRectangle() throws {
        let selection = try SubjectFixture.selection(), light = try SubjectRaster(selection.highlight)
        #expect(light.rgba[3] == 0)
        let middle = (light.height / 2 * light.width + light.width / 2) * 4 + 3
        #expect(light.rgba[middle] == 0)
        let alpha = stride(from: 3, to: light.rgba.count, by: 4).map { light.rgba[$0] }
        #expect(alpha.contains { $0 > 180 })
        #expect(alpha.contains { $0 > 0 && $0 < 80 })
    }
}

@Suite(.serialized) @MainActor struct ImageSubjectAimTests {
    private func fixtureSelection(right: Bool = false) async throws -> ImageSubjectSelection {
        try await Task.detached { try SubjectFixture.selection(right: right) }.value
    }
    private func fixtureImage(changed: Bool = false) async throws -> CGImage {
        try await Task.detached { try SubjectFixture.image(changed: changed) }.value
    }
    @Test func shortDwellAndIconsNeverStartImageAnalysis() async throws {
        var analyses = 0
        let aim = ImageSubjectAimController(dwell: 30_000_000, analyze: { _, _ in analyses += 1; return nil })
        defer { aim.cancel() }
        let point = SubjectFixture.point(0.18, 0.38)
        aim.update(SubjectFixture.target, at: point); aim.cancel()
        let icon = PointTarget(payload: .image(SubjectFixture.rect), title: "icon", bounds: SubjectFixture.rect)
        aim.update(icon, at: point)
        try await Task.sleep(nanoseconds: 70_000_000)
        #expect(analyses == 0 && aim.selected(at: point) == nil)
    }
    @Test func stationaryRevalidationAndSmallTremorKeepOneDwellAndSelection() async throws {
        let selection = try await fixtureSelection(), point = SubjectFixture.point(0.13, 0.38)
        var analyses = 0
        let aim = ImageSubjectAimController(dwell: 10_000_000, analyze: { _, _ in analyses += 1; return selection })
        defer { aim.cancel() }
        let (events, stream) = AsyncStream<Bool>.makeStream(); defer { stream.finish() }
        aim.onSelection = { if $0 != nil { stream.yield(true) } }
        var iterator = events.makeAsyncIterator()
        aim.update(SubjectFixture.target, at: point)
        aim.update(SubjectFixture.target, at: point)
        aim.move(to: CGPoint(x: point.x + 2, y: point.y + 2))
        #expect(await iterator.next() == true)
        #expect(aim.selected(at: point) != nil && analyses == 1)
        aim.move(to: SubjectFixture.point(0.16, 0.40))
        #expect(aim.selected(at: point) != nil)
        // Five points across the silhouette must clear it; jitter tolerance only applies before selection.
        aim.move(to: SubjectFixture.point(0.122, 0.38))
        #expect(aim.selection == nil)
        aim.move(to: CGPoint(x: 2000, y: 2000))
        #expect(aim.selected(at: point) == nil)
    }
    @Test(.timeLimit(.minutes(1))) func movingToAnotherSubjectRejectsAnUncooperativeOldResult() async throws {
        let left = try await fixtureSelection(), right = try await fixtureSelection(right: true)
        let (events, stream) = AsyncStream<String>.makeStream(); defer { stream.finish() }
        let aim = ImageSubjectAimController(dwell: 1_000_000, analyze: { _, point in
            if point.x < SubjectFixture.rect.midX {
                stream.yield("old-start")
                await withCheckedContinuation { done in DispatchQueue.global().asyncAfter(deadline: .now() + 0.08) { done.resume() } }
                stream.yield("old-end"); return left
            }
            return right
        })
        defer { aim.cancel() }
        aim.onSelection = { if $0 != nil { stream.yield("selected") } }
        var iterator = events.makeAsyncIterator()
        aim.update(SubjectFixture.target, at: SubjectFixture.point(0.18, 0.38))
        #expect(await iterator.next() == "old-start")
        aim.move(to: SubjectFixture.point(0.75, 0.36))
        var seen: Set<String> = []
        while !seen.contains("old-end") || !seen.contains("selected") { if let event = await iterator.next() { seen.insert(event) } }
        #expect(aim.selected(at: SubjectFixture.point(0.18, 0.38)) == nil)
        #expect(aim.selected(at: SubjectFixture.point(0.75, 0.36)) != nil)
    }
    @Test func changedPixelsOrTargetCannotExportAnOldSubject() async throws {
        let selected = try await fixtureSelection(), image = try await fixtureImage(), changed = try await fixtureImage(changed: true)
        let point = SubjectFixture.point(0.18, 0.38)
        let same = try await ImageSubjectCapture.prepare(selected, at: point, resolve: { _ in SubjectFixture.target }, snapshot: { _, _ in image })
        #expect(same?.isSubject == true)
        let pressed = try #require(same?.image)
        #expect(try SubjectRaster(pressed).rgba == SubjectRaster(selected.image).rgba)
        let stale = try await ImageSubjectCapture.prepare(selected, at: point, resolve: { _ in SubjectFixture.target }, snapshot: { _, _ in changed })
        #expect(stale == nil)
        var snapshots = 0
        let wrong = try await ImageSubjectCapture.prepare(selected, at: point, resolve: { _ in PointTarget(payload: .text("new"), title: "new") }, snapshot: { _, _ in snapshots += 1; return image })
        #expect(wrong == nil && snapshots == 0)
    }
    @Test func cancellingDuringPressValidationCannotProduceASubject() async throws {
        let selected = try await fixtureSelection(), image = try await fixtureImage()
        let point = SubjectFixture.point(0.18, 0.38)
        let (events, stream) = AsyncStream<Bool>.makeStream(); defer { stream.finish() }
        let task = Task { @MainActor in
            try await ImageSubjectCapture.prepare(selected, at: point, resolve: { _ in SubjectFixture.target }, snapshot: { _, _ in
                stream.yield(true)
                try await Task.sleep(nanoseconds: 150_000_000)
                return image
            })
        }
        var iterator = events.makeAsyncIterator(); #expect(await iterator.next() == true)
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled validation returned content") }
        catch is CancellationError {} catch { Issue.record("Unexpected error: \(error)") }
    }
    @Test func savedAndCopiedSubjectRetainsPNGAlphaAndCutoutIdentity() async throws {
        let selection = try await fixtureSelection()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClampSubject-" + UUID().uuidString)
        let store = ClipStore(root: root); defer { try? FileManager.default.removeItem(at: root) }
        store.addCapturedImage(selection.image, title: "主体", isCutout: true)
        let item = try #require(store.active.first), file = try #require(store.fileURL(item))
        #expect(item.imageIsCutout == true && file.pathExtension == "png")
        let reopened = ClipStore(root: root)
        #expect(reopened.active.first?.imageIsCutout == true)
        reopened.loadThumbnail(item)
        for _ in 0..<100 {
            if reopened.images[item.id] != nil { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let preview = try #require(reopened.images[item.id]?.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #expect(try SubjectRaster(preview).rgba[3] == 0)
        let writer = try #require(store.pasteboardItem(item)), png = try #require(writer.data(forType: .png))
        let decoded = try #require(NSBitmapImageRep(data: png))
        #expect(decoded.colorAt(x: 0, y: 0)?.alphaComponent == 0)
        #expect(writer.string(forType: .fileURL) == file.absoluteString)
    }
}
