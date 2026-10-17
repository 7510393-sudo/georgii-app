import Foundation

/// Пометка серии в строке дела (P359).
struct Repeat: Equatable {
    enum Every: String, CaseIterable {
        // «Каждый день» — для привычек (P378).
        case day, week, month, year

        /// Как это сказать на кнопке.
        var title: String {
            switch self {
            case .day:   return T("каждый день", "every day")
            case .week:  return T("каждую неделю", "every week")
            case .month: return T("каждый месяц", "every month")
            case .year:  return T("каждый год", "every year")
            }
        }
    }

    var every: Every
    var series: String
}

/// Серия повторяющегося дела: с какого дня, как часто, по какой день уже
/// вписана в файлы и каким дело пишется дальше.
struct Series: Codable, Equatable {
    var id: String
    var every: String
    /// День, от которого считаются повторы, — ГГГГ-ММ-ДД.
    var anchor: String
    /// По какой день повторы уже вписаны.
    var until: String
    var time: String?
    var bell: String?
    var text: String
    /// Дни, куда вписать не вышло — файл ещё в iCloud или был открыт;
    /// приложение попробует снова.
    var missed: [String]?

    var kind: Repeat.Every { Repeat.Every(rawValue: every) ?? .week }
}

/// Повторяющиеся дела (P359).
///
/// Повтор — не правило внутри приложения, а настоящая строка дела в файле
/// каждого будущего дня, на год вперёд: откройте папку на Mac — дела там.
/// Приложение дописывает год вперёд, пока им пользуются.
///
/// Писать в файлы будущих дней — новое для приложения, поэтому правила
/// те же, что везде (P182, P183): файл читается напрямую; не прочитался
/// (ещё в iCloud) — день пропускается и пробуется снова позже; перед
/// записью файл читается ещё раз — его не поправили, пока мы его собирали.
/// В день, открытый на экране, фоном не пишется никогда: там правит
/// человек, и его правку не перебить.
enum Repeats {

    static let fileName = "repeats.json"
    /// На сколько дней вперёд вписываются повторы.
    static let horizon = 365

    /// Ежедневное дело — на месяц вперёд, а не на год: иначе одна привычка
    /// заводила бы 365 файлов. Месяц дописывается, пока приложением
    /// пользуются (P378).
    static func horizon(for kind: Repeat.Every) -> Int { kind == .day ? 31 : horizon }

    // MARK: - Список серий

    private static func url(_ vault: Vault) -> URL? {
        vault.folder(.service)?.appendingPathComponent(fileName)
    }

    static func load(_ vault: Vault) -> [Series] { list(vault) ?? [] }

    /// Список серий — или `nil`, если файл есть, но прочитать его нельзя
    /// (ещё в iCloud, испорчен). Тогда писать список нельзя: новый лёг бы
    /// поверх непрочитанного, и все серии пропали бы (P182, P427).
    static func list(_ vault: Vault) -> [Series]? {
        guard let url = url(vault) else { return nil }
        switch Vault.reading(at: url) {
        case .none: return []
        case .away: return nil
        case .text(let text):
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
            return try? JSONDecoder().decode([Series].self, from: Data(text.utf8))
        }
    }

    /// Дни после `date`, в файлах которых стоит дело серии `id`. Нужно,
    /// когда серии нет в списке — список не перенесли с архивом или он ещё
    /// в iCloud: тогда «этот и все следующие» удаляли только этот день
    /// (P427). Смотрятся файлы плана на два года вперёд.
    static func scan(_ id: String, after date: Date, vault: Vault) -> [Date] {
        guard let root = vault.root else { return [] }
        let cal = Calendar.current
        let from = cal.startOfDay(for: date)
        let base = Vault.folder(.planner, in: root)
        let fm = FileManager.default
        var out: [Date] = []
        let year = cal.component(.year, from: from)
        for y in year...(year + 2) {
            let folder = base.appendingPathComponent(String(y))
            guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { continue }
            for name in names where name.hasSuffix(".md") && !name.hasPrefix(".") {
                guard let day = Vault.date(from: String(name.dropLast(3))), day > from,
                      case .text(let text) = Vault.reading(at: folder.appendingPathComponent(name),
                                                           coordinated: false),
                      text.contains(id) else { continue }
                let rows = Plan.rows(from: DayFile(text: text).body)
                if rows.contains(where: { $0.repeats?.series == id }) { out.append(day) }
            }
        }
        return out.sorted()
    }

    @discardableResult
    static func save(_ list: [Series], _ vault: Vault) -> Bool {
        guard let url = url(vault) else { return false }
        let coder = JSONEncoder()
        coder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? coder.encode(list) else { return false }
        return Vault.write(data: data, to: url) == nil
    }

    static func newID() -> String {
        let letters = Array("abcdefghijkmnopqrstuvwxyz23456789")
        return String((0..<6).map { _ in letters[Int.random(in: 0..<letters.count)] })
    }

    // MARK: - Дни повторов

    /// Дни серии строго после `after` и не позже `through`. Месяц и год
    /// считаются от первого дня серии: 31-е в коротком месяце — последний
    /// его день, 29 февраля в обычном году — 28-е.
    static func dates(_ every: Repeat.Every, anchor: Date, after: Date, through: Date) -> [Date] {
        let cal = Calendar.current
        let start = cal.startOfDay(for: anchor)
        let from = cal.startOfDay(for: after)
        let to = cal.startOfDay(for: through)
        var out: [Date] = []
        var k = 1
        while k < 2000 {
            let next: Date?
            switch every {
            case .day:   next = cal.date(byAdding: .day, value: k, to: start)
            case .week:  next = cal.date(byAdding: .day, value: 7 * k, to: start)
            case .month: next = cal.date(byAdding: .month, value: k, to: start)
            case .year:  next = cal.date(byAdding: .year, value: k, to: start)
            }
            guard let day = next.map(cal.startOfDay(for:)), day <= to else { break }
            if day > from { out.append(day) }
            k += 1
        }
        return out
    }

    // MARK: - Запись в файлы дней

    /// Вписать дело серии в файл дня. `true` — оно там (вписано сейчас или
    /// уже было), `false` — не вышло, попробовать позже.
    static func put(_ s: Series, on date: Date, vault: Vault) -> Bool {
        change(on: date, vault: vault) { rows in
            guard !rows.contains(where: { $0.repeats?.series == s.id }) else { return false }
            var row = PlanRow.task(time: s.time, bell: s.bell, s.text)
            row.repeats = Repeat(every: s.kind, series: s.id)
            rows.append(row)
            return true
        }
    }

    /// Дописать строки в конец плана другого дня — дело, перенесённое
    /// свайпом вправо (P383). `false` — файл того дня не прочитался
    /// (ещё в iCloud) или изменился, пока его собирали: не пишем.
    static func add(_ rows: [PlanRow], on date: Date, vault: Vault) -> Bool {
        change(on: date, vault: vault) { list in
            list.append(contentsOf: rows)
            return true
        }
    }

    /// Поправить в файле дня строку дела серии или убрать её. `false` — не
    /// вышло (файл не прочитался или изменился).
    static func edit(_ id: String, on date: Date, vault: Vault,
                     _ apply: @escaping (inout [PlanRow], Int) -> Void) -> Bool {
        change(on: date, vault: vault) { rows in
            guard let i = rows.firstIndex(where: { $0.repeats?.series == id }) else { return false }
            apply(&rows, i)
            return true
        }
    }

    /// Прочитать файл плана дня, дать поправить строки, записать. `fix`
    /// возвращает `false`, если править нечего, — тогда файл не трогается.
    private static func change(on date: Date, vault: Vault,
                               _ fix: (inout [PlanRow]) -> Bool) -> Bool {
        guard let url = vault.file(.planner, for: date) else { return false }
        let was = Vault.reading(at: url)
        if was == .away { return false }
        var file = DayFile(text: was.text)
        var (rows, photos) = Plan.splitPhotos(Plan.rows(from: file.body))
        guard fix(&rows) else { return true }
        file.body = Plan.body(from: rows, photos: photos)
        if file.value("date") == nil { file.set("date", Vault.stamp(date)) }
        // Ещё раз с диска: файл могли поправить, пока мы его собирали.
        guard Vault.reading(at: url, coordinated: false) == was else { return false }
        return Vault.write(file.text, to: url) == nil
    }

    // MARK: - Серия целиком

    /// Дописать повторы серии до `through`. Дни, куда не вышло, — в
    /// `missed`, и те, что пропущены прежде, — ещё раз. `open` — день,
    /// открытый на экране: в него фоном не пишем.
    static func extend(_ s: inout Series, through: Date, vault: Vault, open: Date?) {
        guard let anchor = Vault.date(from: s.anchor),
              let until = Vault.date(from: s.until) else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var missed = (s.missed ?? []).compactMap(Vault.date(from:)).filter { $0 > today }
        missed += dates(s.kind, anchor: anchor, after: until, through: through)
        var still: [String] = []
        for day in missed {
            if let open, cal.isDate(open, inSameDayAs: day) {
                still.append(Vault.stamp(day))
                continue
            }
            if !put(s, on: day, vault: vault) { still.append(Vault.stamp(day)) }
        }
        if through > until { s.until = Vault.stamp(through) }
        s.missed = still.isEmpty ? nil : Array(Set(still)).sorted()
    }

    /// Дописать все серии на год вперёд — при каждом возвращении в
    /// приложение. Обычно писать нечего: год вперёд уже вписан.
    static func extendAll(vault: Vault, open: Date?) {
        var list = load(vault)
        guard !list.isEmpty else { return }
        let today = Calendar.current.startOfDay(for: Date())
        let before = list
        for k in list.indices {
            let horizonDay = Calendar.current.date(byAdding: .day, value: horizon(for: list[k].kind),
                                                   to: today) ?? Date()
            extend(&list[k], through: horizonDay, vault: vault, open: open)
        }
        if list != before { save(list, vault) }
    }

    /// Дни серии после `date`, уже вписанные в файлы.
    static func written(_ s: Series, after date: Date) -> [Date] {
        guard let anchor = Vault.date(from: s.anchor),
              let until = Vault.date(from: s.until) else { return [] }
        return dates(s.kind, anchor: anchor, after: date, through: until)
    }
}

/// Учёт привычки (P378): повторяющееся дело — это и есть привычка. Сколько
/// раз подряд оно сделано и сколько из положенных в этом месяце. Считается
/// по файлам дней — сверх них ничего не хранится.
struct HabitStats: Equatable {
    var streak = 0
    var monthDone = 0
    var monthAll = 0
    /// Последние повторы, от давних к свежим: сделано или нет — для ряда
    /// кружков.
    var recent: [Bool] = []

    /// `days` — день → сделано ли дело серии в этот день (дни, где его нет,
    /// не передаются). Сегодня, если ещё не сделано, серию не обрывает.
    static func count(_ days: [Date: Bool], today: Date) -> HabitStats {
        let cal = Calendar.current
        let now = cal.startOfDay(for: today)
        let past = days.filter { $0.key <= now }.sorted { $0.key > $1.key }
        var out = HabitStats()
        for (k, (day, done)) in past.enumerated() {
            if done {
                out.streak += 1
            } else if k == 0 && day == now {
                continue
            } else {
                break
            }
        }
        let month = cal.dateComponents([.year, .month], from: now)
        for (day, done) in past where cal.dateComponents([.year, .month], from: day) == month {
            out.monthAll += 1
            if done { out.monthDone += 1 }
        }
        out.recent = Array(past.prefix(14).reversed().map(\.value))
        return out
    }
}
