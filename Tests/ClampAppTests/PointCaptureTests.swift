import AppKit
import ApplicationServices
import Testing
@testable import ClampEverything

struct PointTargetResolutionTests {
    @Test func explicitSelectionBeatsParentLink() throws {
        let target = try PointCapture.resolve([
            PointCandidate(role: kAXStaticTextRole, selectedText: "保留选中段落", text: "整个段落"),
            PointCandidate(role: "AXLink", url: URL(string: "https://example.com"))
        ])
        guard case .text(let text) = target.payload else { Issue.record("Expected selected text"); return }
        #expect(text == "保留选中段落")
    }
    @Test func fileIdentityBeatsItsVisibleLabel() throws {
        let url = URL(fileURLWithPath: "/private/tmp/example.pdf")
        let target = try PointCapture.resolve([PointCandidate(role: "AXCell", url: url, selectedText: "example.pdf")])
        guard case .file(let file) = target.payload else { Issue.record("Expected file reference"); return }
        #expect(file == url)
    }
    @Test func linkWithoutSelectionKeepsURL() throws {
        let url = URL(string: "https://example.com/path")!
        let target = try PointCapture.resolve([PointCandidate(role: "AXLink", url: url, selectedText: " \n", title: "网页")])
        guard case .link(let link) = target.payload else { Issue.record("Expected link"); return }
        #expect(link == url)
    }
    @Test func secureAncestorRejectsAllPayloads() {
        do {
            _ = try PointCapture.resolve([PointCandidate(role: kAXStaticTextRole, text: "private"), PointCandidate(role: kAXTextFieldRole, secure: true)])
            Issue.record("Secure content was accepted")
        } catch PointCaptureError.secure {} catch { Issue.record("Wrong error: \(error)") }
    }
    @Test func unknownContainersDoNotBecomeWholeWindowScreenshots() {
        do {
            _ = try PointCapture.resolve([PointCandidate(role: kAXWindowRole, rect: CGRect(x: 0, y: 0, width: 900, height: 700))])
            Issue.record("Unexpected window capture")
        } catch PointCaptureError.unavailable {} catch { Issue.record("Wrong error: \(error)") }
    }
}

@MainActor struct PointPreparationTests {
    private func image() throws -> CGImage {
        let context = try #require(CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        return try #require(context.makeImage())
    }
    @Test func imageFreezesSourceRegionOnceBeforeDrop() async throws {
        let rect = CGRect(x: 32, y: 48, width: 100, height: 80)
        let source = CGPoint(x: 40, y: 60)
        let image = try image()
        var screenshots = 0
        let prepared = try await PointCapture.prepare(at: source, resolve: { _ in
            PointTarget(payload: .image(rect), title: "source")
        }, snapshot: { region, point in
            #expect(region == rect && point == source)
            screenshots += 1
            return image
        })
        #expect(screenshots == 1)
        #expect(prepared.image === image)
    }
    @Test func textDoesNotRequestScreenCapture() async throws {
        var screenshots = 0
        let image = try image()
        let prepared = try await PointCapture.prepare(at: .zero, resolve: { _ in
            PointTarget(payload: .text("text"), title: "selection")
        }, snapshot: { _, _ in screenshots += 1; return image })
        #expect(screenshots == 0)
        #expect(prepared.image == nil)
    }
    @Test func cancelledPreparationCannotDeliverImage() async throws {
        let image = try image()
        let task = Task { @MainActor in
            try await PointCapture.prepare(at: .zero, resolve: { _ in
                PointTarget(payload: .image(CGRect(x: 0, y: 0, width: 8, height: 8)), title: "image")
            }, snapshot: { _, _ in
                try await Task.sleep(nanoseconds: 200_000_000)
                return image
            })
        }
        try await Task.sleep(nanoseconds: 20_000_000)
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancelled capture produced an image") }
        catch is CancellationError {} catch { Issue.record("Wrong error: \(error)") }
    }
}
