import SwiftUI
import ClampCore

/// Folder mouth flexes slightly as the whole housing flips around its jaw.
enum PocketGeometry {
    static func amount(_ p: CGFloat) -> CGFloat { max(0, min(1, p)) }
    static func mouthGap(_ p: CGFloat) -> CGFloat { 2 + amount(p) * 5 }
    static func sheetOffset(_ p: CGFloat) -> CGFloat { (1 - amount(p)) * 12 }
}
struct PocketFront: Shape {
    var opening: CGFloat
    var animatableData: CGFloat { get { opening } set { opening = newValue } }
    func path(in rect: CGRect) -> Path {
        let top = min(41, rect.height * 0.34), radius: CGFloat = min(8, rect.width * 0.08)
        var path = Path()
        path.move(to: CGPoint(x: 0, y: top + radius))
        path.addQuadCurve(to: CGPoint(x: radius, y: top), control: CGPoint(x: 0, y: top))
        path.addQuadCurve(to: CGPoint(x: rect.width - radius, y: top), control: CGPoint(x: rect.midX, y: top + PocketGeometry.mouthGap(opening)))
        path.addQuadCurve(to: CGPoint(x: rect.width, y: top + radius), control: CGPoint(x: rect.width, y: top))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height - radius))
        path.addQuadCurve(to: CGPoint(x: rect.width - radius, y: rect.height), control: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: radius, y: rect.height))
        path.addQuadCurve(to: CGPoint(x: 0, y: rect.height - radius), control: CGPoint(x: 0, y: rect.height))
        path.closeSubpath(); return path
    }
}
struct GripContact: View {
    var material: PhysicalMaterial
    var isLeft: Bool
    var body: some View {
        Ellipse().fill(.black.opacity(0.13 + material.jawOpening * 0.2))
            .frame(width: 18, height: 5 + material.jawOpening * 8).blur(radius: 2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isLeft ? .topLeading : .topTrailing)
            .padding(.top, 18).padding(isLeft ? .leading : .trailing, isLeft ? 28 : 4)
            .allowsHitTesting(false)
    }
}
struct RigidGripEffect: GeometryEffect {
    var pull: PaperPull
    var isLeft: Bool
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(pull.x, pull.y) }
        set { pull = PaperPull(x: newValue.first, y: newValue.second) }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let pin = HingeReveal.grip(size: size, isLeft: isLeft)
        return ProjectionTransform(CGAffineTransform(translationX: pin.x, y: pin.y)
            .rotated(by: pull.x * 0.024)
            .translatedBy(x: -pin.x, y: -pin.y))
    }
}
struct PinnedFlexibleGripEffect: GeometryEffect {
    var pull: PaperPull
    var isLeft: Bool
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(pull.x, pull.y) }
        set { pull = PaperPull(x: newValue.first, y: newValue.second) }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let pin = HingeReveal.grip(size: size, isLeft: isLeft)
        let shear = CGAffineTransform(a: 1, b: pull.x * 0.01, c: pull.x * 0.012, d: 1 - abs(pull.y) * 0.012, tx: 0, ty: 0)
        let transform = CGAffineTransform(translationX: pin.x, y: pin.y)
        return ProjectionTransform(shear.concatenating(transform).translatedBy(x: -pin.x, y: -pin.y))
    }
}
/// Both axes react to dragging, but every transform leaves the jaw fixed.
struct MaterialDragEffect: GeometryEffect {
    var material: PhysicalMaterial
    var pull: PaperPull
    var isLeft: Bool
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(pull.x, pull.y) }
        set { pull = PaperPull(x: newValue.first, y: newValue.second) }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let x = max(-1.5, min(1.5, pull.x)), y = max(-1.5, min(1.5, pull.y))
        let pin = HingeReveal.grip(size: size, isLeft: isLeft)
        let flex = CGFloat(material.flexibility)
        let angle = (x + y * (isLeft ? -0.3 : 0.3)) * CGFloat(material.dragSwing)
        let rotation = CGAffineTransform(rotationAngle: angle)
        let strain = CGAffineTransform(a: 1, b: 0, c: x * flex * 0.018,
                                      d: 1 + y * flex * 0.018, tx: 0, ty: 0)
        var transform = strain.concatenating(rotation)
        transform.tx = pin.x - transform.a * pin.x - transform.c * pin.y
        transform.ty = pin.y - transform.b * pin.x - transform.d * pin.y
        return ProjectionTransform(transform)
    }
}
struct MaterialMovement: ViewModifier {
    var material: PhysicalMaterial
    var pull: PaperPull
    var isLeft: Bool
    var disabled: Bool
    var tracking = false
    func body(content: Content) -> some View {
        content.modifier(MaterialDragEffect(material: material, pull: disabled ? .resting : pull, isLeft: isLeft))
            .animation(disabled || tracking ? nil : .spring(response: material.springResponse,
                                               dampingFraction: material.isPocket ? 0.62 : 0.68), value: pull)
    }
}
