import Foundation
import Testing
@testable import ClampCore

@Suite final class CoreTests {
    var root: URL!
    init() throws { root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("ClampTests-" + UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: root) }
    func write(_ name: String, _ content: String = "original") throws -> URL { let url = root.appendingPathComponent(name); try Data(content.utf8).write(to: url); return url }
    func directory(_ name: String) throws -> URL { let url = root.appendingPathComponent(name, isDirectory: true); try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url }

    @Test func testSearchRequiresAllTermsAndIncludesContents() {
        var item = ClipItem(kind: .text, title: "论文"); item.note = "周五提交"; item.tags = ["配图"]; item.text = "AppKit 的交互"
        checkTrue(item.matches("论文 配图")); checkTrue(item.matches("appkit")); checkFalse(item.matches("论文 明年"))
    }
    @Test func testGroupDissolvePreservesItemsAndFloatingState() {
        var state = LibraryState(); let group = ClipGroup(title: "工作"); var item = ClipItem(kind: .text, title: "材料")
        item.groupID = group.id; item.placement.mode = .floating; state.groups = [group]; state.items = [item]
        state.dissolve(group.id)
        checkEqual(state.items.count, 1); checkNil(state.items[0].groupID); checkEqual(state.items[0].placement.mode, .floating); checkTrue(state.groups.isEmpty)
    }
    @Test func testReorderAndMissingDestination() {
        var state = LibraryState(); let a = ClipItem(kind: .text, title: "a"), b = ClipItem(kind: .text, title: "b"), c = ClipItem(kind: .text, title: "c")
        state.items = [a, b, c]; state.reorder(c.id, before: a.id); checkEqual(state.items.map(\.title), ["c", "a", "b"])
        state.reorder(a.id, before: a.id); checkEqual(state.items.map(\.title), ["c", "a", "b"])
    }
    @Test func testRecoveryBoundary() {
        let now = Date(timeIntervalSince1970: 1800000000)
        var old = ClipItem(kind: .text, title: "到期"); old.removedAt = now.addingTimeInterval(-7 * 86400)
        var fresh = ClipItem(kind: .text, title: "未到期"); fresh.removedAt = now.addingTimeInterval(-7 * 86400 + 1)
        let active = ClipItem(kind: .text, title: "常驻")
        var state = LibraryState(); state.items = [old, fresh, active]
        checkEqual(state.purgeExpired(now: now).map(\.title), ["到期"]); checkEqual(state.items.count, 2)
    }
    @Test func testMonitorFallbackAndReturn() {
        var placement = ClipPlacement(); placement.position = ScreenPosition(screenID: "external", x: 0.25, y: 0.7)
        placement.reconcile(available: ["main"], primary: "main"); checkEqual(placement.position.screenID, "main"); checkEqual(placement.displacedFrom?.screenID, "external")
        placement.reconcile(available: ["main", "external"], primary: "main"); checkEqual(placement.position.screenID, "external"); checkEqual(placement.position.x, 0.25); checkNil(placement.displacedFrom)
    }
    @Test func testUserMoveOverridesFormerMonitor() {
        var placement = ClipPlacement(); placement.position.screenID = "external"; placement.reconcile(available: ["main"], primary: "main")
        placement.userMoved(to: ScreenPosition(screenID: "main", x: 0.4, y: 0.3)); placement.reconcile(available: ["main", "external"], primary: "main")
        checkEqual(placement.position.screenID, "main"); checkNil(placement.displacedFrom)
    }
    @Test func testStorageRoundTripAndPreviousSnapshot() throws {
        let storage = LibraryStorage(root: root); var state = LibraryState()
        var item = ClipItem(kind: .text, title: "中文纸签"); item.text = "内容"; item.createdAt = Date(timeIntervalSince1970: 1700000000); item.tags = ["工作"]; state.items = [item]
        try storage.save(state); checkEqual(try storage.load(), state)
        state.items[0].title = "更新后"; try storage.save(state)
        checkEqual(try storage.load().items[0].title, "更新后"); checkTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("library.previous.json").path))
    }
    @Test func testNewerSchemaRefused() throws {
        let storage = LibraryStorage(root: root); var state = LibraryState(); state.version = 2; try storage.save(state)
        checkThrows(try storage.load())
    }
    @Test func testAssetTraversalRefused() {
        let storage = LibraryStorage(root: root)
        checkThrows(try storage.assetURL("../user.txt")); checkThrows(try storage.assetURL("/tmp/user.txt")); checkThrows(try storage.assetURL(".."))
    }
    @Test func testAssetCleanupNeverDeletesOriginalOrSharedAsset() throws {
        let storage = LibraryStorage(root: root); try storage.prepare(); let original = try write("original.txt")
        let asset = try storage.assetURL("image.png"); try Data([1, 2, 3]).write(to: asset)
        var reference = ClipItem(kind: .file, title: "原文件"); reference.originalPath = original.path
        var owned = ClipItem(kind: .image, title: "内部副本"); owned.assetName = "image.png"
        try storage.deleteAssets(of: [reference, owned], remaining: [owned]); checkTrue(FileManager.default.fileExists(atPath: asset.path)); checkTrue(FileManager.default.fileExists(atPath: original.path))
        try storage.deleteAssets(of: [owned], remaining: []); checkFalse(FileManager.default.fileExists(atPath: asset.path)); checkTrue(FileManager.default.fileExists(atPath: original.path))
    }
    @Test func testCopyRetainsBothAndSource() throws {
        let source = try write("报告.pdf", "new"); let target = try directory("target")
        try Data("existing".utf8).write(to: target.appendingPathComponent("报告.pdf"))
        let output = try FileCopyQueue.copySafely(source, into: target)
        checkEqual(output.lastPathComponent, "报告 (2).pdf"); checkEqual(try String(contentsOf: output), "new")
        checkEqual(try String(contentsOf: target.appendingPathComponent("报告.pdf")), "existing"); checkEqual(try String(contentsOf: source), "new")
        checkFalse(try FileManager.default.contentsOfDirectory(atPath: target.path).contains { $0.hasPrefix(".clamp-copy-") })
    }
    @Test func testCopyDirectoryWithDotUsesWholeName() throws {
        let source = try directory("项目.v1"), target = try directory("target")
        try FileManager.default.createDirectory(at: target.appendingPathComponent("项目.v1"), withIntermediateDirectories: true)
        checkEqual(try FileCopyQueue.copySafely(source, into: target).lastPathComponent, "项目.v1 (2)")
    }
    @Test func testRecursiveCopyAndSymlinkDestinationRejected() throws {
        let source = try directory("project"), child = try directory("project/sub")
        checkThrows(try FileCopyQueue.copySafely(source, into: source)); checkThrows(try FileCopyQueue.copySafely(source, into: child))
        let alias = root.appendingPathComponent("alias"); try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: child)
        checkThrows(try FileCopyQueue.copySafely(source, into: alias))
    }
    @Test func testFailedCopyDoesNotTouchOtherFiles() throws {
        let target = try directory("target"); let keep = target.appendingPathComponent("keep.txt"); try Data("safe".utf8).write(to: keep)
        checkThrows(try FileCopyQueue.copySafely(root.appendingPathComponent("missing.txt"), into: target))
        checkEqual(try String(contentsOf: keep), "safe"); checkEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), ["keep.txt"])
    }
    @Test func testSerialQueueContinuesAfterFailure() async throws {
        let queue = FileCopyQueue(), source = try write("good.txt"), target = try directory("target")
        let bad = await queue.copy(root.appendingPathComponent("missing.txt"), into: target)
        let good = await queue.copy(source, into: target)
        checkNotNil(bad.error); checkNotNil(good.destination); checkNil(good.error)
    }
    @Test func testBookmarkSurvivesRenameAndIdentityMatches() throws {
        let original = try write("before.txt"); let bookmark = try FileReference.bookmark(for: original)
        let renamed = root.appendingPathComponent("after.txt"); try FileManager.default.moveItem(at: original, to: renamed)
        let resolved = try FileReference.resolve(bookmark).url
        checkEqual(resolved.resolvingSymlinksInPath().path, renamed.resolvingSymlinksInPath().path); checkTrue(FileReference.same(resolved, renamed))
    }
}
