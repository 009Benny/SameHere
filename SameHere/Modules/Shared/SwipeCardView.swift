//
//  CardView.swift
//  SameHere
//
//  Created by Benny Reyes on 04/08/26.
//

import SwiftUI

struct SwipeCardView<Content:View>: View {
    let content: Content
    var swipeAction: (SwipeDirection) -> ()
    var onTapAction: () -> ()
    @State private var offset = CGSize.zero
    
    var body: some View {
        ZStack() {
            content
        }
        
        .onTapGesture {
            onTapAction()
        }
        .offset(x: offset.width, y: offset.height * 0.4)
        .rotationEffect(.degrees(Double(offset.width / 15)))
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    offset = gesture.translation
                }
                .onEnded { _ in
                    // If the drag exceeds the tresshold, delete the card
                    if abs(offset.width) > 150 {
                        withAnimation(.easeOut(duration: 0.2)) {
                            // Sent the card outside the window before delete it
                            offset.width = offset.width > 0 ? 500 : -500
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            swipeAction(.left)
                        }
                    } else {
                        // If don't exceed the tresshold, it returns to its center with a spring action
                        withAnimation(.spring()) {
                            offset = .zero
                        }
                    }
                }
        )
    }
    
}
    
#Preview {
    HomeView()
}
