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
    var isDetail:Bool
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
                if isFullScreen && closeAction != nil {
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
                            showPercentages: isDetail
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
