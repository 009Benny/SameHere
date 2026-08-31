//
//  OptionRowView.swift
//  SameHere
//
//  Created by Benny Reyes on 03/08/26.
//

import SwiftUI

struct OptionRowView: View {
    let option: OptionItem
    let selected: UUID?
    
    let callback: ()->()
    
    
    var body: some View {
        Button(action: callback) {
            ZStack{
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .viewGlassContainer()
                    
                HStack(alignment: .center, spacing: 5) {
                    Image(systemName: isSelected() ? "circle.fill" : "circle")
                        .tint(isSelected() ? .blue : .gray)
                        .padding(.horizontal, 10)
                    
                    Text(option.title)
                        .tint(.blackDM)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                    
                    Spacer()
                    
                    if selected != nil {
                        Text("\(option.counter)")
                            .padding(.horizontal, 20)
                    }
                    
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 10)
            }
            .frame(height: 50)
            
        }
        .disabled(selected != nil && selected != option.id)
    }
    
    private func isSelected() -> Bool {
        selected == option.id
    }
}

#Preview {
    let selected = UUID()
//    let notSelected = UUID()
    VStack {
        OptionRowView(
            option: OptionItem(
                id: selected,
                title: "Yes, I am",
                counter: 50),
            selected: nil,
            callback: {}
        )
        
        OptionRowView(
            option: OptionItem(
                id: selected,
                title: "No, I'm not",
                counter: 50),
            selected: nil,
            callback: {}
        )
    }
    
}
