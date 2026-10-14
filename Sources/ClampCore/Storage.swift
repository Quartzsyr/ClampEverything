import Foundation

public enum LibraryError: LocalizedError {
    case newerVersion(Int), unsafeAsset, recursiveCopy, missingDirectory
    public var errorDescription: String? {
        switch self {
        case .newerVersion(let v): return "此资料库来自较新版本（\(v)），请更新应用。原数据未被改写。"
        case .unsafeAsset: return "内部资源路径无效。"
        case .recursiveCopy: return "不能复制到自身或源文件夹内部。"
        case .missingDirectory: return "目标文件夹不存在或设备未连接。"
        }
    }
}
public final class LibraryStorage {
    public let root: URL
    public var assets: URL { root.appendingPathComponent("Assets", isDirectory: true) }
    public var stateURL: URL { root.appendingPathComponent("library.json") }
    public init(root: URL) { self.root = root }
    public func prepare() throws { try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true) }
    public func load() throws -> LibraryState {
        guard FileManager.default.fileExists(atPath: stateURL.path) else { return LibraryState() }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(LibraryState.self, from: Data(contentsOf: stateURL))
        guard state.version <= 1 else { throw LibraryError.newerVersion(state.version) }
        return state
    }
    public func save(_ state: LibraryState) throws {
        try prepare()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        // Keep a previous known-good snapshot as well as an atomic current snapshot.
        if FileManager.default.fileExists(atPath: stateURL.path) {
            try Data(contentsOf: stateURL).write(to: root.appendingPathComponent("library.previous.json"), options: .atomic)
        }
        try data.write(to: stateURL, options: .atomic)
    }
    public func assetURL(_ name: String) throws -> URL {
        guard !name.isEmpty, name == URL(fileURLWithPath: name).lastPathComponent, !name.contains("/"), name != ".", name != ".." else { throw LibraryError.unsafeAsset }
        return assets.appendingPathComponent(name)
    }
    public func deleteAssets(of expired: [ClipItem], remaining: [ClipItem]) throws {
        let referenced = Set(remaining.compactMap(\.assetName))
        for name in Set(expired.compactMap(\.assetName)) where !referenced.contains(name) {
            let url = try assetURL(name)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
    }
}

public enum FileReference {
    public static func bookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
    }
    public static func resolve(_ data: Data) throws -> (url: URL, refreshed: Data?) {
        var stale = false
        let url = try URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale ? try bookmark(for: url) : nil)
    }
    public static func same(_ first: URL, _ second: URL) -> Bool {
        let a = first.standardizedFileURL.resolvingSymlinksInPath(), b = second.standardizedFileURL.resolvingSymlinksInPath()
        if a == b { return true }
        // Paths differ for hard links: compare both volume and file identity.
        let keys: Set<URLResourceKey> = [.fileResourceIdentifierKey, .volumeIdentifierKey]
        guard let av = try? a.resourceValues(forKeys: keys), let bv = try? b.resourceValues(forKeys: keys),
              let ai = av.fileResourceIdentifier as? NSObject, let bi = bv.fileResourceIdentifier as? NSObject,
              let va = av.volumeIdentifier as? NSObject, let vb = bv.volumeIdentifier as? NSObject else { return false }
        return ai == bi && va == vb
    }
}
