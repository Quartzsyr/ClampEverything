import Foundation

/// Separate preferences for physical content, independent of the clip's metalwork.
public enum PreviewSizeKind: String, Codable, CaseIterable, Sendable {
    case pdf, document, webpage, photo, text, code, file, folder, collection, audio, video, archive
    public var title: String {
        switch self {
        case .pdf: return "PDF"
        case .document: return "Word / 其他文稿"
        case .webpage: return "网页首屏"
        case .photo: return "照片"
        case .text: return "文字便笺"
        case .code: return "代码"
        case .file: return "其他文件"
        case .folder: return "文件夹"
        case .collection: return "收纳夹"
        case .audio: return "音频"
        case .video: return "视频"
        case .archive: return "压缩包"
        }
    }
}

public struct PreviewSizes: Codable, Equatable, Sendable {
    private var values: [String: Double] = [:]
    public static let range = 0.65...1.8
    public init() {}
    public subscript(_ kind: PreviewSizeKind) -> Double {
        get { Self.validated(values[kind.rawValue] ?? 1) }
        set { values[kind.rawValue] = Self.validated(newValue) }
    }
    private static func validated(_ value: Double) -> Double {
        value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : 1
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let decoded = try container.decode([String: Double].self)
        for kind in PreviewSizeKind.allCases {
            if let value = decoded[kind.rawValue] { values[kind.rawValue] = Self.validated(value) }
        }
    }
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer(); try container.encode(values)
    }
}
