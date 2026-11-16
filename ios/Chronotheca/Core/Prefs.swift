import Foundation

// Нижний слой (P970): без экрана, только Foundation.

/// Настройки, которые меняют раз и надолго (P249). Хранятся в самом
/// телефоне, не в папке записей: это привычки человека, а не его записи.
enum Prefs {
    static let lock = "prefs.lock"
    static let theme = "prefs.theme"            // "system", "light", "dark"
    static let font = "prefs.font"              // "newyork", "system"
    // P290: погода, «Как прошло?», цвет календаря. Градусы, неделя, часы, сжатие,
    // размер текста, шелест и навигатор — как в iPhone (P633).
    static let noWeather = "prefs.noWeather"    // true — погоды нет
    static let noAsk = "prefs.noAsk"            // true — без «Как прошло?»
    static let ownKeyboardOnly = "prefs.ownKeyboardOnly" // true — только клавиатура iPhone (P633)
    static let calendarTint = "prefs.calendarTint" // "distance", "weekday", "none"
    /// true — прошедшие дни без старой бумаги: просто цвет прошлого (P730).
    static let plainPast = "prefs.plainPast"

    static var weatherOn: Bool { !UserDefaults.standard.bool(forKey: noWeather) }
    static var askOn: Bool { !UserDefaults.standard.bool(forKey: noAsk) }
    /// Первый день недели — как в iPhone (Основные → Язык и регион): с
    /// воскресенья или с понедельника; календарь знает только эти два (P633).
    static var firstWeekday: Int { Calendar.current.firstWeekday == 1 ? 1 : 2 }
}
