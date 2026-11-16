import Foundation

/// Метка архива `System/chronotheca.json` (P952): по ней приложение узнаёт
/// свой архив и версию его формата.
///
/// Ключи — английские, как все имена в архиве (P353): `app`, `format`,
/// `created`. До P952 метка писалась с русскими ключами («приложение»,
/// «версия формата», «заведено») — такая читается так же и при первом
/// случае переписывается английскими, но только прочитанная целиком
/// (P182): метку, которая ещё в iCloud или не разбирается, не трогаем.
enum ArchiveMark {

    /// Версия формата, которую знает это приложение. Поднимается, когда
    /// архив меняется так, что прежнее приложение испортило бы его записью.
    static let format = 1

    struct Mark: Equatable {
        var app: String?
        var format: Int?
        var created: String?
        /// Метка с прежними русскими ключами.
        var russian = false
    }

    private static let keys = (app: "app", format: "format", created: "created")
    private static let russianKeys = (app: "приложение", format: "версия формата", created: "заведено")

    /// Разобрать текст метки. Не JSON-словарь — `nil`.
    static func parse(_ text: String) -> Mark? {
        guard let data = text.data(using: .utf8),
              let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        func number(_ v: Any?) -> Int? {
            if let n = v as? Int { return n }
            if let s = v as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
            return nil
        }
        let russian = dict[keys.app] == nil && dict[keys.format] == nil && dict[keys.created] == nil
            && (dict[russianKeys.app] != nil || dict[russianKeys.format] != nil || dict[russianKeys.created] != nil)
        return Mark(app: (dict[keys.app] ?? dict[russianKeys.app]) as? String,
                    format: number(dict[keys.format] ?? dict[russianKeys.format]),
                    created: (dict[keys.created] ?? dict[russianKeys.created]) as? String,
                    russian: russian)
    }

    /// Текст метки с английскими ключами.
    static func text(app: String = "Graphomanus", format: Int = ArchiveMark.format, created: String) -> String {
        """
        {
          "app": "\(app.replacingOccurrences(of: "\"", with: "'"))",
          "format": \(format),
          "created": "\(created.replacingOccurrences(of: "\"", with: "'"))"
        }

        """
    }

    /// Прочитать метку архива. Русские ключи — переписать английскими,
    /// сохранив значения; только если метка прочитана и разобрана целиком,
    /// и не в архиве новее приложения (P953). Метки нет или она не
    /// читается — `nil`, ничего не пишется.
    @discardableResult
    static func check(root: URL) -> Mark? {
        let url = Vault.folder(.service, in: root).appendingPathComponent(Vault.markerName)
        guard case .text(let text) = Vault.reading(at: url), var mark = parse(text) else { return nil }
        if mark.russian, (mark.format ?? format) <= format {
            let fresh = Self.text(app: mark.app ?? "Graphomanus", format: mark.format ?? format,
                                  created: mark.created ?? Vault.stamp(Date()))
            if Vault.write(fresh, to: url) == nil { mark.russian = false }
        }
        return mark
    }

    /// Архив новее приложения: формат в метке больше известного.
    static func isNewer(_ mark: Mark?) -> Bool {
        (mark?.format ?? format) > format
    }
}
