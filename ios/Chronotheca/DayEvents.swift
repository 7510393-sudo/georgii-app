import EventKit
import EventKitUI
import SwiftUI
import UIKit

/// События Календаря iPhone в плане дня (P376).
///
/// События живут в Календаре, а не в нашей папке: в файл плана они не
/// копируются — иначе копия разойдётся с Календарём, когда событие
/// перенесут или удалят. Время, повтор и напоминание берутся из Календаря;
/// звонит сам Календарь, второе напоминание мы не ставим.
///
/// В файл плана попадает только то, что сделал человек: «сделано» и
/// «убрано из плана этого дня» — строкой вида
/// `- [x] 10:00 Стоматолог (calendar #k3f9a2c1)`. Такая строка читается
/// глазами и в любом редакторе, а приложение не считает её своим делом.
enum DayEvents {

    static let store = EKEventStore()

    static let onKey = "prefs.calendarEvents"
    static let holidaysKey = "prefs.calendarHolidays"

    /// Показывать события Календаря — по умолчанию да.
    static var on: Bool { UserDefaults.standard.object(forKey: onKey) as? Bool ?? true }
    /// Праздники и дни рождения — по умолчанию нет.
    static var holidays: Bool { UserDefaults.standard.bool(forKey: holidaysKey) }

    static var status: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }
    static var allowed: Bool { status == .fullAccess }

    /// Спросить доступ один раз — iPhone сам задаёт вопрос.
    static func ask(_ done: @escaping (Bool) -> Void) {
        store.requestFullAccessToEvents { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }

    // MARK: - События дня

    struct Item: Identifiable, Equatable {
        /// Короткий постоянный ключ события — по нему отметка в файле.
        let key: String
        let title: String
        /// «10:00»; у события на весь день — нет.
        let time: String?
        /// Когда напомнит Календарь.
        let bell: String?
        let repeats: Bool
        let color: Color
        let start: Date
        var id: String { key }
    }

    /// События этого дня из Календаря, по времени: сперва на весь день.
    static func items(for day: Date) -> [Item] {
        guard on, allowed, !Vault.isPreview else { return [] }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return [] }
        let calendars = store.calendars(for: .event).filter { holidays || !isHolidays($0) }
        guard !calendars.isEmpty else { return [] }
        let found = store.events(matching: store.predicateForEvents(withStart: start, end: end,
                                                                     calendars: calendars))
        var used: [String: Int] = [:]
        let list = found.map { e -> Item in
            var key = key(of: e)
            // Два события с одним ключом в один день — второму номер.
            used[key, default: 0] += 1
            if let n = used[key], n > 1 { key += "\(n)" }
            return Item(key: key,
                        title: e.title?.isEmpty == false ? e.title! : T("Без названия", "No title"),
                        time: e.isAllDay || e.startDate < start ? nil : clock(e.startDate),
                        bell: bell(of: e),
                        repeats: e.hasRecurrenceRules,
                        color: Color(cgColor: e.calendar.cgColor),
                        start: e.startDate)
        }
        return list.sorted { a, b in
            switch (a.time, b.time) {
            case (nil, nil): return a.title < b.title
            case (nil, _): return true
            case (_, nil): return false
            default: return a.start < b.start
            }
        }
    }

    /// События дня для календаря: месяц спрашивает сразу о сорока днях, и
    /// каждый раз заново — при каждой перерисовке. Ответ помнится, пока
    /// календарь открыт; открыли заново — спрашиваем Календарь снова.
    private static var cache: [String: [Item]] = [:]

    static func cachedItems(for day: Date) -> [Item] {
        let stamp = Vault.stamp(day)
        if let hit = cache[stamp] { return hit }
        let found = items(for: day)
        cache[stamp] = found
        return found
    }

    static func forgetCache() { cache = [:] }

    /// Само событие — чтобы открыть его или удалить.
    static func event(_ key: String, on day: Date) -> EKEvent? {
        guard allowed else { return nil }
        let cal = Calendar.current
        let start = cal.startOfDay(for: day)
        guard let end = cal.date(byAdding: .day, value: 1, to: start) else { return nil }
        let found = store.events(matching: store.predicateForEvents(withStart: start, end: end,
                                                                     calendars: nil))
        let base = key.prefix(8)
        return found.first { DayEvents.key(of: $0) == base }
    }

    /// Праздники, дни рождения и прочие календари-подписки, которые
    /// нельзя править.
    static func isHolidays(_ c: EKCalendar) -> Bool {
        c.type == .birthday || (c.type == .subscription && !c.allowsContentModifications)
    }

    /// Восемь знаков из постоянного имени события. Своя свёртка, а не
    /// `hashValue`: тот меняется от запуска к запуску.
    static func key(of e: EKEvent) -> String {
        short(e.calendarItemExternalIdentifier ?? e.eventIdentifier ?? e.title ?? "")
    }

    static func short(_ s: String) -> String {
        var h: UInt64 = 0xcbf29ce484222325
        for b in s.utf8 {
            h ^= UInt64(b)
            h = h &* 0x100000001b3
        }
        let text = String(h, radix: 36)
        return String(String(repeating: "0", count: max(0, 8 - text.count)) + text).suffix(8).lowercased()
    }

    private static func clock(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    private static func bell(of e: EKEvent) -> String? {
        guard let alarm = e.alarms?.first else { return nil }
        if let at = alarm.absoluteDate { return clock(at) }
        guard let start = e.startDate else { return nil }
        return clock(start.addingTimeInterval(alarm.relativeOffset))
    }

    // MARK: - Отметки в файле плана

    struct Mark: Equatable {
        var key: String
        var done = false
        var hidden = false
        var time: String?
        var title: String

        private static let tail = #"\s*\(calendar #([a-z0-9]{4,16})( hidden)?\)$"#

        static func parse(_ line: String) -> Mark? {
            guard line.hasPrefix("- [x] ") || line.hasPrefix("- [ ] ") || line.hasPrefix("- [X] "),
                  let range = line.range(of: tail, options: .regularExpression)
            else { return nil }
            let suffix = String(line[range])
            guard let k = suffix.range(of: #"#[a-z0-9]{4,16}"#, options: .regularExpression) else { return nil }
            let from = line.index(line.startIndex, offsetBy: 6)
            var rest = range.lowerBound > from ? String(line[from..<range.lowerBound]) : ""
            var time: String?
            if rest.count >= 5, rest.prefix(5).range(of: #"^\d{2}:\d{2}$"#, options: .regularExpression) != nil {
                time = String(rest.prefix(5))
                rest = String(rest.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
            return Mark(key: String(suffix[k].dropFirst()),
                        done: !line.hasPrefix("- [ ]"),
                        hidden: suffix.contains(" hidden"),
                        time: time, title: rest)
        }

        var line: String {
            var out = done ? "- [x] " : "- [ ] "
            if let time { out += time + " " }
            out += title.replacingOccurrences(of: "\n", with: " ")
            out += hidden ? " (calendar #\(key) hidden)" : " (calendar #\(key))"
            return out
        }
    }

    /// Что показать в плане: события Календаря с отметками из файла и те
    /// сделанные, которых в Календаре уже нет, — чтобы прошедший день
    /// помнил, что было сделано.
    struct Shown: Identifiable, Equatable {
        let key: String
        var row: PlanRow
        var color: Color?
        var id: String { key }

        static func == (a: Shown, b: Shown) -> Bool { a.key == b.key && a.row == b.row }
    }

    static func shown(_ items: [Item], marks: [Mark]) -> [Shown] {
        var out: [Shown] = []
        var seen = Set<String>()
        for item in items {
            seen.insert(item.key)
            let mark = marks.first { $0.key == item.key }
            if mark?.hidden == true { continue }
            var row = PlanRow.task(time: item.time, bell: item.bell, item.title)
            row.done = mark?.done ?? false
            if item.repeats { row.repeats = Repeat(every: .month, series: "calendar") }
            out.append(Shown(key: item.key, row: row, color: item.color))
        }
        for mark in marks where !seen.contains(mark.key) && mark.done && !mark.hidden {
            var row = PlanRow.task(time: mark.time, mark.title)
            row.done = true
            out.append(Shown(key: mark.key, row: row, color: nil))
        }
        return out
    }

    static func marks(in rows: [PlanRow]) -> [Mark] {
        rows.compactMap { $0.verbatim.flatMap(Mark.parse) }
    }
}

/// Событие Календаря в окне Apple: посмотреть, поправить время, название,
/// напоминание или удалить. Правит сам Календарь — мы туда не пишем.
struct EventSheet: UIViewControllerRepresentable {
    let event: EKEvent
    let done: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let view = EKEventViewController()
        view.event = event
        view.allowsEditing = true
        view.allowsCalendarPreview = false
        view.delegate = context.coordinator
        return UINavigationController(rootViewController: view)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, EKEventViewDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }

        func eventViewController(_ controller: EKEventViewController,
                                 didCompleteWith action: EKEventViewAction) {
            done()
        }
    }
}
