import Foundation
import CoreFoundation
import AppKit

// Decode the actual Carbon Alias read from Finder metadata and resolve it through
// macOS, rather than merely checking that its bytes can be parsed by Python.
let alias = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
guard let bookmark = CFURLCreateBookmarkDataFromAliasRecord(kCFAllocatorDefault, alias as CFData)?.takeRetainedValue() else {
    fatalError("Finder background alias cannot be converted")
}
var stale = false
let resolved = try URL(resolvingBookmarkData: bookmark as Data, options: [.withoutUI, .withoutMounting], bookmarkDataIsStale: &stale)
let expected = URL(fileURLWithPath: CommandLine.arguments[2])
guard resolved.standardizedFileURL == expected.standardizedFileURL,
      let image = NSImage(contentsOf: resolved), image.size == CGSize(width: 640, height: 480) else {
    fatalError("Finder background alias does not resolve to the bundled 640×480 artwork: \(resolved)")
}
print("macOS resolved Finder background to \(resolved.path)")
