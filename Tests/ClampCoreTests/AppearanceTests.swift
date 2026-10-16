import Foundation
import Testing
@testable import ClampCore

struct AppearanceTests {
    @Test func oldPreferencesReceiveUsableAppearanceAndBehaviorDefaults() throws {
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: Data("{}".utf8))
        #expect(!preferences.showBrassClip)
        #expect(!AppPreferences().showBrassClip)
        #expect(preferences.folderTint == .kraft)
        #expect(preferences.noteStock == .natural)
        #expect(preferences.autoSnap)
        #expect(preferences.snapDistance == 42)
        #expect(preferences.hoverToExpand)
        #expect(preferences.hoverDelay == 0.35)
        #expect(preferences.motionIntensity == 1)
    }
    @Test func customizedPreferencesRoundTripWithoutChangingShortcuts() throws {
        var preferences = AppPreferences()
        preferences.showBrassClip = true
        preferences.folderTint = .ocean; preferences.noteStock = .ruled
        preferences.autoSnap = false; preferences.snapDistance = 70
        preferences.motionIntensity = 0; preferences.hoverToExpand = false
        preferences.hoverDelay = 0.8; preferences.defaultSide = .left
        preferences.holdToClampEnabled = true
        #expect(try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(preferences)) == preferences)
    }
    @Test func invalidSavedSettingsAreBoundedAndUnknownStylesFallBack() throws {
        let data = Data(#"{"folderTint":"retired","noteStock":"unknown","motionIntensity":99,"snapDistance":-10,"hoverDelay":0}"#.utf8)
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: data)
        #expect(preferences.folderTint == .kraft); #expect(preferences.noteStock == .natural)
        #expect(preferences.motionIntensity == 1.5); #expect(preferences.snapDistance == 16); #expect(preferences.hoverDelay == 0.1)
    }
    @Test func paperIsReservedForTextAndPhotoFlexDoesNotReachFolder() {
        #expect(ContentHousing.forKind(.folder) == .folder)
        #expect(!ContentHousing.forKind(.folder).isFlexible)
        #expect(ContentHousing.forKind(.text) == .note)
        #expect(ContentHousing.forKind(.text).isFlexible)
        #expect(ContentHousing.forKind(.file) == .file)
        #expect(ContentHousing.forKind(.link) == .link)
        #expect(ContentHousing.forKind(nil) == .collection)
    }
}
