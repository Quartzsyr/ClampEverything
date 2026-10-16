import AppKit
import UniformTypeIdentifiers

/// Decode Finder's file URL payloads without accepting ordinary web links.
enum DroppedFileURLs {
    static func decode(_ item: NSSecureCoding?) -> URL? {
        let url: URL?
        if let value = item as? URL { url = value }
        else if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
        else if let text = item as? String { url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)) }
        else { url = nil }
        return url?.isFileURL == true ? url : nil
    }
    static func read(_ providers: [NSItemProvider]) async -> [URL] {
        var result: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            let url: URL? = await withCheckedContinuation { continuation in
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    continuation.resume(returning: decode(item))
                }
            }
            if let url, !result.contains(url) { result.append(url) }
        }
        return result
    }
}
