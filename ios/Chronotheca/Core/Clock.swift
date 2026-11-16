import Foundation

// Нижний слой (P970): без экрана, только Foundation.

enum Clock {
    /// 12 часов или 24 — как в самом iPhone (P633; прежде выбирались в
    /// настройках, P602). В файлах время всегда «21:30» — так его читает
    /// любая программа; на экране — как у телефона.
    static var twelve: Bool { forced ?? phoneTwelve }

    /// Только для проверок: заставить часы показывать 12 или 24 часа, не
    /// трогая телефон (P633).
    static var forced: Bool?

    /// Как в самом iPhone — считается один раз (P605): прежде выяснялось на
    /// каждой плашке плана при каждой отрисовке, и листание страниц, где
    /// рисуются три дня сразу, стало отзываться с задержкой.
    private static let phoneTwelve =
        (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")

    /// «21:30» из файла — на экран: «21:30» или «9:30 PM».
    static func show(_ hhmm: String) -> String {
        guard twelve, hhmm.count == 5, let h = Int(hhmm.prefix(2)) else { return hhmm }
        return "\(h % 12 == 0 ? 12 : h % 12):\(hhmm.suffix(2)) \(h < 12 ? "AM" : "PM")"
    }

    /// Час ровно — «21:00» или «9 PM».
    static func hour(_ h: Int) -> String {
        twelve ? "\(h % 12 == 0 ? 12 : h % 12) \(h < 12 ? "AM" : "PM")" : "\(h):00"
    }

    private static var formatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }

    static func text(_ date: Date) -> String { formatter.string(from: date) }

    static func date(_ text: String?) -> Date? {
        guard let text, let t = formatter.date(from: text) else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: t)
        return Calendar.current.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0,
                                     second: 0, of: Date())
    }

    /// Ближайший следующий круглый час. Ровно в час — он сам: в 23:00
    /// предлагать полночь было бы странно.
    ///
    /// После 23:00 круглый час приходится на следующие сутки, но ролик
    /// показывает только часы и минуты — для него это просто 00:00.
    static func nextHour(_ now: Date = Date()) -> Date {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: now)
        let minute = c.minute ?? 0
        let hour = (minute == 0 ? (c.hour ?? 0) : (c.hour ?? 0) + 1) % 24
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
    }

    /// Полночь — для ролика, которому не от чего отсчитывать.
    static func midnight(_ now: Date = Date()) -> Date {
        Calendar.current.startOfDay(for: now)
    }

    /// Такой-то час ровно.
    static func at(_ hour: Int, _ now: Date = Date()) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
    }

    /// Подогнать к шагу ролика: минуты вниз до кратных шагу.
    ///
    /// Вниз, а не к ближайшему: назначенное на 14:37 дело безопаснее
    /// сдвинуть на 14:35, чем на 14:40 — раньше можно, позже нельзя.
    static func snap(_ date: Date, step: Int = 5) -> Date {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: date)
        let minute = ((c.minute ?? 0) / step) * step
        return cal.date(bySettingHour: c.hour ?? 0, minute: minute,
                        second: 0, of: date) ?? date
    }
}
