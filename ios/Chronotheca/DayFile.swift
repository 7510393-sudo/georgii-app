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
        // Файл из Windows-редактора — «\r\n»: по `.newlines` он делился бы
        // на лишние пустые строки, и план удваивался бы при записи (P951).
        let plain = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = plain.components(separatedBy: "\n")
        var meta: [MetaLine] = []

        // Шапка — только если есть и закрывающая черта. Файл, который просто
        // начинается чертой (разделитель в разметке), — весь текст: прежде
        // он уходил в шапку и показывался пустым (P951).
        if lines.first?.trimmingCharacters(in: .whitespaces) == DayFile.fence,
           let close = lines.dropFirst().firstIndex(where: {
               $0.trimmingCharacters(in: .whitespaces) == DayFile.fence }) {
            for line in lines[1..<close] {
                guard let colon = line.firstIndex(of: ":") else { continue }
                let key = String(line[line.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty { meta.append(MetaLine(key: key, value: value)) }
            }
            lines.removeFirst(close + 1)
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

    func value(_ key: String) -> String? {
        meta.first { $0.key == key }?.value
    }

    mutating func set(_ key: String, _ value: String) {
        if let i = meta.firstIndex(where: { $0.key == key }) {
            meta[i].value = value
        } else {
            meta.append(MetaLine(key: key, value: value))
        }
    }
}
