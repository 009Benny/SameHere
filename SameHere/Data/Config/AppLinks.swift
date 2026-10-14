//
//  AppLinks.swift
//  SameHere
//

import Foundation

/// Public pages the app links to. App Review checks that these load.
/// `support` is also the Support URL to enter in App Store Connect.
enum AppLinks {
    static let termsOfUse = URL(string: "https://www.bennyreyes.dev/sameHere/terms")!
    static let privacyPolicy = URL(string: "https://www.bennyreyes.dev/sameHere/privacy")!
    static let support = URL(string: "https://www.bennyreyes.dev/contact")!
}
