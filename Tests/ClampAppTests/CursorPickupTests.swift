import AppKit
import SwiftUI
import Testing
import ClampCore
@testable import ClampEverything

struct CursorPickupGeometryTests {
    @Test func pickupLiftsBeforeTravellingAndEndsExactlyAtTheJawForEveryMaterial() {
        let source = CGRect(x: -500, y: 200, width: 180, height: 80), jaw = CGPoint(x: 320, y: -180)
        for material in PhysicalMaterial.allCases {
            let first = CursorPickupGeometry.sample(progress: 0, source: source, jaw: jaw, material: material)
            #expect(first.frame == source && first.jaw == 1)
            let contact = CursorPickupGeometry.sample(progress: 0.14, source: source, jaw: jaw, material: material)
            #expect(contact.compression > 0 && contact.frame.minX == source.minX)
            #expect(contact.frame.minY > source.minY)
            let final = CursorPickupGeometry.sample(progress: 1, source: source, jaw: jaw, material: material)
            #expect(final.frame == CursorPickupGeometry.heldFrame(at: jaw))
            #expect(final.angle == -6 && abs(final.bend) < 0.000001)
            #expect(final.miniature == 1 && final.sourceLight == 0)
            #expect(abs(final.jaw - material.jawOpening) < 0.000001)
            // Rotation uses this exact top-edge contact in both views.
            #expect(final.frame.minX + 12 == jaw.x && final.frame.maxY == jaw.y)
        }
        let paper = CursorPickupGeometry.sample(progress: 0.5, source: source, jaw: jaw, material: .note)
        let cassette = CursorPickupGeometry.sample(progress: 0.5, source: source, jaw: jaw, material: .audio)
        #expect(paper.bend > cassette.bend * 10)
    }
    @Test func sourceUsesTextLinesAndBoundsLargeEditorsAndOtherDisplays() {
        let screen = CGRect(x: -1440, y: -200, width: 1440, height: 900), click = CGPoint(x: -700, y: 400)
        let lines = [CGRect(x: -800, y: 290, width: 160, height: 18), CGRect(x: -800, y: 312, width: 90, height: 18)]
        let small = CursorPickupGeometry.source(bounds: CGRect(x: -1400, y: 100, width: 1000, height: 600), regions: lines,
            click: click, screen: screen, desktopTop: 800)
        #expect(small == CGRect(x: -800, y: 470, width: 160, height: 40))
        let large = CursorPickupGeometry.source(bounds: CGRect(x: -1500, y: 0, width: 1600, height: 1200), regions: [],
            click: click, screen: screen, desktopTop: 800)
        #expect(large.width == 260 && large.height == 160 && large.contains(click))
        #expect(screen.contains(large))
        let invalid = CursorPickupGeometry.source(bounds: CGRect(x: CGFloat.infinity, y: 0, width: 20, height: 20), regions: [],
            click: click, screen: screen, desktopTop: 800)
        #expect(invalid.midX == click.x && invalid.midY == click.y)
    }
    @Test func transparentCursorMarginPreservesHotspotAndIncludesHangingObject() {
        for jaw in [CGPoint(x: -500, y: -300), CGPoint(x: 1200, y: 800)] {
            let frame = PointClampCursorGeometry.drawingFrame(at: jaw)
            #expect(frame.minX + PointClampCursorGeometry.drawingInset + PointClampCursorGeometry.hotspot.x == jaw.x)
            #expect(frame.minY + PointClampCursorGeometry.drawingInset + PointClampCursorGeometry.hotspot.y == jaw.y)
            #expect(frame.contains(CursorPickupGeometry.heldFrame(at: jaw).insetBy(dx: -5, dy: -5)))
        }
    }
}

@Suite(.serialized) @MainActor struct CursorPickupLifecycleTests {
    @Test func quickReleaseWaitsForOnePickupAndFollowsLatestPointer() async throws {
        let motion = CursorPickupMotion(); var completions = 0
        motion.onFinish = { completions += 1 }
        motion.start(source: CGRect(x: 10, y: 10, width: 120, height: 60), destination: CGPoint(x: 50, y: 40), material: .photo, animated: true)
        #expect(motion.active)
        motion.move(to: CGPoint(x: -500, y: -300))
        try await motion.finish()
        #expect(!motion.active && motion.progress == 1 && completions == 1)
        #expect(motion.sample.frame == CursorPickupGeometry.heldFrame(at: CGPoint(x: -500, y: -300)))
        try await motion.finish()
        #expect(completions == 1)
    }
    @Test func cancelAndRestartCannotCompleteAnOldPickup() async throws {
        let motion = CursorPickupMotion(); var completions = 0
        motion.onFinish = { completions += 1 }
        let source = CGRect(x: 0, y: 0, width: 80, height: 40)
        motion.start(source: source, destination: .zero, material: .note, animated: true)
        try await Task.sleep(nanoseconds: 30_000_000)
        motion.cancel()
        #expect(!motion.active)
        motion.start(source: source, destination: CGPoint(x: 100, y: 100), material: .folder, animated: true)
        try await motion.finish()
        #expect(completions == 1 && !motion.active)
        #expect(motion.destination == CGPoint(x: 100, y: 100))
    }
    @Test func reducedMotionHasNoFlightOrDelayedCompletion() async throws {
        let motion = CursorPickupMotion(); var frames = 0, completions = 0
        motion.onFrame = { frames += 1 }; motion.onFinish = { completions += 1 }
        motion.start(source: CGRect(x: 0, y: 0, width: 80, height: 40), destination: .zero, material: .document, animated: false)
        try await motion.finish()
        #expect(!motion.active && motion.progress == 1 && frames == 0 && completions == 1)
    }
}

@Suite(.serialized) @MainActor struct CursorPickupRenderingTests {
    @Test func flyingMaterialAndCarriedMaterialHaveTheSamePixelsAtHandoff() async throws {
        _ = NSApplication.shared
        let size = CGSize(width: 200, height: 160), jaw = CGPoint(x: 80, y: 100)
        let panel = CGRect(origin: .zero, size: size), pose = CursorClipPose()
        pose.gripping = true; pose.hasMaterial = true; pose.motionEnabled = false
        pose.material = .note; pose.text = "夹住内容"; pose.openness = pose.material.jawOpening
        let sample = CursorPickupGeometry.sample(progress: 1, source: CGRect(x: 10, y: 10, width: 100, height: 60), jaw: jaw, material: .note)
        func render<V: View>(_ view: V) async throws -> NSBitmapImageRep {
            let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color.white))
            host.frame = panel
            let window = NSWindow(contentRect: panel, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = host; window.setFrameOrigin(CGPoint(x: -16000, y: -16000)); window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            try await Task.sleep(nanoseconds: 80_000_000); host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: panel)); host.cacheDisplay(in: panel, to: bitmap)
            return bitmap
        }
        let flying = try await render(CursorPickupArtwork(sample: sample, source: panel, panel: panel, pose: pose))
        let carried = try await render(ZStack(alignment: .topLeading) {
            Color.clear
            CursorClipView(pose: pose).position(x: jaw.x + 27, y: panel.height - jaw.y)
        })
        let scale = CGFloat(flying.pixelsWide) / size.width
        var differences: Double = 0, pixels = 0, paperPixels = 0
        // Below the jaw: compare the hanging surface without the foreground metal sprite.
        for y in Int(74 * scale)..<Int(84 * scale) {
            for x in Int(69 * scale)..<Int(87 * scale) {
                let a = try #require(flying.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                let b = try #require(carried.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                differences += Double(abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent)) / 3
                if a.blueComponent < 0.95 { paperPixels += 1 }
                pixels += 1
            }
        }
        #expect(paperPixels > 30)
        #expect(differences / Double(pixels) < 0.025)
    }
}
