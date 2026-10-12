import Foundation
import UserNotifications

/// Напоминания колокольчика (P260).
///
/// Колокольчик раньше только записывал время в файл — «(напомнить 08:30)»,
/// — а телефону ничего не передавалось, и в срок он молчал. Теперь по
/// каждому такому делу заводится обычное уведомление iPhone. Файл
/// остаётся главным: напоминания дня каждый раз расставляются заново по
/// тому, что в нём записано, — снял колокольчик в файле на Mac, и
/// напоминание тоже снимется, как только день откроют.
enum Reminders {

    /// В проверках уведомлений не трогаем: там нет приложения, которому
    /// их показывать.
    private static let testing = NSClassFromString("XCTestCase") != nil

    /// Спросить разрешение. Спрашивается, когда человек сам поставил
    /// колокольчик, — не раньше.
    static func ask(done: @escaping (Bool) -> Void = { _ in }) {
        guard !testing else { return done(true) }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                DispatchQueue.main.async { done(true) }
            case .denied:
                DispatchQueue.main.async { done(false) }
            default:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { ok, _ in
                    DispatchQueue.main.async { done(ok) }
                }
            }
        }
    }

    /// Заново расставить напоминания дня: прежние снять, по файлу завести.
    static func sync(day: Date, rows: [PlanRow]) {
        guard !testing else { return }
        let center = UNUserNotificationCenter.current()
        let prefix = "bell." + Vault.stamp(day) + "."
        let now = Date()
        let wanted: [(String, UNNotificationRequest)] = rows.enumerated().compactMap { n, row in
            guard row.isTask, !row.done, let bell = row.bell,
                  let when = moment(bell, on: day), when > now else { return nil }
            let content = UNMutableNotificationContent()
            let title = Geo.stripped(row.text)
            content.title = title.isEmpty ? T("Дело без названия", "Untitled task") : title
            content.body = row.time.map { T("Дело на \($0)", "Task at \($0)") }
                ?? T("Напоминание из плана", "Reminder from your plan")
            // Свой колокольчик вместо обычного звука iPhone (P267).
            content.sound = UNNotificationSound(named: UNNotificationSoundName("bell.wav"))
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute],
                                                        from: when)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let id = prefix + "\(n)"
            return (id, UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
        center.getPendingNotificationRequests { pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: old)
            for (_, request) in wanted { center.add(request) }
        }
    }

    // MARK: Вечером — «запишите день» (P444)

    /// Час вечернего напоминания; −1 — выключено (так по умолчанию).
    static let eveningKey = "prefs.evening"
    static var eveningHour: Int {
        UserDefaults.standard.object(forKey: eveningKey) as? Int ?? -1
    }

    /// Вечерние напоминания на неделю вперёд, каждое — на свой день. Сегодня
    /// уже записано — сегодняшнего нет: напоминать о сделанном незачем.
    /// Расставляется заново, когда приложение открывают и когда день ложится
    /// на диск, — так неделя всегда впереди.
    /// Вечерние мысли вместо «Запишите день» (P452): напоминание не должно
    /// ни спрашивать, ни подгонять.
    static var sayings: [String] {
        [
            T("Память — лучшее средство от времени", "Memory is the best remedy for time"),
            T("Записать легче, чем вспомнить", "Writing it down is easier than remembering"),
            T("Записанная мысль остаётся с вами", "A thought written down stays with you"),
            T("Это электронный дневник — деревья в безопасности", "It’s a digital diary — the trees are safe"),
            T("Пара строк сегодня — целый день через год", "A few lines today — a whole day a year from now"),
            T("Этот день можно оставить себе — парой строк", "This day can stay with you — in just a couple of lines"),
            T("Вечером хорошо оглянуться на день", "Evening is a nice time to look back on the day"),
        ]
    }

    static func evening(todayWritten: Bool) {
        guard !testing else { return }
        let center = UNUserNotificationCenter.current()
        let hour = eveningHour
        center.getPendingNotificationRequests { pending in
            let old = pending.map(\.identifier).filter { $0.hasPrefix("evening.") }
            center.removePendingNotificationRequests(withIdentifiers: old)
            guard hour >= 0 else { return }
            let cal = Calendar.current
            let today = cal.startOfDay(for: DayStore.today())
            let now = Date()
            for k in 0..<7 {
                if k == 0 && todayWritten { continue }
                guard let day = cal.date(byAdding: .day, value: k, to: today),
                      let when = cal.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                      when > now else { continue }
                let content = UNMutableNotificationContent()
                // Не вопрос и не приказ, а мысль — каждый вечер своя (P452).
                let n = cal.ordinality(of: .day, in: .era, for: day) ?? k
                content.title = sayings[n % sayings.count]
                content.body = T("Пара строк — и день останется с вами.", "A couple of lines, and the day stays with you.")
                content.sound = .default
                let parts = cal.dateComponents([.year, .month, .day, .hour, .minute], from: when)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                center.add(UNNotificationRequest(identifier: "evening." + Vault.stamp(day),
                                                 content: content, trigger: trigger))
            }
        }
    }

    /// Когда звонить: час из колокольчика в этот день. Час раньше границы
    /// суток — это уже следующее утро по часам (граница — 4:00, P17).
    static func moment(_ hhmm: String, on day: Date) -> Date? {
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) else {
            return nil
        }
        let cal = Calendar.current
        var base = cal.startOfDay(for: day)
        if parts[0] < DayStore.boundaryHour {
            base = cal.date(byAdding: .day, value: 1, to: base) ?? base
        }
        return cal.date(bySettingHour: parts[0], minute: parts[1], second: 0, of: base)
    }
}

/// Уведомление видно и тогда, когда приложение открыто: иначе iPhone
/// показывает его, только если приложение закрыто, — и напоминание,
/// пришедшее посреди записи, пропадало молча.
final class BellDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = BellDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .list, .sound])
    }

    /// Коснулись вечернего напоминания (P466) — сразу сегодняшний дневник:
    /// пишут именно туда, искать его не надо.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler done: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix("evening.") {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: BellDelegate.evening, object: nil)
            }
        }
        done()
    }

    static let evening = Notification.Name("chronotheca.evening")
}
