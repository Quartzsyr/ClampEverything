import AppKit
import SwiftUI
import PDFKit
import ClampCore

/// Offline examples are held in memory. Only our own temporary documents are
/// written for the same first-page renderer used by real pinned documents.
@MainActor final class GuideExamples: ObservableObject {
    let webPage = WebPagePreviewModel()
    let photo: NSImage
    let pdf: NSImage?
    let document: NSImage?
    static let note = "周末的小计划\n\n去海边走走，带上相机。\n把喜欢的风景，夹在手边。\n\n周六 09:30 · 晴"
    static let code = "import SwiftUI\n\nstruct LittleNote: View {\n    let message = \"留住灵感\"\n\n    var body: some View {\n        Text(message)\n            .padding(20)\n    }\n}"
    static let html = """
    <!doctype html><html lang="zh"><meta charset="utf-8"><style>
    *{box-sizing:border-box}body{margin:0;background:#f6f3eb;color:#283a35;font-family:system-ui}nav{padding:32px 54px;border-bottom:1px solid #ccd4c6;letter-spacing:3px}main{padding:45px 54px}small{color:#65776c}h1{font-size:52px;font-weight:500;line-height:1.2;margin:18px 0}p{font-size:23px;color:#65776c}section{display:flex;gap:28px;margin-top:40px}article{width:42%;padding:25px;background:#e3e8dd}b{font-size:25px}article p{font-size:19px}</style>
    <nav>FIELD NOTES / 田野手记</nav><main><small>周末阅读 · VOL. 08</small><h1>把日常的风景，<br>留在手边。</h1><p>一束光、一段文字、一个值得回来的页面。</p><section><article><b>山间漫步</b><p>给自己留一点空白。</p></article><article><b>纸上灵感</b><p>记录细小而珍贵的发现。</p></article></section></main></html>
    """
    init() {
        photo = Self.landscape()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ClampGuide-" + UUID().uuidString)
        var pdfImage: NSImage?, documentImage: NSImage?
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let page = Self.page()
            let file = PDFDocument(); if let pdfPage = PDFPage(image: page) { file.insert(pdfPage, at: 0) }
            let pdfURL = root.appendingPathComponent("旅行手记.pdf")
            if file.write(to: pdfURL) { pdfImage = DocumentThumbnailRenderer.firstPage(pdfURL) }
            let text = NSMutableAttributedString(string: "周末出行计划\n\n", attributes: [.font: NSFont.systemFont(ofSize: 28, weight: .semibold)])
            text.append(NSAttributedString(string: "目的地：海边的小镇\n日期：本周六\n\n09:30  出发，带上相机和水\n11:00  沿海岸散步，记录风景\n14:00  找一家小店，写写手记\n17:00  趁夕阳回家\n\n随身物品\n相机 / 充电线 / 一本空白笔记\n\n把喜欢的片段夹在手边。", attributes: [.font: NSFont.systemFont(ofSize: 18), .foregroundColor: NSColor.darkGray]))
            let docURL = root.appendingPathComponent("出行计划.docx")
            try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML]).write(to: docURL)
            documentImage = DocumentThumbnailRenderer.firstPage(docURL)
        } catch { /* The same legible page remains available if native document import is unavailable. */ }
        pdf = pdfImage ?? Self.page(); document = documentImage ?? Self.page()
    }
    static func filename(_ kind: PreviewSizeKind) -> String {
        switch kind {
        case .text: return "周末的小计划"
        case .photo: return "山间湖泊.png"
        case .pdf: return "旅行手记.pdf"
        case .document: return "出行计划.docx"
        case .webpage: return "田野手记 · 网页首屏"
        case .code: return "LittleNote.swift"
        case .folder: return "周末旅行"
        case .collection: return "这次旅行的材料"
        case .audio: return "午后的录音.m4a"
        case .video: return "湖边的风.mov"
        case .archive: return "旅行资料.zip"
        case .file: return "相机配置.dat"
        }
    }
    static func explanation(_ kind: PreviewSizeKind) -> String {
        switch kind {
        case .text: return "复制的文字变成一张便笺，随手保留灵感。"
        case .photo: return "照片和截图保持比例，像一张夹住的相纸。"
        case .pdf: return "PDF 保留原页码，滚轮或页角翻页；右键可以快速预览。"
        case .document: return "Word 等文稿可以滚轮分页；拖出时交付原文档。"
        case .webpage: return "链接呈现实时网页，可以滚轮上下浏览，拖出保留原地址。"
        case .code: return "代码显示行号与语法颜色，保留原文件。"
        case .folder: return "文件夹是一只文件袋，可以逐层浏览，拖入文件进行复制。"
        case .collection: return "将多个夹项合并，一只资料袋收纳照片、便笺与文件。"
        case .audio: return "录音成为一盘卡带，打开时交给系统关联应用。"
        case .video: return "视频成为带首帧的胶片，拖出时仍是原视频。"
        case .archive: return "压缩包像牛皮纸收纳袋，保留原压缩文件。"
        case .file: return "其他文件保留原件引用，有系统缩略图时显示缩略图。"
        }
    }
    private static func page() -> NSImage {
        let image = NSImage(size: CGSize(width: 480, height: 640)); image.lockFocus()
        NSColor.white.setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: 480, height: 640)).fill()
        ("旅行手记" as NSString).draw(at: CGPoint(x: 40, y: 550), withAttributes: [.font: NSFont.systemFont(ofSize: 34, weight: .medium), .foregroundColor: NSColor.darkGray])
        ("A LITTLE JOURNEY / 2026" as NSString).draw(at: CGPoint(x: 42, y: 520), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular), .foregroundColor: NSColor.gray])
        landscape().draw(in: CGRect(x: 40, y: 265, width: 400, height: 225))
        ("山间的湖面，像一张留白的纸。\n停下来，记住这一刻。\n\n路线：林间小径 → 湖边 → 山谷\n随行：相机、笔记与好天气" as NSString).draw(in: CGRect(x: 42, y: 70, width: 396, height: 170), withAttributes: [.font: NSFont.systemFont(ofSize: 17), .foregroundColor: NSColor.darkGray])
        image.unlockFocus(); return image
    }
    private static func landscape() -> NSImage {
        let image = NSImage(size: CGSize(width: 800, height: 500)); image.lockFocus()
        NSGradient(starting: NSColor(calibratedRed: 0.76, green: 0.87, blue: 0.86, alpha: 1), ending: NSColor(calibratedRed: 0.94, green: 0.94, blue: 0.83, alpha: 1))!.draw(in: CGRect(x: 0, y: 0, width: 800, height: 500), angle: 90)
        NSColor(calibratedRed: 0.95, green: 0.89, blue: 0.67, alpha: 1).setFill(); NSBezierPath(ovalIn: CGRect(x: 580, y: 355, width: 72, height: 72)).fill()
        for (points, color) in [([CGPoint(x: 0, y: 170), CGPoint(x: 240, y: 420), CGPoint(x: 480, y: 170)], NSColor(calibratedRed: 0.40, green: 0.57, blue: 0.53, alpha: 1)),
            ([CGPoint(x: 220, y: 150), CGPoint(x: 580, y: 360), CGPoint(x: 800, y: 150)], NSColor(calibratedRed: 0.25, green: 0.43, blue: 0.39, alpha: 1))] {
            let path = NSBezierPath(); path.move(to: points[0]); points.dropFirst().forEach { path.line(to: $0) }; path.close(); color.setFill(); path.fill()
        }
        NSColor(calibratedRed: 0.42, green: 0.65, blue: 0.64, alpha: 1).setFill(); NSBezierPath(rect: CGRect(x: 0, y: 0, width: 800, height: 170)).fill()
        NSColor.white.withAlphaComponent(0.3).setStroke()
        for y in stride(from: 25, to: 155, by: 25) { let line = NSBezierPath(); line.move(to: CGPoint(x: y * 2, y: y)); line.line(to: CGPoint(x: 760 - y, y: y)); line.lineWidth = 1; line.stroke() }
        image.unlockFocus(); return image
    }
}
