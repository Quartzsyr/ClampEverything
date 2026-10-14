import SwiftUI
import Testing
import ClampCore
@testable import ClampEverything

struct PhysicalMaterialTests {
    @Test func fileTypesHaveDistinctPhysicalForms() {
        for (suffix, material) in [("PDF", PhysicalMaterial.document), ("m4a", .audio), ("mov", .film), ("zip", .archive), ("bin", .file)] {
            let item = ClipItem(kind: .file, title: "sample." + suffix)
            #expect(PhysicalMaterial.forItem(item) == material)
        }
        #expect(PhysicalMaterial.forItem(ClipItem(kind: .folder, title: "Folder")) == .folder)
        #expect(PhysicalMaterial.forItem(ClipItem(kind: .text, title: "note")) == .note)
        #expect(PhysicalMaterial.forItem(nil) == .collection)
    }
    @Test func materialThicknessAndWeightAreOrdered() {
        #expect(PhysicalMaterial.note.jawOpening < PhysicalMaterial.photo.jawOpening)
        #expect(PhysicalMaterial.photo.jawOpening < PhysicalMaterial.folder.jawOpening)
        #expect(PhysicalMaterial.note.inertia < PhysicalMaterial.folder.inertia)
        #expect(PhysicalMaterial.folder.inertia < PhysicalMaterial.collection.inertia)
        #expect(PhysicalMaterial.note.flexibility > PhysicalMaterial.photo.flexibility)
        for material in PhysicalMaterial.allCases {
            #expect((0...1).contains(material.jawOpening))
            #expect((0...1).contains(material.inertia))
        }
    }
    @Test func rigidAndFlexibleMaterialsKeepActualJawFixed() {
        let size = CGSize(width: 320, height: 420)
        for left in [true, false] {
            let jaw = HingeReveal.grip(size: size, isLeft: left)
            for pull in [PaperPull(x: 1, y: -1), .resting, PaperPull(x: -1, y: 1)] {
                let transforms = [RigidGripEffect(pull: pull, isLeft: left).effectValue(size: size), PinnedFlexibleGripEffect(pull: pull, isLeft: left).effectValue(size: size)]
                for t in transforms {
                    let affine = CGAffineTransform(a: t.m11, b: t.m12, c: t.m21, d: t.m22, tx: t.m31, ty: t.m32)
                    let result = jaw.applying(affine)
                    #expect(abs(result.x - jaw.x) < 0.001)
                    #expect(abs(result.y - jaw.y) < 0.001)
                }
            }
        }
    }
    @Test func everyMaterialRespondsToBothDragAxesAndKeepsJawPinned() {
        let size = CGSize(width: 320, height: 420)
        for material in PhysicalMaterial.allCases {
            for left in [true, false] {
                let pin = HingeReveal.grip(size: size, isLeft: left)
                for pull in [PaperPull(x: 1, y: 0), PaperPull(x: 0, y: 1), PaperPull(x: -1, y: -1)] {
                    let t = MaterialDragEffect(material: material, pull: pull, isLeft: left).effectValue(size: size)
                    let affine = CGAffineTransform(a: t.m11, b: t.m12, c: t.m21, d: t.m22, tx: t.m31, ty: t.m32)
                    let fixed = pin.applying(affine)
                    #expect(abs(fixed.x - pin.x) < 0.001 && abs(fixed.y - pin.y) < 0.001)
                    let corner = CGPoint(x: left ? size.width : 0, y: size.height)
                    let displaced = corner.applying(affine)
                    #expect(hypot(displaced.x - corner.x, displaced.y - corner.y) > 2)
                    #expect(hypot(displaced.x - corner.x, displaced.y - corner.y) < 70)
                }
                let rest = MaterialDragEffect(material: material, pull: .resting, isLeft: left).effectValue(size: size)
                #expect(rest.isIdentity)
            }
        }
    }
    @Test func pocketOpensWithoutLargeCoverProjection() {
        #expect(PocketGeometry.sheetOffset(1) == 0)
        #expect(PocketGeometry.sheetOffset(0) == 12)
        for value: CGFloat in [-5, 0, 0.5, 1, 5] {
            #expect((2...7).contains(PocketGeometry.mouthGap(value)))
            #expect((0...12).contains(PocketGeometry.sheetOffset(value)))
        }
    }
}
