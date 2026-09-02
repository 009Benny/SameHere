//
//  BadgeIconView.swift
//  SameHere
//
//  Created by Benny Reyes on 02/09/26.
//

import SwiftUI

/// Circular brand badge used as the visual anchor of auth and onboarding screens.
///
/// Renders the app logo (`logoDarkMode` — which already adapts to light/dark
/// appearance) inside a transparent circle of the requested diameter.
/// Marked `accessibilityHidden` because it is purely decorative — the screen
/// already exposes the title and instructions to VoiceOver.
struct BadgeIconView: View {
    /// Diameter (width and height) of the badge, in points.
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(Color.clear)
            .frame(width: size, height: size)
            .overlay {
                Image("hand")
                    .resizable()
            }
            .accessibilityHidden(true)
    }
}

#Preview {
    BadgeIconView(size: 180)
}
