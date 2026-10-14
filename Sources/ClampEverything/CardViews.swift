import SwiftUI
import AppKit
import ClampCore

enum ClipStyle {
    static let accent = Color(red: 0.23, green: 0.40, blue: 0.39)
    static let paper = Color(nsColor: .controlBackgroundColor)
}

/// Three mechanically distinct imagegen poses blend through the spring travel.
struct MetalClip: View {
    var opened = false
    var receiver = false
    var openness: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ClipPoseSprite(openness: openness ?? (opened ? 1 : 0), receiver: receiver)
            .frame(width: 54, height: 32)
            .frame(width: 54, height: 36)
            .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.78), value: opened)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.78), value: openness)
            .accessibilityHidden(true)
    }
}

struct ClipPoseSprite: View, Animatable {
    var openness: Double
    var receiver = false
    var animatableData: Double {
        get { openness }
        set { openness = newValue }
    }
    var body: some View {
        let amount = min(1, max(0, openness))
        let base = receiver ? "clip-brass" : "clip-silver"
        ZStack {
            sprite(base).opacity(receiver ? 1 - amount : max(0, 1 - amount * 2))
            if !receiver { sprite("clip-silver-half").opacity(1 - abs(amount * 2 - 1)) }
            sprite(base + "-open").opacity(receiver ? amount : max(0, amount * 2 - 1))
        }
    }
    private func sprite(_ name: String) -> some View {
        Image(nsImage: GeneratedAssets.image(name)).resizable().interpolation(.high).scaledToFit()
    }
}

struct ClipIcon: View {
    let item: ClipItem
    var size: CGFloat = 28
    var body: some View {
        Group {
            if let path = item.originalPath { Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().scaledToFit() }
            else { Image(systemName: item.kind.symbol).resizable().scaledToFit().foregroundStyle(item.kind == .link ? ClipStyle.accent : .secondary) }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct RailView: View {
    @ObservedObject var store: ClipStore
    let manager: WindowManager
    let overflow: Int
    @State private var receiving = false
    var body: some View {
        MetalClip(opened: receiving, receiver: true)
            .scaleEffect(x: ClipOrientation.scale(isLeft: false), y: 1)
            .overlay(DropZone(label: "", receive: { store.ingest($0) }, interaction: { receiving = $0 }, click: { store.chooseFiles() }))
            .help(overflow > 0 ? "单击添加 · 拖入夹住；更多夹项在菜单栏" : "单击添加文件 · 拖入内容夹住 · 右键操作")
            .accessibilityLabel("黄铜加号夹子，拖入内容创建新夹子")
            .contextMenu {
                ScenePicker(store: store)
                Divider()
                Button("夹住剪贴板") { store.ingest(.general) }
                Button("添加文件或文件夹…") { store.chooseFiles() }
                Divider()
                Button("夹子使用指引") { manager.showGuide() }
                Button("设置…") { manager.showSettings() }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
    }
}

struct CardSurface: View {
    @ObservedObject var store: ClipStore
    @ObservedObject var model: CardModel
    let manager: WindowManager
    @State private var resizeOriginal: NSSize?
    @State private var hovering = false
    @State private var grouping = false
    @State private var settling: CGFloat = 0
    @State private var hoverPull = PaperPull.resting
    @State private var previousHover: CGPoint?
    @State private var surfaceSize = CGSize.zero
    @State private var fold: CGFloat = 0
    @State private var hoverReset: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var item: ClipItem? { store.item(model.id) }
    var group: ClipGroup? { store.group(model.id) }
    var housing: ContentHousing { ContentHousing.forKind(item?.kind) }
    var physical: PhysicalMaterial { PhysicalMaterial.forItem(item) }
    var layers: Int { item == nil ? max(1, store.sceneMembers(model.id).count) : (physical == .document ? 3 : 1) }
    var restingJaw: Double { min(0.38, physical.jawOpening + (item == nil ? Double(min(8, layers - 1)) * 0.018 : 0)) }
    var isFolder: Bool { housing == .folder || housing == .collection }
    var motionDisabled: Bool { reduceMotion || store.state.preferences.motionIntensity == 0 }
    var placement: ClipPlacement { item?.placement ?? group?.placement ?? ClipPlacement() }
    var title: String { item?.title ?? group?.title ?? "夹项" }
    var wide: Bool { model.expanded || placement.mode == .floating }
    var isLeft: Bool { placement.side == .left }
    var folderProgress: CGFloat {
        wide && placement.mode == .docked && !model.moving && !motionDisabled ? model.revealProgress : 1
    }
    var hingeProgress: CGFloat {
        wide && placement.mode == .docked && !model.moving && !motionDisabled ? model.revealProgress : 1
    }
    var paperPull: PaperPull {
        guard !motionDisabled else { return .resting }
        let strength = CGFloat(store.state.preferences.motionIntensity) * physical.flexibility
        return PaperPull(x: (model.paperPull.x + hoverPull.x) * strength, y: (model.paperPull.y + hoverPull.y + settling) * strength)
    }
    var dragPull: PaperPull {
        guard !motionDisabled else { return .resting }
        let strength = CGFloat(store.state.preferences.motionIntensity)
        return PaperPull(x: model.paperPull.x * strength + hoverPull.x * strength * 0.25,
                         y: model.paperPull.y * strength + hoverPull.y * strength * 0.25)
    }
    var moveGrip: some View {
        MetalClip(openness: grouping || model.mergeReady ? 1 : (model.nearEdge ? 0.65 : (model.moving ? 0.35 : restingJaw)))
            // The tail stays left; the right jaw overlaps the sheet edge.
            .scaleEffect(x: ClipOrientation.scale(isLeft: isLeft), y: 1)
            .overlay(MoveHandle(begin: { model.beginMove() }, move: { model.move($0) }, end: { model.endMove() }, click: { if wide { model.close() } else { model.show() } }))
            .help("拖动夹子移动 · 靠近边缘松手夹住 · 单击收放")
            .accessibilityLabel(title + "，拖动移动，单击收放")
    }
    var foldGrip: some View {
        Color.clear.frame(width: 36, height: 36)
            .overlay {
                if hovering {
                    Path { path in
                        path.move(to: CGPoint(x: 5, y: 28))
                        path.addQuadCurve(to: CGPoint(x: 28, y: 5), control: CGPoint(x: 6, y: 7))
                    }.stroke(.gray.opacity(0.32), lineWidth: 0.7)
                        .scaleEffect(x: isLeft ? -1 : 1, y: 1).allowsHitTesting(false)
                }
            }
            .overlay(MoveHandle(begin: { hoverPull = .resting; model.interaction(true) },
                move: { delta in fold = min(1, hypot(delta.x, delta.y) / (physical == .photo ? 155 : 95)) },
                end: { fold = 0; model.interaction(false) }, label: "轻拉自由纸角卷起，松手回落"))
            .help(item?.kind == .image ? "轻拉照片角卷起 · 松手回落" : "轻拉纸角卷起 · 松手回落")
            .padding(8)
    }
    var body: some View {
        ZStack(alignment: isLeft ? .topLeading : .topTrailing) {
            ClampBackJaw(isLeft: isLeft).padding(.top, wide ? 12 : 4)
                .padding(.trailing, ClipOrientation.inset(isLeft: isLeft)).zIndex(0)
            if wide {
                VStack(spacing: 0) {
                    if let item, item.kind == .image { PhotoBody(store: store, item: item, interaction: { model.interaction($0) }, pull: paperPull, fold: fold, isLeft: isLeft) }
                    else if let item { ItemBody(store: store, item: item, manager: manager, interaction: { model.interaction($0) }) }
                    else { GroupBody(store: store, groupID: model.id, manager: manager, interaction: { model.interaction($0) }) }
                }
                .padding(.top, housing == .folder || housing == .collection ? 22 : 0)
                .background { HousingMaterial(housing: housing, id: model.id, preferences: store.state.preferences, title: title, pull: paperPull, isLeft: isLeft, material: physical, opening: folderProgress, layers: layers, dragPull: dragPull) }
                .modifier(HousingFinish(housing: housing, pull: paperPull, fold: fold, isLeft: isLeft))
                .overlay { GripContact(material: physical, isLeft: isLeft) }

                .shadow(color: .black.opacity(0.18), radius: 1.8, x: isLeft ? 1 : -1, y: 2)
                .shadow(color: .black.opacity(0.24), radius: 8 + abs(paperPull.y) * 5, x: isLeft ? 2 : -2, y: 7 + abs(paperPull.y) * 5)
                .environment(\.colorScheme, .light)
                .padding(.top, 9).padding(.bottom, 9)
                .padding(.leading, isLeft ? 15 : 9).padding(.trailing, isLeft ? 9 : 15)
                .modifier(MaterialMovement(material: physical, pull: dragPull, isLeft: isLeft, disabled: motionDisabled))
                .animation(reduceMotion ? nil : .spring(response: 0.52, dampingFraction: 0.73), value: fold)
                .overlay(alignment: isLeft ? .bottomTrailing : .bottomLeading) { if housing.isFlexible && !motionDisabled { foldGrip } }
                .overlay(alignment: isLeft ? .bottomTrailing : .bottomLeading) {
                    if hovering {
                        Button { model.close() } label: { Image(systemName: "chevron.compact.right").rotationEffect(.degrees(isLeft ? 180 : 0)).font(.system(size: 15)).padding(10) }
                            .buttonStyle(.plain).foregroundStyle(.gray).help("收回边缘")
                            .padding(isLeft ? .trailing : .leading, 43)
                    }
                }
                .overlay(alignment: isLeft ? .bottomLeading : .bottomTrailing) {
                    if hovering && placement.mode == .floating {
                        Image(systemName: "line.3.horizontal.decrease").font(.system(size: 10)).foregroundStyle(.gray).frame(width: 22, height: 22)
                            .overlay(MoveHandle(begin: { resizeOriginal = model.panel.frame.size; model.interaction(true) }, move: { delta in if let original = resizeOriginal { manager.resize(model.id, delta: delta, original: original) } }, end: { resizeOriginal = nil; model.interaction(false); store.save() }))
                    }
                }
                .modifier(HingeSheetEffect(progress: hingeProgress, isLeft: isLeft))
                .zIndex(1)
            } else {
                CompactClipView(store: store, id: model.id, isLeft: isLeft, open: { model.show() }, interaction: { model.interaction($0) })
                    .zIndex(1)
            }
            moveGrip.padding(.top, wide ? 12 : 4)
                .padding(.trailing, ClipOrientation.inset(isLeft: isLeft)).zIndex(3)
        }
        // The paper pivots at the jaw; this short movement carries both jaws
        // and the pinned paper corner together, keeping the contact intact.
        .modifier(HingeAssemblyEffect(progress: hingeProgress, isLeft: isLeft))
        .frame(width: model.sheetSize.width > 0 ? model.sheetSize.width : nil,
               height: model.sheetSize.height > 0 ? model.sheetSize.height : nil,
               alignment: isLeft ? .topLeading : .topTrailing)
        .contentShape(Rectangle())
        .background(GeometryReader { geometry in
            Color.clear.onAppear { surfaceSize = geometry.size }
                .onChange(of: geometry.size) { _, size in surfaceSize = size }
        }.allowsHitTesting(false))
        .overlay(alignment: .top) {
            LibraryDropZone(destination: model.id, store: store, highlighted: { grouping = $0; model.interaction($0) }, click: { model.show() })
                .frame(width: wide ? 130 : 44, height: 26).padding(.top, wide ? (housing == .folder || housing == .collection ? 30 : 7) : 18)
        }
        .overlay(alignment: .top) {
            if model.mergeReady {
                Text("松手夹成一组").font(.system(size: 10, weight: .medium)).padding(7)
                    .background(ClipStyle.accent, in: Capsule()).foregroundStyle(.white).padding(.top, wide ? 8 : 16).allowsHitTesting(false)
            }
        }
        .contextMenu { actions }
        .onHover { hovering = $0; model.hover($0) }
        .onContinuousHover { phase in
            switch phase {
            case .active(let point):
                if wide, !model.busy, !model.moving, !motionDisabled {
                    hoverPull = SoftSheetGeometry.hover(at: point, previous: previousHover, size: surfaceSize, isLeft: isLeft)
                    hoverReset?.cancel()
                    hoverReset = Task { @MainActor in
                        do { try await Task.sleep(nanoseconds: 90_000_000) } catch { return }
                        hoverPull = .resting
                    }
                }
                previousHover = point
            case .ended: hoverReset?.cancel(); previousHover = nil; hoverPull = .resting
            }
        }
        .help(title)
        .task(id: wide) {
            guard wide, !motionDisabled else { settling = 0; return }
            settling = 0.25
            do { try await Task.sleep(nanoseconds: 70_000_000) } catch { return }
            settling = 0
        }
        .onAppear { if let item, item.kind == .image { store.loadThumbnail(item) } }
        .onDisappear { hoverReset?.cancel() }
        .onChange(of: store.images[model.id]?.size) { _, _ in manager.layout(model) }
        .tint(ClipStyle.accent)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isLeft ? .topLeading : .topTrailing)
    }
    @ViewBuilder var actions: some View {
        Button("编辑名称与备注") { manager.edit(model.id) }
        if let item {
            Menu("夹入材料组") {
                ForEach(store.state.groups.filter { $0.id != item.groupID }) { group in
                    Button(group.title) { _ = store.combine(item.id, with: group.id) }
                }
                Button("建立新的材料组") { store.createGroup([item.id], title: "材料夹 · " + String(item.title.prefix(20))) }
            }
        }
        if let item {
            Button("打开") { store.open(item) }.disabled(item.kind == .text)
            Button("复制") { store.copy(item) }
            if let url = store.fileURL(item) {
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                Button("复制路径") { store.copyPath(item) }
                Button("快速预览") { PreviewController.shared.show(url) }
            }
            if item.bookmark != nil { Button("重新关联位置…") { store.relink(item) } }
            if item.groupID != nil { Button("移出项目组") { store.update(item.id) { $0.groupID = nil } } }
            Button("上移") { store.reorder(item.id, by: -1) }
            Button("下移") { store.reorder(item.id, by: 1) }
            Divider()
            Button("取消固定") { store.remove(item.id) }
        } else { Button("解散项目组（保留成员）") { store.dissolve(model.id) } }
    }
}

struct PhotoBody: View {
    @ObservedObject var store: ClipStore
    let item: ClipItem
    var interaction: (Bool) -> Void
    var pull = PaperPull.resting
    var fold: CGFloat = 0
    var isLeft = false
    var body: some View {
        Group {
            if let image = store.images[item.id] {
                SoftImageSurface(image: image, pull: pull, isLeft: isLeft)
                    .aspectRatio(image.size, contentMode: .fit)
                    .modifier(PhotoFinish(pull: pull, isLeft: isLeft))
                    .overlay(ContentDragHandle(item: item, store: store, interaction: interaction, showLabel: false))
                    .help("轻点复制，拖动照片交给其他应用；右键查看更多操作")
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo").font(.system(size: 30, weight: .light))
                    Text(store.status(item) ?? "正在显影…").font(.system(size: 11))
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.thinMaterial)
            }
        }.frame(maxWidth: .infinity, alignment: .top)
    }
}

struct ItemBody: View {
    @ObservedObject var store: ClipStore
    let item: ClipItem
    let manager: WindowManager
    var interaction: (Bool) -> Void = { _ in }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if item.kind == .file || item.kind == .link {
                HStack(spacing: 7) { ClipIcon(item: item, size: 17); Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(2); Spacer(minLength: 0) }
            }
            if let status = store.status(item) {
                Label(status, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(.orange)
                if item.bookmark != nil { Button("重新关联位置…") { store.relink(item) } }
            }
            if item.kind == .folder { FolderBody(store: store, item: item, interaction: interaction) }
            else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if item.kind == .image || item.kind == .file {
                            Group {
                                if [.audio, .film, .archive].contains(PhysicalMaterial.forItem(item)) {
                                    FileObjectBadge(material: PhysicalMaterial.forItem(item), extensionLabel: URL(fileURLWithPath: item.originalPath ?? item.title).pathExtension)
                                }
                                else if let image = store.images[item.id] { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity).frame(minHeight: 100, maxHeight: 220) }
                                else { ClipIcon(item: item, size: 72).frame(maxWidth: .infinity).frame(height: 130) }
                            }.overlay(ContentDragHandle(item: item, store: store, interaction: interaction, showLabel: false))
                                .onAppear { store.loadThumbnail(item) }
                        } else if let text = item.text {
                            Text(text).font(.system(size: 14)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        } else if let link = item.link {
                            Image(systemName: "link.circle.fill").font(.system(size: 45)).foregroundStyle(ClipStyle.accent).frame(maxWidth: .infinity).padding(.top, 16)
                            Text(link).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: .infinity)
            }
            ContentDragHandle(item: item, store: store, interaction: interaction).frame(height: 22)
            if let message = store.message {
                Text(message).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
            }
            if !item.note.isEmpty || !item.tags.isEmpty { Button { manager.edit(item.id) } label: {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "tag").font(.system(size: 11))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.note.isEmpty ? "添一句用途备注…" : item.note).font(.system(size: 11)).lineLimit(2)
                        if !item.tags.isEmpty { Text(item.tags.joined(separator: " · ")).font(.system(size: 10)).foregroundStyle(.secondary) }
                    }; Spacer(minLength: 0)
                    Image(systemName: "pencil").font(.system(size: 10)).foregroundStyle(.secondary)
                }.padding(9).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }.buttonStyle(.plain).help("编辑名称与备注") }

        }.padding(18).padding(.top, 17).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    var source: String {
        if item.assetName != nil { return "来源：剪贴板图片 · 应用内副本" }
        if item.kind == .text { return "来源：主动夹入的文字 · 可编辑副本" }
        if item.kind == .link { return "来源：网页链接" }
        return "原文件引用：" + (store.fileURL(item)?.path ?? item.originalPath ?? "不可用")
    }
}

struct GroupBody: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: ClipStore
    let groupID: UUID
    let manager: WindowManager
    var interaction: (Bool) -> Void
    @State private var selected: UUID?
    var body: some View {
        VStack(spacing: 0) {
            if let selected, let item = store.item(selected), item.removedAt == nil, item.groupID == groupID, store.visibleInScene(item.id) {
                HStack { Button("返回项目夹", systemImage: "chevron.left") { self.selected = nil }; Spacer(); Button("拉出常驻") { manager.float(item.id) } }.controlSize(.small).padding(10)
                ItemBody(store: store, item: item, manager: manager, interaction: interaction)
            } else {
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(store.sceneMembers(groupID)) { item in
                            HStack(spacing: 10) {
                                Group {
                                    if item.kind == .image, let image = store.images[item.id] {
                                        Image(nsImage: image).resizable().scaledToFill().frame(width: 28, height: 28).clipped().modifier(PhotoFinish())
                                    } else { ClipIcon(item: item) }
                                }.onAppear { if item.kind == .image { store.loadThumbnail(item) } }
                                    .overlay(ContentDragHandle(item: item, store: store, interaction: interaction, showLabel: false))
                                    .help("拖出图标，交给其他应用")
                                Button { selected = item.id } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                        Text(item.placement.mode == .floating ? "留在屏幕" : (item.note.isEmpty ? item.kind.title : item.note)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                    }.frame(maxWidth: .infinity, alignment: .leading)
                                }.buttonStyle(.plain)
                                Menu {
                                    Button("拉出常驻（保留分组）") { manager.float(item.id) }
                                    Button("从组中抽出") { store.extract(item.id) }
                                    Button("上移") { store.reorder(item.id, by: -1) }
                                    Button("下移") { store.reorder(item.id, by: 1) }
                                } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                            }.padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
                                .transition(.modifier(active: HingeSheetEffect(progress: 0, isLeft: true), identity: HingeSheetEffect(progress: 1, isLeft: true)))
                        }
                        if store.sceneMembers(groupID).isEmpty { Text("项目夹里还没有内容。\n在全部夹项中选择内容加入。 ").foregroundStyle(.secondary).padding(20) }
                    }.padding(12).animation(reduceMotion || store.state.preferences.motionIntensity == 0 ? nil : .spring(response: HingeReveal.duration, dampingFraction: 0.72), value: store.sceneMembers(groupID).map(\.id))
                }
                Text("点击查看 · 拖出图标交接 · ⋯ 抽出或排序").font(.system(size: 10)).foregroundStyle(.secondary).padding(12).padding(.bottom, 10)
            }
        }.frame(maxHeight: .infinity)
    }
}

struct FolderEntry: Identifiable {
    let url: URL
    let folder: Bool
    var id: String { url.path }
}
struct FolderBody: View {
    @ObservedObject var store: ClipStore
    let item: ClipItem
    var interaction: (Bool) -> Void
    @State private var directory: URL?
    @State private var entries: [FolderEntry] = []
    @State private var failure: String?
    @State private var loading = false
    @State private var generation = UUID()
    var root: URL? { store.fileURL(item) }
    var current: URL? { directory ?? root }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Button { if let directory, let root, directory != root { self.directory = directory.deletingLastPathComponent(); reload() } } label: { Image(systemName: "chevron.left") }.disabled(current == root)
                Text(current?.lastPathComponent ?? item.title).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer()
                Button { reload() } label: { Image(systemName: "arrow.clockwise") }.help("刷新文件夹")
                Button("Finder") { if let current { NSWorkspace.shared.open(current) } }
            }.controlSize(.small).buttonStyle(.bordered)
            Text(current?.path ?? "目录不可用").font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(2).textSelection(.enabled)
            ScrollView {
                VStack(spacing: 2) {
                    if loading { ProgressView().controlSize(.small).padding(20) }
                    else if let failure { Text(failure).font(.system(size: 11)).foregroundStyle(.orange).padding(12) }
                    else if entries.isEmpty { Text("这个文件夹是空的").font(.system(size: 11)).foregroundStyle(.secondary).padding(20) }
                    ForEach(entries) { entry in
                        HStack(spacing: 6) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path)).resizable().frame(width: 18, height: 18)
                            Button { if entry.folder { directory = entry.url; reload() } else { NSWorkspace.shared.open(entry.url) } } label: { Text(entry.url.lastPathComponent).font(.system(size: 11)).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain)
                            Menu {
                                Button("打开") { NSWorkspace.shared.open(entry.url) }
                                Button("快速预览") { PreviewController.shared.show(entry.url) }
                                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize()
                            ContentDragHandle(item: entryItem(entry), store: store, interaction: interaction, showLabel: false).frame(width: 18, height: 22).overlay(Image(systemName: "arrow.up.forward").font(.system(size: 9)).foregroundStyle(.secondary).allowsHitTesting(false)).help("拖出此项")
                        }.padding(.vertical, 5).padding(.horizontal, 4)
                    }
                }
            }.frame(minHeight: 60, maxHeight: .infinity)
            if let current {
                DropZone(label: "＋ 复制到此文件夹 · 保留两份", fileOnly: true, receive: { board in
                    if let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] { store.startCopy(urls, to: current, for: item.id) }
                }, interaction: interaction).frame(height: 34)
                if let progress = store.copies[item.id] {
                    VStack(alignment: .leading, spacing: 4) {
                        if progress.running {
                            ProgressView(value: Double(progress.completed), total: Double(max(1, progress.total)))
                            HStack { Text("\(progress.completed)/\(progress.total) · 复制中"); Spacer(); Button("停止后续项") { store.copies[item.id]?.cancelRequested = true } }
                        } else {
                            HStack { Text("已完成 \(progress.completed)/\(progress.total)"); Spacer(); if progress.results.contains(where: { $0.error != nil }) { Button("重试失败项") { store.retryCopy(item.id) } } }
                        }
                        Text(progress.target.path).lineLimit(1).help(progress.target.path).foregroundStyle(.secondary)
                        ScrollView { VStack(alignment: .leading, spacing: 3) { ForEach(progress.results) { result in
                            Text(result.error.map { "\(result.source.lastPathComponent)：\($0)" } ?? "✓ \(result.destination?.lastPathComponent ?? "")").foregroundStyle(result.error == nil ? Color.secondary : Color.orange).textSelection(.enabled)
                        } } }.frame(maxHeight: 48)
                    }.font(.system(size: 10)).controlSize(.mini)
                        .onChange(of: progress.running) { _, running in if !running { reload() } }
                }
            }
        }.onAppear { reload() }
            .onChange(of: item.originalPath) { _, _ in directory = nil; reload() }
            .onChange(of: store.state.preferences.showHiddenFiles) { _, _ in reload() }
    }
    func entryItem(_ entry: FolderEntry) -> ClipItem {
        var clip = ClipItem(kind: entry.folder ? .folder : .file, title: entry.url.lastPathComponent); clip.originalPath = entry.url.path; return clip
    }
    func reload() {
        guard let url = current else { failure = "原目录不可用，请重新关联。"; return }
        generation = UUID(); let token = generation
        loading = true; failure = nil; entries = []
        let hidden = store.state.preferences.showHiddenFiles
        Task {
            let result: Result<[FolderEntry], Error> = await Task.detached(priority: .userInitiated) {
                Result {
                    let urls = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: hidden ? [] : [.skipsHiddenFiles])
                    return urls.map { FolderEntry(url: $0, folder: (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) }.sorted { a, b in a.folder != b.folder ? a.folder : a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending }
                }
            }.value
            guard token == generation else { return }; loading = false
            switch result { case .success(let values): entries = values; case .failure(let error): failure = error.localizedDescription }
        }
    }
}
