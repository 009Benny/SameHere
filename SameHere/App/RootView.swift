//
//  RootView.swift
//  SameHere
//

import AuthFeature
import SwiftUI

/// The gate. Everything the app shows hangs off ``AppCoordinator/phase``.
///
/// `SHTabView` appears only in the `signedIn` branch, and ``AppServices`` is put
/// into the environment there — so every screen behind the gate can reach the
/// session and the repositories, and none of them has to handle "what if there is
/// no session".
struct RootView: View {
    @State private var coordinator = AppCoordinator()

    var body: some View {
        ZStack {
            switch coordinator.phase {
            case .launching:
                LaunchView()

            case .misconfigured(let message):
                StatusView(
                    symbol: "gearshape.2",
                    title: "Not configured yet",
                    message: message,
                    actionTitle: "Try again"
                ) {
                    await coordinator.retry()
                }

            case .unreachable(let message):
                StatusView(
                    symbol: "wifi.exclamationmark",
                    title: "Can't reach Same Here",
                    // Said plainly, because the alarming reading of this screen is
                    // "my account is gone" — and it isn't.
                    message: message + "\n\n" + String(localized: "Your account is still on this device. It'll come back as soon as you're connected."),
                    actionTitle: "Try again",
                    secondaryActionTitle: "Sign in instead"
                ) {
                    await coordinator.retry()
                } secondaryAction: {
                    coordinator.continueToSignIn()
                }

            case .signedOut:
                if let services = coordinator.services {
                    AuthFlowView(coordinator: services.auth, theme: .sameHere) {
                        BackgroundView()
                            .opacity(0.4)
                    } logo: {
                        BadgeIconView(
                            image: Image("logo"),
                            size: 130,
                            padding: 0
                        )
                    }
                }

            case .signedIn:
                if let services = coordinator.services {
                    SHTabView()
                        .environment(services)
                        .environment(coordinator)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: coordinator.phase)
        .task { await coordinator.start() }
    }
}

/// Shown while the Keychain is read and the token refreshed. Usually one frame;
/// on a cold start with a slow network, a second or two.
struct LaunchView: View {
    var body: some View {
        ZStack {
            BackgroundView()
                .opacity(0.6)
            VStack(spacing: 18) {
                BadgeIconView(
                    image: Image("logo", bundle: .main),
                    size: 130
                )
                ProgressView()
                    .controlSize(.large)
            }
        }
    }
}

/// Full-screen message with one or two actions. Used for the two states that are
/// nobody's fault but somebody's problem: a build with no credentials, and a
/// launch with no network.
struct StatusView: View {
    let symbol: String
    // Keys, so the fixed titles are translated; `message` is built at runtime.
    let title: LocalizedStringKey
    let message: String
    let actionTitle: LocalizedStringKey
    var secondaryActionTitle: LocalizedStringKey?
    let action: () async -> Void
    var secondaryAction: (() -> Void)?

    @State private var isWorking = false

    var body: some View {
        ZStack {
            BackgroundView()

            ZStack {
                RoundedRectangle(cornerRadius: 22, style: .circular)
                    .viewGlassContainer(height: 300, hPadding: 0)
                    .padding(20)
                
                VStack(spacing: 16) {
                    
                    Image(systemName: symbol)
                        .font(.system(size: 44))
                        .foregroundStyle(Color.secondayTextDarkMode)

                    Text(title)
                        .font(.title2.bold())
                        .foregroundStyle(Color.primaryTextDarkMode)

                    Text(message)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.secondayTextDarkMode)
                        .textSelection(.enabled)

                    Button {
                        Task {
                            isWorking = true
                            await action()
                            isWorking = false
                        }
                    } label: {
                        HStack {
                            if isWorking { ProgressView() }
                            Text(actionTitle)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isWorking)
                    .padding(.top, 8)

                    if let secondaryActionTitle, let secondaryAction {
                        Button(secondaryActionTitle, action: secondaryAction)
                            .font(.footnote)
                    }
                }
                .padding(32)
            }
            
        }
    }
}

#Preview("Launch") {
    LaunchView()
}

#Preview("Not configured") {
    StatusView(
        symbol: "gearshape.2",
        title: "Not configured yet",
        message: "`SUPABASE_ANON_KEY` is missing from the app's Info.plist.",
        actionTitle: "Try again"
    ) { }
}
