import Foundation

public enum PhysicalMaterial: String, CaseIterable {
    case note, photo, folder, collection, file, document, bookmark, audio, film, archive
    public static func forItem(_ item: ClipItem?) -> Self {
        guard let item else { return .collection }
        switch item.kind {
        case .text: return .note
        case .image: return .photo
        case .folder: return .folder
        case .link: return .bookmark
        case .file:
            let suffix = URL(fileURLWithPath: item.originalPath ?? item.title).pathExtension.lowercased()
            if ["pdf", "doc", "docx", "pages", "odt", "rtf"].contains(suffix) { return .document }
            if ["mp3", "wav", "m4a", "aiff", "aac", "flac", "ogg"].contains(suffix) { return .audio }
            if ["mp4", "mov", "m4v", "avi", "mkv", "webm"].contains(suffix) { return .film }
            if ["zip", "rar", "7z", "tar", "gz", "bz2", "xz"].contains(suffix) { return .archive }
            return .file
        }
    }
    public var title: String {
        switch self {
        case .note: return "文字 → 棉纸便笺"
        case .photo: return "图片 / 截图 → 相纸"
        case .folder: return "文件夹 → 牛皮纸文件袋"
        case .collection: return "材料组 → 多层资料袋"
        case .file: return "其他文件 → 硬质文件卡"
        case .document: return "文档 → 装订文稿"
        case .bookmark: return "网页链接 → 书签"
        case .audio: return "音频 → 录音卡带"
        case .film: return "视频 → 胶片卡"
        case .archive: return "压缩包 → 拉链收纳袋"
        }
    }
    public var supportedContent: String {
        switch self {
        case .note: return "复制的纯文字、手动输入的文字"
        case .photo: return "图片文件、剪贴板图片、鼠标夹取的截图"
        case .folder: return "本地文件夹"
        case .collection: return "将多个夹项合并为一组"
        case .file: return "其余文件格式，保留原文件引用"
        case .document: return "PDF、DOC / DOCX、Pages、ODT、RTF"
        case .bookmark: return "完整的 HTTP / HTTPS 网页地址"
        case .audio: return "MP3、WAV、M4A、AIFF、AAC、FLAC、OGG"
        case .film: return "MP4、MOV、M4V、AVI、MKV、WebM"
        case .archive: return "ZIP、RAR、7Z、TAR、GZ、BZ2、XZ"
        }
    }
    public var motionDescription: String {
        switch self {
        case .note: return "轻软纸面随拖动弯曲，松手轻弹"
        case .photo: return "相纸轻弯，拖动倾斜后回弹"
        case .folder: return "袋身惯性摆动，袋口与内页轻晃"
        case .collection: return "厚资料袋缓慢回摆，多层内页错动"
        case .file: return "硬卡随手倾斜，松手回摆落稳"
        case .document: return "装订边固定，纸叠轻弯回弹"
        case .bookmark: return "细长书签摆动，尾部柔韧回弹"
        case .audio: return "硬质卡带整体摆动，保持外壳挺度"
        case .film: return "胶片轻柔扭动，松手回弹"
        case .archive: return "收纳袋轻微拉伸，带重量感回摆"
        }
    }
    /// Whole-object swing is independent of surface flexibility.
    public var dragSwing: Double {
        switch self {
        case .note: return 0.035
        case .photo: return 0.032
        case .folder: return 0.052
        case .collection: return 0.045
        case .file: return 0.038
        case .document: return 0.04
        case .bookmark: return 0.058
        case .audio: return 0.034
        case .film: return 0.045
        case .archive: return 0.04
        }
    }
    public var jawOpening: Double {
        switch self { case .note: return 0.025; case .photo: return 0.065; case .bookmark: return 0.09; case .folder: return 0.18; case .collection: return 0.22; case .document: return 0.13; default: return 0.11 }
    }
    public var flexibility: Double {
        switch self { case .note: return 1; case .photo: return 0.55; case .bookmark: return 0.65; case .folder: return 0.18; case .collection: return 0.12; case .document: return 0.38; case .film: return 0.45; case .archive: return 0.22; default: return 0.05 }
    }
    public var inertia: Double {
        switch self { case .note: return 0.32; case .photo: return 0.4; case .bookmark: return 0.46; case .folder: return 0.68; case .collection: return 0.78; default: return 0.6 }
    }
    public var springResponse: Double { 0.32 + inertia * 0.34 }
    public var isPocket: Bool { self == .folder || self == .collection }
}
