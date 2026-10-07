//
//  Navigation.swift
//  sameHere
//
//  Created by Benny Reyes on 03/08/26.
//

import SwiftUI

struct SHTabView: View {
    @Environment(AppServices.self) private var services: AppServices?
    /// Shown once per account, until the community rules are accepted.
    @State private var needsCommunityRules = false

    var body: some View {
        TabView{
            Tab("Home", systemImage: "house"){
                HomeView()
            }
            Tab("My Thoughts", systemImage: "person.bubble"){
                MyThoughtsView()
            }
            Tab("Profile", systemImage: "person.crop.circle"){
                ProfileView()
            }
        }
        .task {
            guard let services, let user = services.currentUser else { return }
            // If the check itself fails (offline), don't lock the person out;
            // they'll be asked again next launch.
            let accepted = (try? await services.account.hasAcceptedTerms(userID: user.id)) ?? true
            needsCommunityRules = !accepted
        }
        .fullScreenCover(isPresented: $needsCommunityRules) {
            CommunityRulesView {
                guard let services, let user = services.currentUser else { return }
                try await services.account.acceptTerms(userID: user.id)
                needsCommunityRules = false
            }
        }
    }
}


#Preview {
    SHTabView()
}
