import Foundation

/// Язык приложения (P355, P369): десять языков. При первом запуске — язык
/// телефона, если он среди наших, иначе английский; в настройках можно
/// выбрать любой.
///
/// Выбирается в самом приложении, а не только языком телефона: человек
/// может держать телефон на одном языке, а дневник вести на другом.
/// Сменили — приложение перерисовывается целиком (`ChronothecaApp`).
enum Lang {
    static let key = "prefs.language"

    /// Наши языки — названия на них самих, по алфавиту: латиница, кириллица, японский (P439).
    static let all: [(code: String, name: String)] = [
        ("de", "Deutsch"), ("en", "English"), ("es", "Español"), ("fr", "Français"),
        ("it", "Italiano"), ("nl", "Nederlands"), ("pt", "Português"),
        ("ru", "Русский"), ("uk", "Українська"), ("ja", "日本語"),
    ]

    /// Язык сейчас: выбранный в настройках, иначе — язык телефона, если он
    /// у нас есть, иначе английский.
    static var code: String {
        if let chosen = UserDefaults.standard.string(forKey: key),
           all.contains(where: { $0.code == chosen }) { return chosen }
        return phone
    }

    /// Первый из языков телефона, который у нас есть.
    static var phone: String {
        for id in Locale.preferredLanguages {
            let base = String(id.prefix(while: { $0 != "-" && $0 != "_" })).lowercased()
            if all.contains(where: { $0.code == base }) { return base }
        }
        return "en"
    }

    static var isRussian: Bool { code == "ru" }

    /// Название языка для строки настроек — на нём самом.
    static var name: String { all.first { $0.code == code }?.name ?? "English" }

    static func set(_ code: String) {
        UserDefaults.standard.set(code, forKey: key)
    }

    /// Для дат и чисел.
    static var locale: Locale { Locale(identifier: code) }
}

/// Надпись на языке приложения. Русская и английская стоят рядом, в том
/// месте кода, где надпись показывается; остальные языки — в
/// `<язык>.lproj/App.strings`, по английской надписи (P369). Нет перевода —
/// английская.
func T(_ ru: String, _ en: String) -> String {
    switch Lang.code {
    case "ru": return ru
    case "en": return en
    case let code: return Strings.table(code).translate(en)
    }
}

/// Переводы одного языка.
///
/// Ключ — английская надпись; вставки в ней (`\(n)` в коде) записаны как
/// `%@`. Готовая надпись приходит уже со вставками — её сначала ищут как
/// есть, потом по образцам с `%@`; найденные вставки ложатся в перевод на
/// свои места (`%@` по порядку или `%1$@`, `%2$@`).
final class Strings {

    private let exact: [String: String]
    private let patterns: [(NSRegularExpression, String)]
    private var cache: [String: String] = [:]
    private let lock = NSLock()

    private static var tables: [String: Strings] = [:]
    private static let tablesLock = NSLock()

    static func table(_ code: String) -> Strings {
        tablesLock.lock()
        defer { tablesLock.unlock() }
        if let t = tables[code] { return t }
        let t = Strings(code: code)
        tables[code] = t
        return t
    }

    convenience init(code: String, bundle: Bundle = .main) {
        let path = bundle.path(forResource: "App", ofType: "strings", inDirectory: nil,
                               forLocalization: code)
        let dict = (path.flatMap { NSDictionary(contentsOfFile: $0) } as? [String: String]) ?? [:]
        self.init(dict)
    }

    init(_ dict: [String: String]) {
        exact = dict
        // Длинные образцы — первыми: «Files: %@ of %@» раньше, чем «%@ of %@».
        patterns = dict.compactMap { key, value in
            guard key.contains("%@") else { return nil }
            let parts = key.components(separatedBy: "%@").map(NSRegularExpression.escapedPattern(for:))
            let pattern = "^" + parts.joined(separator: "(.+?)") + "$"
            guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators])
            else { return nil }
            return (re, value)
        }
        .sorted { $0.0.pattern.count > $1.0.pattern.count }
    }

    func translate(_ en: String) -> String {
        if let found = exact[en] { return found }
        lock.lock()
        defer { lock.unlock() }
        if let known = cache[en] { return known }
        var out = en
        let range = NSRange(location: 0, length: (en as NSString).length)
        for (re, value) in patterns {
            guard let m = re.firstMatch(in: en, range: range) else { continue }
            let args = (1..<m.numberOfRanges).map { (en as NSString).substring(with: m.range(at: $0)) }
            out = Strings.fill(value, args)
            break
        }
        if cache.count > 500 { cache.removeAll() }
        cache[en] = out
        return out
    }

    /// Вставки на свои места: `%2$@` — вторая, `%@` — следующая по порядку.
    static func fill(_ text: String, _ args: [String]) -> String {
        var out = ""
        var next = 0
        var rest = Substring(text)
        while let at = rest.firstIndex(of: "%") {
            out += rest[..<at]
            let tail = rest[rest.index(after: at)...]
            if tail.hasPrefix("@") {
                out += next < args.count ? args[next] : ""
                next += 1
                rest = tail.dropFirst()
            } else if let d = tail.first, d.isNumber, tail.dropFirst().hasPrefix("$@") {
                let i = Int(String(d))! - 1
                out += i < args.count ? args[i] : ""
                rest = tail.dropFirst(3)
            } else {
                out += "%"
                rest = tail
            }
        }
        out += rest
        return out
    }
}
