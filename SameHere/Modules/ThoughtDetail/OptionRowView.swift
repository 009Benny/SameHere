//
//  OptionRowView.swift
//  SameHere
//
//  Created by Benny Reyes on 03/08/26.
//

import SwiftUI

struct OptionRowView: View {
    let option: OptionItem
    let total: Int
    let selected: UUID?
    let showPercentages: Bool
    
    let callback: ()->()
    
    
    var body: some View {
        Button(action: callback) {
            HStack(alignment: .center, spacing: 5) {
                Image(systemName: isSelected() ? "circle.fill" : "circle")
                    .foregroundColor(isSelected() ? .blue : .gray)
                    .padding(.horizontal, 10)
                
                Text(option.title)
                    .foregroundStyle(.primary)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                
                Spacer()
                
                if showPercentages || selected != nil {
                    Text("\(getPercentage(), specifier: "%.2f")%")
                        .padding(.horizontal, 20)
                }
                
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
            .background(alignment: .leading) {
                if showPercentages || selected != nil {
                    Color.blue.opacity(0.2)
                        .scaleEffect(x: getPercentage() / 100.0, y: 1.0, anchor: .leading)
                        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: getPercentage())
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 25))
        }
        .buttonStyle(.glass)
        .disabled(showPercentages || (selected != nil && selected != option.id) )
    }
    
    private func isSelected() -> Bool {
        showPercentages || (selected == option.id)
    }
    
    private func getPercentage() -> Double {
        guard total > 0 else { return 0 }
        return (Double(option.counter) / Double(total)) * 100
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
                counter: 20
            ),
            total: 500,
            selected: nil,
            showPercentages: false,
            callback: {}
        )
        
        OptionRowView(
            option: OptionItem(
                id: selected,
                title: "No, I'm not",
                counter: 20
        ),
            total: 500,
            selected: nil,
            showPercentages: true,
            callback: {}
        )
    }
    .padding(20)
    
}
