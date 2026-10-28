import SwiftUI
import UserNotifications

/// Чужие клавиатуры (P633): по просьбе человека приложение не пускает в свои
/// поля клавиатуры из App Store — «полный доступ» даёт им видеть набранное.
final class KeyboardGate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     shouldAllowExtensionPointIdentifier id: UIApplication.ExtensionPointIdentifier) -> Bool {
        !(id == .keyboard && UserDefaults.standard.bool(forKey: Prefs.ownKeyboardOnly))
    }
}

@main
struct ChronothecaApp: App {
    @UIApplicationDelegateAdaptor(KeyboardGate.self) private var keyboardGate
    @StateObject private var vault: Vault
    @StateObject private var store: DayStore
    @StateObject private var archive: Archive
    @StateObject private var shell = Shell()
    @Environment(\.scenePhase) private var phase
    /// Когда приложение ушло в фон — по этому решается, была ли пауза.
    @State private var leftAt: Date?

    /// После скольких минут в фоне приложение открывается заново, на
    /// «Сегодня» (P346). Короче — нельзя: человек сбегал в Карты Google за
    /// координатами и вернулся вставить их — его место должно остаться.
    private static let pause: TimeInterval = 5 * 60

    init() {
        _ = LaunchClock.start
        // Граница суток из настроек — до того, как откроется «сегодня».
        Prefs.applyBoundary()
        Prefs.settleFont()
        // Напоминания видны и при открытом приложении (P260).
        if NSClassFromString("XCTestCase") == nil {
            UNUserNotificationCenter.current().delegate = BellDelegate.shared
        }
        let vault = Vault()
        _vault = StateObject(wrappedValue: vault)
        _store = StateObject(wrappedValue: DayStore(vault: vault))
        _archive = StateObject(wrappedValue: Archive(vault: vault))
        LaunchClock.step(T("приложение создано", "app created"))
    }

    /// Сегодняшний день — на плане или на дневнике. План и дневник — одна
    /// страница (P408): на дневник её прокручивает «приземление».
    private func openToday(diary: Bool) {
        // Без хода плашки (P583): с виджета — сразу «День».
        if shell.screen != .today { shell.instant = true }
        store.go(to: DayStore.today())
        shell.tab = diary ? .diary : .plan
        shell.landOnDiary = diary
        shell.landing += 1
        shell.screen = .today
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vault)
                .environmentObject(store)
                .environmentObject(archive)
                .environmentObject(shell)
                // Касание по виджету: chronotheca://today/plan или /diary —
                // открыть сегодняшний день на этой вкладке (P382).
                .onOpenURL { url in
                    guard url.scheme == "chronotheca" else { return }
                    openToday(diary: url.lastPathComponent == "diary")
                }
                // Вечернее напоминание — сразу в сегодняшний дневник (P466).
                .onReceive(NotificationCenter.default.publisher(for: BellDelegate.evening)) { _ in
                    openToday(diary: true)
                }
        }
        .onChange(of: phase) { _, now in
            switch now {
            // Уходя с экрана — записать сразу. Запись идёт через полсекунды
            // после последней буквы, и смахнутое приложение этих полсекунд
            // может не дождаться: последние слова пропадали (решение P184).
            case .inactive:
                store.save()
            case .background:
                store.save()
                leftAt = Date()
            // Вернувшись — сверить день с диском: пока приложение стояло,
            // запись могли поправить на Mac или на другом устройстве, и
            // старая копия не должна лечь поверх новой (P183).
            case .active:
                store.comeBack()
                // Опись папки — в стороне (P565): прежде она читалась
                // целиком до первого кадра, и приложение открывалось долго.
                archive.reloadSoon()
                // Прочее — когда страница уже на экране и отвечает (P565).
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [vault, store, shell] in
                    // Повторяющиеся дела — дописать на год вперёд (P359).
                    Repeats.extendAll(vault: vault, open: store.date)
                    // Файлы, пролежавшие в корзине 30 дней, — стереть (P371).
                    FileTrash.purgeOld(vault)
                    Trash.purgeOld(vault)
                    store.syncUpcomingReminders()
                    store.fetchWeatherIfNeeded()
                    // Записи давно не уходят в iCloud — мягко сказать, раз в день (P575).
                    if vault.uploadStuck(), Vault.mayTellStuck() {
                        shell.say(T("Записи этих дней пока не ушли в iCloud — может быть, в нём нет места. "
                                    + "Подробнее — «Данные в сохранности?» в настройках.",
                                    "Entries from these days have not reached iCloud yet — perhaps it has no space. "
                                    + "More in Settings, “Is my data safe?”."), for: 6)
                    }
                }
                // Долгая пауза — открыть заново, как после запуска (P346).
                if let leftAt, Date().timeIntervalSince(leftAt) > Self.pause {
                    shell.startOver(store)
                }
                leftAt = nil
            @unknown default:
                break
            }
        }
    }
}
