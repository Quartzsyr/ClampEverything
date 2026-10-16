import AppKit
import ClampCore

@MainActor enum MinimalSurfaceLayout {
    static func sheetSize(item: ClipItem?, imageSize: CGSize?, limit: CGSize, scale: Double = 1, maximumSize: CGSize? = nil) -> CGSize {
        let factor = CGFloat(scale.isFinite ? min(PreviewSizes.range.upperBound, max(PreviewSizes.range.lowerBound, scale)) : 1)
        let ceiling = maximumSize ?? CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        guard let item, item.kind != .folder else {
            return CGSize(width: min(ceiling.width, ceil(limit.width * factor)),
                          height: min(ceiling.height, ceil((limit.height - ClipOrientation.verticalMargins) * factor + ClipOrientation.verticalMargins)))
        }
        let form = PinnedContentForm.forItem(item)
        let available = CGSize(width: max(1, limit.width - 24), height: max(1, limit.height - ClipOrientation.verticalMargins))
        let body: CGSize
        switch form {
        case .photo:
            body = fit(imageSize ?? available, into: available)
        case .documentPrint:
            body = fit(imageSize ?? CGSize(width: 3, height: 4), into: CGSize(width: available.width, height: min(ContentPreviewLayout.thumbnailHeight, available.height)))
        case .webPrint:
            body = fit(ContentPreviewLayout.webViewport, into: CGSize(width: available.width, height: min(ContentPreviewLayout.webpageHeight, available.height)))
        case .notePage:
            let width = min(260, available.width)
            let paragraph = NSMutableParagraphStyle(); paragraph.lineSpacing = 5
            let text = String((item.text ?? "").prefix(8000)) as NSString
            let measured = text.boundingRect(with: CGSize(width: max(1, width - 36), height: 100_000), options: [.usesLineFragmentOrigin, .usesFontLeading],
                                             attributes: [.font: NSFont.systemFont(ofSize: 14), .paragraphStyle: paragraph])
            body = CGSize(width: width, height: min(available.height, max(96, min(300, ceil(measured.height) + 44))))
        case .codePage:
            body = CGSize(width: min(360, available.width), height: min(220, available.height))
        case .cassette:
            body = fit(CGSize(width: 280, height: 176), into: CGSize(width: min(280, available.width), height: available.height))
        case .filmStrip:
            body = fit(CGSize(width: 288, height: 168), into: CGSize(width: min(288, available.width), height: available.height))
        case .parcel:
            body = fit(CGSize(width: 240, height: 150), into: CGSize(width: min(240, available.width), height: available.height))
        case .fileSheet:
            body = fit(imageSize ?? CGSize(width: 4, height: 3), into: CGSize(width: min(240, available.width), height: min(192, available.height)))
        case .pocket: body = available
        }
        let desired = CGSize(width: body.width * factor, height: body.height * factor)
        let bounded = fit(desired, into: CGSize(width: min(desired.width, max(1, ceiling.width - 24)),
                                                height: min(desired.height, max(1, ceiling.height - ClipOrientation.verticalMargins))))
        let result = CGSize(width: bounded.width + 24, height: bounded.height + ClipOrientation.verticalMargins)
        // NSWindow rounds nonintegral frames; keep model and native bounds equal.
        return form == .photo ? result : CGSize(width: ceil(result.width), height: ceil(result.height))
    }
    private static func fit(_ source: CGSize, into available: CGSize) -> CGSize {
        guard source.width > 0, source.height > 0 else { return available }
        let scale = min(available.width / source.width, available.height / source.height)
        return CGSize(width: source.width * scale, height: source.height * scale)
    }
}


extension PreviewSizeKind {
    static func forItem(_ item: ClipItem?) -> Self {
        guard let item else { return .collection }
        switch PinnedContentForm.forItem(item) {
        case .pocket: return .folder
        case .photo: return .photo
        case .notePage: return .text
        case .codePage: return .code
        case .webPrint: return .webpage
        case .cassette: return .audio
        case .filmStrip: return .video
        case .parcel: return .archive
        case .fileSheet: return .file
        case .documentPrint:
            let url = URL(fileURLWithPath: item.originalPath ?? item.title)
            return url.pathExtension.lowercased() == "pdf" ? .pdf : .document
        }
    }
}
