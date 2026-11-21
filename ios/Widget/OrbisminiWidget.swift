import AppIntents
import SwiftUI
import WidgetKit

// Widget d’écran d’accueil : or, argent, courbe ; toucher ouvre l’application.
// Réglage par appui long → « Modifier le widget » : métal et période (comme le paramètre
// « or », « argent 7 »… du widget Scriptable).

enum MetalOption: String, AppEnum {
    case or, argent

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Métal" }
    static var caseDisplayRepresentations: [MetalOption: DisplayRepresentation] {
        [.or: "Or", .argent: "Argent"]
    }
    var metal: Metal { self == .argent ? .silver : .gold }
}

enum PeriodOption: String, AppEnum {
    case jour, semaine, mois, an

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Période" }
    static var caseDisplayRepresentations: [PeriodOption: DisplayRepresentation] {
        [.jour: "1 jour", .semaine: "7 jours", .mois: "1 mois", .an: "1 an"]
    }
    var period: Period {
        switch self {
        case .jour: return .day
        case .semaine: return .week
        case .mois: return .month
        case .an: return .year
        }
    }
}

struct CoursSettings: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Cours d’Orbismini" }
    static var description: IntentDescription { IntentDescription("Métal et période de la courbe.") }

    @Parameter(title: "Métal", default: .or)
    var metal: MetalOption

    @Parameter(title: "Période", default: .jour)
    var period: PeriodOption

    init() {}
}

struct CoursEntry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
    let metal: Metal
    let stale: Bool
    let message: String?
}

struct CoursProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CoursEntry {
        CoursEntry(date: Date(), snapshot: DemoData.snapshot(), metal: .gold, stale: false, message: nil)
    }

    func snapshot(for configuration: CoursSettings, in context: Context) async -> CoursEntry {
        let period = configuration.period.period
        let kept = SharedStore.snapshot(period)
        return CoursEntry(date: Date(), snapshot: kept ?? (context.isPreview ? DemoData.snapshot(period) : nil),
                          metal: configuration.metal.metal, stale: false, message: nil)
    }

    func timeline(for configuration: CoursSettings, in context: Context) async -> Timeline<CoursEntry> {
        let period = configuration.period.period
        let entry: CoursEntry
        do {
            let fresh = try await DataService.snapshot(period: period, client: .widget, preferWidgetKey: true)
            SharedStore.saveSnapshot(fresh)
            entry = CoursEntry(date: Date(), snapshot: fresh, metal: configuration.metal.metal, stale: false, message: nil)
        } catch {
            // Hors connexion ou Render endormi : dernier relevé gardé, signalé par ⚠.
            let message = (error as? APIError) == .needsLogin
                ? "Ouvre Orbismini et saisis le mot de passe."
                : error.localizedDescription
            entry = CoursEntry(date: Date(), snapshot: SharedStore.snapshot(period), metal: configuration.metal.metal,
                               stale: true, message: message)
        }
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
    }
}

struct CoursWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CoursEntry

    var body: some View {
        WidgetContent(snapshot: entry.snapshot, metal: entry.metal, size: size, stale: entry.stale, message: entry.message)
            .containerBackground(for: .widget) { Theme.background }
            .widgetURL(URL(string: "orbismini://cours"))
    }

    private var size: WidgetSize {
        switch family {
        case .systemSmall: return .small
        case .systemLarge, .systemExtraLarge: return .large
        default: return .medium
        }
    }
}

struct CoursWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "OrbisminiCours", intent: CoursSettings.self, provider: CoursProvider()) { entry in
            CoursWidgetView(entry: entry)
        }
        .configurationDisplayName("Cours de l’or")
        .description("Or et argent avec leur courbe. Touche pour ouvrir Orbismini.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct OrbisminiWidgetBundle: WidgetBundle {
    var body: some Widget {
        CoursWidget()
    }
}
