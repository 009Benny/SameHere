//
//  LocalizationTests.swift
//  SameHereTests
//

import Foundation
import Testing
@testable import SameHere

struct LocalizationTests {

    /// The app's Latin-American Spanish strings.
    private var spanish: Bundle? {
        // A class defined in the app (not the test bundle) points at the app's resources.
        let app = Bundle(for: HomeViewModel.self)
        return app.path(forResource: "es-419", ofType: "lproj").flatMap(Bundle.init(path:))
    }

    @Test func appShipsSpanishStrings() {
        #expect(spanish != nil)
    }

    @Test(arguments: [
        "Technology", "Entertainment", "Sports", "Food", "Travel", "Relationships", "Work",
        "Offensive or hateful", "Harassment or bullying", "Sexual content", "Something else",
        "You appear to be offline. Check your connection and try again.",
        "Your session expired. Please sign in again.",
        "You already answered this one.",
        "You don't have permission to do that.",
        "Sign in to continue", "Sign in",
        "Guests can read and vote. To share your own thought, sign in or create an account.",
        "To report a thought, sign in or create an account. This keeps reports from being abused.",
        "To block someone, sign in or create an account.",
        "New questions", "Off", "Daily", "Weekly", "Open Settings"
    ])
    func keyIsTranslatedToSpanish(key: String) throws {
        let bundle = try #require(spanish)
        let translated = bundle.localizedString(forKey: key, value: "__missing__", table: nil)
        #expect(translated != "__missing__", "\"\(key)\" has no Spanish entry")
        #expect(translated != key, "\"\(key)\" is not translated")
    }
}
