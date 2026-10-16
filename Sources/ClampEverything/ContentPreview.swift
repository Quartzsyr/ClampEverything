import AppKit
import SwiftUI
import UniformTypeIdentifiers
import ClampCore

enum FilePreviewKind: Equatable {
    case pdf, code, document, other
    static func forURL(_ url: URL) -> Self {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" { return .pdf }
        if ["doc", "docx", "odt", "rtf", "rtfd", "pages", "xls", "xlsx", "ppt", "pptx", "key", "numbers"].contains(ext) { return .document }
        let source = ["swift", "py", "js", "jsx", "ts", "tsx", "json", "yaml", "yml", "toml", "xml", "html", "css", "scss", "sh", "bash", "zsh", "c", "h", "cpp", "hpp", "rs", "go", "java", "kt", "rb", "php", "sql", "md", "txt", "log", "csv", "tex", "typ", "vue", "svelte", "ipynb"]
        if source.contains(ext) || ["dockerfile", "makefile", ".gitignore", ".env"].contains(url.lastPathComponent.lowercased()) { return .code }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .plainText) || type.conforms(to: .sourceCode) { return .code }
        return .other
    }
}

struct CodeExcerpt: Sendable {
    let text: String
    let truncated: Bool
    static let byteLimit = 128 * 1024
    static let lineLimit = 400
    static func read(_ url: URL) throws -> Self {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: byteLimit + 1) ?? Data()
        let bytes = Data(data.prefix(byteLimit))
        // UTF-16 is accepted only with a BOM; binary files never become gibberish.
        let text: String?
        if bytes.starts(with: [0xff, 0xfe]) || bytes.starts(with: [0xfe, 0xff]) { text = String(data: bytes, encoding: .utf16) }
        else if !bytes.contains(0) {
            // A bounded prefix can end in the middle of a UTF-8 scalar.
            text = (0...min(3, max(0, bytes.count - 1))).lazy.compactMap { String(data: bytes.dropLast($0), encoding: .utf8) }.first
        } else { text = nil }
        guard let text else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        return Self(text: lines.prefix(lineLimit).joined(separator: "\n"), truncated: data.count > byteLimit || lines.count > lineLimit)
    }
    var lineCount: Int { text.components(separatedBy: "\n").count }
}

enum CodeColoring {
    static func highlight(_ text: String) -> AttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.foregroundColor: NSColor.labelColor, .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)])
        let range = NSRange(location: 0, length: (text as NSString).length)
        let patterns: [(String, NSColor)] = [
            (#"\b(class|struct|enum|func|let|var|const|function|return|if|else|for|while|import|from|def|async|await|public|private|static|true|false|null|nil|None|True|False|try|catch|throw|export|interface|type|fn|use|impl)\b"#, .systemPurple),
            (#"\b\d+(?:\.\d+)?\b"#, .systemOrange),
            (#"\"(?:\\.|[^\"\\])*\"|'(?:\\.|[^'\\])*'"#, .systemRed),
            (#"(?m)//[^\n]*|^\s*#[^\n]*"#, .systemGreen)
        ]
        for (pattern, color) in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: range) { result.addAttribute(.foregroundColor, value: color, range: match.range) }
        }
        return AttributedString(result)
    }
}

struct CodeFilePreview: View {
    let url: URL
    @State private var excerpt: CodeExcerpt?
    @State private var failed = false
    var body: some View {
        Group {
            if let excerpt {
                CodeReadingView(source: excerpt.text)
            } else if failed { PreviewUnavailable(message: "无法读取文本编码") }
            else { ProgressView().controlSize(.small).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.task(id: url) {
            excerpt = nil; failed = false
            do {
                let loaded = try await Task.detached(priority: .utility) { try CodeExcerpt.read(url) }.value
                guard !Task.isCancelled else { return }
                excerpt = loaded
            } catch { if !Task.isCancelled { failed = true } }
        }
    }
}

enum ContentPreviewLayout {
    static let thumbnailHeight: CGFloat = 256
    static let webpageHeight: CGFloat = 208
    static let webViewport = CGSize(width: 1024, height: 640)
}

struct FileThumbnailPreview: View {
    @ObservedObject var store: ClipStore
    let item: ClipItem
    var body: some View {
        Group {
            if let image = store.images[item.id] {
                Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
            } else {
                VStack(spacing: 9) {
                    ClipIcon(item: item, size: 42)
                    Text(item.title).font(.system(size: 11)).lineLimit(2).multilineTextAlignment(.center)
                }.padding(18).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background { if PinnedContentForm.forItem(item) == .documentPrint { QuietPaper() } }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .onAppear { store.loadThumbnail(item) }
    }
}

struct PreviewUnavailable: View {
    let message: String
    var body: some View {
        VStack(spacing: 8) { Image(systemName: "doc.text.magnifyingglass").font(.system(size: 26)); Text(message).font(.system(size: 11)).multilineTextAlignment(.center) }
            .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WebLinkPreview: View {
    let url: URL
    @ObservedObject var store: ClipStore
    let item: ClipItem
    var interaction: (Bool) -> Void
    @StateObject private var page = WebPagePreviewModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovering = false
    var animated: Bool { !reduceMotion && store.state.preferences.motionIntensity != 0 }
    var body: some View {
        ZStack {
            WebPageSnapshotView(model: page, url: url, live: true,
                                initialPosition: store.webpageScrollPositions[item.id] ?? .zero).id(page.revision)
            if page.loading, let image = page.image { Image(nsImage: image).resizable().interpolation(.high).scaledToFit() }
            if page.failed {
                if let image = page.image { Image(nsImage: image).resizable().scaledToFit() }
                else {
                    VStack(spacing: 9) {
                        Image(systemName: "globe").font(.system(size: 24)).foregroundStyle(.secondary)
                        Text(url.host ?? item.title).font(.system(size: 12)).lineLimit(2)
                        Text("暂时无法加载 · 右键重试").font(.system(size: 10)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).background { QuietPaper() }
                }
            }
            if page.loading && page.image == nil { ProgressView().controlSize(.small).padding(5).background(.regularMaterial, in: Circle()) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(SoftSheetMask(pull: PaperPull(x: 0, y: animated ? page.scrollBend : 0), isLeft: false))
        .overlay(SheetLighting(pull: PaperPull(x: 0, y: animated ? page.scrollBend : 0), isLeft: false))
        .modifier(PaperFlexEffect(pull: PaperPull(x: 0, y: animated ? page.scrollBend : 0), isLeft: false))
        .overlay(ContentDragHandle(item: item, store: store, interaction: interaction, showLabel: false,
                                   scroll: { page.scroll($0, animated: animated) }))
        .overlay(alignment: .bottomTrailing) {
            if hovering && !page.failed { Image(systemName: "arrow.up.and.down").font(.system(size: 10)).padding(7).background(.regularMaterial, in: Circle()).padding(5).allowsHitTesting(false) }
        }
        .onHover { hovering = $0 }
        .help((page.title.isEmpty ? item.title : page.title) + " · 滚轮浏览网页 · 单击复制链接 · 拖出复制链接")
        .contextMenu {
            Button("打开网页") { NSWorkspace.shared.open(url) }
            Button("复制链接") { store.copy(item) }
            Button("重新加载网页") { page.retry() }
        }
        .onAppear { page.onScrollPosition = { store.webpageScrollPositions[item.id] = $0 } }
        .onChange(of: page.scrolling) { _, scrolling in interaction(scrolling) }
        .onDisappear { page.cancel(); interaction(false) }
    }
}
