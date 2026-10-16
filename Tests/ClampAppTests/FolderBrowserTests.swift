import AppKit
import SwiftUI
import Testing
import ClampCore
@testable import ClampEverything

@Suite(.serialized) @MainActor struct FolderBrowserTests {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ClampFolder-" + UUID().uuidString, isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url.resolvingSymlinksInPath()
    }
    private func wait(_ browser: FolderBrowser) async throws {
        for _ in 0..<120 { if !browser.loading { return }; try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(!browser.loading)
    }
    @Test func completeDirectoryIncludesEveryEntryAndKeepsNaturalFolderFirstOrder() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<1100 { try Data().write(to: root.appendingPathComponent("file\(i).txt")) }
        try Data().write(to: root.appendingPathComponent(".hidden"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("subfolder"), withIntermediateDirectories: false)
        let normal = try FolderContents.read(root, hidden: false)
        #expect(normal.count == 1101 && normal.first?.folder == true)
        #expect(normal.last?.url.lastPathComponent == "file1099.txt")
        #expect(normal.firstIndex { $0.url.lastPathComponent == "file2.txt" }! < normal.firstIndex { $0.url.lastPathComponent == "file10.txt" }!)
        #expect(try FolderContents.read(root, hidden: true).count == 1102)
    }
    @Test func navigatingFilteringAndExternalChangesUpdateTheWholeDirectory() async throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let sub = root.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try Data().write(to: sub.appendingPathComponent("inside.txt"))
        try Data().write(to: root.appendingPathComponent(".hidden"))
        let browser = FolderBrowser(); defer { browser.stop() }
        browser.openRoot(root, hidden: false); try await wait(browser)
        #expect(browser.entries.count == 1 && !browser.canGoBack)
        browser.enter(try #require(browser.entries.first)); try await wait(browser)
        #expect(browser.current == sub && browser.canGoBack && browser.entries.first?.url.lastPathComponent == "inside.txt")
        browser.back(); try await wait(browser)
        browser.setHidden(true); try await wait(browser)
        #expect(browser.current == root && browser.entries.count == 2)
        let added = root.appendingPathComponent("new.txt"); try Data().write(to: added)
        for _ in 0..<120 { if browser.entries.contains(where: { $0.url == added }) { break }; try await Task.sleep(nanoseconds: 20_000_000) }
        #expect(browser.entries.contains { $0.url == added })
        browser.stop()
        let count = browser.entries.count
        try Data().write(to: root.appendingPathComponent("after-stop.txt"))
        try await Task.sleep(nanoseconds: 180_000_000)
        #expect(browser.entries.count == count)
    }
    @Test func everyRowIsReachableAndItsCopySurfaceForwardsWheelEventsToTheNativeScroller() async throws {
        _ = NSApplication.shared
        let root = try root(), store = ClipStore(root: root.appendingPathComponent("library"))
        defer { try? FileManager.default.removeItem(at: root) }
        let entries = (0..<1500).map { FolderEntry(url: root.appendingPathComponent("file\($0).txt"), folder: false) }
        let view = FolderListView(frame: CGRect(x: 0, y: 0, width: 260, height: 210)); view.store = store
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.contentView = nil; window.close() }
        view.update(entries, directory: root); view.layoutSubtreeIfNeeded()
        #expect(view.table.numberOfRows == 1500)
        view.table.scrollRowToVisible(1499); view.layoutSubtreeIfNeeded()
        #expect(view.table.rows(in: view.documentVisibleRect).contains(1499))
        let row = try #require(view.table.view(atColumn: 0, row: 1499, makeIfNecessary: true) as? FolderRowView)
        row.layoutSubtreeIfNeeded()
        #expect(row.surface.readingScrollTarget(at: CGPoint(x: 30, y: 15)) === view)
        let center = row.surface.convert(CGPoint(x: 30, y: 15), to: view)
        #expect(view.hitTest(view.convert(center, to: view.superview)) === row.surface)
        let file = entries.last!.url; try Data("original".utf8).write(to: file)
        let writer = try #require(row.surface.writer())
        #expect(writer.string(forType: .fileURL) == file.absoluteString)
        let before = view.contentView.bounds.minY
        let cg = try #require(CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: 100, wheel2: 0, wheel3: 0))
        let wheel = try #require(NSEvent(cgEvent: cg))
        row.surface.scrollWheel(with: wheel)
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(view.contentView.bounds.minY < before)
        // Updating the same directory preserves the currently visible anchor.
        view.update([FolderEntry(url: root.appendingPathComponent("a.txt"), folder: false)] + entries, directory: root)
        #expect(view.contentView.bounds.minY > 40_000)
        view.update(entries, directory: root.appendingPathComponent("other"))
        #expect(view.contentView.bounds.minY == 0)
    }
    @Test func folderDisclosureNavigatesAndReusedRowsCannotCopyADifferentFileOnRelease() throws {
        _ = NSApplication.shared
        let first = FolderEntry(url: URL(fileURLWithPath: "/tmp/folder-a", isDirectory: true), folder: true)
        let next = FolderEntry(url: URL(fileURLWithPath: "/tmp/file-b.txt"), folder: false)
        let row = FolderRowView(frame: CGRect(x: 0, y: 0, width: 240, height: 30))
        row.configure(first); row.layoutSubtreeIfNeeded()
        var entered = 0, copied = 0
        row.openFolder = { entered += 1 }; row.surface.copyAction = { copied += 1 }
        #expect(!row.disclosure.isHidden)
        row.disclosure.performClick(nil); #expect(entered == 1)
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: CGPoint(x: 30, y: 15), modifierFlags: [], timestamp: 1,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        row.surface.mouseDown(with: down)
        row.configure(next); row.layoutSubtreeIfNeeded()
        row.surface.mouseUp(with: down)
        #expect(copied == 0 && row.disclosure.isHidden)
        row.surface.mouseDown(with: down); row.surface.mouseUp(with: down)
        #expect(copied == 1)
    }
}
