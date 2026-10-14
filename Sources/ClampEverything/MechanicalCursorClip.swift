import SwiftUI

/// Jaw centre is fixed at (54,18). The wire loop remains strictly to its left.
struct MechanicalCursorClip: View, Animatable {
    var openness: Double
    var animatableData: Double { get { openness } set { openness = newValue } }
    var body: some View {
        Canvas { context, _ in
            let gap = CGFloat(max(0, min(1, openness))) * 7
            let steel = Gradient(colors: [Color(white: 0.48), Color(white: 0.98), Color(white: 0.63), Color(white: 0.88), Color(white: 0.38)])
            // A rounded spring-steel handle, never mirrored between poses.
            var wire = Path()
            wire.move(to: CGPoint(x: 35, y: 11))
            wire.addCurve(to: CGPoint(x: 16, y: 5), control1: CGPoint(x: 28, y: 12), control2: CGPoint(x: 23, y: 5))
            wire.addCurve(to: CGPoint(x: 5, y: 18), control1: CGPoint(x: 7, y: 2), control2: CGPoint(x: 5, y: 9))
            wire.addCurve(to: CGPoint(x: 16, y: 31), control1: CGPoint(x: 5, y: 27), control2: CGPoint(x: 7, y: 34))
            wire.addCurve(to: CGPoint(x: 35, y: 25), control1: CGPoint(x: 23, y: 31), control2: CGPoint(x: 28, y: 24))
            context.stroke(wire, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: 3.8, lineCap: .round))
            context.stroke(wire, with: .linearGradient(steel, startPoint: CGPoint(x: 0, y: 3), endPoint: CGPoint(x: 0, y: 32)), style: StrokeStyle(lineWidth: 2.7, lineCap: .round))
            for sign: CGFloat in [-1, 1] {
                let tip = CGPoint(x: 54, y: 18 + sign * (1 + gap))
                var jaw = Path()
                jaw.move(to: CGPoint(x: 34, y: 18 + sign * 2))
                jaw.addLine(to: CGPoint(x: 51, y: tip.y + sign * 5))
                jaw.addQuadCurve(to: tip, control: CGPoint(x: 54, y: tip.y + sign * 5))
                jaw.addLine(to: CGPoint(x: 35, y: 18 + sign * 0.5))
                jaw.closeSubpath()
                context.fill(jaw, with: .linearGradient(steel, startPoint: CGPoint(x: 33, y: 8), endPoint: CGPoint(x: 54, y: 29)))
                context.stroke(jaw, with: .color(.black.opacity(0.4)), lineWidth: 0.6)
            }
            let hinge = Path(roundedRect: CGRect(x: 31, y: 10, width: 7, height: 16), cornerRadius: 2)
            context.fill(hinge, with: .linearGradient(steel, startPoint: CGPoint(x: 31, y: 0), endPoint: CGPoint(x: 38, y: 0)))
            context.fill(Path(ellipseIn: CGRect(x: 33, y: 15, width: 3, height: 3)), with: .color(.white.opacity(0.7)))
        }.frame(width: 54, height: 36).shadow(color: .black.opacity(0.3), radius: 1, y: 1)
            .accessibilityHidden(true)
    }
}
