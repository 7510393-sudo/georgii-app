import Foundation

/// Строка шапки записи: «ключ: значение».
struct MetaLine: Equatable {
    var key: String
    var value: String
}

/// Разбор и сборка файла записи.
///
/// Файл состоит из необязательной шапки между двумя чертами и текста под ней:
///
///     ---
///     date: 2026-09-16
///     title: Первый день осени
///     ---
///
///     08:15 Проснулся раньше будильника.
///
/// Файл без шапки — это просто текст, и он тоже читается. Приложение никогда
/// не отказывается открыть файл только потому, что его писали не мы.
struct DayFile: Equatable {

    static let fence = "---"

    var meta: [MetaLine]
    var body: String

    init(meta: [MetaLine] = [], body: String = "") {
        self.meta = meta
        self.body = body
    }

    init(text: String) {
        var lines = text.components(separatedBy: .newlines)
        var meta: [MetaLine] = []

        if lines.first?.trimmingCharacters(in: .whitespaces) == DayFile.fence {
            lines.removeFirst()
            while let line = lines.first {
                lines.removeFirst()
                if line.trimmingCharacters(in: .whitespaces) == DayFile.fence { break }
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty { meta.append(MetaLine(key: key, value: value)) }
            }
        }

        self.meta = meta
        self.body = lines.joined(separator: "\n").trimmingCharacters(in: .newlines)
    }

    var text: String {
        var out = ""
        if !meta.isEmpty {
            out += DayFile.fence + "\n"
            for line in meta { out += "\(line.key): \(line.value)\n" }
            out += DayFile.fence + "\n\n"
        }
        out += body
        if !out.hasSuffix("\n") { out += "\n" }
        return out
    }

    /// Прежние, русские, ключи шапки — и какими они стали (P353). Читаются
    /// оба; пишется английский: ключ, который приложение задаёт само,
    /// переводится при первой же правке дня.
    static let english: [String: String] = [
        "дата": "date", "заголовок": "title", "погода": "weather",
        "место": "place", "правлено": "edited", "название": "name",
        "значок": "icon",
    ]

    static func canon(_ key: String) -> String { english[key] ?? key }

    func value(_ key: String) -> String? {
        let k = DayFile.canon(key)
        return meta.first { DayFile.canon($0.key) == k }?.value
    }

    mutating func set(_ key: String, _ value: String) {
        let k = DayFile.canon(key)
        if let i = meta.firstIndex(where: { DayFile.canon($0.key) == k }) {
            meta[i].key = k
            meta[i].value = value
        } else {
            meta.append(MetaLine(key: k, value: value))
        }
    }
}
