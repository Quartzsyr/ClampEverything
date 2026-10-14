import Foundation

public struct CopyResult: Identifiable, Equatable, Sendable {
    public let id = UUID()
    public var source: URL
    public var destination: URL?
    public var error: String?
    public init(source: URL, destination: URL? = nil, error: String? = nil) { self.source = source; self.destination = destination; self.error = error }
}

public actor FileCopyQueue {
    public init() {}
    public func copy(_ source: URL, into directory: URL) -> CopyResult {
        do { return CopyResult(source: source, destination: try Self.copySafely(source, into: directory)) }
        catch { return CopyResult(source: source, error: Self.message(for: error)) }
    }
    public static func message(for error: Error) -> String {
        let e = error as NSError
        if e.domain == NSCocoaErrorDomain {
            switch e.code {
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return "源文件不存在或设备未连接。"
            case NSFileReadNoPermissionError: return "没有读取源文件的权限。"
            case NSFileWriteNoPermissionError: return "没有写入目标文件夹的权限。"
            case NSFileWriteOutOfSpaceError: return "目标磁盘空间不足。"
            case NSFileWriteVolumeReadOnlyError: return "目标磁盘为只读。"
            default: break
            }
        }
        return error.localizedDescription
    }
    public static func candidate(for source: URL, in directory: URL, number: Int) -> URL {
        let isFolder = (try? source.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        let ext = isFolder ? "" : source.pathExtension
        let stem = ext.isEmpty ? source.lastPathComponent : source.deletingPathExtension().lastPathComponent
        let suffix = number == 1 ? "" : " (\(number))"
        let name = stem + suffix + (ext.isEmpty ? "" : "." + ext)
        return directory.appendingPathComponent(name, isDirectory: isFolder)
    }
    public static func copySafely(_ source: URL, into directory: URL) throws -> URL {
        let fm = FileManager.default
        let target = directory.standardizedFileURL.resolvingSymlinksInPath()
        let origin = source.standardizedFileURL.resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: target.path, isDirectory: &isDirectory), isDirectory.boolValue else { throw LibraryError.missingDirectory }
        let sourceIsDirectory = (try? origin.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        if sourceIsDirectory && (origin.path == target.path || target.path.hasPrefix(origin.path + "/")) { throw LibraryError.recursiveCopy }
        // Copy to an owned staging path. Failure cleanup can never remove an existing user file.
        let staging = target.appendingPathComponent(".clamp-copy-" + UUID().uuidString)
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: source, to: staging)
        for number in 1...10000 {
            let destination = candidate(for: source, in: target, number: number)
            if fm.fileExists(atPath: destination.path) { continue }
            do { try fm.moveItem(at: staging, to: destination); return destination }
            catch let error as NSError {
                if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError { continue }
                throw error
            }
        }
        throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError, userInfo: [NSLocalizedDescriptionKey: "同名副本过多，请更改名称后重试。"])
    }
}
