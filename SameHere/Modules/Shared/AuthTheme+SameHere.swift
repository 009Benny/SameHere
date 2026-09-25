//
//  AuthTheme+SameHere.swift
//  SameHere
//

import AuthFeature
import SwiftUI

extension LoginTheme {
    /// Same Here's colours for the packaged auth screens.
    ///
    /// The package ships no art and no palette — the background and logo are
    /// passed in as views, and this supplies the type colours — so the login
    /// screen reads as part of the app rather than as a bolted-on framework.
    static let sameHere = LoginTheme(
        primaryTextColor: Color.primaryTextDarkMode,
        secondaryTextColor: Color.secondayTextDarkMode,
        accentColor: Color.accentColor
    )
}
