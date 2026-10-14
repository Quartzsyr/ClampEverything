import Foundation

public enum FolderTint: String, Codable, CaseIterable, Sendable {
    case kraft, ocean, sage
    public var title: String { switch self { case .kraft: return "牛皮纸"; case .ocean: return "雾蓝"; case .sage: return "鼠尾草绿" } }
}
public enum NoteStock: String, Codable, CaseIterable, Sendable {
    case natural, ivory, ruled
    public var title: String { switch self { case .natural: return "自然纹理"; case .ivory: return "暖白纸"; case .ruled: return "横线便笺" } }
}
public enum ContentHousing: Equatable {
    case folder, note, photo, file, link, collection
    public static func forKind(_ kind: ClipKind?) -> Self {
        switch kind { case .folder: return .folder; case .text: return .note; case .image: return .photo; case .file: return .file; case .link: return .link; case nil: return .collection }
    }
    public var isFlexible: Bool { self == .note || self == .photo }
}
