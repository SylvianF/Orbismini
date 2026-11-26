import Foundation
import SwiftUI

/// Réglages fixes d’Orbismini, communs à l’application et au widget.
enum Config {
    static let host = "mon-cours-or.onrender.com"
    static let baseURL = URL(string: "https://" + host)!
    static let appGroup = "group.fr.cndo.orbismini"
    static let sessionCookie = "goldapp_session"

    /// Lancement avec « -demo » : données d’exemple, sans réseau (captures d’écran de GitHub Actions).
    static var isDemo: Bool { ProcessInfo.processInfo.arguments.contains("-demo") }

    /// Lancement avec « -ecran meteo » (captures) : écran ouvert au démarrage.
    static var startScreen: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-ecran"), i + 1 < args.count else { return nil }
        return args[i + 1]
    }

    /// Environnement des notifications d’Apple pour cette compilation.
    static var apnsEnvironment: String {
        #if DEBUG
        return "sandbox"
        #else
        return "production"
        #endif
    }
}

/// Thèmes d’Orbismini, les mêmes que le site (theme.js) : Saphir, Onyx, Perle. Choix gardé dans
/// le groupe partagé (widget compris) sous la même clé que le site, « orbismini-theme ».
enum ThemeChoice: String, CaseIterable, Identifiable {
    case saphir = "dark", onyx = "graphite", perle = "light"

    static let key = "orbismini-theme"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .saphir: return "Saphir"
        case .onyx: return "Onyx"
        case .perle: return "Perle"
        }
    }
    var isLight: Bool { self == .perle }
    var colorScheme: ColorScheme { isLight ? .light : .dark }

    static var current: ThemeChoice {
        ThemeChoice(rawValue: SharedStore.defaults.string(forKey: key) ?? "") ?? .saphir
    }
}

struct Palette {
    let bg1, bg2, card, line, text, muted, gold, silver, up, down: UInt32

    // Couleurs calculées avec les règles de theme.js (Onyx : ardoises noircies ; Perle : clair).
    static let saphir = Palette(bg1: 0x1B2A34, bg2: 0x121D25, card: 0x1F313D, line: 0x344853, text: 0xEDF2F5,
                                muted: 0xB5C7D3, gold: 0xE9BF75, silver: 0xD0DAE5, up: 0x8FDFB0, down: 0xFF9CA4)
    static let onyx = Palette(bg1: 0x202021, bg2: 0x161617, card: 0x252626, line: 0x373738, text: 0xF2F1F0,
                              muted: 0xC5C4C3, gold: 0xE9BF75, silver: 0xDCDBD9, up: 0x8FDFB0, down: 0xFF9CA4)
    static let perle = Palette(bg1: 0xF7F1E6, bg2: 0xECE3D3, card: 0xFFFFFF, line: 0xD6C7AD, text: 0x21292F,
                               muted: 0x556774, gold: 0xCA8D20, silver: 0x3A4852, up: 0x2D9F5C, down: 0xCC0010)
}

/// Couleurs du thème choisi.
enum Theme {
    static var palette: Palette {
        switch ThemeChoice.current {
        case .saphir: return .saphir
        case .onyx: return .onyx
        case .perle: return .perle
        }
    }
    static var bg1: Color { Color(hex: palette.bg1) }
    static var bg2: Color { Color(hex: palette.bg2) }
    static var card: Color { Color(hex: palette.card) }
    static var line: Color { Color(hex: palette.line) }
    static var text: Color { Color(hex: palette.text) }
    static var muted: Color { Color(hex: palette.muted) }
    static var gold: Color { Color(hex: palette.gold) }
    static var silver: Color { Color(hex: palette.silver) }
    static var up: Color { Color(hex: palette.up) }
    static var down: Color { Color(hex: palette.down) }
    /// Texte posé sur un bouton or.
    static var onGold: Color { ThemeChoice.current.isLight ? .white : Color(hex: 0x18242B) }

    static var background: LinearGradient {
        LinearGradient(colors: [bg1, bg2], startPoint: .top, endPoint: .bottom)
    }

    static func trend(_ delta: Double?) -> Color {
        guard let delta else { return muted }
        return delta > 0 ? up : delta < 0 ? down : muted
    }

    static func metal(_ m: Metal) -> Color { m == .gold ? gold : silver }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}
