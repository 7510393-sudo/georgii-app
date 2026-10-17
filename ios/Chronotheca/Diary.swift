import Foundation

/// Тело записи дневника: ответы «Как прошло?» и свободный текст.
///
/// Ответы лежат в том же файле, над текстом, под заголовком — так их видно
/// и в обычном текстовом редакторе, без приложения. Привязаны они к названию
/// дела, а не к его номеру: переставили дела местами — ответы остались при
/// своих делах.
///
/// Всё, что не разобрано, остаётся текстом и возвращается в файл как есть.
struct Diary: Equatable {

    /// Заголовок ответов в файле — английский (P353). Прежний, русский,
    /// читается по-прежнему; при первой правке дня он становится новым.
    static let heading = "## How did it go?"
    static let oldHeading = "## Как прошло?"

    /// Название дела → ответ.
    var answers: [String: String] = [:]
    var text: String = ""

    /// Фотографии дня — ссылки из записи на файлы в папке «Фотографии».
    ///
    /// В файле каждая стоит своей строкой в конце записи, обычной ссылкой
    /// разметки: `![](../../Фотографии/2026/2026-09-24_08.15.30.jpg)`. Её
    /// понимает любой редактор разметки — Obsidian покажет саму фотографию.
    /// В поле записи приложение этих строк не показывает: фотографии стоят
    /// над текстом картинками (решение P200).
    var photos: [String] = []

    init(answers: [String: String] = [:], text: String = "", photos: [String] = []) {
        self.answers = answers
        self.text = text
        self.photos = photos
    }

    /// Разобрать тело записи.
    ///
    /// `known` — настоящие названия дел этого дня. Без них строку приходится
    /// делить по двоеточию наугад, а двоеточие бывает и в названии дела
    /// («Позвонить в 10:00»), и в ответе («сделал в 10:30»). Со списком дел
    /// гадать не нужно: название узнаётся целиком (решение P155).
    init(body: String, known: [String] = []) {
        var lines = body.components(separatedBy: .newlines)

        // Заголовок ищем только в самом начале: ниже по тексту такая же
        // строка — часть записи человека, и трогать её нельзя.
        var i = 0
        while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).isEmpty { i += 1 }
        guard i < lines.count,
              [Diary.heading, Diary.oldHeading]
                .contains(lines[i].trimmingCharacters(in: .whitespaces)) else {
            (text, photos) = Diary.split(body.trimmingCharacters(in: .newlines))
            return
        }

        lines.removeFirst(i + 1)
        while let line = lines.first {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { lines.removeFirst(); continue }
            guard trimmed.hasPrefix("- ") else { break }
            let rest = String(trimmed.dropFirst(2))

            // Сначала ищем настоящее название дела. Нашлось — делим по нему,
            // и никакие двоеточия внутри не мешают.
            if let task = known.first(where: { !$0.isEmpty && rest.hasPrefix($0 + ":") }) {
                answers[task] = String(rest.dropFirst(task.count + 1))
                    .trimmingCharacters(in: .whitespaces)
                lines.removeFirst()
                continue
            }

            // Не нашлось — делим по первому двоеточию: название стоит первым,
            // и всё, что за ним, принадлежит ответу.
            guard let colon = rest.firstIndex(of: ":") else { break }
            let task = String(rest[..<colon]).trimmingCharacters(in: .whitespaces)
            let answer = String(rest[rest.index(after: colon)...])
                .trimmingCharacters(in: .whitespaces)
            if !task.isEmpty { answers[task] = answer }
            lines.removeFirst()
        }
        (text, photos) = Diary.split(
            lines.joined(separator: "\n").trimmingCharacters(in: .newlines))
    }

    private static let pictureLine = try! NSRegularExpression(
        pattern: #"^\s*(!?)\[[^\]]*\]\((.+)\)\s*$"#)

    /// Один снимок где угодно в строке: `![](путь)` или `![](<путь с пробелом>)`.
    private static let onePicture = try! NSRegularExpression(
        pattern: #"!\[[^\]]*\]\((<[^>]*>|[^)\s]+)\)"#)

    /// Снимки, стоящие в строке рядом — `![](a) ![](b)`, — если в строке
    /// нет ничего, кроме них и пробелов (P348). Пусто — строка не такая.
    /// Строку с одним снимком разбирает и `picture(in:)`; эта — для ряда.
    static func pictures(in line: String) -> [(range: NSRange, link: String)] {
        let ns = line as NSString
        guard line.contains("![") else { return [] }
        var found: [(range: NSRange, link: String)] = []
        for m in onePicture.matches(in: line, range: NSRange(location: 0, length: ns.length)) {
            var link = ns.substring(with: m.range(at: 1))
            if link.hasPrefix("<"), link.hasSuffix(">") {
                link = String(link.dropFirst().dropLast())
            }
            guard !link.contains("://"), !link.hasPrefix("geo:") else { return [] }
            found.append((range: m.range, link: link))
        }
        guard !found.isEmpty else { return [] }
        let rest = NSMutableString(string: line)
        for piece in found.reversed() { rest.replaceCharacters(in: piece.range, with: "") }
        guard (rest as String).trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return found
    }

    /// Снимки где угодно в тексте — и посреди фразы (P357). Сюда снимок
    /// мог попасть при переносе; показывать его буквами нельзя, и вернуть
    /// его в полоску нужно уметь, где бы он ни стоял.
    static func anywhere(in text: String) -> [(range: NSRange, link: String)] {
        guard text.contains("![") else { return [] }
        let ns = text as NSString
        return onePicture.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { m -> (range: NSRange, link: String)? in
                var link = ns.substring(with: m.range(at: 1))
                if link.hasPrefix("<"), link.hasSuffix(">") {
                    link = String(link.dropFirst().dropLast())
                }
                guard !link.contains("://"), !link.hasPrefix("geo:") else { return nil }
                return (range: m.range, link: link)
            }
    }

    /// Все вложения строки: одно — как прежде, или ряд снимков (P348).
    static func links(in line: String) -> [String] {
        if let one = picture(in: line) { return [one] }
        return pictures(in: line).map(\.link)
    }

    /// Ссылка на вложение, если строка — только она и ничего больше:
    /// `![](снимок.jpg)` или `[голос](голос.m4a)`.
    ///
    /// Ссылка посреди фразы — часть того, что человек написал, и вложением
    /// не считается. Ссылка на сайт — тоже: вложение лежит в папке
    /// (P200, P209).
    static func picture(in line: String) -> String? {
        let ns = line as NSString
        guard let m = pictureLine.firstMatch(in: line, range: NSRange(location: 0, length: ns.length))
        else { return nil }
        var link = ns.substring(with: m.range(at: 2))
        if link.hasPrefix("<"), link.hasSuffix(">") {
            link = String(link.dropFirst().dropLast())
        }
        // Точка на карте `[Дом](geo:…)` — тоже не вложение: у неё нет
        // файла, она остаётся в тексте кнопкой (P213). Несколько снимков
        // в одной строке — не один снимок со странным именем, а ряд
        // (`pictures(in:)`, P348).
        guard !link.contains("://"), !link.hasPrefix("geo:"), !link.contains("](")
        else { return nil }
        return link
    }

    /// Ответ «Как прошло?» с вложением в конце — через пробел, в ту же
    /// строку: в файле ответ — одна строка (P172, P407).
    static func adding(_ piece: String, to answer: String) -> String {
        let body = answer.trimmingCharacters(in: .whitespaces)
        return body.isEmpty ? piece : body + " " + piece
    }

    /// Какого рода вложение — по расширению файла.
    enum Kind { case photo, video, audio, file }

    static func kind(of link: String) -> Kind {
        switch (link as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg", "png", "heic", "heif", "gif", "webp": return .photo
        case "mov", "mp4", "m4v", "3gp": return .video
        case "m4a", "mp3", "wav", "aac", "caf", "aiff": return .audio
        default: return .file
        }
    }

    /// Отделить фотографии, стоящие в конце записи, от текста.
    ///
    /// Конец записи — это полоска внизу страницы. Фотография, которую
    /// человек поставил посреди текста, остаётся в тексте на своём месте:
    /// там её и рисует поле записи (решение P203).
    static func split(_ text: String) -> (text: String, photos: [String]) {
        var lines = text.components(separatedBy: "\n")
        var photos: [String] = []
        while let last = lines.last {
            if last.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.removeLast()
            } else if let link = picture(in: last) {
                photos.insert(link, at: 0)
                lines.removeLast()
            } else {
                break
            }
        }
        guard !photos.isEmpty else { return (text, []) }
        return (lines.joined(separator: "\n").trimmingCharacters(in: .newlines), photos)
    }

    /// Строка-вложение для файла. Снимок — картинкой `![](…)`, остальное —
    /// ссылкой с именем файла `[имя](…)`: так их показывают редакторы
    /// разметки. Путь с пробелом берётся в угловые скобки.
    static func line(_ link: String) -> String {
        let path = link.contains(" ") ? "<\(link)>" : link
        if kind(of: link) == .photo { return "![](\(path))" }
        let name = ((link as NSString).lastPathComponent as NSString).deletingPathExtension
        return "[\(name)](\(path))"
    }

    /// Собрать обратно. Порядок ответов задаётся списком дел, чтобы файл не
    /// перетасовывался при каждой записи.
    ///
    /// Ответы, у которых дела в списке не нашлось, **не выбрасываются**, а
    /// дописываются следом. Раньше выбрасывались — и человек терял
    /// написанное, стоило переименовать дело или удалить его. Написанное
    /// человеком не исчезает оттого, что приложению неудобно (решение P155).
    func body(order: [String]) -> String {
        let written = answers.filter { !$0.value.isEmpty }.keys
        let kept = order.filter { (answers[$0] ?? "").isEmpty == false }
            + written.filter { !order.contains($0) }.sorted()
        var out = ""
        if !kept.isEmpty {
            out += Diary.heading + "\n\n"
            for task in kept { out += "- \(task): \(answers[task] ?? "")\n" }
            out += "\n"
        }
        out += text
        if !photos.isEmpty {
            if !out.trimmingCharacters(in: .newlines).isEmpty { out += "\n\n" }
            out += photos.map(Diary.line).joined(separator: "\n")
        }
        return out.trimmingCharacters(in: .newlines)
    }
}
