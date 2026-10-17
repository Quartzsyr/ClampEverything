// QuickNote.swift - 在 macOS SwiftUI 项目中运行的最小便笺示例。
// 将此文件设为项目入口；网页编辑器仅编辑文件，不执行 Swift。
import SwiftUI

@main
struct QuickNoteApp: App {
    var body: some Scene {
        WindowGroup {
            QuickNoteView()
        }
        .defaultSize(width: 320, height: 240)
    }
}

struct QuickNoteView: View {
    @AppStorage("quick-note-text") private var text = "把灵感，夹在手边。"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("我的便笺", systemImage: "note.text")
                .font(.headline)
            TextEditor(text: $text)
                .font(.body)
                .scrollContentBackground(.hidden)
            Text("文字保存在这台 Mac 上。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(minWidth: 280, minHeight: 200)
        .background(Color(red: 0.98, green: 0.97, blue: 0.91))
    }
}
