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
    static func scale(isLeft: Bool) -> CGFloat { 1 }
    static func inset(isLeft: Bool) -> CGFloat { isLeft ? 0 : 22 }
    static let size = CGSize(width: 44, height: 60)
    static let hook = CGPoint(x: 22, y: 8)
    static let jaw = CGPoint(x: 22, y: 54)
    static let top: CGFloat = 18
    static let compactHookY: CGFloat = top + hook.y
    static let displayScale: CGFloat = 0.5
    static let edgeAnchor: CGFloat = 44
    static let contactY = compactHookY + (jaw.y - hook.y) * displayScale
    static let insertion: CGFloat = 5
    static let paperTop: CGFloat = contactY - insertion
    static let verticalMargins: CGFloat = paperTop + 9

    /// Folder shoulders are below the tab. Align the jaw with that actual edge,
    /// including when a short window reduces the silhouette's tab height.
    static func materialTop(housing: ContentHousing, height: CGFloat) -> CGFloat {
        guard housing == .folder || housing == .collection else { return paperTop }
        let tab = min(24, max(0, (height - 9 - paperTop) * 0.18 / 0.82))
        return paperTop - tab
    }

}

/// Scaling keeps the raised wire loop on its nail; the parent owns rotation.
struct SuspendedClipScale: GeometryEffect {
    var scale: CGFloat
    var animatableData: CGFloat {
        get { scale }
        set { scale = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let pin = ClipOrientation.hook
        return ProjectionTransform(CGAffineTransform(translationX: pin.x, y: pin.y)
            .scaledBy(x: scale, y: scale).translatedBy(x: -pin.x, y: -pin.y))
    }
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
        .zero // a suspended loop cannot slide away from its nail
    }
    static func suspension(size: CGSize, isLeft: Bool) -> CGPoint {
        CGPoint(x: isLeft ? ClipOrientation.edgeAnchor : size.width - ClipOrientation.edgeAnchor, y: ClipOrientation.compactHookY)
    }
    static func grip(size: CGSize, isLeft: Bool) -> CGPoint {
        CGPoint(x: isLeft ? ClipOrientation.edgeAnchor : size.width - ClipOrientation.edgeAnchor, y: ClipOrientation.contactY)
    }
    static func swingHeight(size: CGSize, isLeft: Bool) -> CGFloat {
        let pin = suspension(size: size, isLeft: isLeft)
        let reach = isLeft ? size.width - pin.x : pin.x
        return max(size.height, pin.y + hypot(reach, size.height - pin.y) + 12)
    }
}

/// Rotate the complete card assembly around its raised loop and stationary nail. Standalone row transitions
/// can also use this transform, but a card must apply it only once to the group.
struct HingeSheetEffect: GeometryEffect {
    var progress: CGFloat
    var isLeft: Bool
    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        let pin = HingeReveal.suspension(size: size, isLeft: isLeft)
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
enum HoverExpansionGate {
    static func blocks(mouseButtons: Int, materialMoving: Bool, pointClamping: Bool) -> Bool {
        mouseButtons != 0 || materialMoving || pointClamping
    }
}

enum DockGeometry {
    static let compactSize = CGSize(width: 64, height: 60)
    static let thumbnailSize = CGSize(width: 30, height: 22.5)
    static let spacing: CGFloat = 68
    static func side(at point: CGPoint, in frame: CGRect, distance: CGFloat = 42) -> ClampCore.ClipSide? {
        if point.x - frame.minX < distance { return .left }
        if frame.maxX - point.x < distance { return .right }
        return nil
    }
    static func height(at y: CGFloat, in frame: CGRect) -> Double {
        Double(max(0, min(1, (y - compactSize.height / 2 - frame.minY) / max(1, frame.height - compactSize.height))))
    }
    static func origins(heights: [Double?], in frame: CGRect) -> [CGFloat] {
        guard !heights.isEmpty else { return [] }
        let desired = heights.enumerated().map { originY(height: $0.element, index: $0.offset, in: frame) }
        let order = desired.indices.sorted { desired[$0] == desired[$1] ? $0 < $1 : desired[$0] < desired[$1] }
        let gap = min(spacing, max(0, frame.height - compactSize.height) / CGFloat(max(1, heights.count - 1)))
        var result = desired
        var floor = frame.minY
        for index in order { result[index] = max(floor, desired[index]); floor = result[index] + gap }
        var ceiling = frame.maxY - compactSize.height
        for index in order.reversed() { result[index] = min(ceiling, result[index]); ceiling = result[index] - gap }
        return result
    }
    static func originY(height: Double?, index: Int, in frame: CGRect) -> CGFloat {
        guard let height, height.isFinite else { return max(frame.minY, frame.maxY - 108 - CGFloat(index) * spacing) }
        return frame.minY + CGFloat(max(0, min(1, height))) * max(0, frame.height - compactSize.height)
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
