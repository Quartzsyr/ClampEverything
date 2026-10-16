import AppKit
import SwiftUI
import Testing
import ClampCore
@testable import ClampEverything

struct ClipAssemblyGeometryTests {
    private func project(_ point: CGPoint, through t: ProjectionTransform) -> CGPoint {
        CGPoint(x: t.m11 * point.x + t.m21 * point.y + t.m31,
                y: t.m12 * point.x + t.m22 * point.y + t.m32)
    }
    @Test func raisedLoopStaysOnItsNailThroughoutMirroredReveal() {
        for left in [false, true] {
            let size = CGSize(width: 320, height: 420)
            let hook = HingeReveal.suspension(size: size, isLeft: left)
            for p: CGFloat in [0, 0.25, 0.5, 0.75, 1, 1.02] {
                let scale = SuspendedClipScale(scale: ClipOrientation.displayScale).effectValue(size: ClipOrientation.size)
                let local = project(ClipOrientation.hook, through: scale)
                #expect(abs(local.x - ClipOrientation.hook.x) < 0.001)
                #expect(abs(local.y - ClipOrientation.hook.y) < 0.001)
                let root = CGPoint(x: local.x + (left ? 22 : size.width - 66), y: local.y + ClipOrientation.top)
                let result = project(root, through: HingeSheetEffect(progress: p, isLeft: left).effectValue(size: size))
                #expect(abs(result.x - hook.x) < 0.001)
                #expect(abs(result.y - hook.y) < 0.001)
                let jaw = project(ClipOrientation.jaw, through: scale)
                let contact = HingeReveal.grip(size: size, isLeft: left)
                #expect(abs(jaw.y + ClipOrientation.top - contact.y) < 0.001)
                #expect(HingeReveal.translation(progress: p, isLeft: left) == .zero)
            }
        }
    }
    @Test func clipKeepsItsSmallPhysicalSizeAtEveryRevealAngle() {
        for left in [true, false] {
            let size = CGSize(width: 320, height: 420)
            let scale = SuspendedClipScale(scale: ClipOrientation.displayScale).effectValue(size: ClipOrientation.size)
            let a = project(ClipOrientation.hook, through: scale)
            let b = project(ClipOrientation.jaw, through: scale)
            for p: CGFloat in [0, 0.25, 0.5, 0.75, 1] {
                let rotation = HingeSheetEffect(progress: p, isLeft: left).effectValue(size: size)
                let hook = project(a, through: rotation), jaw = project(b, through: rotation)
                #expect(abs(hypot(jaw.x - hook.x, jaw.y - hook.y) - 23) < 0.001)
            }
        }
    }
    @Test func jawBitesInsideEveryHousingInsteadOfHangingAboveItsEdge() {
        for housing in [ContentHousing.folder, .collection, .file, .note, .link, .photo] {
            for height: CGFloat in [120, 180, 300, 620] {
                let top = ClipOrientation.materialTop(housing: housing, height: height)
                let bodySize = CGSize(width: 296, height: height - top - 9)
                let edge = housing == .folder || housing == .collection ? min(24, bodySize.height * 0.18) : 0
                #expect(abs(ClipOrientation.contactY - top - edge - ClipOrientation.insertion) < 0.001)
                if housing == .folder || housing == .collection {
                    let path = FolderSilhouette().path(in: CGRect(origin: .zero, size: bodySize))
                    for x: CGFloat in [21, 29, 37, 259, 267, 275] {
                        #expect(path.contains(CGPoint(x: x, y: ClipOrientation.contactY - top)))
                    }
                }
            }
        }
    }
    @Test func largerCompactMaterialRemainsInsideBothDockPanels() {
        let size = DockGeometry.compactSize
        for left in [true, false] {
            let pin = HingeReveal.suspension(size: size, isLeft: left)
            let rotation = HingeSheetEffect(progress: 0, isLeft: left).effectValue(size: size)
            for folder in [true, false] {
                let top = ClipOrientation.paperTop - (folder ? DockGeometry.thumbnailSize.height * 0.18 : 0)
                for x in [pin.x - DockGeometry.thumbnailSize.width / 2, pin.x + DockGeometry.thumbnailSize.width / 2] {
                    for y in [top, top + DockGeometry.thumbnailSize.height] {
                        let result = project(CGPoint(x: x, y: y), through: rotation)
                        #expect((0...size.width).contains(result.x))
                        #expect((0...size.height).contains(result.y))
                    }
                }
            }
        }
    }
    @Test func compactAndWideMetalShareTheSameFoldedPose() {
        for left in [false, true] {
            let wide = CGSize(width: 320, height: 420), compact = DockGeometry.compactSize
            let scale = SuspendedClipScale(scale: ClipOrientation.displayScale).effectValue(size: ClipOrientation.size)
            for local in [ClipOrientation.hook, ClipOrientation.jaw, CGPoint(x: 2, y: 58), CGPoint(x: 42, y: 58)] {
                let a = project(local, through: scale)
                func point(_ size: CGSize) -> CGPoint {
                    project(CGPoint(x: a.x + (left ? 22 : size.width - 66), y: a.y + ClipOrientation.top), through: HingeSheetEffect(progress: 0, isLeft: left).effectValue(size: size))
                }
                let w = point(wide), c = point(compact)
                #expect(abs(w.x - (left ? 0 : wide.width - compact.width) - c.x) < 0.001)
                #expect(abs(w.y - c.y) < 0.001)
                #expect((0...64).contains(c.x))
                #expect((0...DockGeometry.compactSize.height).contains(c.y))
            }
            #expect(ClipOrientation.hook.y < ClipOrientation.jaw.y)
            #expect(HingeReveal.grip(size: wide, isLeft: left).y > ClipOrientation.paperTop)
        }
    }
}

@Suite(.serialized) @MainActor struct ClipAssemblyPanelTests {
    @Test func expansionAndPickupPreserveTheSuspensionHeight() throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: "/private/tmp/ClampAssemblyRegression-" + UUID().uuidString)
        let store = ClipStore(root: root); store.hidden = true
        store.addTextOrLink("joint test")
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        let id = try #require(store.active.first?.id)
        for side in [ClipSide.left, .right] {
            store.update(id) { $0.placement.side = side; $0.placement.dockHeight = 0.5 }
            let card = manager.model(id)
            manager.dock(id)
            let before = card.panel.frame.maxY - ClipOrientation.compactHookY
            card.present(animated: false)
            #expect(abs(card.panel.frame.maxY - HingeReveal.suspension(size: card.sheetSize, isLeft: side == .left).y - before) < 0.001)
            manager.dock(id)
            let pickup = card.panel.frame.maxY - ClipOrientation.compactHookY
            card.beginMove()
            #expect(abs(card.panel.frame.maxY - HingeReveal.suspension(size: card.sheetSize, isLeft: side == .left).y - pickup) < 0.001)
            card.moving = false; card.busy = false
        }
    }
    @Test func silverAtlasHasThreeAlignedPosesAndTransparentLoop() throws {
        let poses = HangingClipAtlas.poses
        #expect(poses.count == 3)
        for pose in poses {
            #expect(pose.size.width > 30 && pose.size.width <= 40)
            #expect(pose.size.height > 48 && pose.size.height <= 52)
            #expect(abs(pose.offset.width + pose.size.width / 2 - ClipOrientation.hook.x) < 0.001)
            #expect(abs(pose.offset.height + pose.size.height * 0.055 - ClipOrientation.hook.y) < 0.001)
            let cg = try #require(pose.image.cgImage(forProposedRect: nil, context: nil, hints: nil))
            #expect(cg.alphaInfo != .none)
        }
    }
}
