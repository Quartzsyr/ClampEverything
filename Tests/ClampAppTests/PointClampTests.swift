import AppKit
import Testing
@testable import ClampEverything

@MainActor struct PointClampTests {
    @Test func cursorJawMatchesClickAcrossScreenCoordinates() {
        for point in [CGPoint(x: 400, y: 300), CGPoint(x: -1200, y: 800), CGPoint(x: 1800, y: -200)] {
            let frame = PointClampCursorGeometry.frame(at: point)
            #expect(frame.size == NSSize(width: 64, height: 46))
            #expect(frame.minX + PointClampCursorGeometry.hotspot.x == point.x)
            #expect(frame.minY + PointClampCursorGeometry.hotspot.y == point.y)
            // The left-facing mouth sits five points inside the left panel edge.
            #expect(point.x - frame.minX == 5)
        }
    }

    @Test func eventCoordinatesConvertWithoutClampingOtherDisplays() throws {
        let top = try #require(NSScreen.screens.first?.frame.maxY)
        let point = CGPoint(x: -500, y: top + 200)
        #expect(PointClampController.cocoaPoint(point) == CGPoint(x: -500, y: -200))
    }
}

@MainActor struct DockGeometryTests {
    let frame = CGRect(x: -1440, y: 30, width: 1440, height: 860)

    @Test func snapUsesDisplayEdges() {
        #expect(DockGeometry.side(at: CGPoint(x: -1430, y: 300), in: frame) == .left)
        #expect(DockGeometry.side(at: CGPoint(x: -10, y: 300), in: frame) == .right)
        #expect(DockGeometry.side(at: CGPoint(x: -700, y: 300), in: frame) == nil)
    }

    @Test func heightRoundTripsAndStaysVisible() {
        for y: CGFloat in [52, 200, 470, 868] {
            let stored = DockGeometry.height(at: y, in: frame)
            #expect(abs(DockGeometry.originY(height: stored, index: 0, in: frame) + 22 - y) < 0.001)
        }
        #expect(DockGeometry.height(at: -1000, in: frame) == 0)
        #expect(DockGeometry.height(at: 2000, in: frame) == 1)
    }

    @Test func crowdedClipsDoNotOverlapOrLeaveScreen() {
        for heights: [Double?] in [[0, 0, 0], [1, 1, 1], [nil, 0.9, 0.9, nil]] {
            let origins = DockGeometry.origins(heights: heights, in: frame).sorted()
            #expect(origins.first! >= frame.minY)
            #expect(origins.last! + 44 <= frame.maxY)
            for pair in zip(origins, origins.dropFirst()) { #expect(pair.1 - pair.0 >= 52) }
        }
    }
}

@MainActor struct CustomBehaviorTests {
    @Test func configuredSnapDistanceChangesEdgeDetection() {
        let frame = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let point = CGPoint(x: 65, y: 400)
        #expect(DockGeometry.side(at: point, in: frame, distance: 42) == nil)
        #expect(DockGeometry.side(at: point, in: frame, distance: 80) == .left)
    }
    @Test func newItemsUseConfiguredDefaultSide() throws {
        let root = URL(fileURLWithPath: "/private/tmp/ClampDefaults-" + UUID().uuidString)
        let store = ClipStore(root: root)
        defer { try? FileManager.default.removeItem(at: root) }
        store.state.preferences.defaultSide = .left
        store.addTextOrLink("new note")
        #expect(store.active.first?.placement.side == .left)
    }
}

@MainActor struct CursorVisibilityTests {
    @Test func hidingIsAcquiredOnceAndBalancedAcrossRepeatedExits() {
        var hides = 0, shows = 0
        let lease = CursorVisibilityLease(hide: { hides += 1; return true }, show: { shows += 1 })
        #expect(lease.acquire())
        #expect(lease.acquire())
        #expect(hides == 1)
        lease.release(); lease.release()
        #expect(shows == 1)
        #expect(!lease.acquired)
        #expect(lease.acquire())
        lease.release()
        #expect(hides == 2 && shows == 2)
    }
    @Test func failedHidingDoesNotOwnAnUnhideCallAndCanRetry() {
        var attempt = 0, shows = 0
        let lease = CursorVisibilityLease(hide: { attempt += 1; return attempt > 1 }, show: { shows += 1 })
        #expect(!lease.acquire())
        lease.release()
        #expect(shows == 0)
        #expect(lease.acquire())
        lease.release()
        #expect(shows == 1)
    }
}

@MainActor struct ImageGenCursorTests {
    @Test func atlasHasThreeTransparentPosesWithOneScale() throws {
        let poses = CursorAtlas.poses
        #expect(poses.count == 3)
        for pose in poses {
            #expect(pose.size.width > 30 && pose.size.width <= 54)
            #expect(pose.size.height > 10 && pose.size.height <= 36)
            let image = try #require(pose.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            #expect(image.alphaInfo != .none)
        }
        #expect(PointClampCursorGeometry.hotspot.x == 5)
    }
    @Test func poseSelectionFollowsJawOpennessWithoutOverlappingImages() {
        #expect(CursorAtlas.poseIndex(1) == 0)
        #expect(CursorAtlas.poseIndex(0.5) == 1)
        #expect(CursorAtlas.poseIndex(0) == 2)
        for amount in stride(from: -0.1, through: 1.1, by: 0.01) {
            #expect((0...2).contains(CursorAtlas.poseIndex(amount)))
        }
    }
}
