import AppKit
import SwiftUI
import ClampCore

enum PinnedContentForm: Equatable {
    case pocket, photo, notePage, codePage, documentPrint, webPrint, fileSheet, cassette, filmStrip, parcel
    static func forItem(_ item: ClipItem?) -> Self {
        guard let item else { return .pocket }
        switch item.kind {
        case .folder: return .pocket
        case .image: return .photo
        case .text: return .notePage
        case .link: return .webPrint
        case .file:
            switch PhysicalMaterial.forItem(item) {
            case .audio: return .cassette
            case .film: return .filmStrip
            case .archive: return .parcel
            default:
                let url = URL(fileURLWithPath: item.originalPath ?? item.title)
                switch FilePreviewKind.forURL(url) {
                case .code: return .codePage
                case .pdf, .document: return .documentPrint
                default: return .fileSheet
                }
            }
        }
    }
    var isManuscript: Bool { [.notePage, .codePage, .documentPrint, .webPrint, .fileSheet].contains(self) }
    var usesPaperStock: Bool { self == .notePage || self == .codePage || self == .fileSheet }
}

/// Only loose paper gets a paper backing. Printed pages and web captures are
/// already the object being clipped; no common panel is drawn behind them.
struct PinnedObjectFinish: ViewModifier {
    let form: PinnedContentForm
    let id: UUID
    let preferences: AppPreferences
    var pull: PaperPull
    var fold: CGFloat
    var isLeft: Bool
    var housing: ContentHousing
    var physical: PhysicalMaterial
    var opening: CGFloat
    var layers: Int
    var dragPull: PaperPull
    var title: String
    @ViewBuilder func body(content: Content) -> some View {
        if form == .pocket {
            content.background {
                HousingMaterial(housing: housing, id: id, preferences: preferences, title: title, pull: pull, isLeft: isLeft,
                                material: physical, opening: opening, layers: layers, dragPull: dragPull)
            }.modifier(HousingFinish(housing: housing, pull: pull, fold: fold, isLeft: isLeft))
        } else if form.usesPaperStock {
            content.background { QuietPaper(stock: form == .notePage ? preferences.noteStock : .natural) }
                .clipShape(SoftSheetMask(pull: pull, isLeft: isLeft))
                .overlay { SheetLighting(pull: pull, isLeft: isLeft) }
                .modifier(ManuscriptPaper(seed: PaperWearGeometry.seed(id), pull: dragPull, fold: fold, clipOnLeft: isLeft))
        } else if form == .webPrint {
            content.modifier(ManuscriptPaper(seed: PaperWearGeometry.seed(id), pull: dragPull, fold: fold, clipOnLeft: isLeft))
        } else { content }
    }
}

struct QuietPaper: View {
    var stock: NoteStock = .natural
    var body: some View {
        Image(nsImage: GeneratedAssets.image("paper-minimal-v1")).resizable().interpolation(.high)
            .overlay {
                if stock == .ivory { Color(red: 1, green: 0.97, blue: 0.88).opacity(0.13) }
                if stock == .ruled {
                    Canvas { context, size in
                        for y in stride(from: 38.0, to: size.height, by: 22) {
                            var line = Path(); line.move(to: CGPoint(x: 12, y: y)); line.addLine(to: CGPoint(x: size.width - 12, y: y))
                            context.stroke(line, with: .color(.blue.opacity(0.09)), lineWidth: 0.5)
                        }
                    }
                }
            }.allowsHitTesting(false)
    }
}

struct MinimalPinnedContent: View {
    @ObservedObject var store: ClipStore
    let item: ClipItem
    var interaction: (Bool) -> Void
    var form: PinnedContentForm { .forItem(item) }
    var body: some View {
        Group {
            switch form {
            case .notePage:
                ScrollView {
                    Text(String((item.text ?? "").prefix(8000))).font(.system(size: 14)).lineSpacing(5)
                        .frame(maxWidth: .infinity, alignment: .topLeading).padding(18).padding(.top, 8)
                }.overlay(copyHandle)
            case .codePage:
                if let url = store.fileURL(item) { CodeFilePreview(url: url).overlay(copyHandle) }
                else { missingObject }
            case .documentPrint:
                DocumentReadingPreview(store: store, item: item, interaction: interaction)
            case .fileSheet:
                FileThumbnailPreview(store: store, item: item).overlay(copyHandle)
            case .webPrint:
                if let value = item.link, let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? "") {
                    WebLinkPreview(url: url, store: store, item: item, interaction: interaction).id(url)
                } else { missingObject.overlay(copyHandle) }
            case .cassette, .filmStrip, .parcel:
                MinimalMediaObject(form: form, title: item.title, image: store.images[item.id])
                    .overlay(copyHandle).onAppear { store.loadThumbnail(item) }
            default: missingObject
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .help((store.status(item) ?? item.title) + " · 单击复制 · 拖出复制 · 右键操作")
    }
    var copyHandle: some View { ContentDragHandle(item: item, store: store, interaction: interaction, showLabel: false) }
    var missingObject: some View {
        VStack(spacing: 9) { ClipIcon(item: item, size: 40); Text(item.title).font(.system(size: 11)).lineLimit(2) }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct MinimalMediaObject: View {
    let form: PinnedContentForm
    let title: String
    var image: NSImage?
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            if form == .cassette {
                ZStack {
                    RoundedRectangle(cornerRadius: 6).fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.09)], startPoint: .top, endPoint: .bottom))
                    VStack(spacing: 0) {
                        Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).foregroundStyle(.black.opacity(0.8))
                            .frame(maxWidth: .infinity).padding(.vertical, 10).padding(.horizontal, 6)
                            .background(Color(red: 0.93, green: 0.91, blue: 0.84)).padding(10)
                        HStack(spacing: size.width * 0.18) {
                            ForEach(0..<2) { _ in
                                Circle().stroke(Color(white: 0.5), lineWidth: 5).background(Circle().fill(.black))
                                    .overlay(Circle().fill(Color(white: 0.75)).frame(width: 7, height: 7))
                                    .frame(width: size.height * 0.24, height: size.height * 0.24)
                            }
                        }.frame(maxHeight: .infinity)
                        Capsule().fill(Color(white: 0.3)).frame(width: size.width * 0.5, height: 6).padding(.bottom, 14)
                    }
                }.overlay(RoundedRectangle(cornerRadius: 6).stroke(.white.opacity(0.18), lineWidth: 0.6))
            } else if form == .filmStrip {
                ZStack {
                    FilmStripShape().fill(Color(white: 0.09), style: FillStyle(eoFill: true))
                    Group {
                        if let image { Image(nsImage: image).resizable().scaledToFill() }
                        else { Text(title).font(.system(size: 11)).foregroundStyle(.white.opacity(0.8)).lineLimit(2).padding(16) }
                    }.frame(width: max(1, size.width - 28), height: max(1, size.height - 10)).clipped()
                }
            } else {
                ZStack(alignment: .top) {
                    ParcelShape().fill(LinearGradient(colors: [Color(red: 0.82, green: 0.69, blue: 0.49), Color(red: 0.72, green: 0.56, blue: 0.35)], startPoint: .top, endPoint: .bottom))
                    Canvas { context, size in
                        var seam = Path(); seam.move(to: CGPoint(x: 6, y: 13)); seam.addLine(to: CGPoint(x: size.width - 6, y: 13))
                        context.stroke(seam, with: .color(.brown.opacity(0.45)), style: StrokeStyle(lineWidth: 2, dash: [1, 2]))
                        var fold = Path(); fold.move(to: CGPoint(x: 7, y: size.height - 9)); fold.addLine(to: CGPoint(x: size.width - 7, y: size.height - 9))
                        context.stroke(fold, with: .color(.white.opacity(0.17)), lineWidth: 0.7)
                    }
                    Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.black.opacity(0.65)).lineLimit(2)
                        .padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

struct FilmStripShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        for y in stride(from: 8.0, to: max(8, rect.height - 8), by: 20) {
            for x in [4.0, rect.width - 10] {
                path.addPath(Path(roundedRect: CGRect(x: x, y: y, width: 6, height: 10), cornerRadius: 1))
            }
        }
        return path
    }
}
struct ParcelShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: 3, y: 0)); p.addLine(to: CGPoint(x: rect.width - 3, y: 0))
            p.addLine(to: CGPoint(x: rect.width, y: 3)); p.addLine(to: CGPoint(x: rect.width, y: rect.height - 3))
            p.addLine(to: CGPoint(x: rect.width - 3, y: rect.height)); p.addLine(to: CGPoint(x: 3, y: rect.height))
            p.addLine(to: CGPoint(x: 0, y: rect.height - 3)); p.addLine(to: CGPoint(x: 0, y: 3)); p.closeSubpath()
        }
    }
}
