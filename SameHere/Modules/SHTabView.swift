//
//  Navigation.swift
//  sameHere
//
//  Created by Benny Reyes on 03/08/26.
//

import SwiftUI

struct SHTabView: View {
    var body: some View {
        TabView{
            Tab("Home", systemImage: "house"){
                HomeView()
            }
            Tab("My Toughts", systemImage: "person.bubble"){
                MyThoughtsView()
            }
        }
    }
}


#Preview {
    SHTabView()
}
