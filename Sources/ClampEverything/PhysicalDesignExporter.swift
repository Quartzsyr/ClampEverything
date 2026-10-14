import AppKit
import SwiftUI
import ClampCore

extension DesignExporter {
    static func exportPhysical(store: ClipStore, manager: WindowManager, to output: URL) async throws {
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let folder = store.active.first { $0.kind == .folder }!
        let note = store.active.first { $0.kind == .text }!
        let photo = store.active.first { $0.kind == .image }!
        let link = store.active.first { $0.kind == .link }!
        var extras: [UUID] = []
        for title in ["会议材料.pdf", "访谈录音.m4a", "参考视频.mov", "项目归档.zip"] {
            let item = ClipItem(kind: .file, title: title)
            store.state.items.append(item); extras.append(item.id)
        }
        let ids = [folder.id, note.id, photo.id, link.id] + extras + [store.state.groups.first!.id]
        let models = ids.map { id -> CardModel in
            let model = CardModel(id: id, manager: manager); model.expanded = true; model.revealProgress = 1
            return model
        }
        try await snapshot(VStack(alignment: .leading, spacing: 20) {
            Text("不同的材料，不同的受力与厚度").font(.system(size: 26, weight: .semibold)).foregroundStyle(.white)
            ForEach(0..<3) { row in
                HStack(alignment: .top, spacing: 22) {
                    ForEach(Array(models[(row * 3)..<(row * 3 + 3)]), id: \.id) { model in
                        VStack(spacing: 12) {
                            CardSurface(store: store, model: model, manager: manager).frame(width: 290, height: 350)
                            Text(store.item(model.id)?.title ?? "材料组").font(.system(size: 11)).foregroundStyle(.white.opacity(0.85)).lineLimit(1)
                        }
                    }
                }
            }
        }.padding(30).background(Color(red: 0.24, green: 0.31, blue: 0.35)), size: NSSize(width: 980, height: 1250), to: output.appendingPathComponent("26-physical-materials.png"))
        let poses = [CGFloat(0), 0.5, 1].map { progress -> CardModel in
            let model = CardModel(id: folder.id, manager: manager); model.expanded = true; model.revealProgress = progress
            return model
        }
        try await snapshot(VStack(alignment: .leading, spacing: 20) {
            Text("外壳固定 · 袋口撑开 · 内页抽出").font(.system(size: 22, weight: .medium))
            HStack(spacing: 22) {
                ForEach(Array(poses.enumerated()), id: \.offset) { index, model in
                    VStack(spacing: 10) {
                        CardSurface(store: store, model: model, manager: manager).frame(width: 290, height: 330)
                        Text(["袋口闭合", "撑开并抽取", "完整展开"][index]).font(.system(size: 11))
                    }
                }
            }
        }.padding(30).background(Color(white: 0.92)), size: NSSize(width: 980, height: 450), to: output.appendingPathComponent("27-folder-pocket.png"))
        try await snapshot(HStack(spacing: 38) {
            ForEach([Double(1), 0.4, 0.03], id: \.self) { openness in
                VStack(spacing: 20) {
                    ImageGenCursorClip(openness: openness).scaleEffect(3).frame(width: 180, height: 115)
                    Text(openness > 0.5 ? "张开" : (openness > 0.1 ? "夹住厚材料" : "夹住薄纸")).font(.system(size: 12))
                }
            }
        }.padding(35).background(Color(red: 0.85, green: 0.88, blue: 0.89)), size: NSSize(width: 700, height: 220), to: output.appendingPathComponent("28-mouse-clip.png"))
    }
}
