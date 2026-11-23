import SwiftUI
import WidgetKit

@MainActor
final class CoursModel: ObservableObject {
    @Published var period: Period = Period(rawValue: UserDefaults.standard.string(forKey: "coursPeriode") ?? "") ?? .day
    @Published var snapshot: Snapshot?
    @Published var status: LoadStatus = .idle
    private var waking: NSObjectProtocol?

    init() {
        snapshot = Config.isDemo ? DemoData.snapshot(period) : SharedStore.snapshot(period)
        waking = NotificationCenter.default.addObserver(forName: .serverWaking, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                if self?.status == .loading { self?.status = .waking }
            }
        }
    }

    deinit {
        if let waking { NotificationCenter.default.removeObserver(waking) }
    }

    func choose(_ p: Period) async {
        period = p
        UserDefaults.standard.set(p.rawValue, forKey: "coursPeriode")
        if snapshot?.period != p { snapshot = Config.isDemo ? DemoData.snapshot(p) : SharedStore.snapshot(p) }
        await refresh()
    }

    func refresh() async {
        if Config.isDemo {
            snapshot = DemoData.snapshot(period)
            status = .demo
            return
        }
        let p = period
        status = .loading
        do {
            let fresh = try await DataService.snapshot(period: p, client: .app, preferWidgetKey: false)
            guard p == period else { return }
            snapshot = fresh
            SharedStore.saveSnapshot(fresh)
            status = .fresh(fresh.updatedAt)
            WidgetCenter.shared.reloadAllTimelines()
        } catch APIError.needsLogin {
            AppModel.shared.needLogin()
        } catch is CancellationError {
            if status == .loading || status == .waking { status = .idle }
        } catch {
            guard p == period else { return }
            status = .offline(snapshot?.updatedAt, error.localizedDescription)
        }
    }
}

struct CoursView: View {
    @EnvironmentObject private var app: AppModel
    @StateObject private var model = CoursModel()
    @Environment(\.scenePhase) private var phase
    @AppStorage("coursMetal") private var metalRaw = Metal.gold.rawValue
    @AppStorage("coursBollinger") private var bollinger = false

    private var metal: Metal { Metal(rawValue: metalRaw) ?? .gold }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    topBar
                    SpotCard(snapshot: model.snapshot, metal: metalBinding, period: periodBinding,
                             bollinger: $bollinger, now: Config.isDemo ? DemoData.now : Date())
                    shortcuts
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 12)
            }
            .orbisminiBackground()
            .toolbar(.hidden, for: .navigationBar)
            .refreshable { await model.refresh() }
            .task {
                // Actualisation à l’ouverture, puis chaque minute tant que l’écran est affiché.
                while !Task.isCancelled {
                    await model.refresh()
                    try? await Task.sleep(nanoseconds: 60_000_000_000)
                }
            }
            .onChange(of: phase) { _, now in
                if now == .active { Task { await model.refresh() } }
            }
        }
    }

    /// Ligne du haut : état des données, alerte, réglages (pas de grand titre).
    private var topBar: some View {
        HStack(spacing: 14) {
            StatusLine(status: model.status)
            Button { app.showAlert = true } label: { Image(systemName: "bell") }
                .accessibilityLabel("Alerte de cours")
            Button { app.showSettings = true } label: { Image(systemName: "gearshape") }
                .accessibilityLabel("Réglages")
        }
        .font(.body)
        .foregroundStyle(Theme.gold)
        .frame(minHeight: 30)
    }

    private var shortcuts: some View {
        HStack(spacing: 10) {
            NavigationLink {
                WebModuleView(view: "cours", title: "Pièces et lingots")
            } label: {
                shortcut("Pièces et lingots", "list.bullet")
            }
            Button { app.showAlert = true } label: { shortcut("Alerte de cours", "bell.badge") }
        }
        .buttonStyle(.plain)
    }

    private func shortcut(_ title: String, _ icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Theme.card.opacity(0.75), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line.opacity(0.6), lineWidth: 0.5))
    }

    private var metalBinding: Binding<Metal> {
        Binding(get: { metal }, set: { metalRaw = $0.rawValue })
    }

    private var periodBinding: Binding<Period> {
        Binding(get: { model.period }, set: { p in Task { await model.choose(p) } })
    }
}

/// Cadre de la courbe, comme le site : Or / Argent, cours, variation, périodes, Bollinger.
private struct SpotCard: View {
    let snapshot: Snapshot?
    @Binding var metal: Metal
    @Binding var period: Period
    @Binding var bollinger: Bool
    let now: Date

    private var full: MetalSeries? { snapshot?.series(metal) }
    private var shown: MetalSeries? { full?.within(period, now: now) }
    private var band: [BandPoint] {
        guard bollinger, let full, let first = shown?.points.first?.date else { return [] }
        return Bollinger.bands(full.points).filter { $0.date >= first }
    }

    var body: some View {
        Card {
            header
            status
            periods
            chart
            footer
        }
    }

    private var header: some View {
        HStack {
            Text(metal.title).font(.headline).foregroundStyle(Theme.metal(metal))
            Spacer()
            Picker("Métal", selection: $metal) {
                Text("Or").tag(Metal.gold)
                Text("Argent").tag(Metal.silver)
            }
            .pickerStyle(.segmented)
            .frame(width: 140)
        }
    }

    @ViewBuilder
    private var status: some View {
        if let shown, shown.isAvailable {
            priceBlock(shown)
        } else if let error = full?.error {
            Text("Cours indisponible").font(.title3.bold()).foregroundStyle(Theme.muted)
            Text(error).font(.caption).foregroundStyle(Theme.muted)
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 60)
        }
    }

    private func priceBlock(_ s: MetalSeries) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Fmt.euros(price(s)))
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
                .contentTransition(.numericText())
            Text(Fmt.variation(s, withAmount: true) + " sur " + period.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.trend(s.delta))
            Text(meta).font(.caption).foregroundStyle(Theme.muted)
        }
    }

    /// Or : cours Kitco (Bid), comme le site ; argent : dernier point de BullionVault.
    private func price(_ s: MetalSeries) -> Double {
        if metal == .gold, let p = full?.price { return p }
        return s.points.last?.price ?? 0
    }

    private var meta: String {
        guard let full else { return "" }
        var out = metal == .gold ? "Or pur : " + (full.source ?? "Kitco") : "Argent : BullionVault"
        if let d = (metal == .gold ? full.quotedAt : nil) ?? full.points.last?.date { out += " · " + Fmt.dayTime(d) }
        if metal == .gold, full.marketClosed { out += " · marché fermé" }
        return out
    }

    private var periods: some View {
        Picker("Période", selection: $period) {
            ForEach(Period.allCases) { Text($0.short).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var chart: some View {
        if let shown, shown.hasCurve {
            CourseChart(points: shown.points, color: Theme.metal(metal), showLabels: true,
                        interactive: true, period: period, band: band)
                .frame(height: 230)
        }
    }

    private var note: String {
        bollinger
            ? "Bande de Bollinger : moyenne des 20 derniers points (1 point = " + period.step + ") ± 2 écarts-types · BullionVault"
            : "Courbe BullionVault · touche la courbe pour lire un cours"
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(note)
                .font(.caption2)
                .foregroundStyle(Theme.muted)
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("Bollinger", isOn: $bollinger)
                .toggleStyle(.button)
                .font(.caption.weight(.semibold))
                .tint(Theme.band)
        }
    }
}
