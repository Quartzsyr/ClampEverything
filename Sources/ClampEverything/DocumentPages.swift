import AppKit
import PDFKit

/// The PDF and TextKit objects stay on one worker actor. Only the current page
/// and two recent neighbours are cached, rather than rasterizing the whole file.
actor DocumentPages {
    let url: URL
    private var pdf: PDFDocument?
    private var storage: NSTextStorage?
    private var layout: NSLayoutManager?
    private var containers: [NSTextContainer] = []
    private var opened = false
    private var count = 0
    private var images: [Int: NSImage] = [:]
    init(url: URL) { self.url = url }
    func pageCount() throws -> Int { try open(); return count }
    func image(at index: Int) throws -> NSImage? {
        try open()
        guard (0..<count).contains(index) else { return nil }
        if let image = images[index] { return image }
        let image: NSImage?
        if let page = pdf?.page(at: index) { image = page.thumbnail(of: CGSize(width: 960, height: 1280), for: .mediaBox) }
        else if let layout {
            let container = containers[index]
            let range = layout.glyphRange(for: container)
            let pageSize = CGSize(width: 480, height: 640)
            // A flipped high-resolution context matches TextKit's top-left origin.
            let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 960, pixelsHigh: 1280,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            bitmap.size = pageSize
            NSGraphicsContext.saveGraphicsState()
            let context = NSGraphicsContext(bitmapImageRep: bitmap)!
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context.cgContext, flipped: true)
            context.cgContext.translateBy(x: 0, y: pageSize.height)
            context.cgContext.scaleBy(x: 1, y: -1)
            NSColor.white.setFill(); NSBezierPath(rect: CGRect(origin: .zero, size: pageSize)).fill()
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: CGRect(x: 24, y: 24, width: 432, height: 592)).addClip()
            layout.drawBackground(forGlyphRange: range, at: CGPoint(x: 24, y: 24))
            layout.drawGlyphs(forGlyphRange: range, at: CGPoint(x: 24, y: 24))
            NSGraphicsContext.restoreGraphicsState(); NSGraphicsContext.restoreGraphicsState()
            let rendered = NSImage(size: pageSize); rendered.addRepresentation(bitmap); image = rendered
        } else { image = nil }
        if let image {
            images[index] = image
            while images.count > 3, let farthest = images.keys.max(by: { abs($0 - index) < abs($1 - index) }) { images[farthest] = nil }
        }
        return image
    }
    private func open() throws {
        guard !opened else { return }
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url), !document.isLocked else { throw CocoaError(.fileReadCorruptFile) }
            pdf = document; count = document.pageCount; opened = true; return
        }
        let type: NSAttributedString.DocumentType
        switch url.pathExtension.lowercased() {
        case "docx": type = .officeOpenXML
        case "doc": type = .docFormat
        case "rtf": type = .rtf
        case "rtfd": type = .rtfd
        case "odt": type = .openDocument
        default: throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        let text = try NSAttributedString(url: url, options: [.documentType: type], documentAttributes: nil)
        let storage = NSTextStorage(attributedString: text), layout = NSLayoutManager()
        layout.backgroundLayoutEnabled = false
        storage.addLayoutManager(layout)
        self.storage = storage; self.layout = layout
        var end = 0
        repeat {
            let container = NSTextContainer(containerSize: CGSize(width: 432, height: 592))
            container.lineFragmentPadding = 0; layout.addTextContainer(container); containers.append(container)
            let range = layout.glyphRange(for: container)
            let next = NSMaxRange(range)
            if next <= end { break }
            end = next
        } while end < layout.numberOfGlyphs
        count = containers.count; opened = true
    }
}
