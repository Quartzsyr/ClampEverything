import SwiftUI
import ClampCore

extension FolderTint {
    var base: Color {
        switch self {
        case .kraft: return Color(red: 0.76, green: 0.57, blue: 0.31)
        case .ocean: return Color(red: 0.39, green: 0.61, blue: 0.72)
        case .sage: return Color(red: 0.51, green: 0.65, blue: 0.48)
        }
    }
    var face: Color {
        switch self {
        case .kraft: return Color(red: 0.92, green: 0.79, blue: 0.57)
        case .ocean: return Color(red: 0.72, green: 0.84, blue: 0.89)
        case .sage: return Color(red: 0.79, green: 0.85, blue: 0.70)
        }
    }
}

struct FolderSilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let tab = min(24, h * 0.18), r = min(9, w * 0.08)
        var path = Path()
        path.move(to: CGPoint(x: r, y: tab))
        path.addLine(to: CGPoint(x: w * 0.10, y: tab))
        path.addQuadCurve(to: CGPoint(x: w * 0.14, y: 0), control: CGPoint(x: w * 0.11, y: 0))
        path.addLine(to: CGPoint(x: w * 0.39, y: 0))
        path.addQuadCurve(to: CGPoint(x: w * 0.46, y: tab), control: CGPoint(x: w * 0.43, y: 0))
        path.addLine(to: CGPoint(x: w - r, y: tab))
        path.addQuadCurve(to: CGPoint(x: w, y: tab + r), control: CGPoint(x: w, y: tab))
        path.addLine(to: CGPoint(x: w, y: h - r))
        path.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
        path.addLine(to: CGPoint(x: r, y: h))
        path.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
        path.addLine(to: CGPoint(x: 0, y: tab + r))
        path.addQuadCurve(to: CGPoint(x: r, y: tab), control: CGPoint(x: 0, y: tab))
        path.closeSubpath()
        return path
    }
}

/// Code-drawn layers keep the tab, seams and pocket crisp at every window size.
struct FolderMaterial: View {
    var tint: FolderTint
    var title = ""
    var opening: CGFloat = 1
    var layers: Int = 1
    var dragPull = PaperPull.resting
    var motionDisabled = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        GeometryReader { geometry in
            let compact = geometry.size.width < 100
            let tabHeight: CGFloat = compact ? 5 : 24
            ZStack(alignment: .topLeading) {
                FolderSilhouette().fill(tint.face)
                    .overlay(FolderSilhouette().fill(LinearGradient(colors: [.white.opacity(0.08), .black.opacity(0.015)], startPoint: .top, endPoint: .bottom)))
                if compact {
                    RoundedRectangle(cornerRadius: 2).fill(.white.opacity(0.75))
                        .padding(.horizontal, 3).padding(.top, tabHeight + 2).padding(.bottom, 3)
                    PocketFront(opening: 0)
                        .fill(LinearGradient(colors: [tint.face, tint.base.opacity(0.85)], startPoint: .top, endPoint: .bottom))
                } else {
                    // A thin matte sleeve around one warm-white sheet, with a shallow folded lip.
                    RoundedRectangle(cornerRadius: 3).fill(Color(red: 0.993, green: 0.990, blue: 0.978))
                        .shadow(color: .black.opacity(0.10), radius: 1, y: 0.5)
                        .padding(.horizontal, 4).padding(.top, tabHeight + 6).padding(.bottom, 10)
                    UnevenRoundedRectangle(topLeadingRadius: 1, bottomLeadingRadius: 8, bottomTrailingRadius: 8, topTrailingRadius: 1)
                        .fill(tint.face)
                        .overlay(alignment: .top) { Rectangle().fill(tint.base.opacity(0.26)).frame(height: 0.5) }
                        .frame(height: 9 + PocketGeometry.mouthGap(opening) * 0.25 + abs(dragPull.y) * 0.8)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                    Canvas { context, size in
                        var crease = Path()
                        crease.move(to: CGPoint(x: 12, y: size.height - 5))
                        crease.addLine(to: CGPoint(x: size.width - 12, y: size.height - 5))
                        context.stroke(crease, with: .color(tint.base.opacity(0.20)), lineWidth: 0.5)
                    }
                    if !title.isEmpty {
                        Text(title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                            .foregroundStyle(Color.black.opacity(0.60))
                            .frame(width: geometry.size.width * 0.38, height: 22, alignment: .leading)
                            .offset(x: geometry.size.width * 0.15, y: 1)
                    }
                }
            }.clipShape(FolderSilhouette())
                .overlay(FolderSilhouette().stroke(tint.base.opacity(0.40), lineWidth: 0.6))
        }.allowsHitTesting(false)
            .animation(reduceMotion || motionDisabled ? nil : .spring(response: 0.55, dampingFraction: 0.65), value: dragPull)
    }
}

struct HousingMaterial: View {
    let housing: ContentHousing
    let id: UUID
    let preferences: AppPreferences
    var title = ""
    var pull = PaperPull.resting
    var isLeft = false
    var material: PhysicalMaterial = .file
    var opening: CGFloat = 1
    var layers: Int = 1
    var dragPull = PaperPull.resting
    var body: some View {
        switch housing {
        case .folder, .collection: FolderMaterial(tint: preferences.folderTint, title: title, opening: opening, layers: layers, dragPull: dragPull, motionDisabled: preferences.motionIntensity == 0)
        case .note: PaperMaterial(id: id, pull: pull, isLeft: isLeft, stock: preferences.noteStock)
        case .file: FileMaterial(material: material)
        case .link: BookmarkMaterial()
        case .photo: Color.clear
        }
    }
}

struct HousingFinish: ViewModifier {
    let housing: ContentHousing
    var pull: PaperPull
    var fold: CGFloat
    var isLeft: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if housing.isFlexible {
            content
                .overlay { SheetLighting(pull: pull, isLeft: isLeft, photo: housing == .photo) }
                .clipShape(SoftSheetMask(pull: pull, fold: fold, isLeft: isLeft))
                .contentShape(SoftSheetMask(pull: pull, fold: fold, isLeft: isLeft))
                .overlay { SheetFoldFace(amount: fold, pull: pull, isLeft: isLeft, photo: housing == .photo) }
        } else if housing == .folder || housing == .collection {
            content.clipShape(FolderSilhouette()).contentShape(FolderSilhouette())
        } else if housing == .link {
            content.clipShape(BookmarkShape(), style: FillStyle(eoFill: true)).contentShape(BookmarkShape(), eoFill: true)
        } else {
            content.clipShape(RoundedRectangle(cornerRadius: 12)).contentShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}
