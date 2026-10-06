//
//  ViewExtension.swift
//  SameHere
//
//  Created by Benny Reyes on 04/08/26.
//
import SwiftUI

extension View {

    /// Shared visual container used by every auth field (plain or secure).
    ///
    /// Applies the brand typography, a thin glass capsule background and a
    /// soft drop shadow.
    /// - Parameter castsShadow: `false` for a container covered by another one,
    ///   like the cards under the top of the Home stack. The material is
    ///   translucent — especially in dark mode — so shadows underneath show
    ///   through and add up into a dark frame.
    func viewGlassContainer(
        height: CGFloat = 45,
        hPadding: CGFloat = 10,
        cornerRadius: CGFloat = 22,
        castsShadow: Bool = true
    ) -> some View {
        self
            .foregroundStyle(Color.glassBackground)
            .padding(.horizontal, hPadding)
            .frame(height: height)
            .background(.thinMaterial)
            .cornerRadius(cornerRadius)
            // Fades rather than switches, so a card reaching the top of the
            // stack gains its shadow smoothly.
            .shadow(color: .black.opacity(castsShadow ? 0.1 : 0), radius: 16, x: 0, y: 2)
    }
}
