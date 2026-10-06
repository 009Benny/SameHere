//
//  Sections.swift
//  SameHere
//
//  Created by Benny Reyes on 04/08/26.
//

import Foundation

/// The topics a thought can be filed under.
///
/// `rawValue` is exactly what is stored in `thoughts.topic` — upper case with
/// no accents, the same format as the seeded questions (`TECNOLOGIA`), so
/// filtering by topic matches both. `title` is what the UI shows.
///
/// To add a topic, add a case here; nothing else needs to change.
enum Topic: String, CaseIterable, Identifiable {
    case general = "GENERAL"
    case tecnologia = "TECNOLOGIA"
    case entretenimiento = "ENTRETENIMIENTO"
    case deportes = "DEPORTES"
    case comida = "COMIDA"
    case viajes = "VIAJES"
    case relaciones = "RELACIONES"
    case trabajo = "TRABAJO"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .tecnologia: "Tecnología"
        case .entretenimiento: "Entretenimiento"
        case .deportes: "Deportes"
        case .comida: "Comida"
        case .viajes: "Viajes"
        case .relaciones: "Relaciones"
        case .trabajo: "Trabajo"
        }
    }
}
