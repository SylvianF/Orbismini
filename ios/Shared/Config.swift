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

/// Couleurs d’Orbismini (les mêmes que le site et le widget Scriptable).
enum Theme {
    static let bg1 = Color(hex: 0x1B2A34)
    static let bg2 = Color(hex: 0x121D25)
    static let card = Color(hex: 0x1F313D)
    static let line = Color(hex: 0x344853)
    static let text = Color(hex: 0xEDF2F5)
    static let muted = Color(hex: 0xB5C7D3)
    static let gold = Color(hex: 0xE9BF75)
    static let silver = Color(hex: 0xD0DAE5)
    static let up = Color(hex: 0x8FDFB0)
    static let down = Color(hex: 0xFF9CA4)

    static var background: LinearGradient {
        LinearGradient(colors: [bg1, bg2], startPoint: .top, endPoint: .bottom)
    }

    static func trend(_ delta: Double?) -> Color {
        guard let delta else { return muted }
        return delta > 0 ? up : delta < 0 ? down : muted
    }
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
