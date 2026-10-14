import SwiftUI
import AppKit

/// A supple sheet bends progressively away from its clamped corner.
/// The same field drives the texture, silhouette and folded reverse face.
enum SoftSheetGeometry {
    static func point(_ point: CGPoint, size: CGSize, pull: PaperPull, isLeft: Bool) -> CGPoint {
        guard size.width > 24, size.height > 24 else { return point }
        let anchor = CGPoint(x: isLeft ? 12 : size.width - 12, y: 12)
        let x = max(0, min(1, point.x / size.width))
        let v = max(0, min(1, (point.y - anchor.y) / (size.height - anchor.y)))
        let free = min(1, abs(point.x - anchor.x) / max(anchor.x, size.width - anchor.x))
        let px = max(-1, min(1, pull.x)), py = max(-1, min(1, pull.y))
        let bow = sin(x * .pi) * sin(v * .pi)
        let dx = (anchor.x - point.x) * abs(px) * 0.063 * v * v + px * 4 * bow * free
        let dy = -abs(py) * 21 * v * v * free + py * 3 * bow
        return CGPoint(x: point.x + dx, y: point.y + dy)
    }

    static func hover(at point: CGPoint, previous: CGPoint?, size: CGSize, isLeft: Bool) -> PaperPull {
        guard let previous, size.width > 0, size.height > 0 else { return .resting }
        let free = isLeft ? point.x / size.width : 1 - point.x / size.width
        let lower = max(0, min(1, point.y / size.height))
        let weight = max(0, min(1, free)) * lower * 0.18
        let velocity = PaperPull.following(NSPoint(x: point.x - previous.x, y: previous.y - point.y))
        return PaperPull(x: velocity.x * weight, y: velocity.y * weight)
    }

    static func foldLength(amount: CGFloat, size: CGSize) -> CGFloat {
        max(0, min(1, amount)) * min(76, min(size.width, size.height) * 0.27)
    }
}

/// A small texture mesh bends the actual photo pixels, rather than rotating a
/// rigid rectangle. At rest there is one draw; mesh work runs only in motion.
struct SoftImageSurface: View, Animatable {
    let image: NSImage
    var pull = PaperPull.resting
    var isLeft = false
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(pull.x, pull.y) }
        set { pull = PaperPull(x: newValue.first, y: newValue.second) }
    }
    var body: some View {
        Canvas { context, size in
            let texture = context.resolve(Image(nsImage: image))
            let rect = CGRect(origin: .zero, size: size)
            guard abs(pull.x) + abs(pull.y) > 0.015 else { context.draw(texture, in: rect); return }
            let columns = 10, rows = 14
            for row in 0..<rows {
                for column in 0..<columns {
                    let x0 = size.width * CGFloat(column) / CGFloat(columns)
                    let x1 = size.width * CGFloat(column + 1) / CGFloat(columns)
                    let y0 = size.height * CGFloat(row) / CGFloat(rows)
                    let y1 = size.height * CGFloat(row + 1) / CGFloat(rows)
                    let a = CGPoint(x: x0, y: y0), b = CGPoint(x: x1, y: y0)
                    let c = CGPoint(x: x0, y: y1), d = CGPoint(x: x1, y: y1)
                    drawTriangle([a, b, c], texture: texture, rect: rect, context: context)
                    drawTriangle([d, c, b], texture: texture, rect: rect, context: context)
                }
            }
        }.allowsHitTesting(false)
    }
    private func drawTriangle(_ source: [CGPoint], texture: GraphicsContext.ResolvedImage, rect: CGRect, context: GraphicsContext) {
        let target = source.map { SoftSheetGeometry.point($0, size: rect.size, pull: pull, isLeft: isLeft) }
        let sx = source[1].x - source[0].x, sy = source[2].y - source[0].y
        guard sx != 0, sy != 0 else { return }
        let a = (target[1].x - target[0].x) / sx, b = (target[1].y - target[0].y) / sx
        let c = (target[2].x - target[0].x) / sy, d = (target[2].y - target[0].y) / sy
        let transform = CGAffineTransform(a: a, b: b, c: c, d: d,
            tx: target[0].x - a * source[0].x - c * source[0].y,
            ty: target[0].y - b * source[0].x - d * source[0].y)
        // Subpixel overlap avoids antialiasing seams between adjacent triangles.
        let center = CGPoint(x: target.map(\.x).reduce(0, +) / 3, y: target.map(\.y).reduce(0, +) / 3)
        let expanded = target.map { point -> CGPoint in
            let distance = max(1, hypot(point.x - center.x, point.y - center.y))
            return CGPoint(x: point.x + (point.x - center.x) * 1.25 / distance,
                           y: point.y + (point.y - center.y) * 1.25 / distance)
        }
        var triangle = Path(); triangle.addLines(expanded); triangle.closeSubpath()
        var layer = context
        layer.clip(to: triangle); layer.concatenate(transform); layer.draw(texture, in: rect)
    }
}

struct SoftSheetMask: Shape {
    var pull = PaperPull.resting
    var fold: CGFloat = 0
    var isLeft = false
    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(pull.x, pull.y), fold) }
        set { pull = PaperPull(x: newValue.first.first, y: newValue.first.second); fold = newValue.second }
    }
    func path(in rect: CGRect) -> Path {
        let f = SoftSheetGeometry.foldLength(amount: fold, size: rect.size)
        let raw: [CGPoint]
        if isLeft {
            raw = [CGPoint(x: 0, y: 0), CGPoint(x: rect.width, y: 0), CGPoint(x: rect.width, y: rect.height - f), CGPoint(x: rect.width - f, y: rect.height), CGPoint(x: 0, y: rect.height)]
        } else {
            raw = [CGPoint(x: 0, y: 0), CGPoint(x: rect.width, y: 0), CGPoint(x: rect.width, y: rect.height), CGPoint(x: f, y: rect.height), CGPoint(x: 0, y: rect.height - f)]
        }
        var points: [CGPoint] = []
        for i in raw.indices {
            let start = raw[i], end = raw[(i + 1) % raw.count]
            for step in 0..<16 {
                let t = CGFloat(step) / 16
                let p = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
                let bent = SoftSheetGeometry.point(p, size: rect.size, pull: pull, isLeft: isLeft)
                points.append(CGPoint(x: bent.x + rect.minX, y: bent.y + rect.minY))
            }
        }
        return Path { $0.addLines(points); $0.closeSubpath() }
    }
}

struct SheetFoldFace: View, Animatable {
    var amount: CGFloat
    var pull: PaperPull
    var isLeft: Bool
    var photo = false
    var animatableData: AnimatablePair<CGFloat, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(amount, AnimatablePair(pull.x, pull.y)) }
        set { amount = newValue.first; pull = PaperPull(x: newValue.second.first, y: newValue.second.second) }
    }
    var body: some View {
        Canvas { context, size in
            let f = SoftSheetGeometry.foldLength(amount: amount, size: size)
            guard f > 0.3 else { return }
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
                SoftSheetGeometry.point(CGPoint(x: isLeft ? size.width - x : x, y: y), size: size, pull: pull, isLeft: isLeft)
            }
            let a = p(f, size.height), b = p(0, size.height - f)
            let tip = p(f * 0.82, size.height - f * 0.82)
            var flap = Path(); flap.move(to: a)
            flap.addQuadCurve(to: b, control: p(f * 0.43, size.height - f * 0.45))
            flap.addQuadCurve(to: tip, control: p(f * 0.3, size.height - f * 0.86))
            flap.addQuadCurve(to: a, control: p(f * 0.93, size.height - f * 0.28))
            flap.closeSubpath()
            context.drawLayer { shade in
                shade.addFilter(.shadow(color: .black.opacity(0.19), radius: f * 0.06, x: isLeft ? -1 : 1, y: 2))
                shade.fill(flap, with: .color(photo ? Color(white: 0.96) : Color(red: 0.97, green: 0.95, blue: 0.89)))
            }
            context.fill(flap, with: .linearGradient(Gradient(colors: [.black.opacity(0.075), .white.opacity(0.65), .white.opacity(0.06)]), startPoint: a, endPoint: tip))
            var crease = Path(); crease.move(to: a); crease.addQuadCurve(to: b, control: p(f * 0.43, size.height - f * 0.45))
            context.stroke(crease, with: .color(.black.opacity(0.09)), lineWidth: 0.65)
        }.allowsHitTesting(false)
    }
}

/// Local contact shadow and restrained travelling highlight reveal the bend.
struct SheetLighting: View {
    var pull: PaperPull
    var isLeft: Bool
    var photo = false
    var body: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black.opacity(Double(abs(pull.x) + abs(pull.y)) * 0.035), location: 0.55),
            .init(color: .white.opacity(Double(abs(pull.x) + abs(pull.y)) * (photo ? 0.1 : 0.045)), location: 0.84),
            .init(color: .clear, location: 1)
        ], startPoint: isLeft ? .topLeading : .topTrailing, endPoint: isLeft ? .bottomTrailing : .bottomLeading)
        .allowsHitTesting(false)
    }
}

struct ClampBackJaw: View {
    var isLeft: Bool
    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.87), Color(white: 0.5)], startPoint: .leading, endPoint: .trailing))
            .frame(width: 19, height: 25)
            .frame(width: 54, height: 36, alignment: .trailing)
            .offset(x: -2, y: 1)
            .allowsHitTesting(false).accessibilityHidden(true)
    }
}
