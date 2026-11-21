import SwiftUI

@MainActor
final class MeteoModel: ObservableObject {
    @Published var weather: Weather?
    @Published var status: LoadStatus = .idle
    @Published var keptAt: Date?

    init() {
        weather = Config.isDemo ? DemoData.weather : SharedStore.weather()
        keptAt = DateParser.parse(weather?.at)
    }

    func refresh() async {
        if Config.isDemo {
            weather = DemoData.weather
            status = .demo
            return
        }
        status = .loading
        do {
            let w = try await DataService.weather(client: .app)
            weather = w
            keptAt = DateParser.parse(w.at) ?? Date()
            SharedStore.saveWeather(w)
            status = .fresh(Date())
        } catch APIError.needsLogin {
            AppModel.shared.needLogin()
        } catch is CancellationError {
            status = .idle
        } catch {
            status = .offline(keptAt, error.localizedDescription)
        }
    }
}

struct MeteoView: View {
    @StateObject private var model = MeteoModel()
    @State private var open: Set<String> = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    StatusLine(status: model.status)
                    if let w = model.weather {
                        sky(w)
                        if let days = w.history?.filter({ $0.weather != nil }), !days.isEmpty {
                            history(days, today: w.weather)
                        }
                        ForEach(w.groups) { group in
                            Card {
                                Text(group.name).font(.headline).foregroundStyle(Theme.gold)
                                ForEach(group.items) { indicator(of: $0) }
                            }
                        }
                        Text("Météo de l’or : un résumé des indices de tendance, pas une prévision. Dollar et euro sont de simples repères.")
                            .font(.caption2).foregroundStyle(Theme.muted)
                    } else if model.status == .loading || model.status == .waking || model.status == .idle {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        Text("Météo de l’or indisponible pour le moment.").foregroundStyle(Theme.muted)
                    }
                }
                .padding(16)
            }
            .orbisminiBackground()
            .navigationTitle("Météo de l’or")
            .refreshable { await model.refresh() }
            .task { await model.refresh() }
        }
    }

    private func sky(_ w: Weather) -> some View {
        Card {
            HStack(alignment: .center, spacing: 14) {
                Text(w.weather?.icon ?? "❔").font(.system(size: 56))
                VStack(alignment: .leading, spacing: 4) {
                    Text(w.weather?.label ?? "Pas assez d’indices").font(.title2.bold()).foregroundStyle(Theme.text)
                    if let text = w.weather?.text { Text(text).font(.subheadline).foregroundStyle(Theme.muted) }
                }
            }
            if let score = w.score { ScoreBar(score: score) }
            counts(w)
            if let line = Self.agitation(w) {
                Text(line).font(.footnote).foregroundStyle(Theme.muted)
            }
            if let line = Self.missing(w) {
                Text(line).font(.caption).foregroundStyle(Theme.down)
            }
        }
    }

    private func counts(_ w: Weather) -> some View {
        HStack(spacing: 14) {
            Label(Self.count(w.up, "haussier"), systemImage: "arrowtriangle.up.fill").foregroundStyle(Theme.up)
            Label(Self.count(w.down, "baissier"), systemImage: "arrowtriangle.down.fill").foregroundStyle(Theme.down)
            Label(Self.count(w.flat, "neutre"), systemImage: "minus").foregroundStyle(Theme.muted)
        }
        .font(.footnote.weight(.semibold))
    }

    private static func count(_ n: Int?, _ word: String) -> String {
        let n = n ?? 0
        return "\(n) " + word + (n > 1 ? "s" : "")
    }

    private static func agitation(_ w: Weather) -> String? {
        guard let a = w.agitation, let level = a.level else { return nil }
        var line = "Agitation du marché : " + level
        if let p = a.percent { line += " (" + Fmt.decimal(p, digits: 2) + " % par jour)" }
        return line
    }

    private static func missing(_ w: Weather) -> String? {
        guard let missing = w.missing, !missing.isEmpty else { return nil }
        return "Sans réponse pour l’instant : " + missing.joined(separator: ", ") + " (nouvel essai dans 5 min)"
    }

    private func history(_ days: [Weather.Day], today: Weather.Sky?) -> some View {
        Card {
            Text("Jours précédents").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.muted)
            HStack(spacing: 10) {
                ForEach(days.suffix(7), id: \.day) { d in
                    VStack(spacing: 2) {
                        Text(d.weather?.icon ?? "·").font(.title3)
                        Text(String(d.day.suffix(2))).font(.caption2).foregroundStyle(Theme.muted)
                    }
                }
                if let today {
                    VStack(spacing: 2) {
                        Text(today.icon).font(.title3)
                        Text("Auj.").font(.caption2.bold()).foregroundStyle(Theme.gold)
                    }
                }
            }
        }
    }

    private func indicator(of x: Weather.Indicator) -> some View {
        let s = x.signal ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            Button {
                if open.contains(x.key) { open.remove(x.key) } else { open.insert(x.key) }
            } label: {
                HStack {
                    Image(systemName: s > 0 ? "arrowtriangle.up.fill" : s < 0 ? "arrowtriangle.down.fill" : "minus")
                        .foregroundStyle(s > 0 ? Theme.up : s < 0 ? Theme.down : Theme.muted)
                        .frame(width: 18)
                    Text(x.label).foregroundStyle(Theme.text)
                    Spacer()
                    Text(x.value ?? "").foregroundStyle(Theme.muted).monospacedDigit()
                }
                .font(.subheadline)
            }
            .buttonStyle(.plain)
            if open.contains(x.key), let text = x.text {
                Text(text).font(.footnote).foregroundStyle(Theme.muted).padding(.leading, 26)
            }
        }
    }
}

/// Jauge du score : de « Orage » (−1) à « Grand soleil » (+1).
private struct ScoreBar: View {
    let score: Double

    var body: some View {
        GeometryReader { geo in
            let x = (min(max(score, -1), 1) + 1) / 2 * geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(LinearGradient(colors: [Theme.down, Theme.muted.opacity(0.6), Theme.up],
                                              startPoint: .leading, endPoint: .trailing))
                    .frame(height: 6)
                Circle().fill(Theme.text).frame(width: 14, height: 14).offset(x: x - 7)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 16)
        .accessibilityLabel("Score " + Fmt.decimal(score, digits: 2))
    }
}
