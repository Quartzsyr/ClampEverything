import AppKit
import SwiftUI
import Testing
import ClampCore
@testable import ClampEverything

struct PinnedContentFormTests {
    @Test func everyContentTypeIsItsOwnObjectRatherThanACommonCard() {
        func file(_ name: String) -> ClipItem { ClipItem(kind: .file, title: name) }
        #expect(PinnedContentForm.forItem(nil) == .pocket)
        #expect(PinnedContentForm.forItem(ClipItem(kind: .folder, title: "folder")) == .pocket)
        #expect(PinnedContentForm.forItem(ClipItem(kind: .image, title: "image")) == .photo)
        #expect(PinnedContentForm.forItem(ClipItem(kind: .text, title: "note")) == .notePage)
        #expect(PinnedContentForm.forItem(ClipItem(kind: .link, title: "web")) == .webPrint)
        #expect(PinnedContentForm.forItem(file("source.swift")) == .codePage)
        #expect(PinnedContentForm.forItem(file("page.pdf")) == .documentPrint)
        #expect(PinnedContentForm.forItem(file("page.docx")) == .documentPrint)
        #expect(PinnedContentForm.forItem(file("clip.mov")) == .filmStrip)
        #expect(PinnedContentForm.forItem(file("record.m4a")) == .cassette)
        #expect(PinnedContentForm.forItem(file("archive.zip")) == .parcel)
        #expect(PinnedContentForm.forItem(file("data.bin")) == .fileSheet)
        #expect(!PinnedContentForm.documentPrint.usesPaperStock)
        #expect(!PinnedContentForm.webPrint.usesPaperStock)
        #expect(PinnedContentForm.notePage.usesPaperStock)
    }
    @Test func filmHasRealSprocketHolesButItsClampingEdgeIsSolid() {
        let shape = FilmStripShape().path(in: CGRect(x: 0, y: 0, width: 288, height: 168))
        #expect(!shape.contains(CGPoint(x: 7, y: 12), eoFill: true))
        #expect(shape.contains(CGPoint(x: 29, y: 5), eoFill: true))
        #expect(shape.contains(CGPoint(x: 144, y: 80), eoFill: true))
        #expect(ParcelShape().path(in: CGRect(x: 0, y: 0, width: 240, height: 150)).contains(CGPoint(x: 29, y: 5)))
    }
}

@MainActor struct MinimalSurfaceLayoutTests {
    @Test func shortNotesShrinkAndLongNotesStayBounded() {
        var note = ClipItem(kind: .text, title: "note"); note.text = "只留一张纸。"
        let limit = CGSize(width: 320, height: 420)
        let small = MinimalSurfaceLayout.sheetSize(item: note, imageSize: nil, limit: limit)
        note.text = String(repeating: "长便笺内容。\n", count: 500)
        let long = MinimalSurfaceLayout.sheetSize(item: note, imageSize: nil, limit: limit)
        #expect(small.height < long.height)
        #expect(small.height < 200)
        #expect(long.height <= 420 && long.width <= 320)
    }
    @Test func documentsAndWebpagesStayAtThumbnailSizeWithoutAnEmptyPanel() {
        let limit = CGSize(width: 456, height: 620)
        for name in ["document.pdf", "document.docx"] {
            let item = ClipItem(kind: .file, title: name)
            let size = MinimalSurfaceLayout.sheetSize(item: item, imageSize: CGSize(width: 600, height: 800), limit: limit)
            #expect(size.height == 256 + ClipOrientation.verticalMargins)
            #expect(size.width == 216)
        }
        let web = MinimalSurfaceLayout.sheetSize(item: ClipItem(kind: .link, title: "site"), imageSize: nil, limit: limit)
        #expect(web == CGSize(width: 357, height: 208 + ClipOrientation.verticalMargins))
        #expect(MinimalSurfaceLayout.sheetSize(item: ClipItem(kind: .folder, title: "folder"), imageSize: nil, limit: limit) == limit)
    }
    @Test func allPhysicalObjectsFitAndKeepTheSameContactHeight() {
        for name in ["code.swift", "letter.pdf", "work.docx", "record.mp3", "clip.mp4", "archive.zip", "data.bin"] {
            let item = ClipItem(kind: .file, title: name)
            let size = MinimalSurfaceLayout.sheetSize(item: item, imageSize: nil, limit: CGSize(width: 320, height: 420))
            #expect(size.width <= 320 && size.height <= 420)
            #expect(size.width >= 100 && size.height >= 100)
            #expect(size.width.rounded() == size.width && size.height.rounded() == size.height)
            for left in [true, false] {
                #expect(HingeReveal.grip(size: size, isLeft: left).y == ClipOrientation.paperTop + ClipOrientation.insertion)
            }
        }
    }
}


@Suite(.serialized) @MainActor struct MinimalThumbnailLayoutTests {
    @Test func lateThumbnailDoesNotMoveADraggedOrFlippingObject() throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: "/private/tmp/ClampMinimalLayout-" + UUID().uuidString)
        let store = ClipStore(root: root); store.hidden = true
        store.addTextOrLink("document layout")
        let id = try #require(store.active.first?.id)
        store.update(id) { $0.kind = .file; $0.title = "document.pdf" }
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        let model = manager.model(id); model.present(animated: false)
        let before = model.panel.frame
        model.moving = true
        store.images[id] = NSImage(size: CGSize(width: 800, height: 450)); store.onThumbnailChange?(id)
        #expect(model.panel.frame == before)
        model.moving = false; model.revealInFlight = true
        store.onThumbnailChange?(id)
        #expect(model.panel.frame == before)
        model.revealInFlight = false; store.onThumbnailChange?(id)
        #expect(model.panel.frame.width > before.width)
        #expect(abs(model.panel.frame.maxX - before.maxX) < 0.001)
        #expect(abs(model.panel.frame.maxY - before.maxY) < 0.001)
    }
}

@MainActor struct PreviewSizeLayoutTests {
    @Test func everyTypeHasAnIndependentSizeCategory() {
        let files: [(String, PreviewSizeKind)] = [("report.PDF", .pdf), ("report.docx", .document), ("source.swift", .code),
            ("sound.mp3", .audio), ("movie.mov", .video), ("archive.zip", .archive), ("data.bin", .file)]
        let examples: [(ClipItem?, PreviewSizeKind)] = [
            (nil, .collection), (ClipItem(kind: .folder, title: "folder"), .folder),
            (ClipItem(kind: .image, title: "photo"), .photo), (ClipItem(kind: .text, title: "text"), .text),
            (ClipItem(kind: .link, title: "site"), .webpage)
        ] + files.map { (ClipItem(kind: .file, title: $0.0), $0.1) }
        #expect(Set(examples.map { $0.1 }) == Set(PreviewSizeKind.allCases))
        for (item, kind) in examples {
            #expect(PreviewSizeKind.forItem(item) == kind)
            let small = MinimalSurfaceLayout.sheetSize(item: item, imageSize: nil, limit: CGSize(width: 320, height: 420), scale: 0.65)
            let large = MinimalSurfaceLayout.sheetSize(item: item, imageSize: nil, limit: CGSize(width: 320, height: 420), scale: 1.8)
            #expect(large.width > small.width && large.height > small.height)
            #expect(HingeReveal.grip(size: large, isLeft: true).y == HingeReveal.grip(size: small, isLeft: true).y)
        }
    }
    @Test func enlargedDocumentPreservesPageRatioAndFitsSmallScreens() {
        let pdf = ClipItem(kind: .file, title: "report.pdf")
        for scale in [0.65, 1.0, 1.8] {
            let size = MinimalSurfaceLayout.sheetSize(item: pdf, imageSize: CGSize(width: 600, height: 800),
                limit: CGSize(width: 320, height: 420), scale: scale, maximumSize: CGSize(width: 300, height: 400))
            #expect(size.width <= 300 && size.height <= 400)
            #expect(abs((size.width - 24) / (size.height - ClipOrientation.verticalMargins) - 0.75) < 0.01)
        }
    }
}

@Suite(.serialized) @MainActor struct PreviewSizePanelTests {
    @Test func changingPDFSizeRelayoutsExpandedPDFAndPersistsWithoutChangingWordOrCompactClip() throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: "/private/tmp/ClampPreviewSize-" + UUID().uuidString)
        let store = ClipStore(root: root); store.hidden = true
        let pdf = ClipItem(kind: .file, title: "report.pdf"), word = ClipItem(kind: .file, title: "report.docx")
        store.state.items = [pdf, word]
        let manager = WindowManager(store: store)
        defer { manager.shutdown(); try? FileManager.default.removeItem(at: root) }
        let pdfModel = manager.model(pdf.id), wordModel = manager.model(word.id)
        pdfModel.present(animated: false); wordModel.present(animated: false)
        let pdfBefore = pdfModel.sheetSize, wordBefore = wordModel.sheetSize
        store.state.preferences.previewSizes[.pdf] = 1.5; store.changed(immediate: true)
        #expect(pdfModel.sheetSize.height > pdfBefore.height)
        #expect(wordModel.sheetSize == wordBefore)
        #expect(try store.storage.load().preferences.previewSizes[.pdf] == 1.5)
        pdfModel.expanded = false; pdfModel.revealProgress = 0; manager.layout(pdfModel)
        #expect(pdfModel.sheetSize == DockGeometry.compactSize)
    }
}
