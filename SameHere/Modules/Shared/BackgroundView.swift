//
//  BackgroundView.swift
//  sameHere
//
//  Created by Benny Reyes on 03/08/26.
//

import SwiftUI

struct BackgroundView: View {
    var body: some View {
        ZStack{
            Color.whiteDM
            LinearGradient(
                colors: [
                    Color.backgroundYellow,
                    Color.backgroundPink,
                    Color.backgroundPurple,
                    Color.backgroundBlue
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            
        }
        .ignoresSafeArea()
    }
}

#Preview {
    BackgroundView()
}
