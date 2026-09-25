//
//  SameHereApp.swift
//  SameHere
//
//  Created by Benny Reyes on 03/08/26.
//

import SwiftUI

@main
struct SameHereApp: App {
    var body: some Scene {
        WindowGroup {
            // Everything — configuration, session restore, the auth gate and
            // SHTabView — hangs off RootView. See `App/AppCoordinator.swift`.
            RootView()
        }
    }
}
