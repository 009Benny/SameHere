//
//  ReportReason.swift
//  SameHere
//

import Foundation

/// Why a thought is being reported. `rawValue` is what `public.reports.reason`
/// stores — the check constraint in `supabase/moderation.sql` lists the same
/// five values.
enum ReportReason: String, CaseIterable, Identifiable {
    case offensive
    case harassment
    case sexual
    case spam
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .offensive: String(localized: "Offensive or hateful")
        case .harassment: String(localized: "Harassment or bullying")
        case .sexual: String(localized: "Sexual content")
        case .spam: String(localized: "Spam")
        case .other: String(localized: "Something else")
        }
    }
}
