//
//  SupabaseConfig.swift
//  SameHere
//

import AuthFeature
import Foundation

/// Reads the Supabase credentials the app was built with.
///
/// The values come from `Config/Secrets.xcconfig` → the generated `Info.plist`
/// (see that file's header for the one-time Xcode wiring). Nothing is hardcoded
/// here, and the real xcconfig is git-ignored.
///
/// Failure is loud and explains itself: a missing key is a build-configuration
/// mistake, and a blank screen or a silent 404 would send you looking in the
/// wrong place for it.
nonisolated enum SupabaseConfig {

    enum Failure: LocalizedError {
        case missingKey(String)
        case malformedURL(String)

        var errorDescription: String? {
            switch self {
            case .missingKey(let key):
                return """
                `\(key)` is missing from the app's Info.plist.

                1. Copy Config/Secrets.example.xcconfig to Config/Secrets.xcconfig \
                and fill in your project's values.
                2. In Xcode: Project "SameHere" → Info → Configurations → set both \
                Debug and Release to "Secrets".
                3. Clean the build folder (⇧⌘K) and run again.
                """
            case .malformedURL(let value):
                return """
                "\(value)" is not a usable Supabase URL.

                SUPABASE_HOST should be just the host — abcdefghijkl.supabase.co — \
                with no https:// prefix. In an xcconfig, `//` starts a comment, so a \
                full URL gets truncated to "https:".
                """
            }
        }
    }

    /// Builds the auth configuration from the bundle's Info.plist.
    ///
    /// - Parameter bundle: Injectable for tests.
    /// - Throws: ``Failure`` naming the exact key that is missing.
    static func load(bundle: Bundle = .main) throws -> SupabaseAuthConfiguration {
        let anonKey = try string("SUPABASE_ANON_KEY", in: bundle)

        // SUPABASE_URL wins when set (local / self-hosted); otherwise the host is
        // the normal path and the scheme is added here.
        let urlString: String
        if let explicit = optionalString("SUPABASE_URL", in: bundle) {
            urlString = explicit
        } else {
            urlString = "https://" + (try string("SUPABASE_HOST", in: bundle))
        }

        guard let url = URL(string: urlString),
              url.scheme?.hasPrefix("http") == true,
              url.host != nil else {
            throw Failure.malformedURL(urlString)
        }

        return SupabaseAuthConfiguration(
            projectURL: url,
            anonKey: anonKey,
            // Add a redirect here once there is a deep link for password recovery,
            // and list the same URL under Authentication → URL Configuration.
            redirectURL: nil
        )
    }

    // MARK: - Info.plist

    private static func string(_ key: String, in bundle: Bundle) throws -> String {
        guard let value = optionalString(key, in: bundle) else {
            throw Failure.missingKey(key)
        }
        return value
    }

    private static func optionalString(_ key: String, in bundle: Bundle) -> String? {
        // An unsubstituted xcconfig variable arrives as the literal "$(NAME)", and
        // the placeholder from the example file arrives verbatim. Both mean "not
        // configured", and both would otherwise fail much later as a 401.
        guard let raw = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.hasPrefix("$("),
              value != "paste-your-anon-key-here",
              value != "abcdefghijkl.supabase.co" else { return nil }
        return value
    }
}
