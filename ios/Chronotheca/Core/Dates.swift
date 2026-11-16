import Foundation

// Нижний слой (P970): без экрана, только Foundation.

/// Даты на языке приложения: месяцы, дни недели, длинная и короткая дата.
enum Ru {

    // Имя осталось от времени, когда приложение было только русским; даты
    // теперь на языке приложения (P355).

    private static let ruMonths = ["января", "февраля", "марта", "апреля", "мая", "июня",
                                   "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    private static let enMonths = ["January", "February", "March", "April", "May", "June",
                                   "July", "August", "September", "October", "November", "December"]
    private static let ruMonthNames = ["январь", "февраль", "март", "апрель", "май", "июнь",
                                       "июль", "август", "сентябрь", "октябрь", "ноябрь", "декабрь"]

    /// Русский и английский — свои, выверенные; прочие языки (P369) —
    /// как их пишет сам iPhone.
    private static var own: Bool { Lang.code == "ru" || Lang.code == "en" }

    private static var formatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Lang.locale
        return f
    }

    private static func pattern(_ template: String, _ date: Date) -> String {
        let f = formatter
        f.setLocalizedDateFormatFromTemplate(template)
        return f.string(from: date)
    }

    /// Месяц в дате: «30 сентября» / «30 September».
    static var months: [String] {
        own ? (Lang.isRussian ? ruMonths : enMonths) : formatter.monthSymbols
    }
    /// Месяц сам по себе: «сентябрь» / «September».
    static var monthNames: [String] {
        own ? (Lang.isRussian ? ruMonthNames : enMonths) : formatter.standaloneMonthSymbols
    }

    /// Порядок как у `Calendar.component(.weekday)`: 1 — воскресенье.
    static var weekdays: [String] {
        guard own else { return formatter.standaloneWeekdaySymbols }
        return Lang.isRussian
            ? ["воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"]
            : ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
    }
    static var weekdaysShort: [String] {
        guard own else { return formatter.shortStandaloneWeekdaySymbols.map(trimDot) }
        return Lang.isRussian ? ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
                              : ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
    }

    /// «So.» → «So»: в клетке календаря точка лишняя.
    private static func trimDot(_ s: String) -> String {
        s.hasSuffix(".") ? String(s.dropLast()) : s
    }

    /// Понедельник первым.
    static var weekHeader: [String] {
        guard own else {
            let short = weekdaysShort
            return Array(short[1...]) + [short[0]]
        }
        return Lang.isRussian ? ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]
                              : ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
    }

    private static func index(_ date: Date) -> Int {
        Calendar.current.component(.weekday, from: date) - 1
    }

    static func weekday(_ date: Date) -> String { weekdays[index(date)] }
    static func weekdayShort(_ date: Date) -> String { weekdaysShort[index(date)] }

    /// «13 сентября 2026 г.»
    static func longDate(_ date: Date) -> String {
        guard own else { return pattern("dMMMMy", date) }
        let c = Calendar.current.dateComponents([.day, .month, .year], from: date)
        let tail = Lang.isRussian ? " г." : ""
        return "\(c.day ?? 1) \(months[(c.month ?? 1) - 1]) \(c.year ?? 2026)" + tail
    }

    /// «13 сентября ’26» — год двумя цифрами, для строки под именем дня
    /// (P271).
    static func headDate(_ date: Date) -> String {
        guard own else { return pattern("dMMMMyy", date) }
        let c = Calendar.current.dateComponents([.day, .month, .year], from: date)
        return "\(c.day ?? 1) \(months[(c.month ?? 1) - 1]) ’\(String(format: "%02d", (c.year ?? 2026) % 100))"
    }

    /// «13 сентября»
    static func shortDate(_ date: Date) -> String {
        guard own else { return pattern("dMMMM", date) }
        let c = Calendar.current.dateComponents([.day, .month], from: date)
        return "\(c.day ?? 1) \(months[(c.month ?? 1) - 1])"
    }

    static func monthTitle(_ date: Date) -> String {
        guard own else { return pattern("LLLLy", date) }
        let c = Calendar.current.dateComponents([.month, .year], from: date)
        return "\(monthNames[(c.month ?? 1) - 1].capitalized) \(c.year ?? 2026)"
    }

}
