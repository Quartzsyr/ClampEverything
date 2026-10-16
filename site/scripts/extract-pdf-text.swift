// Generate selectable text from the actual image-only demo PDF, without
// changing its bytes or inventing document content. Run on macOS.
import AppKit
import PDFKit
import Vision
import CryptoKit

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let bytes = try Data(contentsOf: input)
let pdf = PDFDocument(data: bytes)!
var pages: [[[String: Any]]] = []
for index in 0..<pdf.pageCount {
    let page = pdf.page(at: index)!, size = page.bounds(for: .mediaBox).size
    let image = page.thumbnail(of: CGSize(width: size.width * 3, height: size.height * 3), for: .mediaBox)
    let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["zh-Hans", "en-US"]
    request.usesLanguageCorrection = false
    try VNImageRequestHandler(cgImage: cgImage).perform([request])
    let lines: [[String: Any]] = (request.results ?? []).compactMap { observation in
        guard let text = observation.topCandidates(1).first else { return nil }
        let r = observation.boundingBox
        return ["text": text.string, "x": Double(r.minX), "y": Double(1 - r.maxY), "width": Double(r.width), "height": Double(r.height), "confidence": text.confidence]
    }.sorted { ($0["y"] as! Double) < ($1["y"] as! Double) }
    pages.append(lines)
}
let result: [String: Any] = ["sourceSHA256": SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined(), "method": "Apple Vision accurate recognition of the original PDF page pixels", "pages": pages]
try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output)
