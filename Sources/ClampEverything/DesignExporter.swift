import AppKit
import SwiftUI
import ClampCore

@MainActor enum DesignExporter {
    static func demoImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 800, height: 450))
        image.lockFocus()
        NSColor(calibratedRed: 0.91, green: 0.94, blue: 0.93, alpha: 1).setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 800, height: 450)).fill()
        let paragraph = NSMutableParagraphStyle(); paragraph.alignment = .left
        ("夹住 → 看见 → 使用" as NSString).draw(at: NSPoint(x: 45, y: 370), withAttributes: [.font: NSFont.systemFont(ofSize: 30, weight: .medium), .foregroundColor: NSColor(calibratedRed: 0.23, green: 0.4, blue: 0.39, alpha: 1)])
        for (index, title) in ["常用项目", "当前参照", "交接材料"].enumerated() {
            let rect = NSRect(x: 45 + index * 250, y: 70, width: 210, height: 230)
            NSColor.white.setFill(); NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).fill()
            NSColor.gray.withAlphaComponent(0.3).setStroke(); NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14).stroke()
            (title as NSString).draw(at: NSPoint(x: rect.minX + 20, y: rect.maxY - 50), withAttributes: [.font: NSFont.systemFont(ofSize: 21, weight: .semibold), .foregroundColor: NSColor.darkGray])
            for line in 0..<4 {
                NSColor.gray.withAlphaComponent(0.15).setFill()
                let lineY = rect.minY + 35 + CGFloat(line) * 30
                let lineRect = NSRect(x: rect.minX + 20, y: lineY, width: line == 3 ? 100 : 165, height: 8)
                NSBezierPath(roundedRect: lineRect, xRadius: 4, yRadius: 4).fill()
            }
        }
        image.unlockFocus(); return image
    }
    static func exportWorkbench(store: ClipStore, manager: WindowManager, to output: URL) async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let folder = store.active.first { $0.kind == .folder }!
        let note = store.active.first { $0.kind == .text }!
        let photo = store.active.first { $0.kind == .image }!
        let group = store.state.groups.first!
        _ = store.createScene(title: "论文写作", ids: Set(store.active.map(\.id)))
        _ = store.createScene(title: "图片参考", ids: [photo.id])
        store.selectScene(store.state.scenes.first?.id)
        let groupModel = CardModel(id: group.id, manager: manager); groupModel.expanded = true; groupModel.revealProgress = 1
        try await snapshot(VStack(alignment: .leading, spacing: 22) {
            Text("手边的临时工作台").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 22) {
                    Text("收起只留小夹子").font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
                    ForEach([folder.id, note.id, photo.id, group.id], id: \.self) { id in
                        CompactClipView(store: store, id: id, isLeft: false, open: {}, interaction: { _ in })
                            .frame(width: 64, height: 44)
                            .overlay(alignment: .topTrailing) { MetalClip().padding(.trailing, 10).padding(.top, 4) }
                    }
                }.frame(width: 165)
                CardSurface(store: store, model: groupModel, manager: manager).frame(width: 320, height: 460)
                SceneSettingsView(store: store).padding(20).frame(width: 370, height: 460)
                    .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
            }
        }.padding(30).background(Color(red: 0.24, green: 0.31, blue: 0.35)), size: NSSize(width: 975, height: 560), to: output.appendingPathComponent("24-workbench.png"))
        try await snapshot(HStack(spacing: 25) {
            ForEach([CGFloat(0.2), 0.6, 1], id: \.self) { progress in
                VStack(spacing: 16) {
                    ZStack {
                        FolderMaterial(tint: .kraft, title: "项目资料")
                        VStack(alignment: .leading, spacing: 18) {
                            Label("研究笔记.txt", systemImage: "doc.text")
                            Label("参考图片", systemImage: "folder.fill")
                        }.font(.system(size: 12)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(24).padding(.top, 35)
                    }.frame(width: 250, height: 300).modifier(HingeSheetEffect(progress: progress, isLeft: false))
                    Text(progress < 0.5 ? "绕夹点翻出" : (progress == 1 ? "展开完成" : "回摆落稳")).font(.system(size: 12))
                }
            }
        }.padding(30).background(Color(white: 0.94)), size: NSSize(width: 860, height: 390), to: output.appendingPathComponent("25-folder-reveal.png"))
    }
    static func exportCustomization(store: ClipStore, manager: WindowManager, to output: URL) async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let folder = store.active.first { $0.kind == .folder }!
        let note = store.active.first { $0.kind == .text }!
        let link = store.active.first { $0.kind == .link }!
        let cards = [folder, note, link].map { item -> CardModel in
            let model = CardModel(id: item.id, manager: manager)
            model.expanded = true; model.revealProgress = 1
            return model
        }
        try await snapshot(VStack(alignment: .leading, spacing: 18) {
            Text("每种内容，都有自己的形态").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
            Text("文件夹 · 文字便笺 · 链接卡片").font(.system(size: 13)).foregroundStyle(.white.opacity(0.7))
            HStack(alignment: .top, spacing: 20) {
                ForEach(cards, id: \.id) { model in
                    CardSurface(store: store, model: model, manager: manager).frame(width: 310, height: 440)
                }
            }
        }.padding(30).background(Color(red: 0.24, green: 0.31, blue: 0.35)), size: NSSize(width: 1030, height: 560), to: output.appendingPathComponent("20-content-housings.png"))
        try await snapshot(MaterialCatalogView(store: store).padding(25).background(Color(nsColor: .windowBackgroundColor)), size: NSSize(width: 550, height: 1580), to: output.appendingPathComponent("30-material-catalog.png"))
        try await snapshot(SettingsView(store: store, manager: manager).materials.padding(25).background(Color(nsColor: .windowBackgroundColor)), size: NSSize(width: 490, height: 650), to: output.appendingPathComponent("21-custom-materials.png"))
        try await snapshot(SettingsView(store: store, manager: manager).habits.padding(25).background(Color(nsColor: .windowBackgroundColor)), size: NSSize(width: 490, height: 650), to: output.appendingPathComponent("22-custom-behavior.png"))
        try await snapshot(HStack(spacing: 25) {
            ForEach(FolderTint.allCases, id: \.self) { tint in
                VStack(spacing: 16) {
                    FolderMaterial(tint: tint, title: "项目资料").frame(width: 250, height: 230)
                    Text(tint.title).font(.system(size: 13))
                }
            }
        }.padding(30).background(Color(white: 0.94)), size: NSSize(width: 860, height: 330), to: output.appendingPathComponent("23-folder-palettes.png"))
    }
    static func export(store: ClipStore, manager: WindowManager, to output: URL) async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        guard let folder = store.active.first(where: { $0.kind == .folder }), let image = store.active.first(where: { $0.kind == .image }), let group = store.state.groups.first else { throw LibraryError.missingDirectory }
        let originalPlacement = folder.placement
        for side in [ClipSide.left, .right] {
            store.update(folder.id) { $0.placement.mode = .docked; $0.placement.side = side }
            let model = CardModel(id: folder.id, manager: manager); model.expanded = true; model.revealProgress = 1
            try await snapshot(CardSurface(store: store, model: model, manager: manager).frame(width: 320, height: 430).padding(22).background(Color(red: 0.34, green: 0.43, blue: 0.49)), size: NSSize(width: 364, height: 474), to: output.appendingPathComponent("16-attachment-\(side == .left ? "left" : "right").png"))
        }
        store.update(folder.id) { $0.placement = originalPlacement }
        try await snapshot(ClipGuideView(playback: GuidePlayback(), examples: GuideExamples()).padding(24).background(Color(red: 0.15, green: 0.24, blue: 0.31)), size: NSSize(width: 828, height: 608), to: output.appendingPathComponent("18-clip-guide.png"))
        try await snapshot(HingeRevealStudy(), size: NSSize(width: 960, height: 490), to: output.appendingPathComponent("19-hinge-reveal.png"))
        try await snapshot(SoftSheetStudy(photo: store.images[image.id] ?? demoImage()), size: NSSize(width: 1000, height: 600), to: output.appendingPathComponent("17-soft-sheet.png"))
        try await snapshot(ClipMotionStudy(), size: NSSize(width: 960, height: 650), to: output.appendingPathComponent("15-clip-motion.png"))
        try await snapshot(MaterialStudy(store: store, manager: manager, ids: store.active.map(\.id), photo: image.id), size: NSSize(width: 960, height: 560), to: output.appendingPathComponent("13-paper-photo.png"))
        try await snapshot(ZStack {
            Color(red: 0.12, green: 0.15, blue: 0.19)
            VStack(alignment: .leading, spacing: 12) {
                Text("参考资料").font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 14) {
                    Image(systemName: "doc.text.fill").font(.system(size: 30)).foregroundStyle(.white.opacity(0.8))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("项目研究笔记.pdf").font(.system(size: 16, weight: .medium))
                        Text("文稿 · 2.4 MB").font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }.padding(20).frame(width: 300, height: 90)
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 7))
                    .overlay { TargetGlowView(animated: false).padding(-14) }
            }.foregroundStyle(.white).environment(\.colorScheme, .dark)
        }, size: NSSize(width: 460, height: 230), to: output.appendingPathComponent("32-target-glow.png"))
        let pickupPose = CursorClipPose()
        pickupPose.gripping = true; pickupPose.hasMaterial = true; pickupPose.material = .folder; pickupPose.pickupMessage = "论文项目"; pickupPose.nearEdge = true
        try await snapshot(VStack(spacing: 12) {
            CursorClipView(pose: pickupPose)
            PickupHintView(pose: pickupPose).frame(width: 240, height: 62)
        }.padding(24).background(Color(white: 0.88)), size: NSSize(width: 310, height: 180), to: output.appendingPathComponent("31-pickup-feedback.png"))
        try await snapshot(HoldSettingsView(store: store, controller: manager.pointClamp).padding(28).background(Color(nsColor: .windowBackgroundColor)), size: NSSize(width: 450, height: 580), to: output.appendingPathComponent("14-hold-settings.png"))
        let states: [(String, String, UUID, Bool)] = [
            ("01-edge", "边缘收起 · 常用入口留在手边", folder.id, false),
            ("02-folder", "文件夹展开 · 浏览与复制分开", folder.id, true),
            ("03-image", "截图常驻 · 参照时继续输入", image.id, true),
            ("04-project", "混合项目夹 · 一组材料共用一个夹子", group.id, true)
        ]
        for (name, title, id, expanded) in states {
            let model = CardModel(id: id, manager: manager); model.expanded = expanded; model.revealProgress = expanded ? 1 : 0
            if id == folder.id { store.update(id) { $0.placement.mode = .docked } }
            try await snapshot(DesignCanvas(title: title, store: store, model: model, manager: manager, expanded: expanded), size: NSSize(width: 800, height: 600), to: output.appendingPathComponent(name + ".png"))
        }
        let paper = store.active.first { $0.kind == .text }!
        let paperModel = CardModel(id: paper.id, manager: manager); paperModel.expanded = true; paperModel.revealProgress = 1
        let edgeModel = CardModel(id: folder.id, manager: manager)
        try await snapshot(EdgeStudy(store: store, manager: manager, paper: paperModel, edge: edgeModel), size: NSSize(width: 960, height: 640), to: output.appendingPathComponent("12-edge-material.png"))
        let text = store.active.first { $0.kind == .text }!
        store.update(text.id) { $0.removedAt = Date() }
        try await snapshot(RecoveryScene(store: store), size: NSSize(width: 620, height: 420), to: output.appendingPathComponent("06-recovery.png"))
        // Liquid Glass is composited by WindowServer, not cacheDisplay. Preserve
        // 07-settings.png, captured from the real settings window with computer use.
        if #unavailable(macOS 26.0) {
            try await snapshot(SettingsView(store: store, manager: manager), size: NSSize(width: 720, height: 530), to: output.appendingPathComponent("07-settings.png"))
        }
        store.restore(text.id)
        store.images[image.id] = demoImage()
        let model = CardModel(id: image.id, manager: manager); model.expanded = true; model.revealProgress = 1
        try await snapshot(DesignCanvas(title: "深色模式 · 内容清晰，材质克制", store: store, model: model, manager: manager, expanded: true).environment(\.colorScheme, .dark), size: NSSize(width: 800, height: 600), to: output.appendingPathComponent("08-dark.png"), dark: true)
        if let folderURL = store.fileURL(folder) {
            let source = folderURL.appendingPathComponent("研究笔记.txt")
            let copied = await store.copyQueue.copy(source, into: folderURL)
            let failed = await store.copyQueue.copy(folderURL.appendingPathComponent("已离线的文件.txt"), into: folderURL)
            var progress = CopyProgress(target: folderURL, total: 2)
            progress.completed = 2; progress.results = [copied, failed]; progress.running = false
            store.copies[folder.id] = progress
            let folderModel = CardModel(id: folder.id, manager: manager); folderModel.expanded = true; folderModel.revealProgress = 1
            store.update(folder.id) { $0.placement.height = 490 }
            try await snapshot(CardSurface(store: store, model: folderModel, manager: manager).frame(width: 320, height: 490).padding(35).background(Color(nsColor: .windowBackgroundColor)), size: NSSize(width: 390, height: 560), to: output.appendingPathComponent("10-copy-results.png"))
        }
        var missing = ClipItem(kind: .file, title: "待重新关联的材料.pdf")
        missing.originalPath = "/Volumes/工作盘/待重新关联的材料.pdf"
        missing.bookmark = folder.bookmark
        // Use an actual missing bookmark target instead of misrepresenting a working reference.
        let vanished = store.storage.root.appendingPathComponent("待重新关联的材料.pdf")
        try Data("示例".utf8).write(to: vanished)
        missing.bookmark = try FileReference.bookmark(for: vanished); missing.originalPath = vanished.path
        try FileManager.default.removeItem(at: vanished)
        store.state.items.append(missing)
        let missingModel = CardModel(id: missing.id, manager: manager); missingModel.expanded = true; missingModel.revealProgress = 1
        try await snapshot(CardSurface(store: store, model: missingModel, manager: manager).frame(width: 320, height: 420).padding(35).background(Color(nsColor: .windowBackgroundColor)), size: NSSize(width: 390, height: 490), to: output.appendingPathComponent("11-missing-reference.png"))
        print("Exported native interface states (Liquid Glass settings captured separately) to \(output.path)")
    }
    static func snapshot<V: View>(_ view: V, size: NSSize, to url: URL, dark: Bool = false) async throws {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: 80, y: 80), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view); host.frame = NSRect(origin: .zero, size: size); window.contentView = host; window.orderFrontRegardless()
        // Let onAppear, AppKit bridge views and folder enumeration complete before caching.
        try await Task.sleep(nanoseconds: 500_000_000)
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw LibraryError.unsafeAsset }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw LibraryError.unsafeAsset }
        try data.write(to: url, options: .atomic); window.orderOut(nil)
    }
}

struct HingeRevealStudy: View {
    private let id = UUID(uuidString: "A31A31A3-1111-4444-8888-000000000001")!
    var body: some View {
        HStack(spacing: 35) {
            ForEach(0..<3) { step in
                VStack(spacing: 16) {
                    ZStack(alignment: .topTrailing) {
                        HangingBackJaw()
                            .modifier(SuspendedClipScale(scale: ClipOrientation.displayScale))
                            .padding(.top, ClipOrientation.top).padding(.trailing, ClipOrientation.inset(isLeft: false))
                        PaperMaterial(id: id)
                            .overlay(alignment: .topLeading) {
                                VStack(alignment: .leading, spacing: 18) {
                                    Text("从夹住的角，\n轻轻翻出来。").font(.system(size: 18, weight: .medium))
                                    Text("夹子带动纸角，\n自由边回摆落稳。").font(.system(size: 12)).lineSpacing(4)
                                }.padding(24).padding(.top, 16)
                            }
                            .shadow(color: .black.opacity(0.3), radius: 10, y: 8)
                            .padding(.top, ClipOrientation.paperTop).padding(.trailing, 15).padding(.leading, 9).padding(.bottom, 9)
                        HangingMetalClip()
                            .modifier(SuspendedClipScale(scale: ClipOrientation.displayScale))
                            .padding(.top, ClipOrientation.top).padding(.trailing, ClipOrientation.inset(isLeft: false))
                    }
                    .frame(width: 260, height: 330)
                    .modifier(HingeSheetEffect(progress: [CGFloat(0), 0.55, 1][step], isLeft: false))
                    .modifier(HingeAssemblyEffect(progress: [CGFloat(0), 0.55, 1][step], isLeft: false))
                    .overlay(alignment: .topTrailing) { SuspensionNail().padding(.top, ClipOrientation.compactHookY - 3).padding(.trailing, ClipOrientation.edgeAnchor - 3) }
                    .frame(width: 260, height: 390, alignment: .topTrailing).clipped()
                    Text(["折在边缘", "绕尾环翻出", "回摆落稳"][step]).font(.system(size: 12)).foregroundStyle(.white.opacity(0.8))
                }
            }
        }.padding(35).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.15, green: 0.24, blue: 0.31)).environment(\.colorScheme, .light)
    }
}

struct SoftSheetStudy: View {
    let photo: NSImage
    private let id = UUID(uuidString: "A31A31A3-1111-4444-8888-000000000001")!
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("轻拉自由角，松手回落。").font(.system(size: 27, weight: .light))
            HStack(alignment: .top, spacing: 38) {
                sample(title: "纸张 · 静止", photo: false, pull: .resting, fold: 0)
                sample(title: "纸张 · 随手弯折", photo: false, pull: PaperPull(x: 0.85, y: 0.8), fold: 0.8)
                sample(title: "照片 · 柔软背面", photo: true, pull: PaperPull(x: -0.85, y: 0.85), fold: 0.95)
            }
            Text("固定受夹的角 · 轻摆自由边 · 保留原有复制与拖出动作").font(.system(size: 12)).foregroundStyle(.secondary)
        }.padding(46).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.77, green: 0.81, blue: 0.79)).environment(\.colorScheme, .light)
    }
    func sample(title: String, photo isPhoto: Bool, pull: PaperPull, fold: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ZStack(alignment: .topTrailing) {
                ClampBackJaw(isLeft: false).padding(.top, 12).padding(.trailing, 10)
                Group {
                    if isPhoto { SoftImageSurface(image: photo, pull: pull).modifier(PhotoFinish(pull: pull)) }
                    else {
                        PaperMaterial(id: id, pull: pull)
                            .overlay(alignment: .topLeading) {
                                VStack(alignment: .leading, spacing: 15) {
                                    Text("留一点空间。 ").font(.system(size: 18, weight: .medium))
                                    Text("给手边的东西。\n\n细纤维、柔软的弯折，\n和轻轻落下的自由边。").font(.system(size: 12)).lineSpacing(5)
                                }.padding(22).padding(.top, 12)
                            }
                    }
                }
                .aspectRatio(isPhoto ? photo.size : NSSize(width: 251, height: 332), contentMode: .fit)
                .overlay { SheetLighting(pull: pull, isLeft: false, photo: isPhoto) }
                .clipShape(SoftSheetMask(pull: pull, fold: fold))
                .overlay { SheetFoldFace(amount: fold, pull: pull, isLeft: false, photo: isPhoto) }
                .shadow(color: .black.opacity(0.15), radius: 6, x: -1, y: 5)
                .padding(.top, 9).padding(.trailing, 15).padding(.leading, 9).padding(.bottom, 9)
                MetalClip().scaleEffect(x: ClipOrientation.scale(isLeft: false), y: 1).padding(.top, 12).padding(.trailing, 10)
            }.frame(width: 275, height: 350)
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }
}

struct DesignCanvas: View {
    let title: String
    @ObservedObject var store: ClipStore
    @ObservedObject var model: CardModel
    let manager: WindowManager
    let expanded: Bool
    @Environment(\.colorScheme) var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 25) {
            HStack { Text("屏幕夹子").font(.system(size: 12, weight: .semibold)); Spacer(); Text("原生界面 · 1.0").font(.system(size: 11)).foregroundStyle(.secondary) }
            Text(title).font(.system(size: 23, weight: .medium))
            HStack(alignment: .center, spacing: 55) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(expanded ? "需要时，拉到眼前。" : "收起来，也能找得到。").font(.system(size: 17, weight: .medium))
                    Text("抓住金属夹 → 调整位置\n拖出内容 → 交给其他应用\n点击纸签 → 说明用途").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(8)
                    Text("文件保留原位\n主动夹入 · 本地保存").font(.system(size: 11)).foregroundStyle(.tertiary).lineSpacing(5).padding(.top, 10)
                }.frame(width: 265, alignment: .leading)
                Spacer(minLength: 0)
                CardSurface(store: store, model: model, manager: manager).frame(width: expanded ? 320 : 64, height: expanded ? 420 : 44)
                    .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
            }.frame(maxHeight: .infinity)
        }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(scheme == .dark ? Color(nsColor: .windowBackgroundColor) : Color(red: 0.94, green: 0.95, blue: 0.93))
    }
}
struct RecoveryScene: View {
    @ObservedObject var store: ClipStore
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Label("恢复区", systemImage: "arrow.uturn.backward").font(.system(size: 25, weight: .medium))
            Text("取消固定后，内部副本保留 7 天。\n到期清理只涉及应用副本，原文件始终保留。").font(.system(size: 13)).foregroundStyle(.secondary).lineSpacing(6)
            ForEach(store.recovery) { item in
                HStack(spacing: 12) { ClipIcon(item: item); VStack(alignment: .leading, spacing: 5) { Text(item.title).font(.system(size: 14, weight: .medium)); Text("保留至 " + (item.expiresAt()?.formatted(date: .abbreviated, time: .shortened) ?? "")).font(.system(size: 11)).foregroundStyle(.secondary) }; Spacer(); Button("恢复") { store.restore(item.id) } }.padding(16).background(ClipStyle.paper, in: RoundedRectangle(cornerRadius: 9))
            }
            Spacer()
        }.padding(35).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color(nsColor: .windowBackgroundColor)).tint(ClipStyle.accent)
    }
}

struct EdgeStudy: View {
    @ObservedObject var store: ClipStore
    let manager: WindowManager
    let paper: CardModel
    let edge: CardModel
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color(red: 0.77, green: 0.80, blue: 0.78)
            VStack(alignment: .leading, spacing: 12) {
                Text("夹在边上。 ").font(.system(size: 36, weight: .light))
                Text("一枚夹子，一张纸。 ").font(.system(size: 14)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(.leading, 80)
            RailView(store: store, manager: manager, overflow: 0).frame(width: 58, height: 44).padding(.top, 30)
            CardSurface(store: store, model: edge, manager: manager).frame(width: 64, height: 44).padding(.top, 92)
            CardSurface(store: store, model: paper, manager: manager).frame(width: 300, height: 350).padding(.top, 166)
        }
    }
}

struct MaterialStudy: View {
    @ObservedObject var store: ClipStore
    let manager: WindowManager
    let ids: [UUID]
    let photo: UUID
    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("每一张，都不一样。").font(.system(size: 28, weight: .light))
                    Text("黄铜接收夹 / 独立纸纹 / 实体照片").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                MetalClip(receiver: true)
            }
            HStack(alignment: .top, spacing: 26) {
                ForEach(Array(ids.prefix(2).enumerated()), id: \.element) { index, id in
                    ZStack(alignment: .topTrailing) {
                        PaperMaterial(id: id)
                        VStack(alignment: .leading, spacing: 16) {
                            Text(index == 0 ? "留给今天。" : "关于明天。").font(.system(size: 20, weight: .medium))
                            Text(index == 0 ? "一点折痕，\n一些细小的纤维。\n\n把想法留在手边。" : "每张纸的边缘和纹理\n都属于它自己。\n\n下次打开，还是这一张。").font(.system(size: 13)).lineSpacing(7)
                            Spacer()
                        }.padding(24).padding(.top, 10)
                        MetalClip().scaleEffect(x: ClipOrientation.scale(isLeft: false), y: 1).offset(x: -1, y: 4)
                    }.frame(width: 238, height: 330).environment(\.colorScheme, .light)
                }
                VStack(alignment: .leading, spacing: 18) {
                    if let image = store.images[photo] {
                        Image(nsImage: image).resizable().scaledToFit().modifier(PhotoFinish())
                            .overlay(alignment: .topTrailing) { MetalClip().scaleEffect(x: ClipOrientation.scale(isLeft: false), y: 1).offset(x: -1, y: 4) }
                    }
                    Text("照片，不垫纸。 ").font(.system(size: 16, weight: .medium))
                    Text("薄薄的相片厚度，\n沿着边缘的一点反光。").font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(6)
                }.frame(width: 300)
            }
        }.padding(48).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.75, green: 0.79, blue: 0.77))
    }
}


struct ClipMotionStudy: View {
    private let ids = [
        UUID(uuidString: "A31A31A3-1111-4444-8888-000000000001")!,
        UUID(uuidString: "A31A31A3-1111-4444-8888-000000000002")!,
        UUID(uuidString: "A31A31A3-1111-4444-8888-000000000003")!
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 30) {
            Text("张开，夹住，轻轻落下。").font(.system(size: 30, weight: .light))
            HStack(spacing: 90) {
                ForEach(0..<3) { index in
                    VStack(spacing: 12) {
                        MetalClip(openness: Double(index) / 2).scaleEffect(1.7).frame(width: 160, height: 60)
                        Text(["夹紧", "半闭合", "张开"][index]).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }.frame(maxWidth: .infinity)
            HStack(alignment: .top, spacing: 35) {
                ForEach(0..<3) { index in
                    let pull = index == 1 ? PaperPull(x: 0.9, y: 0.8) : PaperPull.resting
                    VStack(alignment: .leading, spacing: 14) {
                        ZStack(alignment: .topTrailing) {
                            PaperMaterial(id: ids[index], pull: pull)
                                .overlay(alignment: .topLeading) {
                                    VStack(alignment: .leading, spacing: 14) {
                                        Text(["纸张自然垂落", "自由边随拖动弯曲", "松手后轻微回弹"][index]).font(.system(size: 16, weight: .medium))
                                        Text("纤维、张力与一点留白。\n受夹的角留在原处。").font(.system(size: 12)).lineSpacing(6)
                                    }.padding(24).padding(.top, 8)
                                }
                                .modifier(PaperFlexEffect(pull: pull, isLeft: false))
                            MetalClip(openness: index == 1 ? 1 : 0).scaleEffect(x: ClipOrientation.scale(isLeft: false), y: 1).offset(x: -1, y: 4)
                        }.frame(width: 245, height: 300)
                        Text(["静止", "拖动", "回落"][index]).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
        }.padding(48).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(red: 0.75, green: 0.79, blue: 0.77))
            .environment(\.colorScheme, .light)
    }
}
