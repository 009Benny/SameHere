//
//  GuestBanner.swift
//  SameHere
//

import SwiftUI

/// The nudge that turns a guest into a saved account.
///
/// Placed on My Thoughts on purpose: that screen is, by definition, a list of
/// exactly what the person would lose. Asking on the login screen would be asking
/// before they have anything at stake; asking here answers a question they are
/// already starting to ask themselves.
///
/// It names the real risk in one line rather than saying "create an account to
/// unlock features" — nothing is locked, and pretending otherwise would be the
/// kind of small lie that costs trust later.
struct GuestBanner: View {
    let thoughtCount: Int
    let onSave: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 6) {
                Text(headline)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.primaryTextDarkMode)

                Text("You're signed in as a guest, so everything lives only on this iPhone. Add an email and you'll keep it if you switch phones.")
                    .font(.caption)
                    .foregroundStyle(Color.secondayTextDarkMode)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Save my account", action: onSave)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(.top, 2)
            }

            Spacer(minLength: 0)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.secondayTextDarkMode)
                    .padding(6)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(14)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        }
        .padding(.horizontal, 16)
    }

    private var headline: String {
        switch thoughtCount {
        case 0: "Your account isn't saved"
        case 1: "1 thought at risk"
        default: "\(thoughtCount) thoughts at risk"
        }
    }
}

#Preview {
    ZStack {
        BackgroundView()
        VStack(spacing: 16) {
            GuestBanner(thoughtCount: 0, onSave: {}, onDismiss: {})
            GuestBanner(thoughtCount: 3, onSave: {}, onDismiss: {})
        }
    }
}
