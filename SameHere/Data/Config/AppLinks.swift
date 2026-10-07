//
//  AppLinks.swift
//  SameHere
//

import Foundation

/// Public pages the app links to. App Review checks that these load.
///
/// TODO before submitting: replace the placeholders with your real pages and
/// support address (items 13–15 of the release checklist).
enum AppLinks {
    static let termsOfUse = URL(string: "https://www.bennyreyes.dev/sameHere/terms")!
    static let privacyPolicy = URL(string: "https://www.bennyreyes.dev/sameHere/privacy")!
    static let supportEmail = URL(string: "mailto:bennyreyesdev@gmail.com")!
}
