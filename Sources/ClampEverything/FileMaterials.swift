import SwiftUI
import ClampCore

struct FileMaterial: View {
    var material: PhysicalMaterial
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 11)
                .fill(LinearGradient(colors: [.white, Color(white: 0.91), Color(white: 0.8)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(.white.opacity(0.9), lineWidth: 1).padding(1))
                .overlay(RoundedRectangle(cornerRadius: 11).stroke(.black.opacity(0.16), lineWidth: 0.7))
            Canvas { context, size in
                if material == .film {
                    for y in stride(from: 48.0, to: size.height - 20, by: 18) {
                        for x in [5.0, size.width - 11] {
                            context.fill(Path(roundedRect: CGRect(x: x, y: y, width: 6, height: 9), cornerRadius: 1.5), with: .color(.black.opacity(0.28)))
                        }
                    }
                } else if material == .audio {
                    for point in [CGPoint(x: 9, y: 45), CGPoint(x: size.width - 9, y: 45), CGPoint(x: 9, y: size.height - 10), CGPoint(x: size.width - 9, y: size.height - 10)] {
                        context.fill(Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)), with: .color(.black.opacity(0.24)))
                        var slot = Path(); slot.move(to: CGPoint(x: point.x - 1.5, y: point.y)); slot.addLine(to: CGPoint(x: point.x + 1.5, y: point.y))
                        context.stroke(slot, with: .color(.white.opacity(0.7)), lineWidth: 0.5)
                    }
                } else if material == .archive {
                    for y in stride(from: 46.0, to: size.height - 18, by: 6) {
                        context.fill(Path(CGRect(x: size.width - 10, y: y, width: 3, height: 3)), with: .color(.brown.opacity(0.45)))
                        context.fill(Path(CGRect(x: size.width - 6, y: y + 3, width: 3, height: 3)), with: .color(.brown.opacity(0.28)))
                    }
                    context.fill(Path(roundedRect: CGRect(x: size.width - 12, y: 49, width: 8, height: 14), cornerRadius: 2), with: .color(.gray))
                } else if material == .document {
                    for y in [size.height - 4, size.height - 7] {
                        var edge = Path(); edge.move(to: CGPoint(x: 12, y: y)); edge.addLine(to: CGPoint(x: size.width - 12, y: y))
                        context.stroke(edge, with: .color(.black.opacity(0.12)), lineWidth: 0.7)
                    }
                    context.fill(Path(roundedRect: CGRect(x: 4, y: 40, width: 4, height: max(1, size.height - 52)), cornerRadius: 2), with: .color(.brown.opacity(0.15)))
                } else {
                    context.stroke(Path(roundedRect: CGRect(x: 9, y: 42, width: max(1, size.width - 18), height: max(1, size.height - 51)), cornerRadius: 6), with: .color(.black.opacity(0.04)), lineWidth: 0.6)
                }
            }
        }.allowsHitTesting(false)
    }
}
struct BookmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect, cornerRadius: min(10, rect.width * 0.1))
        let depth = min(12, rect.height * 0.12), notch = min(20, rect.width * 0.15)
        var triangle = Path(); triangle.move(to: CGPoint(x: rect.midX - notch, y: rect.maxY)); triangle.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - depth)); triangle.addLine(to: CGPoint(x: rect.midX + notch, y: rect.maxY)); triangle.closeSubpath()
        path.addPath(triangle); return path
    }
}
struct BookmarkMaterial: View {
    var body: some View {
        BookmarkShape().fill(LinearGradient(colors: [Color(red: 0.86, green: 0.94, blue: 0.91), Color(red: 0.62, green: 0.79, blue: 0.73)], startPoint: .topLeading, endPoint: .bottomTrailing), style: FillStyle(eoFill: true))
            .overlay(BookmarkShape().stroke(.black.opacity(0.15), lineWidth: 0.7))
            .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.4)).frame(width: 1).padding(.leading, 8).padding(.vertical, 18) }
            .allowsHitTesting(false)
    }
}
struct FileObjectBadge: View {
    var material: PhysicalMaterial
    var extensionLabel: String
    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(.black.opacity(material == .archive ? 0.06 : 0.8))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.6), lineWidth: 0.7))
                Image(systemName: material == .audio ? "waveform" : (material == .film ? "film" : "archivebox"))
                    .font(.system(size: 38, weight: .ultraLight)).foregroundStyle(material == .archive ? Color.brown : .white.opacity(0.8))
            }.frame(width: 140, height: 82).shadow(color: .black.opacity(0.16), radius: 3, y: 3)
            Text(extensionLabel.uppercased()).font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity).padding(.vertical, 18)
    }
}
