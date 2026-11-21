import SwiftUI
import WidgetKit

@MainActor
final class CoursModel: ObservableObject {
    @Published var period: Period = .day
    @Published var snapshot: Snapshot?
    @Published var status: LoadStatus = .idle
    private var waking: NSObjectProtocol?

    init() {
        snapshot = Config.isDemo ? DemoData.snapshot() : SharedStore.snapshot(.day)
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

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    StatusLine(status: model.status)

                    Picker("Période", selection: Binding(get: { model.period }, set: { p in Task { await model.choose(p) } })) {
                        ForEach(Period.allCases) { Text($0.short).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    ForEach(Metal.allCases) { metal in
                        MetalCard(series: model.snapshot?.series(metal), metal: metal, period: model.period,
                                  marketClosed: metal == .gold && (model.snapshot?.gold.marketClosed ?? false))
                    }

                    Button { app.showAlert = true } label: {
                        Label("Alerte de cours", systemImage: "bell.badge")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .foregroundStyle(Theme.bg2)
                    .controlSize(.large)

                    NavigationLink {
                        WebModuleView(view: "cours", title: "Pièces et lingots")
                    } label: {
                        Label("Pièces, lingots et prix de rachat", systemImage: "list.bullet")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)

                    Text("Courbes : BullionVault. Or pur : Kitco (Bid), BullionVault en secours.")
                        .font(.caption2)
                        .foregroundStyle(Theme.muted)
                }
                .padding(16)
            }
            .orbisminiBackground()
            .navigationTitle("Orbismini")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { app.showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Réglages")
                }
            }
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
}

private struct MetalCard: View {
    let series: MetalSeries?
    let metal: Metal
    let period: Period
    let marketClosed: Bool

    var body: some View {
        Card {
            HStack(alignment: .firstTextBaseline) {
                Text(metal.title)
                    .font(.headline)
                    .foregroundStyle(metal == .gold ? Theme.gold : Theme.silver)
                Spacer()
                if marketClosed {
                    Text("Marché fermé").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            if let series, series.isAvailable, let price = series.price {
                Text(Fmt.euros(price))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                Text(Fmt.variation(series, withAmount: true) + " sur " + period.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.trend(series.delta))
                if series.hasCurve {
                    CourseChart(points: series.points, color: metal == .gold ? Theme.gold : Theme.silver,
                                showLabels: true, interactive: true, period: period)
                        .frame(height: 170)
                }
                if let source = series.source {
                    Text("Cours : " + source + (series.quotedAt.map { " · " + Fmt.dayTime($0) } ?? ""))
                        .font(.caption2).foregroundStyle(Theme.muted)
                }
            } else if let error = series?.error {
                Text("Cours indisponible").font(.title3.bold()).foregroundStyle(Theme.muted)
                Text(error).font(.caption).foregroundStyle(Theme.muted)
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 120)
            }
        }
    }
}
