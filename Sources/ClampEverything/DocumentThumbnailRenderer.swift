import AppKit
import PDFKit

/// These fallbacks keep document previews as images, with no embedded reader.
enum DocumentThumbnailRenderer {
    static let size = CGSize(width: 480, height: 640)
    static func firstPage(_ url: URL) -> NSImage? {
        if url.pathExtension.lowercased() == "pdf" {
            guard let document = PDFDocument(url: url), !document.isLocked, let page = document.page(at: 0) else { return nil }
            return page.thumbnail(of: size, for: .mediaBox)
        }
        guard url.pathExtension.lowercased() == "docx",
              let text = try? NSAttributedString(url: url, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil) else { return nil }
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.white.setFill(); NSBezierPath(rect: CGRect(origin: .zero, size: size)).fill()
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: CGRect(x: 24, y: 24, width: size.width - 48, height: size.height - 48)).addClip()
        text.draw(with: CGRect(x: 24, y: 24, width: size.width - 48, height: size.height - 48), options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
        image.unlockFocus()
        return image
    }
}
