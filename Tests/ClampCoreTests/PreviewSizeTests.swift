import Foundation
import Testing
@testable import ClampCore

struct PreviewSizePreferenceTests {
    @Test func olderPreferencesUseNormalSizeAndEachTypePersistsSeparately() throws {
        let old = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))
        for kind in PreviewSizeKind.allCases { #expect(old.previewSizes[kind] == 1) }
        var preferences = old
        preferences.previewSizes[.pdf] = 1.55
        preferences.previewSizes[.document] = 0.8
        let restored = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(preferences))
        #expect(restored.previewSizes[.pdf] == 1.55)
        #expect(restored.previewSizes[.document] == 0.8)
        #expect(restored.previewSizes[.photo] == 1)
        preferences.previewSizes = PreviewSizes()
        #expect(preferences.previewSizes[.pdf] == 1)
    }
    @Test func invalidAndFutureValuesStayBounded() throws {
        let decoded = try JSONDecoder().decode(PreviewSizes.self, from: Data(#"{"pdf":99,"document":-1,"future":1.5}"#.utf8))
        #expect(decoded[.pdf] == 1.8)
        #expect(decoded[.document] == 0.65)
        #expect(decoded[.webpage] == 1)
        var sizes = decoded; sizes[.photo] = .nan; sizes[.text] = .infinity
        #expect(sizes[.photo] == 1 && sizes[.text] == 1)
    }
}
