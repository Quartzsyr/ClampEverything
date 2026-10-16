import Foundation
import AppKit
import Testing
import ClampCore
@testable import ClampEverything

@Suite(.serialized) @MainActor final class StoreTests {
    let root: URL
    let store: ClipStore
    init() throws {
        root = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("ClampStoreTests-" + UUID().uuidString)
        store = ClipStore(root: root)
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func board() -> NSPasteboard { NSPasteboard(name: .init("ClampStoreTests-" + UUID().uuidString)) }
    @Test func copyReportsSuccessOnlyWhenTheOriginalCanBeWritten() throws {
        let pasteboard = board(); defer { pasteboard.releaseGlobally() }
        let file = root.appendingPathComponent("report.pdf"); try Data("original".utf8).write(to: file)
        var item = ClipItem(kind: .file, title: "report.pdf"); item.originalPath = file.path
        #expect(store.copy(item, to: pasteboard))
        #expect(pasteboard.string(forType: .fileURL) == file.absoluteString)
        try FileManager.default.removeItem(at: file)
        let before = pasteboard.changeCount
        #expect(!store.copy(item, to: pasteboard))
        #expect(pasteboard.changeCount == before)
    }
    @Test func duplicateFileReferencesAndURLs() throws {
        let file = root.appendingPathComponent("file.txt"); try Data("source".utf8).write(to: file)
        store.importFiles([file, file]); #expect(store.active.count == 1)
        store.addTextOrLink("https://example.com/project"); store.addTextOrLink("https://example.com/project"); #expect(store.active.count == 2)
    }
    @Test func clipboardFileTakesPriorityOverText() throws {
        let file = root.appendingPathComponent("file.txt"); try Data("source".utf8).write(to: file)
        let pasteboard = board(); let payload = NSPasteboardItem(); payload.setString(file.absoluteString, forType: .fileURL); payload.setString("unrelated text", forType: .string); pasteboard.writeObjects([payload])
        store.ingest(pasteboard); #expect(store.active.count == 1); #expect(store.active.first?.kind == .file)
    }
    @Test func clipboardImageOwnsItsContent() throws {
        let image = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 32, pixelsHigh: 24, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let pasteboard = board(); pasteboard.setData(image.representation(using: .png, properties: [:])!, forType: .png)
        store.ingest(pasteboard)
        #expect(store.active.first?.kind == .image); #expect(store.active.first?.assetName != nil)
        if let item = store.active.first, let url = store.fileURL(item) { #expect(FileManager.default.fileExists(atPath: url.path)) }
    }
    @Test func pointCapturedImagePersistsWithoutChangingClipboard() throws {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 24, pixelsHigh: 16, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let image = try #require(bitmap.cgImage)
        let clipboardVersion = NSPasteboard.general.changeCount
        store.addCapturedImage(image, title: "点击的图片")
        let item = try #require(store.active.first)
        #expect(item.kind == .image)
        #expect(item.title == "点击的图片")
        #expect(NSPasteboard.general.changeCount == clipboardVersion)
        let saved = ClipStore(root: root)
        #expect(saved.active.first?.assetName == item.assetName)
        #expect(FileManager.default.fileExists(atPath: try store.storage.assetURL(try #require(item.assetName)).path))
    }
    @Test func linksMustBeWholeHTTPURLs() {
        store.addTextOrLink("https://example.com"); store.addTextOrLink("Please see https://example.com"); store.addTextOrLink("file:///tmp/file.txt")
        #expect(store.active.map(\.kind) == [.link, .text, .text])
    }
    @Test func removingAndRestoringPreservesOriginal() throws {
        let file = root.appendingPathComponent("source.txt"); try Data("safe".utf8).write(to: file)
        store.importFiles([file]); let id = store.active[0].id
        store.remove(id); #expect(store.active.isEmpty); #expect(store.recovery.count == 1); #expect(try String(contentsOf: file) == "safe")
        store.undo.undo(); #expect(store.active.count == 1); #expect(store.active[0].id == id)
    }
    @Test func persistenceRestoresGroupsTagsAndLayout() throws {
        store.addTextOrLink("example text"); let id = store.active[0].id
        store.update(id) { $0.tags = ["项目"]; $0.placement.mode = .floating; $0.placement.position.x = 0.4 }
        store.createGroup([id], title: "测试项目"); store.save()
        let loaded = ClipStore(root: root)
        #expect(loaded.active[0].groupID == loaded.state.groups[0].id); #expect(loaded.active[0].tags == ["项目"]); #expect(loaded.active[0].placement.mode == .floating); #expect(loaded.active[0].placement.position.x == 0.4)
    }
    @Test func corruptLibraryCannotBeOverwritten() throws {
        let url = root.appendingPathComponent("library.json"); let corrupt = Data("{invalid".utf8); try corrupt.write(to: url)
        let protected = ClipStore(root: root); #expect(!protected.writable)
        protected.addTextOrLink("should not be saved"); protected.save(); #expect(try Data(contentsOf: url) == corrupt)
    }
    @Test func expiredAssetsAreCleanedWithoutTouchingReferences() throws {
        let file = root.appendingPathComponent("original.txt"); try Data("safe".utf8).write(to: file); store.importFiles([file])
        var image = ClipItem(kind: .image, title: "副本"); image.assetName = "expired.png"; image.removedAt = Date().addingTimeInterval(-8 * 86400)
        let asset = try store.storage.assetURL("expired.png"); try Data([1]).write(to: asset); store.state.items.append(image)
        store.prune(); #expect(!FileManager.default.fileExists(atPath: asset.path)); #expect(FileManager.default.fileExists(atPath: file.path)); #expect(store.active.count == 1)
    }
    @Test func outgoingReferencesUseCopyableFileURL() throws {
        let file = root.appendingPathComponent("file.txt"); try Data("safe".utf8).write(to: file); store.importFiles([file])
        let payload = store.pasteboardItem(store.active[0]); #expect(payload?.string(forType: .fileURL) != nil); #expect(try String(contentsOf: file) == "safe")
    }
    @Test func batchCopyReportsFailureAndContinues() async throws {
        let directory = root.appendingPathComponent("target"); try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = root.appendingPathComponent("file.txt"); try Data("safe".utf8).write(to: file)
        let id = UUID(); store.startCopy([root.appendingPathComponent("missing.txt"), file], to: directory, for: id)
        for _ in 0..<100 where store.copies[id]?.running == true { try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(store.copies[id]?.running == false); #expect(store.copies[id]?.completed == 2); #expect(store.copies[id]?.results.filter { $0.error != nil }.count == 1)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("file.txt").path))
    }
}
