import Foundation

/// Строка плана.
///
/// Это может быть дело — тогда у него есть состояние, необязательное время,
/// текст и строки подробностей. А может быть что угодно другое: заголовок,
/// пустая строка, заметка, дописанная человеком в текстовом редакторе.
///
/// Всё, чего приложение не понимает, хранится в `verbatim` и возвращается
/// в файл нетронутым и на своём месте. Это не мелочь, а прямое следствие
/// обещания: файл принадлежит человеку, а не программе, и программа не
/// имеет права съесть то, чего не поняла.
struct PlanRow: Identifiable, Equatable {
    let id = UUID()

    /// Непустое — значит строка не разобрана и сохраняется как есть.
    var verbatim: String?

    var done = false
    var time: String?

    /// Время напоминания. Живёт в конце строки словами — «(напомнить 08:30)», —
    /// чтобы в текстовом редакторе было понятно, что это, без объяснений.
    var bell: String?

    var text = ""
    var details: [String] = []
    /// Дело из повторяющейся серии (P359). В файле — пометкой в конце
    /// строки: «(every week #k3f9)».
    var repeats: Repeat? = nil

    var isTask: Bool { verbatim == nil }

    static func task(time: String? = nil, bell: String? = nil, _ text: String) -> PlanRow {
        PlanRow(verbatim: nil, done: false, time: time, bell: bell, text: text, details: [])
    }

    static func verbatim(_ line: String) -> PlanRow {
        PlanRow(verbatim: line)
    }

    /// Надпись пустой плашки следующего дела (P452) — одна и та же на открытой
    /// и на соседних страницах (P114, P481).
    static var ghostTitle: String { T("Напомню о вашем деле", "I’ll remind you about your task") }

    /// Дело ничем не заполнено: ни названия, ни времени, ни
    /// напоминания, ни подробностей (P406).
    static func blank(_ r: PlanRow) -> Bool {
        r.isTask && r.text.trimmingCharacters(in: .whitespaces).isEmpty
            && r.time == nil && r.bell == nil && r.details.isEmpty
    }

    static func == (a: PlanRow, b: PlanRow) -> Bool {
        a.verbatim == b.verbatim && a.done == b.done && a.time == b.time
            && a.bell == b.bell && a.text == b.text && a.details == b.details
            && a.repeats == b.repeats
    }
}

enum Plan {

    /// Отступ строк подробностей. Он же служит признаком при разборе.
    static let indent = "      "

    // MARK: - Разбор

    static func rows(from body: String) -> [PlanRow] {
        var rows: [PlanRow] = []

        for line in body.components(separatedBy: .newlines) {
            if let task = parseTask(line) {
                rows.append(task)
                continue
            }
            // Строка с отступом сразу после дела — его подробности.
            if !line.trimmingCharacters(in: .whitespaces).isEmpty,
               line.hasPrefix(" "),
               let last = rows.indices.last,
               rows[last].isTask {
                rows[last].details.append(
                    String(line.drop(while: { $0 == " " || $0 == "\t" })))
                continue
            }
            rows.append(.verbatim(line))
        }

        // Хвостовые пустые строки — наши же, при сборке добавится перевод.
        while let last = rows.last, last.verbatim?.isEmpty == true {
            rows.removeLast()
        }
        return rows
    }

    private static func parseTask(_ line: String) -> PlanRow? {
        // Отметка события Календаря (P376) — не наше дело: остаётся
        // строкой файла как есть.
        if DayEvents.Mark.parse(line) != nil { return nil }
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        guard trimmed.hasPrefix("- [") else { return nil }

        let afterBracket = trimmed.dropFirst(3)
        guard let mark = afterBracket.first,
              afterBracket.dropFirst().first == "]" else { return nil }
        let done: Bool
        switch mark {
        case " ": done = false
        case "x", "X": done = true
        default: return nil
        }

        var rest = String(afterBracket.dropFirst(2))
        if rest.hasPrefix(" ") { rest.removeFirst() }

        var time: String?
        if rest.count >= 5 {
            let candidate = String(rest.prefix(5))
            if isTime(candidate) {
                time = candidate
                rest = String(rest.dropFirst(5))
                if rest.hasPrefix(" ") { rest.removeFirst() }
            }
        }

        // Пометка серии стоит последней: «… (remind 18:30) (every week #k3f9)»
        // (P359).
        var repeats: Repeat?
        if let range = rest.range(of: #"\s*\(every (day|week|month|year) #[a-z0-9]{4,12}\)$"#,
                                  options: .regularExpression) {
            let inside = String(rest[range]).trimmingCharacters(in: .whitespaces)
                .dropFirst(7).dropLast()
            let parts = inside.split(separator: " ")
            if parts.count == 2, let every = Repeat.Every(rawValue: String(parts[0])) {
                repeats = Repeat(every: every, series: String(parts[1].dropFirst()))
                rest.removeSubrange(range)
            }
        }

        var bell: String?
        // «(remind 08:30)»; до P355 — «(напомнить 08:30)», читается и так.
        if let range = rest.range(of: #"\s*\((?:remind|напомнить) (\d{2}:\d{2})\)$"#,
                                  options: .regularExpression) {
            let inside = String(rest[range])
            if let t = inside.range(of: #"\d{2}:\d{2}"#, options: .regularExpression),
               isTime(String(inside[t])) {
                bell = String(inside[t])
                rest.removeSubrange(range)
            }
        }

        return PlanRow(verbatim: nil, done: done, time: time, bell: bell,
                       text: rest, details: [], repeats: repeats)
    }

    private static func isTime(_ s: String) -> Bool {
        let parts = s.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count == 2, parts[1].count == 2,
              let h = Int(parts[0]), let m = Int(parts[1]) else { return false }
        return (0...23).contains(h) && (0...59).contains(m)
    }

    // MARK: - Фотографии

    /// Отделить фотографии, стоящие в конце плана, от строк плана.
    ///
    /// Фотографии плана и дневника разные: снимок, положенный в план,
    /// лежит в файле плана и показывается на странице плана (решение P203).
    ///
    /// Полоска — это снимки, стоящие в самом конце **после пустой строки**
    /// (так их всегда и пишет `body`). Снимки сразу под делом, без пустой
    /// строки, — это снимки того дела (P358): они остаются под ним, даже
    /// если дело последнее.
    static func splitPhotos(_ rows: [PlanRow]) -> (rows: [PlanRow], photos: [String]) {
        func blank(_ row: PlanRow) -> Bool {
            row.verbatim?.trimmingCharacters(in: .whitespaces).isEmpty == true
        }
        var rows = rows
        while let last = rows.last, blank(last) { rows.removeLast() }
        var start = rows.count
        while start > 0, let line = rows[start - 1].verbatim, Diary.stripItem(in: line) != nil {
            start -= 1
        }
        guard start < rows.count, start == 0 || blank(rows[start - 1]) else { return (rows, []) }
        let photos = rows[start...].compactMap { $0.verbatim.flatMap(Diary.stripItem(in:)) }
        rows.removeSubrange(start...)
        while let last = rows.last, blank(last) { rows.removeLast() }
        return (rows, photos)
    }

    /// Строка из одних вложений — снимки, голос, файлы, точки, сколько угодно
    /// вперемешку. Такая строка стоит под делом и ходит вместе с ним (P629).
    static func isAttachmentRow(_ line: String) -> Bool {
        !Diary.objects(in: line).isEmpty
    }

    /// Строка снимков под делом: один снимок или ряд (P358).
    static func isPhotoRow(_ line: String) -> Bool {
        let links = Diary.links(in: line)
        return !links.isEmpty && links.allSatisfy { Diary.kind(of: $0) == .photo }
    }

    /// План вместе с фотографиями в конце.
    static func body(from rows: [PlanRow], photos: [String]) -> String {
        let plan = body(from: rows)
        guard !photos.isEmpty else { return plan }
        let lines = photos.map(Diary.line).joined(separator: "\n")
        return plan.isEmpty ? lines : plan + "\n\n" + lines
    }

    // MARK: - Сборка

    static func body(from rows: [PlanRow]) -> String {
        var out = ""
        for row in rows {
            if let verbatim = row.verbatim {
                out += verbatim + "\n"
                continue
            }
            out += row.done ? "- [x] " : "- [ ] "
            if let time = row.time { out += time + " " }
            out += row.text
            if let bell = row.bell { out += " (remind \(bell))" }
            if let r = row.repeats { out += " (every \(r.every.rawValue) #\(r.series))" }
            out += "\n"
            for detail in row.details {
                out += indent + detail + "\n"
            }
        }
        while out.hasSuffix("\n\n") { out.removeLast() }
        if out.hasSuffix("\n") { out.removeLast() }
        return out
    }
}
