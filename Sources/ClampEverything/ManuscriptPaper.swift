import SwiftUI
import ClampCore

struct ManuscriptMotion {
    var pull = PaperPull.resting
    var fold: CGFloat = 0
    var isLeft = false
    var disabled = false
    var turnActivity: (Bool) -> Void = { _ in }
}
private struct ManuscriptMotionKey: EnvironmentKey {
    static let defaultValue = ManuscriptMotion()
}
extension EnvironmentValues {
    var manuscriptMotion: ManuscriptMotion {
        get { self[ManuscriptMotionKey.self] }
        set { self[ManuscriptMotionKey.self] = newValue }
    }
}

/// Stable, sub-point wear avoids frame-to-frame noise and leaves the printed
/// area intact. A bound edge and the top jaw contact stay straight.
enum PaperWearGeometry {
    static func seed(_ id: UUID) -> UInt64 {
        id.uuidString.utf8.reduce(UInt64(14695981039346656037)) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
    static func depth(edge: Int, fraction: CGFloat, seed: UInt64, boundLeft: Bool, clipOnLeft: Bool) -> CGFloat {
        if boundLeft && edge == 3 { return 0 }
        if edge == 0 && (clipOnLeft ? fraction < 0.36 : fraction > 0.64) { return 0 }
        let phase = CGFloat(seed % 997) * 0.013 + CGFloat(edge) * 1.7
        let noise = sin(fraction * 73 + phase) * 0.24 + sin(fraction * 193 + phase * 1.9) * 0.18
        return max(0.08, min(1.05, 0.42 + noise))
    }
    static func curl(size: CGSize, fold: CGFloat, pull: PaperPull) -> CGFloat {
        let edge = max(0, min(size.width, size.height))
        let resting = min(10, edge * 0.035)
        return min(edge * 0.22, resting + min(1, max(0, fold)) * min(46, edge * 0.18) + min(1, abs(pull.x) + abs(pull.y)) * 5)
    }
}

struct ManuscriptOutline: Shape {
    var seed: UInt64
    var corner: CGFloat
    var curlRight = true
    var boundLeft = false
    var clipOnLeft = false
    var turnAmount: CGFloat = 0
    var verticalOutset: CGFloat = 0
    var horizontalOutset: CGFloat = 0
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(corner, turnAmount) }
        set { corner = newValue.first; turnAmount = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: horizontalOutset, dy: verticalOutset)
        let w = rect.width, h = rect.height
        guard w > 0, h > 0 else { return Path() }
        let curl = min(max(0, corner), min(w, h) * 0.22)
        var points: [CGPoint] = []
        func point(_ x: CGFloat, _ y: CGFloat) {
            let p = LeftBindingPageGeometry.project(CGPoint(x: x, y: y), size: rect.size, amount: turnAmount)
            points.append(CGPoint(x: rect.minX + p.x, y: rect.minY + p.y))
        }
        func depth(_ edge: Int, _ t: CGFloat) -> CGFloat {
            PaperWearGeometry.depth(edge: edge, fraction: t, seed: seed, boundLeft: boundLeft, clipOnLeft: clipOnLeft)
        }
        for i in 0...64 { let t = CGFloat(i) / 64; point(w * t, depth(0, t)) }
        for i in 1...64 {
            let t = CGFloat(i) / 64, y = (h - (curlRight ? curl : 0)) * t
            point(w - depth(1, y / h), y)
        }
        if curlRight { point(w - curl, h) }
        let start = curlRight ? w - curl : w
        let end = curlRight ? 0 : curl
        for i in 1...64 { let t = CGFloat(i) / 64; let x = start + (end - start) * t; point(x, h - depth(2, x / w)) }
        if !curlRight { point(0, h - curl) }
        let leftStart = curlRight ? h : h - curl
        for i in 1...64 { let t = CGFloat(i) / 64, y = leftStart * (1 - t); point(depth(3, y / h), y) }
        return Path { p in p.addLines(points); p.closeSubpath() }
    }
}

struct PaperCornerLift: View, Animatable {
    var amount: CGFloat
    var right: Bool
    var turnAmount: CGFloat = 0
    var verticalOutset: CGFloat = 0
    var horizontalOutset: CGFloat = 0
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(amount, turnAmount) }
        set { amount = newValue.first; turnAmount = newValue.second }
    }
    var body: some View {
        Canvas { original, canvasSize in
            var context = original
            context.translateBy(x: horizontalOutset, y: verticalOutset)
            let size = CGSize(width: max(1, canvasSize.width - horizontalOutset * 2), height: max(1, canvasSize.height - verticalOutset * 2))
            let c = min(max(0, amount), min(size.width, size.height) * 0.22)
            guard c > 0.5 else { return }
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { LeftBindingPageGeometry.project(CGPoint(x: right ? size.width - x : x, y: y), size: size, amount: turnAmount) }
            let a = p(c, size.height), b = p(0, size.height - c), tip = p(c * 0.87, size.height - c * 0.87)
            var flap = Path(); flap.move(to: a)
            flap.addQuadCurve(to: tip, control: p(c * 1.05, size.height - c * 0.42))
            flap.addQuadCurve(to: b, control: p(c * 0.45, size.height - c * 1.05))
            flap.addQuadCurve(to: a, control: p(c * 0.55, size.height - c * 0.48)); flap.closeSubpath()
            context.drawLayer { shadow in
                shadow.addFilter(.shadow(color: .black.opacity(0.18), radius: max(0.7, c * 0.09), x: right ? -0.5 : 0.5, y: 1))
                shadow.fill(flap, with: .linearGradient(Gradient(colors: [Color(white: 0.85), Color(red: 0.99, green: 0.98, blue: 0.94), .white]), startPoint: tip, endPoint: a))
            }
            var crease = Path(); crease.move(to: a); crease.addQuadCurve(to: b, control: p(c * 0.55, size.height - c * 0.48))
            context.stroke(crease, with: .color(.black.opacity(0.12)), lineWidth: 0.5)
        }.allowsHitTesting(false)
    }
}

struct ManuscriptPaper: ViewModifier {
    var seed: UInt64
    var boundLeft = false
    var pull = PaperPull.resting
    var fold: CGFloat = 0
    var clipOnLeft = false
    var turnAmount: CGFloat = 0
    var verticalOutset: CGFloat = 0
    var horizontalOutset: CGFloat = 0
    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geometry in
                let size = CGSize(width: max(1, geometry.size.width - horizontalOutset * 2), height: max(1, geometry.size.height - verticalOutset * 2))
                let curl = PaperWearGeometry.curl(size: size, fold: fold, pull: pull)
                let right = boundLeft || clipOnLeft
                let shape = ManuscriptOutline(seed: seed, corner: curl, curlRight: right, boundLeft: boundLeft, clipOnLeft: clipOnLeft, turnAmount: turnAmount, verticalOutset: verticalOutset, horizontalOutset: horizontalOutset)
                shape.stroke(.brown.opacity(0.15), lineWidth: 0.7)
                    .overlay(shape.stroke(.white.opacity(0.40), lineWidth: 0.3).offset(y: -0.35))
                    .overlay { PaperCornerLift(amount: curl, right: right, turnAmount: turnAmount, verticalOutset: verticalOutset, horizontalOutset: horizontalOutset) }
            }.allowsHitTesting(false)
        }
        .mask {
            GeometryReader { geometry in
                let size = CGSize(width: max(1, geometry.size.width - horizontalOutset * 2), height: max(1, geometry.size.height - verticalOutset * 2))
                ManuscriptOutline(seed: seed, corner: PaperWearGeometry.curl(size: size, fold: fold, pull: pull),
                    curlRight: boundLeft || clipOnLeft, boundLeft: boundLeft, clipOnLeft: clipOnLeft, turnAmount: turnAmount, verticalOutset: verticalOutset, horizontalOutset: horizontalOutset).fill(.white)
            }
        }
    }
}
