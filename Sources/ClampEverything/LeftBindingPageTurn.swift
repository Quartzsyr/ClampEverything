import SwiftUI

enum LeftBindingPageGeometry {
    static func drawingOutset(height: CGFloat) -> CGFloat { ceil(max(0, height) * 0.21 + 2) }
    static func amount(progress: CGFloat, direction: Int) -> CGFloat {
        let p = max(0, min(1, progress))
        return direction >= 0 ? p : 1 - p
    }
    static func opacity(amount: CGFloat) -> Double {
        Double(max(0, min(1, (0.88 - amount) / 0.12)))
    }
    static func projection(size: CGSize, amount: CGFloat) -> ProjectionTransform {
        let angle = -105 * max(0, min(1, amount)) * CGFloat.pi / 180
        // The free edge comes toward the viewer: its perspective denominator
        // decreases, so it grows rather than receding into the page stack.
        let k = sin(angle) / max(1, size.width * 3.5)
        // Homography for a vertical hinge at x=0. Every point on the left
        // binding maps to itself, including the top and bottom of the spine.
        var result = ProjectionTransform(CGAffineTransform.identity)
        result.m11 = cos(angle); result.m12 = size.height * 0.5 * k; result.m13 = k
        return result
    }
    static func project(_ point: CGPoint, size: CGSize, amount: CGFloat) -> CGPoint {
        let t = projection(size: size, amount: amount)
        let w = t.m13 * point.x + t.m23 * point.y + t.m33
        return CGPoint(x: (t.m11 * point.x + t.m21 * point.y + t.m31) / w,
                       y: (t.m12 * point.x + t.m22 * point.y + t.m32) / w)
    }
    static func curlPoint(_ point: CGPoint, size: CGSize, pull: PaperPull) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return point }
        let u = max(0, min(1, point.x / size.width)), v = max(0, min(1, point.y / size.height))
        return CGPoint(x: point.x - u * u * min(18, size.width * 0.07) * abs(pull.x),
                       y: point.y + u * u * sin(v * CGFloat.pi) * min(12, size.height * 0.04) * pull.y)
    }
}

