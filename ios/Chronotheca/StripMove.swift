import Foundation

/// Перенос прежнего ряда вложений плана в конец записи дневника того же дня
/// (P922, P917 п. 2, P959) — один раз всем архивом, в стороне от экрана.
///
/// Прежде вложение, положенное «в план», ложилось рядом в конец файла плана;
/// теперь всякое вложение ложится в конец записи дневника (P665). На экране
/// ничего не меняется — полоска и так одна (P408), — меняется файл, в
/// котором записана строка вложения. Ссылки переносятся дословно: путь от
/// `Planner/год/` и от `Diary/год/` один и тот же.
///
/// Осторожность — та же, что у записи дня (P182–P184):
/// - файл, который ещё в iCloud, не трогается и ждёт следующего запуска;
/// - прежние тексты плана и дневника сперва кладутся копией в
///   `System/Before attachments move/` и сверяются байт в байт;
/// - каждая запись — только если файл не изменился с прочтения;
/// - после правки разбор сверяется: текст, ответы и дела те же, вложения —
///   прежние и перенесённые;
/// - открытый сейчас день пропускается (его файл держит `DayStore`), как и
///   день с недописанной правкой (`Pending`);
/// - обрыв между записью дневника и плана не страшен: повторный проход
///   увидит ссылки уже в дневнике и только снимет ряд с плана.
///
/// Итог — `System/attachments-move.txt`. Пока в нём «waiting» больше нуля,
/// проход повторяется при следующем запуске.
enum StripMove {

    /// Где лежат копии прежних файлов — внутри `System` архива.
    static let backupName = "Before attachments move"
    /// Файл итога в `System`.
    static let reportName = "attachments-move.txt"

    /// Что вышло с одним днём.
    enum Outcome: Equatable {
        /// Ряда в плане нет — делать нечего.
        case nothing
        /// Перенесено столько вложений (0 — они уже были в дневнике, снят
        /// только ряд плана).
        case moved(Int)
        /// Файл ещё в iCloud.
        case away
        /// Файл изменили между чтением и записью.
        case changed
        /// Не сошлась проверка или не прошла запись — ничего не тронуто
        /// или тронут только дневник (повторный проход доделает).
        case failed(String)
    }

    struct Report: Equatable {
        var moved = 0
        var attachments = 0
        /// День → почему ждёт.
        var waiting: [String: String] = [:]

        var text: String {
            var out = "Attachments moved from the planner to the diary (P959)\n"
            out += "date: \(Vault.stamp(Date()))\n"
            out += "days moved: \(moved)\n"
            out += "attachments moved: \(attachments)\n"
            out += "waiting: \(waiting.count)\n"
            for stamp in waiting.keys.sorted() {
                out += "  \(stamp): \(waiting[stamp] ?? "")\n"
            }
            return out
        }
    }

    // MARK: - Правка текстов (без файлов)

    /// Отделить прежний ряд вложений в конце плана от строк плана. Читается
    /// только здесь, для переноса (P961): приложение такой ряд больше не
    /// пишет и не показывает отдельно — оставшийся (файл был в iCloud) виден
    /// строкой вложений под последним делом.
    ///
    /// Ряд — это вложения в самом конце **после пустой строки** (так его
    /// писало приложение). Вложения сразу под делом, без пустой строки, —
    /// вложения того дела (P358): они остаются под ним, даже если дело
    /// последнее.
    static func split(_ rows: [PlanRow]) -> (rows: [PlanRow], photos: [String]) {
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

    /// План без ряда вложений в конце. `nil` — ряда нет или файл устроен
    /// не так, как его пишет приложение (тогда его не трогаем). Меняются
    /// только последние строки файла; шапка и дела остаются байт в байт.
    static func planWithout(_ raw: String) -> (plan: String, links: [String])? {
        // Файл из Windows-редактора не правим построчно — пусть ждёт.
        guard !raw.contains("\r") else { return nil }
        let file = DayFile(text: raw)
        let parts = split(Plan.rows(from: file.body))
        guard !parts.photos.isEmpty else { return nil }

        var lines = raw.components(separatedBy: "\n")
        func dropBlank() {
            while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
                lines.removeLast()
            }
        }
        dropBlank()
        var found: [String] = []
        while let last = lines.last, let item = Diary.stripItem(in: last) {
            found.insert(item, at: 0)
            lines.removeLast()
        }
        guard found == parts.photos else { return nil }
        dropBlank()
        let plan = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"

        // Сверка: шапка та же, дела те же, ряда больше нет.
        let after = DayFile(text: plan)
        let again = split(Plan.rows(from: after.body))
        guard after.meta == file.meta, again.photos.isEmpty,
              Plan.body(from: again.rows) == Plan.body(from: parts.rows) else { return nil }
        return (plan, parts.photos)
    }

    /// Запись дневника с вложениями в конце — теми, которых в ней ещё нет.
    /// Текст записи не перестраивается: строки дописываются в конец файла,
    /// после пустой строки, рядами по четыре, как их пишет приложение
    /// (P665). `known` — названия дел дня, по ним разбираются ответы
    /// «Как прошло?» (P155). `nil` — проверка разбора не сошлась.
    static func diaryAdding(_ links: [String], to raw: String, known: [String]) -> String? {
        guard !raw.contains("\r") else { return nil }
        let fresh = links.filter { !raw.contains($0) }
        guard !fresh.isEmpty else { return raw }
        let file = DayFile(text: raw)
        let before = Diary(body: file.body, known: known)

        let rows = stride(from: 0, to: fresh.count, by: 4).map { start in
            fresh[start..<min(start + 4, fresh.count)].map(Diary.line).joined(separator: " ")
        }.joined(separator: "\n")
        var base = raw
        while let last = base.last, last == "\n" || last == " " || last == "\t" { base.removeLast() }
        let result = (base.isEmpty ? "" : base + "\n\n") + rows + "\n"

        // Сверка: шапка, текст и ответы те же; вложения — прежние и новые.
        let afterFile = DayFile(text: result)
        let after = Diary(body: afterFile.body, known: known)
        guard afterFile.meta == file.meta, after.text == before.text,
              after.answers == before.answers, after.photos == before.photos + fresh
        else { return nil }
        return result
    }

    // MARK: - Один день

    private static func dayURL(_ folder: Vault.Folder, _ stamp: String, root: URL) -> URL {
        Vault.folder(folder, in: root)
            .appendingPathComponent(String(stamp.prefix(4)))
            .appendingPathComponent(stamp + ".md")
    }

    private static func backupURL(_ folder: Vault.Folder, _ stamp: String, root: URL) -> URL {
        Vault.folder(.service, in: root)
            .appendingPathComponent(backupName)
            .appendingPathComponent(folder.rawValue)
            .appendingPathComponent(String(stamp.prefix(4)))
            .appendingPathComponent(stamp + ".md")
    }

    /// Положить копию прежнего текста и сверить её байт в байт. Копия уже
    /// есть (прошлый проход оборвался) — она старше и остаётся.
    private static func keep(_ text: String, as url: URL) -> Bool {
        if FileManager.default.fileExists(atPath: url.path) { return true }
        guard Vault.write(text, to: url) == nil,
              let back = try? Data(contentsOf: url) else { return false }
        return back == Data(text.utf8)
    }

    /// Текст файла сейчас; `nil` — файла нет; `.away` — в iCloud.
    private enum Now: Equatable { case none, text(String), away }

    private static func now(_ url: URL) -> Now {
        switch Vault.reading(at: url) {
        case .none: return .none
        case .text(let t): return .text(t)
        case .away: return .away
        }
    }

    /// Перенести ряд одного дня. Звать на главной очереди: открытый день и
    /// записи `DayStore` тоже там, и между чтением и записью никто не
    /// вклинится.
    static func moveOne(_ stamp: String, root: URL) -> Outcome {
        if Vault.newer { return .failed("archive is newer than the app") }
        let planURL = dayURL(.planner, stamp, root: root)
        let diaryURL = dayURL(.diary, stamp, root: root)

        guard case .text(let plan) = now(planURL) else {
            return now(planURL) == .away ? .away : .nothing
        }
        guard let cut = planWithout(plan) else { return .nothing }

        let diaryNow = now(diaryURL)
        if diaryNow == .away { return .away }
        let diary: String
        if case .text(let t) = diaryNow { diary = t } else { diary = "" }

        let known = Plan.rows(from: DayFile(text: plan).body).filter(\.isTask).map(\.text)
        guard let newDiary = diaryAdding(cut.links, to: diary, known: known) else {
            return .failed("check did not match")
        }

        // Копии прежних текстов — до всякой записи.
        guard keep(plan, as: backupURL(.planner, stamp, root: root)) else {
            return .failed("backup of the planner file")
        }
        if diaryNow != .none, !keep(diary, as: backupURL(.diary, stamp, root: root)) {
            return .failed("backup of the diary file")
        }

        // Дневник — только если его не меняли с прочтения.
        if newDiary != diary {
            guard now(diaryURL) == diaryNow else { return .changed }
            if let trouble = Vault.write(newDiary, to: diaryURL) { return .failed(trouble) }
            guard now(diaryURL) == .text(newDiary) else { return .failed("diary did not read back") }
        }
        // План — только если его не меняли с прочтения.
        guard now(planURL) == .text(plan) else { return .changed }
        if let trouble = Vault.write(cut.plan, to: planURL) { return .failed(trouble) }
        guard now(planURL) == .text(cut.plan) else { return .failed("planner did not read back") }

        let fresh = cut.links.filter { !diary.contains($0) }
        return .moved(fresh.count)
    }

    // MARK: - Весь архив

    /// Дни, у которых в плане есть ряд или файл плана ещё в iCloud. Читает
    /// папку целиком — звать в стороне от экрана. Вторые версии
    /// («— second version») — не дни и не трогаются (P183).
    static func candidates(root: URL) -> (days: [String], away: [String]) {
        let fm = FileManager.default
        let planner = Vault.folder(.planner, in: root)
        var days: [String] = [], away: [String] = []
        let years = (try? fm.contentsOfDirectory(atPath: planner.path)) ?? []
        for year in years.sorted() where year.count == 4 && Int(year) != nil {
            let folder = planner.appendingPathComponent(year)
            let names = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
            for name in names.sorted() {
                // «.ГГГГ-ММ-ДД.md.icloud» — файл ещё в облаке.
                var plain = name
                let stub = plain.hasPrefix(".") && plain.hasSuffix(".icloud")
                if stub { plain = String(plain.dropFirst().dropLast(7)) }
                guard plain.hasSuffix(".md") else { continue }
                let stamp = String(plain.dropLast(3))
                guard Vault.date(from: stamp) != nil else { continue }
                if stub { away.append(stamp); continue }
                switch Vault.reading(at: folder.appendingPathComponent(plain), coordinated: false) {
                case .text(let t): if planWithout(t) != nil { days.append(stamp) }
                case .away: away.append(stamp)
                case .none: break
                }
            }
        }
        return (days, away)
    }

    /// Итог прошлого прохода: всё перенесено — второй раз не идём.
    static func isDone(root: URL) -> Bool {
        let url = Vault.folder(.service, in: root).appendingPathComponent(reportName)
        guard case .text(let t) = Vault.reading(at: url, coordinated: false) else { return false }
        return t.components(separatedBy: "\n").contains("waiting: 0")
    }

    /// Пройти весь архив. `skip` — день, который сейчас трогать нельзя
    /// (открыт или с недописанной правкой): причина или `nil`. `onMain` —
    /// как выполнить шаг на главной очереди (в проверках — сразу).
    static func run(root: URL,
                    skip: @escaping (String) -> String? = { _ in nil },
                    onMain: (() -> Void) -> Void = { $0() }) -> Report {
        var report = Report()
        let found = candidates(root: root)
        for stamp in found.away { report.waiting[stamp] = "in iCloud" }
        for stamp in found.days {
            var outcome = Outcome.nothing
            var why: String?
            onMain {
                why = skip(stamp)
                if why == nil { outcome = moveOne(stamp, root: root) }
            }
            if let why { report.waiting[stamp] = why; continue }
            switch outcome {
            case .nothing: break
            case .moved(let n):
                report.moved += 1
                report.attachments += n
            case .away: report.waiting[stamp] = "in iCloud"
            case .changed: report.waiting[stamp] = "changed while moving"
            case .failed(let why): report.waiting[stamp] = why
            }
        }
        let url = Vault.folder(.service, in: root).appendingPathComponent(reportName)
        Vault.write(report.text, to: url)
        return report
    }

    // MARK: - После запуска

    private static var started = false

    /// Один проход после запуска, в стороне от экрана, через несколько
    /// секунд — не мешая первому экрану и описи. `openDay` — открытый день
    /// (спрашивается на главной очереди). `done` — что-то перенесено:
    /// опись перечитать.
    static func startSoon(vault: Vault, openDay: @escaping () -> Date, done: @escaping () -> Void) {
        guard !started, !Vault.isPreview, NSClassFromString("XCTestCase") == nil,
              !Vault.newer, let root = vault.root else { return }
        started = true
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 6) {
            guard !isDone(root: root) else { return }
            let report = run(root: root, skip: { stamp in
                if Vault.stamp(openDay()) == stamp { return "open on screen" }
                if let date = Vault.date(from: stamp),
                   Pending.draft(.planner, date: date, root: root) != nil
                    || Pending.draft(.diary, date: date, root: root) != nil {
                    return "unsaved edit"
                }
                return nil
            }, onMain: { step in DispatchQueue.main.sync(execute: step) })
            DispatchQueue.main.async {
                Trace.note("перенос вложений: дней \(report.moved), вложений \(report.attachments), ждут \(report.waiting.count)")
                if report.moved > 0 { done() }
            }
        }
    }
}
