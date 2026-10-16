import SwiftUI
import ClampCore

struct CompactClipView: View {
    @ObservedObject var store: ClipStore
    let id: UUID
    let isLeft: Bool
    var open: () -> Void
    var interaction: (Bool) -> Void
    var item: ClipItem? { store.item(id) }
    var body: some View {
        thumbnail.frame(width: 36, height: 27)
            .overlay {
                if let item { ContentDragHandle(item: item, store: store, interaction: interaction, showLabel: false) }
            }
            .scaleEffect(5.0 / 6)
            .frame(width: DockGeometry.thumbnailSize.width, height: DockGeometry.thumbnailSize.height)
            .position(x: HingeReveal.suspension(size: DockGeometry.compactSize, isLeft: isLeft).x,
                      y: ClipOrientation.paperTop - (item == nil || item?.kind == .folder ? DockGeometry.thumbnailSize.height * 0.18 : 0) + DockGeometry.thumbnailSize.height / 2)
            .frame(width: DockGeometry.compactSize.width, height: DockGeometry.compactSize.height)
            .onAppear { if let item { store.loadThumbnail(item) } }
            .help(item == nil ? "点击展开材料夹" : "拖出缩略图直接使用 · 轻点复制")
    }
    @ViewBuilder var thumbnail: some View {
        let form = PinnedContentForm.forItem(item)
        if item != nil, [.photo, .documentPrint, .fileSheet].contains(form), let image = store.images[id] {
            Image(nsImage: image).resizable().scaledToFill().frame(width: 36, height: 27).clipped()
        } else if form == .pocket {
            ZStack {
                if item == nil {
                    FolderMaterial(tint: store.state.preferences.folderTint).offset(x: -3, y: -3)
                    FolderMaterial(tint: store.state.preferences.folderTint).offset(x: -1, y: -1)
                }
                FolderMaterial(tint: store.state.preferences.folderTint)
            }.onTapGesture { if item == nil { open() } }
        } else if [.cassette, .filmStrip, .parcel].contains(form) {
            MinimalMediaObject(form: form, title: "", image: store.images[id])
                .frame(width: 144, height: 108).scaleEffect(0.25).frame(width: 36, height: 27)
        } else if form == .webPrint, let link = item?.link, let url = URL(string: link), let cached = WebPagePreviewCache.entry(url) {
            Image(nsImage: cached.image).resizable().scaledToFill().frame(width: 36, height: 27).clipped()
        } else {
            QuietPaper().overlay {
                if form == .notePage {
                    Text(String((item?.text ?? "").prefix(80))).font(.system(size: 5)).lineLimit(3).padding(3)
                } else if let item { ClipIcon(item: item, size: 13) }
            }
        }
    }
}
