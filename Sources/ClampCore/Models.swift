import Foundation

public enum ClipKind: String, Codable, CaseIterable, Sendable {
    case file, folder, image, text, link
    public var title: String {
        switch self { case .file: return "文件"; case .folder: return "文件夹"; case .image: return "图片"; case .text: return "文字"; case .link: return "链接" }
    }
    public var symbol: String {
        switch self { case .file: return "doc"; case .folder: return "folder.fill"; case .image: return "photo"; case .text: return "text.alignleft"; case .link: return "link" }
    }
}
public enum ClipSide: String, Codable, Sendable { case left, right }
public enum PlacementMode: String, Codable, Sendable { case docked, floating }
public struct ScreenPosition: Codable, Equatable, Sendable {
    public var screenID: String
    public var x: Double
    public var y: Double
    public init(screenID: String, x: Double = 0.65, y: Double = 0.5) {
        self.screenID = screenID; self.x = x; self.y = y
    }
}
public struct ClipPlacement: Codable, Equatable, Sendable {
    public var mode: PlacementMode = .docked
    public var side: ClipSide = .right
    public var position = ScreenPosition(screenID: "main")
    public var width: Double = 320
    public var height: Double = 420
    public var displacedFrom: ScreenPosition?
    /// Normalized height of the docked clip; nil preserves automatic arrangement.
    public var dockHeight: Double?
    public init() {}
    // Once the user moves a displaced card, its former monitor is no longer its home.
    public mutating func userMoved(to position: ScreenPosition) {
        self.position = position; displacedFrom = nil
    }
    public mutating func reconcile(available: Set<String>, primary: String) {
        if let old = displacedFrom, available.contains(old.screenID) {
            position = old; displacedFrom = nil
        } else if !available.contains(position.screenID) {
            if displacedFrom == nil { displacedFrom = position }
            position.screenID = primary
            position.x = min(1, max(0, position.x)); position.y = min(1, max(0, position.y))
        }
    }
}
public struct ClipItem: Identifiable, Codable, Equatable, Sendable {
    public var id = UUID()
    public var kind: ClipKind
    public var title: String
    public var note = ""
    public var tags: [String] = []
    public var createdAt = Date()
    public var bookmark: Data?
    public var originalPath: String?
    public var assetName: String?
    public var text: String?
    public var link: String?
    public var groupID: UUID?
    public var placement = ClipPlacement()
    public var removedAt: Date?
    public init(kind: ClipKind, title: String) { self.kind = kind; self.title = title }
    public var ownsContent: Bool { assetName != nil || kind == .text }
    public var searchable: String { ([title, note, text ?? "", link ?? ""] + tags).joined(separator: "\n") }
    public func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        return words.allSatisfy { searchable.localizedStandardContains(String($0)) }
    }
    public func expiresAt(days: Int = 7) -> Date? { removedAt?.addingTimeInterval(Double(days) * 86400) }
}
public struct ClipGroup: Identifiable, Codable, Equatable {
    public var id = UUID()
    public var title: String
    public var placement = ClipPlacement()
    public init(title: String) { self.title = title }
}
public struct Shortcut: Codable, Equatable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    public var label: String
    public init(keyCode: UInt32, modifiers: UInt32, label: String) { self.keyCode = keyCode; self.modifiers = modifiers; self.label = label }
}
public struct AppPreferences: Codable, Equatable {
    public var hideInFullScreen = true
    public var showHiddenFiles = false
    public var shortcut: Shortcut?
    public var holdToClampEnabled = false
    public var holdShortcut: HoldShortcut = .option
    public var folderTint: FolderTint = .kraft
    public var noteStock: NoteStock = .natural
    public var motionIntensity: Double = 1
    public var tactileFeedback = false
    public var autoSnap = true
    public var snapDistance: Double = 42
    public var hoverToExpand = true
    public var hoverDelay: Double = 0.35
    public var defaultSide: ClipSide = .right

    public init() {}
    private enum CodingKeys: String, CodingKey { case hideInFullScreen, showHiddenFiles, shortcut, holdToClampEnabled, holdShortcut, folderTint, noteStock, motionIntensity, autoSnap, snapDistance, hoverToExpand, hoverDelay, defaultSide, tactileFeedback }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        hideInFullScreen = try values.decodeIfPresent(Bool.self, forKey: .hideInFullScreen) ?? true
        showHiddenFiles = try values.decodeIfPresent(Bool.self, forKey: .showHiddenFiles) ?? false
        shortcut = try values.decodeIfPresent(Shortcut.self, forKey: .shortcut)
        holdToClampEnabled = try values.decodeIfPresent(Bool.self, forKey: .holdToClampEnabled) ?? false
        holdShortcut = try values.decodeIfPresent(HoldShortcut.self, forKey: .holdShortcut) ?? .option
        folderTint = (try? values.decodeIfPresent(FolderTint.self, forKey: .folderTint)) ?? .kraft
        noteStock = (try? values.decodeIfPresent(NoteStock.self, forKey: .noteStock)) ?? .natural
        let motion = try values.decodeIfPresent(Double.self, forKey: .motionIntensity) ?? 1
        motionIntensity = motion.isFinite ? min(1.5, max(0, motion)) : 1
        tactileFeedback = try values.decodeIfPresent(Bool.self, forKey: .tactileFeedback) ?? false
        autoSnap = try values.decodeIfPresent(Bool.self, forKey: .autoSnap) ?? true
        let distance = try values.decodeIfPresent(Double.self, forKey: .snapDistance) ?? 42
        snapDistance = distance.isFinite ? min(96, max(16, distance)) : 42
        hoverToExpand = try values.decodeIfPresent(Bool.self, forKey: .hoverToExpand) ?? true
        let delay = try values.decodeIfPresent(Double.self, forKey: .hoverDelay) ?? 0.35
        hoverDelay = delay.isFinite ? min(1.2, max(0.1, delay)) : 0.35
        defaultSide = (try? values.decodeIfPresent(ClipSide.self, forKey: .defaultSide)) ?? .right
        if !holdShortcut.isValid { holdShortcut = .option; holdToClampEnabled = false }
    }
}
public struct LibraryState: Codable, Equatable {
    public var version = 1
    public var items: [ClipItem] = []
    public var groups: [ClipGroup] = []
    public var preferences = AppPreferences()
    public var scenes: [WorkScene] = []
    public var activeSceneID: UUID?
    public init() {}
    private enum CodingKeys: String, CodingKey { case version, items, groups, preferences, scenes, activeSceneID }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        items = try values.decodeIfPresent([ClipItem].self, forKey: .items) ?? []
        groups = try values.decodeIfPresent([ClipGroup].self, forKey: .groups) ?? []
        preferences = try values.decodeIfPresent(AppPreferences.self, forKey: .preferences) ?? AppPreferences()
        scenes = try values.decodeIfPresent([WorkScene].self, forKey: .scenes) ?? []
        let selected = try values.decodeIfPresent(UUID.self, forKey: .activeSceneID)
        activeSceneID = scenes.contains { $0.id == selected } ? selected : nil
    }
    public var activeItems: [ClipItem] { items.filter { $0.removedAt == nil } }
    public mutating func dissolve(_ group: UUID) {
        for index in items.indices where items[index].groupID == group { items[index].groupID = nil }
        groups.removeAll { $0.id == group }
    }
    @discardableResult public mutating func purgeExpired(now: Date = Date()) -> [ClipItem] {
        let expired = items.filter { $0.expiresAt().map { $0 <= now } ?? false }
        let ids = Set(expired.map(\.id)); items.removeAll { ids.contains($0.id) }; return expired
    }
    public mutating func reorder(_ id: UUID, before destination: UUID) {
        guard id != destination, let source = items.firstIndex(where: { $0.id == id }) else { return }
        let item = items.remove(at: source)
        let target = items.firstIndex(where: { $0.id == destination }) ?? items.endIndex
        items.insert(item, at: target)
    }
}
