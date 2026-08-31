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
    func viewGlassContainer(
        height: CGFloat = 45,
        hPadding: CGFloat = 10,
        cornerRadius: CGFloat = 22
    ) -> some View {
        self
            .foregroundStyle(Color.glassBackground)
            .padding(.horizontal, hPadding)
            .frame(height: height)
            .background(.thinMaterial)
            .cornerRadius(cornerRadius)
            .shadow(color: .black.opacity(0.1), radius: 16, x: 0, y: 2)
    }
}
