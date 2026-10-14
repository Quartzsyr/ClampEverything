import SwiftUI
import ClampCore

/// Bounded deformation keeps the gripped corner fixed and text easy to read.
struct PaperPull: Equatable {
    var x: CGFloat = 0
    var y: CGFloat = 0
    static let resting = PaperPull()
    static func following(_ delta: NSPoint) -> PaperPull {
        PaperPull(x: max(-1, min(1, delta.x / 24)), y: max(-1, min(1, -delta.y / 24)))
    }
}

enum ClipOrientation {
    // The source asset already has its wire tail on the left.
    // Keep that direction for both screen edges and the receiver.
    static func scale(isLeft: Bool) -> CGFloat { 1 }
    static func inset(isLeft: Bool) -> CGFloat { isLeft ? 0 : 10 }
}

enum HingeReveal {
    static let duration: TimeInterval = 0.52
    static let settleDuration: TimeInterval = 0.8
    static let closeDuration: TimeInterval = 0.28
    // Allow a small spring overshoot, so the free edge can settle past vertical.
    static func bounded(_ progress: CGFloat) -> CGFloat { max(0, min(1.025, progress)) }
    static func angle(progress: CGFloat, isLeft: Bool) -> CGFloat {
        (1 - bounded(progress)) * .pi * 105 / 180 * (isLeft ? 1 : -1)
    }
    static func translation(progress: CGFloat, isLeft: Bool) -> CGSize {
        let p = bounded(progress)
        return CGSize(width: (1 - p) * 10 * (isLeft ? -1 : 1),
                      height: -sin(min(1, p) * .pi) * 3)
    }
    static func grip(size: CGSize, isLeft: Bool) -> CGPoint {
        // Centre of the right-facing jaw, including the card's outer padding.
        CGPoint(x: isLeft ? 44 : size.width - 26, y: 30)
    }
    static func swingHeight(size: CGSize, isLeft: Bool) -> CGFloat {
        let pin = grip(size: size, isLeft: isLeft)
        let reach = isLeft ? size.width - pin.x : pin.x
        return max(size.height, pin.y + hypot(reach, size.height - pin.y) + 12)
    }
}

/// Rotation takes place at the jaw, rather than at the centre of the card.
/// The common translation is applied outside this effect to move both jaws too.
struct HingeSheetEffect: GeometryEffect {
    var progress: CGFloat
    var isLeft: Bool
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let pin = HingeReveal.grip(size: size, isLeft: isLeft)
        let transform = CGAffineTransform(translationX: pin.x, y: pin.y)
            .rotated(by: HingeReveal.angle(progress: progress, isLeft: isLeft))
            .translatedBy(x: -pin.x, y: -pin.y)
        return ProjectionTransform(transform)
    }
}

struct HingeAssemblyEffect: GeometryEffect {
    var progress: CGFloat
    var isLeft: Bool
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let movement = HingeReveal.translation(progress: progress, isLeft: isLeft)
        return ProjectionTransform(CGAffineTransform(translationX: movement.width, y: movement.height))
    }
}

struct PaperFlexEffect: GeometryEffect {
    var pull: PaperPull
    var isLeft: Bool
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(pull.x, pull.y) }
        set { pull = PaperPull(x: newValue.first, y: newValue.second) }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let anchor = CGPoint(x: isLeft ? 12 : size.width - 12, y: 12)
        // A shallow shear and compression are stable in both AppKit hit testing
        // and native snapshots. The irregular edge supplies the local bending.
        var transform = CGAffineTransform(translationX: anchor.x, y: anchor.y)
        transform = transform.rotated(by: pull.x * 0.038)
        let shear = CGAffineTransform(a: 1, b: 0, c: pull.x * 0.016, d: 1, tx: 0, ty: 0)
        transform = shear.concatenating(transform)
        transform = transform.scaledBy(x: 1 - abs(pull.x) * 0.008, y: 1 - abs(pull.y) * 0.018)
        transform = transform.translatedBy(x: -anchor.x, y: -anchor.y)
        return ProjectionTransform(transform)
    }
}

struct PaperMovement: ViewModifier {
    var pull: PaperPull
    var isLeft: Bool
    var enabled = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content
            .modifier(PaperFlexEffect(pull: enabled && !reduceMotion ? pull : .resting, isLeft: isLeft))
            .animation(reduceMotion ? nil : .spring(response: 0.58, dampingFraction: 0.53), value: pull)
    }
}

/// Dock positions are stored independently from expanded paper dimensions.
enum DockGeometry {
    static func side(at point: CGPoint, in frame: CGRect, distance: CGFloat = 42) -> ClampCore.ClipSide? {
        if point.x - frame.minX < distance { return .left }
        if frame.maxX - point.x < distance { return .right }
        return nil
    }
    static func height(at y: CGFloat, in frame: CGRect) -> Double {
        Double(max(0, min(1, (y - 22 - frame.minY) / max(1, frame.height - 44))))
    }
    static func origins(heights: [Double?], in frame: CGRect) -> [CGFloat] {
        guard !heights.isEmpty else { return [] }
        let desired = heights.enumerated().map { originY(height: $0.element, index: $0.offset, in: frame) }
        let order = desired.indices.sorted { desired[$0] == desired[$1] ? $0 < $1 : desired[$0] < desired[$1] }
        let gap = min(52, max(0, frame.height - 44) / CGFloat(max(1, heights.count - 1)))
        var result = desired
        var floor = frame.minY
        for index in order { result[index] = max(floor, desired[index]); floor = result[index] + gap }
        var ceiling = frame.maxY - 44
        for index in order.reversed() { result[index] = min(ceiling, result[index]); ceiling = result[index] - gap }
        return result
    }
    static func originY(height: Double?, index: Int, in frame: CGRect) -> CGFloat {
        guard let height, height.isFinite else { return max(frame.minY, frame.maxY - 108 - CGFloat(index) * 52) }
        return frame.minY + CGFloat(max(0, min(1, height))) * max(0, frame.height - 44)
    }
}

/// Velocity uses elapsed time, so a 120 Hz mouse and a 60 Hz mouse feel alike.
struct DragMotionSampler {
    private var lastTime: TimeInterval = 0
    private var lastDelta = CGPoint.zero
    private(set) var pull = PaperPull.resting
    mutating func reset(at time: TimeInterval) {
        lastTime = time; lastDelta = .zero; pull = .resting
    }
    mutating func sample(delta: CGPoint, at time: TimeInterval, inertia: Double) -> PaperPull? {
        let elapsed = time - lastTime
        guard elapsed >= 1.0 / 60 else { return nil }
        let duration = max(1.0 / 240, elapsed)
        let target = PaperPull(x: max(-1, min(1, (delta.x - lastDelta.x) / duration / 900)),
                               y: max(-1, min(1, -(delta.y - lastDelta.y) / duration / 900)))
        let blend = CGFloat(1 - exp(-elapsed / (0.025 + inertia * 0.04)))
        pull = PaperPull(x: pull.x + (target.x - pull.x) * blend, y: pull.y + (target.y - pull.y) * blend)
        lastDelta = delta; lastTime = time
        return pull
    }
}
