//
//  ThoughView.swift
//  SameHere
//
//  Created by Benny Reyes on 03/08/26.
//

import SwiftUI

struct ThoughView: View {
    let thought: Thought
    let isFullScreen:Bool
    var animation: Namespace.ID
    var answerAction: ((UUID) -> ())?
    var closeAction: (() -> ())?
    @State private var selected: UUID? = nil
    
    var body: some View {
        ZStack{
            if isFullScreen {
                BackgroundView()
            }
            VStack {
                if isFullScreen {
                    HStack {
                        Spacer()
                        Button(action: {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                closeAction?()
                            }
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title)
                                .foregroundColor(.white.opacity(0.7))
                        }
                    }
        
                    Spacer()
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .circular)
                        .viewGlassContainer(height: 300)
                        .matchedGeometryEffect(id: "background_\(thought.id)", in: animation)
                    
                    Text(thought.message)
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .font(.headline)
                }
                
                
                if isFullScreen {
                    Spacer()
                    ForEach(thought.options) { option in
                        OptionRowView(
                            option: option,
                            selected: selected,
                        ) {
                            answerAction?(option.id)
                            selected = option.id
                        }
                    }
                    Spacer()
                }
            }
            .padding(20)
        }
    }
}

#Preview {
    HomeView()
}

//#Preview {
//    let tought = Thought(
//        id: UUID(),
//        user: User(
//            id: UUID(),
//            name: "Benny",
//            email: "benny@mail.com"
//        ),
//        message: "Are you unemployed?",
//        options: [
//            OptionItem(
//                id: UUID(),
//                title: "Yes, I am",
//                counter: 50
//            ),
//            OptionItem(
//                id: UUID(),
//                title: "No, I'm not",
//                counter: 100
//            )
//        ], topic: "Topic"
//    )
//    ThoughView(thought: tought, answerAction: {}, isFullScreen: true)
//}
