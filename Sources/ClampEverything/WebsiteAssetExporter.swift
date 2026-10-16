import AppKit
import SwiftUI
import PDFKit
import AVFoundation
import ClampCore

/// Reproducible website materials rendered by the shipping AppKit/SwiftUI views.
/// This path never opens the normal library or puts a window on the screen.
@MainActor enum WebsiteAssetExporter {
    static let padding: CGFloat = 32
    struct Entry: Codable {
        var kind: String
        var title: String
        var file: String
        var source: String
        var width: CGFloat
        var height: CGFloat
        var left: String
        var right: String
        var compactLeft: String
        var compactRight: String
        var pinLeft: [CGFloat]
        var pinRight: [CGFloat]
        var pages: [[String: String]]?
    }
    static func export(to output: URL) async throws {
        if ProcessInfo.processInfo.environment["CLAMP_WEBSITE_WEB_ONLY"] == "1" {
            try await exportWebOnly(to: output)
            return
        }
        let fm = FileManager.default
        try fm.createDirectory(at: output, withIntermediateDirectories: true)
        let files = output.deletingLastPathComponent().appendingPathComponent("files", isDirectory: true)
        try fm.createDirectory(at: files, withIntermediateDirectories: true)
        let temporary = fm.temporaryDirectory.appendingPathComponent("ClampWebsite-" + UUID().uuidString)
        let store = ClipStore(root: temporary)
        store.hidden = true
        store.state.preferences.holdToClampEnabled = false
        store.state.preferences.motionIntensity = 0
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? fm.removeItem(at: temporary) }
        let examples = GuideExamples()
        let fixtures = try await makeFiles(at: files, examples: examples)
        var ids: [(String, UUID, String)] = []
        for kind in ["photo", "document", "word", "folder", "code", "audio", "video", "archive", "file"] {
            guard let file = fixtures[kind] else { continue }
            store.importFiles([file])
            if let item = store.active.last { ids.append((kind, item.id, file.lastPathComponent)) }
        }
        store.addTextOrLink(GuideExamples.note)
        let note = store.active.last!
        ids.insert(("note", note.id, fixtures["note"]!.lastPathComponent), at: 1)
        // Serve the exact saved HTML through WebKit's regular live webpage path.
        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-m", "http.server", "18764", "--bind", "127.0.0.1", "--directory", files.path]
        server.standardOutput = FileHandle.nullDevice; server.standardError = FileHandle.nullDevice
        try server.run()
        defer { if server.isRunning { server.terminate() } }
        try await Task.sleep(nanoseconds: 300_000_000)
        store.addTextOrLink("http://127.0.0.1:18764/field-notes.html")
        let webID = store.active.last!.id
        store.update(webID) { $0.title = "田野手记 · 网页首屏" }
        ids.append(("web", webID, fixtures["web"]!.lastPathComponent))
        // The native material group uses real members, without changing their standalone fixtures.
        var group = ClipGroup(title: "这次旅行的材料")
        group.id = UUID(uuidString: "C1A00000-0000-4000-8000-000000000012")!
        store.state.groups.append(group)
        for kind in ["photo", "document", "note"] {
            if let fixture = ids.first(where: { $0.0 == kind }), let original = store.item(fixture.1) {
                var member = original; member.id = UUID(); member.groupID = group.id
                store.state.items.append(member)
                if let image = store.images[original.id] { store.images[member.id] = image }
            }
        }
        ids.append(("group", group.id, fixtures["archive"]!.lastPathComponent))
        for item in store.active { store.loadThumbnail(item) }
        // Read document pages through the same renderer used by DocumentReadingPreview.
        var pageImages: [UUID: [NSImage]] = [:]
        for kind in ["document", "word"] {
            if let tuple = ids.first(where: { $0.0 == kind }), let item = store.item(tuple.1), let url = store.fileURL(item) {
                let pages = DocumentPages(url: url)
                let count = try await pages.pageCount()
                var images: [NSImage] = []
                for index in 0..<min(6, count) { if let image = try await pages.image(at: index) { images.append(image) } }
                pageImages[item.id] = images
                store.images[item.id] = images.first
            }
        }
        try await Task.sleep(nanoseconds: 1_000_000_000)
        var entries: [Entry] = []
        for (kind, id, filename) in ids {
            let item = store.item(id)
            let title = item?.title ?? store.group(id)?.title ?? kind
            let size = MinimalSurfaceLayout.sheetSize(item: item, imageSize: store.images[id]?.size,
                limit: CGSize(width: 320, height: 420))
            let model = CardModel(id: id, manager: manager)
            model.expanded = true; model.revealProgress = 1; model.sheetSize = size; model.sticky = true
            for side in [ClipSide.left, .right] {
                setSide(side, id: id, store: store)
                try await snapshot(CardSurface(store: store, model: model, manager: manager, showsNail: false),
                    size: size, to: output.appendingPathComponent("\(kind)-\(side.rawValue).png"), wait: kind == "web" ? 3 : 0.8)
            }
            model.expanded = false; model.revealProgress = 0; model.sheetSize = DockGeometry.compactSize
            for side in [ClipSide.left, .right] {
                setSide(side, id: id, store: store)
                try await snapshot(CardSurface(store: store, model: model, manager: manager, showsNail: false),
                    size: DockGeometry.compactSize, to: output.appendingPathComponent("\(kind)-compact-\(side.rawValue).png"), wait: 0.25)
            }
            // Source is an actual unpinned content rendering, never a newly designed HTML card.
            if kind == "folder", let item, let url = store.fileURL(item) {
                try writeImage(NSWorkspace.shared.icon(forFile: url.path), to: output.appendingPathComponent("\(kind)-source.png"))
            } else if let image = pageImages[id]?.first ?? store.images[id] {
                try writeImage(image, to: output.appendingPathComponent("\(kind)-source.png"))
            } else if let item {
                try await snapshot(ItemBody(store: store, item: item, manager: manager)
                    .environment(\.colorScheme, .light), size: CGSize(width: max(1, size.width - 24), height: max(1, size.height - 53)),
                    to: output.appendingPathComponent("\(kind)-source.png"), wait: kind == "web" ? 3 : 0.8, margin: 0)
            } else {
                try await snapshot(GroupBody(store: store, groupID: id, manager: manager, interaction: { _ in })
                    .environment(\.colorScheme, .light), size: CGSize(width: size.width - 24, height: size.height - 53),
                    to: output.appendingPathComponent("\(kind)-source.png"), wait: 0.8, margin: 0)
            }
            var pageFiles: [[String: String]]? = nil
            if let pages = pageImages[id], pages.count > 1 {
                pageFiles = []
                for index in pages.indices {
                    store.documentPageIndices[id] = index
                    model.expanded = true; model.revealProgress = 1; model.sheetSize = size
                    var pair: [String: String] = [:]
                    for side in [ClipSide.left, .right] {
                        setSide(side, id: id, store: store)
                        let name = "\(kind)-page-\(index + 1)-\(side.rawValue).png"
                        try await snapshot(CardSurface(store: store, model: model, manager: manager, showsNail: false),
                            size: size, to: output.appendingPathComponent(name), wait: 0.8)
                        pair[side.rawValue] = name
                        let surface = "\(kind)-page-\(index + 1)-surface-\(side.rawValue).png"
                        let motion = ManuscriptMotion(pull: .resting, fold: 0, isLeft: side == .left, disabled: true, turnActivity: { _ in })
                        try await snapshot(PageTurnPreview(image: pages[index], progress: 1, direction: 1, seed: PaperWearGeometry.seed(id), page: index)
                            .environment(\.manuscriptMotion, motion), size: CGSize(width: size.width - 24, height: size.height - 53),
                            to: output.appendingPathComponent(surface), wait: 0.05, margin: 0)
                        pair[side == .left ? "surfaceLeft" : "surfaceRight"] = surface
                    }
                    pageFiles?.append(pair)
                }
                store.documentPageIndices[id] = 0
            }
            entries.append(Entry(kind: kind, title: title, file: "../files/" + (kind == "folder" ? "周末旅行.zip" : filename), source: "\(kind)-source.png",
                width: size.width, height: size.height, left: "\(kind)-left.png", right: "\(kind)-right.png",
                compactLeft: "\(kind)-compact-left.png", compactRight: "\(kind)-compact-right.png",
                pinLeft: [44, 26], pinRight: [size.width - 44, 26], pages: pageFiles))
            print("Exported native \(kind): \(Int(size.width))×\(Int(size.height))")
        }
        for (name, openness) in [("open", 1.0), ("half", 0.5), ("closed", 0.0)] {
            try await snapshot(ImageGenCursorClip(openness: openness), size: CGSize(width: 54, height: 36),
                to: output.appendingPathComponent("cursor-\(name).png"), wait: 0.05, margin: 8)
        }
        try await snapshot(SuspensionNail(), size: CGSize(width: 6, height: 6), to: output.appendingPathComponent("nail.png"), wait: 0.05, margin: 4)
        struct Manifest: Encodable {
            let padding: CGFloat
            let compactWidth = 64
            let compactHeight = 60
            let compactRotationApplied = true
            let compactPinLeft = [44, 26]
            let compactPinRight = [20, 26]
            let expandedRotationLeft = 105
            let expandedRotationRight = -105
            let pngPixelScale: CGFloat
            let renderer = "CardSurface / ItemBody / DocumentPages / ImageGenCursorClip"
            let cursor = ["width": 54, "height": 36, "padding": 8, "mouthX": 0, "mouthY": 18]
            let items: [Entry]
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(Manifest(padding: padding, pngPixelScale: NSScreen.main?.backingScaleFactor ?? 2, items: entries)).write(to: output.appendingPathComponent("manifest.json"), options: .atomic)
        try await exportWebOnly(to: output)
    }
    /// Repair/update just the webpage material without touching the other native
    /// captures or their provenance. WebKit snapshots bypass its composition layer.
    private static func exportWebOnly(to output: URL) async throws {
        let files = output.deletingLastPathComponent().appendingPathComponent("files", isDirectory: true)
        let html = try String(contentsOf: files.appendingPathComponent("field-notes.html"), encoding: .utf8)
        let url = URL(string: "https://guide.clamp.invalid/field-notes.html")!
        let page = WebPagePreviewModel()
        let pageSize = CGSize(width: 296, height: 185)
        let browserHost = NSHostingView(rootView: WebPageSnapshotView(model: page, url: url, html: html)
            .frame(width: pageSize.width, height: pageSize.height))
        let browserWindow = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: pageSize), styleMask: .borderless, backing: .buffered, defer: false)
        browserWindow.isReleasedWhenClosed = false; browserWindow.isOpaque = false; browserWindow.backgroundColor = .clear
        browserWindow.contentView = browserHost; browserHost.layoutSubtreeIfNeeded(); browserWindow.displayIfNeeded()
        defer { page.cancel(); browserWindow.contentView = nil; browserWindow.close() }
        for _ in 0..<160 {
            if page.image != nil || page.failed { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        guard let image = page.image, !page.failed else { throw LibraryError.unsafeAsset }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("ClampWebsiteWeb-" + UUID().uuidString)
        let store = ClipStore(root: temporary); store.hidden = true
        store.state.preferences.holdToClampEnabled = false; store.state.preferences.motionIntensity = 0
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: temporary) }
        store.addTextOrLink(url.absoluteString)
        let id = store.active.last!.id
        store.update(id) { $0.title = "田野手记 · 网页首屏" }
        let size = CGSize(width: 320, height: 238)
        let model = CardModel(id: id, manager: manager)
        model.expanded = true; model.revealProgress = 1; model.sheetSize = size; model.sticky = true
        for side in [ClipSide.left, .right] {
            setSide(side, id: id, store: store)
            try await snapshot(CardSurface(store: store, model: model, manager: manager, showsNail: false, exportWebSnapshot: image),
                size: size, to: output.appendingPathComponent("web-\(side.rawValue).png"), wait: 0.2)
        }
        model.expanded = false; model.revealProgress = 0; model.sheetSize = DockGeometry.compactSize
        for side in [ClipSide.left, .right] {
            setSide(side, id: id, store: store)
            try await snapshot(CardSurface(store: store, model: model, manager: manager, showsNail: false, exportWebSnapshot: image),
                size: DockGeometry.compactSize, to: output.appendingPathComponent("web-compact-\(side.rawValue).png"), wait: 0.2)
        }
        try writeImage(image, to: output.appendingPathComponent("web-source.png"))
        print("Exported native web material from the real HTML through WebKit.takeSnapshot")
    }
    private static func setSide(_ side: ClipSide, id: UUID, store: ClipStore) {
        if let index = store.state.items.firstIndex(where: { $0.id == id }) {
            store.state.items[index].placement.side = side; store.state.items[index].placement.mode = .docked
        } else if let index = store.state.groups.firstIndex(where: { $0.id == id }) {
            store.state.groups[index].placement.side = side; store.state.groups[index].placement.mode = .docked
        }
    }
    private static func snapshot<V: View>(_ view: V, size: CGSize, to url: URL, wait: Double, margin: CGFloat = 32) async throws {
        let canvas = CGSize(width: ceil(size.width) + margin * 2, height: ceil(size.height) + margin * 2)
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20000, y: -20000), size: canvas),
            styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.isOpaque = false; window.backgroundColor = .clear; window.hasShadow = false
        window.appearance = NSAppearance(named: .aqua)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).padding(margin))
        host.frame = CGRect(origin: .zero, size: canvas); window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded(); window.displayIfNeeded()
        try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw LibraryError.unsafeAsset }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { throw LibraryError.unsafeAsset }
        try data.write(to: url, options: .atomic)
    }
    private static func writeImage(_ image: NSImage, to url: URL) throws {
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
            let data = bitmap.representation(using: .png, properties: [:]) else { throw LibraryError.unsafeAsset }
        try data.write(to: url, options: .atomic)
    }
    private static func makeFiles(at files: URL, examples: GuideExamples) async throws -> [String: URL] {
        let names = ["photo": "山间湖泊.png", "document": "旅行手记.pdf", "word": "出行计划.docx", "code": "LittleNote.swift",
                     "note": "周末的小计划.txt", "web": "field-notes.html", "audio": "午后的录音.wav", "video": "湖边的风.mov",
                     "archive": "旅行资料.zip", "file": "相机配置.dat", "folder": "周末旅行"]
        let result = names.mapValues { files.appendingPathComponent($0) }
        try writeImage(examples.photo, to: result["photo"]!)
        try Data(GuideExamples.note.utf8).write(to: result["note"]!)
        try Data(GuideExamples.code.utf8).write(to: result["code"]!)
        try Data(GuideExamples.html.utf8).write(to: result["web"]!)
        try Data([0x43, 0x4c, 0x41, 0x4d, 0x50, 0x00, 0x01, 0x00]).write(to: result["file"]!)
        let pdf = PDFDocument()
        for index in 0..<3 {
            let image: NSImage
            if index == 0 { image = examples.pdf! }
            else {
                image = NSImage(size: CGSize(width: 480, height: 640)); image.lockFocus()
                NSColor.white.setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: 480, height: 640)).fill()
                ((index == 1 ? "沿湖散步" : "日落以后") as NSString).draw(at: CGPoint(x: 40, y: 550), withAttributes: [.font: NSFont.systemFont(ofSize: 34, weight: .medium), .foregroundColor: NSColor.darkGray])
                examples.photo.draw(in: CGRect(x: 40, y: 265, width: 400, height: 250))
                ((index == 1 ? "沿着水边，慢慢走。\n把看到的风景留在纸上。" : "今天的旅程结束了。\n下一次，再从这里出发。") as NSString).draw(in: CGRect(x: 42, y: 120, width: 396, height: 100), withAttributes: [.font: NSFont.systemFont(ofSize: 19), .foregroundColor: NSColor.darkGray])
                ("\(index + 1)" as NSString).draw(at: CGPoint(x: 235, y: 35), withAttributes: [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.gray])
                image.unlockFocus()
            }
            if let page = PDFPage(image: image) { pdf.insert(page, at: index) }
        }
        guard pdf.write(to: result["document"]!) else { throw LibraryError.unsafeAsset }
        let document = NSMutableAttributedString(string: "周末出行计划\n\n", attributes: [.font: NSFont.systemFont(ofSize: 28, weight: .semibold)])
        document.append(NSAttributedString(string: "目的地：海边的小镇\n日期：本周六\n\n09:30  出发，带上相机和水\n11:00  沿海岸散步，记录风景\n14:00  找一家小店，写写手记\n17:00  趁夕阳回家\n\n随身物品\n相机 / 充电线 / 一本空白笔记\n\n把喜欢的片段夹在手边。\n\n", attributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.darkGray]))
        for section in ["沿海岸的步行路线", "摄影与随行手记"] {
            document.append(NSAttributedString(string: "\n\(section)\n\n", attributes: [.font: NSFont.systemFont(ofSize: 24, weight: .semibold)]))
            for i in 1...18 { document.append(NSAttributedString(string: "\(i). 留意路边的光影，记录旅途的小发现。\n", attributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.darkGray])) }
        }
        try document.data(from: NSRange(location: 0, length: document.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]).write(to: result["word"]!)
        let folder = result["folder"]!
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for kind in ["photo", "document", "word", "code", "note"] {
            let destination = folder.appendingPathComponent(result[kind]!.lastPathComponent)
            if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
            try FileManager.default.copyItem(at: result[kind]!, to: destination)
        }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("路线与参考"), withIntermediateDirectories: true)
        try makeWave(to: result["audio"]!)
        try await makeVideo(image: examples.photo, to: result["video"]!)
        let zip = Process(); zip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        zip.arguments = ["-c", "-k", "--keepParent", folder.path, result["archive"]!.path]
        try zip.run(); zip.waitUntilExit()
        guard zip.terminationStatus == 0 else { throw LibraryError.unsafeAsset }
        let folderArchive = files.appendingPathComponent("周末旅行.zip")
        if FileManager.default.fileExists(atPath: folderArchive.path) { try FileManager.default.removeItem(at: folderArchive) }
        try FileManager.default.copyItem(at: result["archive"]!, to: folderArchive)
        return result
    }
    private static func makeWave(to url: URL) throws {
        let count = 22050 * 2, bytes = count * 2
        var data = Data()
        func text(_ value: String) { data.append(Data(value.utf8)) }
        func u16(_ value: UInt16) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        func u32(_ value: UInt32) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        text("RIFF"); u32(UInt32(36 + bytes)); text("WAVEfmt "); u32(16); u16(1); u16(1); u32(22050); u32(44100); u16(2); u16(16); text("data"); u32(UInt32(bytes))
        for i in 0..<count { let fade = min(1, Double(i) / 2205) * min(1, Double(count - i) / 4410); u16(UInt16(bitPattern: Int16(sin(Double(i) * 2 * .pi * 220 / 22050) * 2500 * fade))) }
        try data.write(to: url, options: .atomic)
    }
    private static func makeVideo(image: NSImage, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 800, AVVideoHeightKey: 500])
        let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB, kCVPixelBufferWidthKey as String: 800, kCVPixelBufferHeightKey as String: 500])
        writer.add(input); writer.startWriting(); writer.startSession(atSourceTime: .zero)
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw LibraryError.unsafeAsset }
        for index in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(nanoseconds: 10_000_000) }
            var pixel: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 800, 500, kCVPixelFormatType_32ARGB, [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true] as CFDictionary, &pixel)
            guard let pixel else { throw LibraryError.unsafeAsset }
            CVPixelBufferLockBaseAddress(pixel, [])
            if let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: 800, height: 500, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue) {
                context.draw(cg, in: CGRect(x: 0, y: 0, width: 800, height: 500))
            }
            CVPixelBufferUnlockBaseAddress(pixel, [])
            guard adapter.append(pixel, withPresentationTime: CMTime(value: Int64(index), timescale: 15)) else { throw writer.error ?? LibraryError.unsafeAsset }
        }
        input.markAsFinished(); await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? LibraryError.unsafeAsset }
    }
}
