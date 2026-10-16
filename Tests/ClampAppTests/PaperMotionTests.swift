import Foundation
import SwiftUI
import Testing
@testable import ClampEverything

struct PaperMotionTests {
    @Test func largePointerJumpsStayBounded() {
        let forward = PaperPull.following(NSPoint(x: 10000, y: -10000))
        let backward = PaperPull.following(NSPoint(x: -10000, y: 10000))
        #expect(forward == PaperPull(x: 1, y: 1))
        #expect(backward == PaperPull(x: -1, y: -1))
        #expect(PaperPull.following(.zero) == .resting)
    }
    @Test func grippingCornerStaysAttachedDuringBending() {
        let size = CGSize(width: 300, height: 400)
        for left in [true, false] {
            let grip = CGPoint(x: left ? 12 : size.width - 12, y: 12)
            for pull in [PaperPull(x: 1, y: -1), PaperPull(x: -1, y: 1), .resting] {
                let t = PaperFlexEffect(pull: pull, isLeft: left).effectValue(size: size)
                let w = t.m13 * grip.x + t.m23 * grip.y + t.m33
                let x = (t.m11 * grip.x + t.m21 * grip.y + t.m31) / w
                let y = (t.m12 * grip.x + t.m22 * grip.y + t.m32) / w
                #expect(abs(x - grip.x) < 0.001)
                #expect(abs(y - grip.y) < 0.001)
            }
        }
    }
    @Test func restingPaperHasNoPerspectiveDrift() {
        let t = PaperFlexEffect(pull: .resting, isLeft: false).effectValue(size: CGSize(width: 300, height: 400))
        #expect(t.m11 == 1 && t.m22 == 1 && t.m33 == 1)
        #expect(t.m12 == 0 && t.m21 == 0 && t.m31 == 0 && t.m32 == 0)
    }
    @Test func textureAndSilhouetteKeepTheClampedCornerFixed() {
        let size = CGSize(width: 320, height: 430)
        for left in [true, false] {
            let grip = CGPoint(x: left ? 12 : size.width - 12, y: 12)
            let freeCorner = CGPoint(x: left ? size.width : 0, y: size.height)
            let pull = PaperPull(x: 0.85, y: -0.8)
            #expect(SoftSheetGeometry.point(grip, size: size, pull: pull, isLeft: left) == grip)
            let free = SoftSheetGeometry.point(freeCorner, size: size, pull: pull, isLeft: left)
            #expect(free.y < freeCorner.y - 8)
            #expect(left ? free.x < freeCorner.x : free.x > freeCorner.x)
            #expect(SoftSheetGeometry.point(freeCorner, size: size, pull: .resting, isLeft: left) == freeCorner)
        }
    }
    @Test func foldIsBoundedAndOpeningDoesNotCutTheClampedCorner() {
        let size = CGSize(width: 320, height: 430)
        #expect(SoftSheetGeometry.foldLength(amount: -5, size: size) == 0)
        #expect(SoftSheetGeometry.foldLength(amount: 5, size: size) == 76)
        for left in [true, false] {
            let mask = SoftSheetMask(fold: 1, isLeft: left).path(in: CGRect(origin: .zero, size: size))
            #expect(mask.contains(CGPoint(x: left ? 12 : 308, y: 12)))
            #expect(!mask.contains(CGPoint(x: left ? 318 : 2, y: 428)))
            #expect(mask.contains(CGPoint(x: 160, y: 215)))
        }
    }
    @Test func hoverMotionDoesNotJumpOnEntryAndRemainsSubtle() {
        let size = CGSize(width: 320, height: 430)
        let pointer = CGPoint(x: 5, y: 420)
        #expect(SoftSheetGeometry.hover(at: pointer, previous: nil, size: size, isLeft: false) == .resting)
        let pull = SoftSheetGeometry.hover(at: pointer, previous: CGPoint(x: 5000, y: -5000), size: size, isLeft: false)
        #expect(abs(pull.x) <= 0.18 && abs(pull.y) <= 0.18)
    }
    @Test func hingeMirrorsItsSwingAndCarriesTheClipIntoTheScreen() {
        for progress in [CGFloat(0), 0.25, 0.5, 0.75, 1, 1.02] {
            let left = HingeReveal.translation(progress: progress, isLeft: true)
            let right = HingeReveal.translation(progress: progress, isLeft: false)
            #expect(left.width == -right.width && left.height == right.height)
            #expect(HingeReveal.angle(progress: progress, isLeft: true) == -HingeReveal.angle(progress: progress, isLeft: false))
        }
        #expect(HingeReveal.translation(progress: 0, isLeft: false).width == 0)
        #expect(HingeReveal.translation(progress: 1, isLeft: false).width == 0)
        #expect(abs(HingeReveal.translation(progress: 1, isLeft: false).height) < 0.001)
        #expect(abs(HingeReveal.angle(progress: 5, isLeft: false)) < .pi / 60)
        #expect(ClipOrientation.scale(isLeft: true) == 1)
        #expect(ClipOrientation.scale(isLeft: false) == 1)
    }
    @Test func sheetPivotRemainsInsideBothMovingJawsThroughoutReveal() {
        for size in [CGSize(width: 320, height: 430), CGSize(width: 460, height: 264)] {
            for left in [true, false] {
                let pin = HingeReveal.suspension(size: size, isLeft: left)
                for p in [CGFloat(0), 0.25, 0.5, 0.75, 1, 1.02] {
                    let sheet = HingeSheetEffect(progress: p, isLeft: left).effectValue(size: size)
                    let jaw = HingeAssemblyEffect(progress: p, isLeft: left).effectValue(size: size)
                    let x = sheet.m11 * pin.x + sheet.m21 * pin.y + sheet.m31 + jaw.m31
                    let y = sheet.m12 * pin.x + sheet.m22 * pin.y + sheet.m32 + jaw.m32
                    #expect(abs(x - (pin.x + jaw.m31)) < 0.001)
                    #expect(abs(y - (pin.y + jaw.m32)) < 0.001)
                }
                let rest = HingeSheetEffect(progress: 1, isLeft: left).effectValue(size: size)
                #expect(rest.m11 == 1 && rest.m22 == 1 && rest.m31 == 0 && rest.m32 == 0)
                let freeCorner = CGPoint(x: left ? size.width : 0, y: size.height)
                let closed = HingeSheetEffect(progress: 0, isLeft: left).effectValue(size: size)
                let freeX = closed.m11 * freeCorner.x + closed.m21 * freeCorner.y + closed.m31
                #expect(left ? freeX < 0 : freeX > size.width)
            }
        }
    }
    @Test func animationSpaceIncludesTheSwingingBottomCorner() {
        for size in [CGSize(width: 320, height: 430), CGSize(width: 460, height: 264)] {
            for left in [true, false] {
                let height = HingeReveal.swingHeight(size: size, isLeft: left)
                for step in 0...100 {
                    let p = CGFloat(step) / 100
                    let t = HingeSheetEffect(progress: p, isLeft: left).effectValue(size: size)
                    let movement = HingeReveal.translation(progress: p, isLeft: left)
                    for x in [CGFloat(0), size.width] {
                        for y in [CGFloat(0), size.height] {
                            let rotatedY = t.m12 * x + t.m22 * y + t.m32 + movement.height
                            #expect(rotatedY <= height)
                        }
                    }
                }
            }
        }
    }
}
