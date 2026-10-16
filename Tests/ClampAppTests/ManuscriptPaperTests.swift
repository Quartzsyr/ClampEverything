import AppKit
import SwiftUI
import Testing
import ClampCore
@testable import ClampEverything

struct LeftBindingPaperTests {
    private func apply(_ t: ProjectionTransform, _ p: CGPoint) -> CGPoint {
        let w = t.m13 * p.x + t.m23 * p.y + t.m33
        return CGPoint(x: (t.m11 * p.x + t.m21 * p.y + t.m31) / w,
                       y: (t.m12 * p.x + t.m22 * p.y + t.m32) / w)
    }
    @Test func theWholeLeftBindingStaysFixedThroughoutForwardAndBackwardTurns() {
        for size in [CGSize(width: 192, height: 256), CGSize(width: 400, height: 220)] {
            for direction in [-1, 1] {
                for p in stride(from: CGFloat(0), through: 1, by: 0.05) {
                    let t = LeftBindingPageGeometry.projection(size: size,
                        amount: LeftBindingPageGeometry.amount(progress: p, direction: direction))
                    for y in [CGFloat(0), size.height * 0.25, size.height * 0.5, size.height] {
                        let point = apply(t, CGPoint(x: 0, y: y))
                        #expect(abs(point.x) < 0.00001 && abs(point.y - y) < 0.00001)
                        let bent = LeftBindingPageGeometry.curlPoint(CGPoint(x: 0, y: y), size: size, pull: PaperPull(x: 0.9, y: 0.7))
                        #expect(bent == CGPoint(x: 0, y: y))
                    }
                }
            }
        }
    }
    @Test func backwardLaysTheIncomingSheetDownInsteadOfPeelingTheCurrentSheetAgain() {
        #expect(LeftBindingPageGeometry.amount(progress: 0, direction: 1) == 0)
        #expect(LeftBindingPageGeometry.amount(progress: 1, direction: 1) == 1)
        #expect(LeftBindingPageGeometry.amount(progress: 0, direction: -1) == 1)
        #expect(LeftBindingPageGeometry.amount(progress: 1, direction: -1) == 0)
        #expect(LeftBindingPageGeometry.opacity(amount: 1) == 0)
        let size = CGSize(width: 200, height: 280)
        let mid = apply(LeftBindingPageGeometry.projection(size: size, amount: 0.5), CGPoint(x: 200, y: 140))
        #expect(mid.x > 0 && mid.x < 200 && abs(mid.y - 140) < 0.001)
    }
    @Test func freeEdgeLiftsOutTowardTheViewerInsteadOfRecedingIntoTheStack() {
        let size = CGSize(width: 200, height: 280)
        for amount: CGFloat in [0.2, 0.4, 0.6, 0.8] {
            let t = LeftBindingPageGeometry.projection(size: size, amount: amount)
            let top = apply(t, CGPoint(x: size.width, y: 0))
            let bottom = apply(t, CGPoint(x: size.width, y: size.height))
            #expect(t.m13 < 0)
            #expect(top.y < 0 && bottom.y > size.height)
            #expect(bottom.y - top.y > size.height)
            #expect(top.x.isFinite && bottom.y.isFinite)
        }
    }
    @Test func wearIsStableFineAndPreservesTheBindingAndJaw() {
        let id = UUID(uuidString: "44905A51-BB53-4AAC-9862-27BF09480DA1")!
        let seed = PaperWearGeometry.seed(id)
        #expect(PaperWearGeometry.seed(id) == seed)
        var depths = Set<CGFloat>()
        for i in 0...100 {
            let t = CGFloat(i) / 100
            let d = PaperWearGeometry.depth(edge: 1, fraction: t, seed: seed, boundLeft: true, clipOnLeft: false)
            #expect(d >= 0 && d <= 1.05); depths.insert(d)
            #expect(PaperWearGeometry.depth(edge: 3, fraction: t, seed: seed, boundLeft: true, clipOnLeft: false) == 0)
        }
        #expect(depths.count > 20)
        #expect(PaperWearGeometry.depth(edge: 0, fraction: 0.85, seed: seed, boundLeft: true, clipOnLeft: false) == 0)
    }
    @Test func curlStaysInTheMarginAndLeavesThePrintedCentreIntact() {
        let size = CGSize(width: 192, height: 256)
        let rest = PaperWearGeometry.curl(size: size, fold: 0, pull: .resting)
        let pulled = PaperWearGeometry.curl(size: size, fold: 1, pull: PaperPull(x: 1, y: 1))
        #expect(rest < 10 && pulled > rest && pulled <= size.width * 0.22)
        let shape = ManuscriptOutline(seed: 51, corner: rest, boundLeft: true).path(in: CGRect(origin: .zero, size: size))
        for x in [CGFloat(3), 24, 96, 168, 189] {
            for y in [CGFloat(12), 24, 128, 232] { #expect(shape.contains(CGPoint(x: x, y: y))) }
        }
        #expect(!shape.contains(CGPoint(x: 191.9, y: 255.9)))
        #expect(shape.contains(CGPoint(x: 0.05, y: 128)))
        #expect(shape.boundingRect.width <= size.width && shape.boundingRect.height <= size.height)
    }
    @Test func onlyManuscriptFormsReceivePaperWear() {
        for form in [PinnedContentForm.notePage, .codePage, .documentPrint, .webPrint, .fileSheet] { #expect(form.isManuscript) }
        for form in [PinnedContentForm.photo, .pocket, .cassette, .filmStrip, .parcel] { #expect(!form.isManuscript) }
    }
}

@Suite(.serialized) @MainActor struct ManuscriptRenderingTests {
    @Test func pageTurnWindowMakesRoomWithoutMovingTheClipAndReturnsToItsRestingFrame() throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClampOutwardTurn-" + UUID().uuidString)
        let store = ClipStore(root: root); store.hidden = true
        let item = ClipItem(kind: .file, title: "sample.pdf"); store.state.items = [item]
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        let model = manager.model(item.id); model.present(animated: false)
        let resting = model.panel.frame, sheet = model.sheetSize
        model.documentTurn(true)
        #expect(model.pageTurnInset > 0 && model.sheetSize == sheet)
        #expect(abs(model.panel.frame.maxY - model.pageTurnInset - resting.maxY) < 0.01)
        #expect(abs(model.panel.frame.height - resting.height - model.pageTurnInset * 2) < 0.01)
        #expect(abs(model.panel.frame.minX + model.pageTurnSideInset - resting.minX) < 0.01)
        #expect(abs(model.panel.frame.width - resting.width - model.pageTurnSideInset * 2) < 0.01)
        model.documentTurn(false)
        #expect(model.panel.frame == resting && model.pageTurnInset == 0)
    }
    @Test func liftedPageRemainsVisibleOutsideTheRestingPaperBounds() async throws {
        _ = NSApplication.shared
        func image(_ color: NSColor) -> NSImage {
            let image = NSImage(size: CGSize(width: 200, height: 280)); image.lockFocus()
            color.setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: 200, height: 280)).fill(); image.unlockFocus(); return image
        }
        for direction in [-1, 1] {
            let host = NSHostingView(rootView: PageTurnPreview(image: image(direction > 0 ? .blue : .red),
                previous: image(direction > 0 ? .red : .blue), progress: 0.5, direction: direction)
                .frame(width: 200, height: 280).padding(60).background(Color.white))
            let bounds = CGRect(x: 0, y: 0, width: 320, height: 400)
            let window = NSWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; host.frame = bounds
            defer { window.contentView = nil; window.close() }
            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            try await Task.sleep(nanoseconds: 150_000_000)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: bounds)); host.cacheDisplay(in: bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / bounds.width
            let lifted = try #require(bitmap.colorAt(x: Int(180 * scale), y: Int(45 * scale))?.usingColorSpace(.sRGB))
            #expect(lifted.redComponent > lifted.blueComponent + 0.3)
        }
    }
    @Test func aHalfTurnRevealsTheNextPageOnTheRightWhileTheLeftStillCarriesTheOldSheet() async throws {
        _ = NSApplication.shared
        func image(_ color: NSColor) -> NSImage {
            let image = NSImage(size: CGSize(width: 200, height: 280)); image.lockFocus()
            color.setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: 200, height: 280)).fill(); image.unlockFocus(); return image
        }
        let old = image(.red), next = image(.blue)
        for progress in [CGFloat(0), 0.5, 1] {
            let bounds = CGRect(x: 0, y: 0, width: 200, height: 280)
            let host = NSHostingView(rootView: PageTurnPreview(image: next, previous: old, progress: progress, direction: 1)
                .frame(width: 200, height: 280).background(Color.white))
            let window = NSWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.contentView = host; host.frame = bounds
            defer { window.contentView = nil; window.close() }
            host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
            try await Task.sleep(nanoseconds: 150_000_000)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: bounds)); host.cacheDisplay(in: bounds, to: bitmap)
            let left = try #require(bitmap.colorAt(x: Int(Double(bitmap.pixelsWide) * 0.1), y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
            let right = try #require(bitmap.colorAt(x: Int(Double(bitmap.pixelsWide) * 0.85), y: bitmap.pixelsHigh / 2)?.usingColorSpace(.sRGB))
            if progress < 1 { #expect(left.redComponent > left.blueComponent + 0.3) }
            else { #expect(left.blueComponent > left.redComponent + 0.3) }
            if progress > 0 { #expect(right.blueComponent > right.redComponent + 0.3) }
            else { #expect(right.redComponent > right.blueComponent + 0.3) }
        }
    }
}
