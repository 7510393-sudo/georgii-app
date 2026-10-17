import StoreKit
import SwiftUI

/// Покупка (M14, P432): месяц всё целиком, дальше — разовая покупка.
///
/// Проба по правилам Apple (3.1.1) — бесплатная покупка «30-day Trial»:
/// человек сам её «покупает» за 0, и с этой минуты идёт месяц. Дата пробы
/// и полная покупка живут у Apple, привязаны к Apple ID и переживают
/// переустановку и новый телефон.
///
/// Месяц кончился, а покупки нет — **написанное читается всегда**, нельзя
/// только писать новое (M14). Импорт бесплатен всегда.
///
/// Никого не запирать по ошибке: если товары у Apple не нашлись (их ещё не
/// завели, нет сети, тесты), приложение работает целиком. Запирается только
/// тот, кому покупка действительно доступна.
///
/// Подарок — код предложения в App Store (`docs/41`): погашенный код
/// приходит сюда же обычной покупкой.
@MainActor
final class Purchase: ObservableObject {

    static let shared = Purchase()

    static let trialID = "com.kobiashvili.diary.trial30"
    static let fullID = "com.kobiashvili.diary.full"
    static let trialDays = 30

    @Published private(set) var full: Product?
    @Published private(set) var trial: Product?
    @Published private(set) var owned = false
    @Published private(set) var trialStart: Date?
    @Published private(set) var busy = false
    @Published var problem: String?
    /// Показать листок покупки.
    @Published var asking = false

    private var listening: Task<Void, Never>?

    /// Можно ли писать. Пока не известно — можно.
    nonisolated static var canWrite: Bool {
        UserDefaults.standard.object(forKey: lockedKey) as? Bool != true
    }
    nonisolated private static let lockedKey = "purchase.locked"

    enum State: Equatable {
        case owned
        case trial(daysLeft: Int)
        case notStarted
        case expired
        /// Товаров у Apple нет — всё открыто.
        case unavailable
    }

    var state: State {
        if owned { return .owned }
        guard full != nil else { return .unavailable }
        guard let trialStart else { return .notStarted }
        let passed = Calendar.current.dateComponents([.day], from: trialStart, to: Date()).day ?? 0
        let left = Self.trialDays - passed
        return left > 0 ? .trial(daysLeft: left) : .expired
    }

    private init() {}

    /// При запуске: слушать покупки (и погашенные коды), спросить товары и
    /// то, что уже куплено.
    func start() {
        guard listening == nil, NSClassFromString("XCTestCase") == nil, !Vault.isPreview else { return }
        listening = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let t) = update { await t.finish() }
                await self?.refresh()
            }
        }
        Task { await load() }
    }

    func load() async {
        do {
            let found = try await Product.products(for: [Self.trialID, Self.fullID])
            full = found.first { $0.id == Self.fullID }
            trial = found.first { $0.id == Self.trialID }
        } catch {
            full = nil
            trial = nil
        }
        await refresh()
        // Первый запуск — предложить начать месяц; месяц кончился — сказать.
        if state == .notStarted || state == .expired { asking = true }
    }

    func refresh() async {
        var isOwned = false
        var started: Date?
        for await entitlement in Transaction.currentEntitlements {
            guard case .verified(let t) = entitlement, t.revocationDate == nil else { continue }
            if t.productID == Self.fullID { isOwned = true }
            if t.productID == Self.trialID { started = t.originalPurchaseDate }
        }
        owned = isOwned
        trialStart = started
        UserDefaults.standard.set(state == .expired, forKey: Self.lockedKey)
        objectWillChange.send()
    }

    func buy(_ product: Product?) async {
        guard let product else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let check):
                if case .verified(let t) = check { await t.finish() }
                await refresh()
                if state != .notStarted { asking = false }
            case .userCancelled, .pending: break
            @unknown default: break
            }
        } catch {
            problem = error.localizedDescription
        }
    }

    /// «Восстановить покупки» — обязательная кнопка по правилам Apple.
    func restore() async {
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        await refresh()
    }

    var priceText: String { full?.displayPrice ?? "£15" }

    /// Строка для настроек.
    var summary: String {
        switch state {
        case .owned: return T("куплено — навсегда", "purchased — for good")
        case .trial(let n): return T("пробный месяц: впереди дней — \(n)", "trial month: \(n) days ahead")
        case .notStarted: return T("пробный месяц не начат", "trial month not started")
        case .expired: return T("месяц прошёл — записи читаются, писать новое после покупки",
                                "the month is over — entries are readable; writing needs the purchase")
        case .unavailable: return T("покупка пока недоступна — всё открыто", "purchase not available yet — everything is open")
        }
    }
}

/// Листок покупки: что даёт месяц, что будет после, сколько стоит —
/// всё сказано до начала пробы, как требует Apple.
struct PurchaseSheet: View {
    @ObservedObject var purchase: Purchase
    @Environment(\.dismiss) private var dismiss
    @State private var redeeming = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(headline)
                        .font(Look.serif(22, weight: .semibold))
                        .foregroundStyle(Look.ink)
                    Text(T("Месяц — всё приложение целиком, без урезаний. Потом — одна покупка за \(purchase.priceText), навсегда, без подписки.",
                           "A month of the whole app, nothing held back. Then one purchase of \(purchase.priceText), for good, no subscription."))
                    Text(T("Не купили — ничего не теряете: всё написанное читается всегда, файлы остаются в вашей папке. Нельзя будет только писать новое.",
                           "If you don't buy, you lose nothing: everything you wrote stays readable, and the files stay in your folder. Only writing new entries stops."))
                        .foregroundStyle(Look.inkSoft)
                    if purchase.state == .notStarted {
                        Button {
                            Task { await purchase.buy(purchase.trial) }
                        } label: {
                            Text(T("Начать бесплатный месяц", "Start the free month")).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(purchase.busy || purchase.trial == nil)
                    }
                    if purchase.state != .owned {
                        Button {
                            Task { await purchase.buy(purchase.full) }
                        } label: {
                            Text(T("Купить навсегда — \(purchase.priceText)", "Buy for good — \(purchase.priceText)"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(purchase.busy || purchase.full == nil)
                    }
                    HStack {
                        Button(T("Восстановить покупки", "Restore purchases")) {
                            Task { await purchase.restore() }
                        }
                        Spacer()
                        Button(T("Ввести код", "Redeem a code")) { redeeming = true }
                    }
                    .font(Look.sans(14))
                    .disabled(purchase.busy)
                    if purchase.busy { ProgressView() }
                    if let problem = purchase.problem {
                        Text(problem).font(Look.sans(13)).foregroundStyle(.red)
                    }
                }
                .font(Look.sans(15))
                .padding(20)
            }
            .navigationTitle(T("Graphomanus", "Graphomanus"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("Закрыть", "Close")) { dismiss() }
                }
            }
            .offerCodeRedemption(isPresented: $redeeming) { _ in
                Task { await purchase.refresh() }
            }
        }
    }

    private var headline: String {
        switch purchase.state {
        case .owned: return T("Куплено. Спасибо!", "Purchased. Thank you!")
        case .expired: return T("Пробный месяц прошёл", "The trial month is over")
        case .trial(let n): return T("Пробный месяц: впереди дней — \(n)", "Trial month: \(n) days ahead")
        default: return T("Месяц бесплатно", "A month for free")
        }
    }
}
