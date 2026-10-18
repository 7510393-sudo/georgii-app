import Foundation
import CoreLocation

/// Один день: файл плана и файл дневника.
///
/// Держит ровно то, что сейчас на экране, и ничего сверх того. Уходя со дня,
/// пишет на диск; приходя на день — читает с диска. Никакой своей копии данных.
final class DayStore: ObservableObject {

    /// День в прошлом: план такого дня выцветает целиком (решение P16),
    /// а дневник остаётся контрастным в любом возрасте.
    var isPast: Bool { date < DayStore.today() }

    /// День ещё не наступил.
    var isFuture: Bool { date > DayStore.today() }
    var isToday: Bool { date == DayStore.today() }

    /// План правится в любой день — и в прошедший тоже, теми же жестами,
    /// что сегодняшний (P381: «Править этот день» убрано). Нельзя только,
    /// пока файл плана не скачан из iCloud.
    /// Месяц прошёл без покупки — писать новое нельзя, читать можно всегда
    /// (M14, P432).
    var canEditPlan: Bool { !away.contains(.planner) && Purchase.canWrite }

    /// Дневник живёт назад: вчерашнее дописывают и через неделю (решение P63).
    /// А вот дня, который ещё не наступил, в дневнике не бывает.
    var canEditDiary: Bool { !isFuture && !away.contains(.diary) && Purchase.canWrite }

    /// Файлы дня, которые лежат, но не прочитались — чаще всего ещё не
    /// скачаны из iCloud. Писать в такой день нельзя: пустая страница на
    /// экране не значит пустой файл на диске (решение P182).
    @Published private(set) var away: Set<Vault.Folder> = []

    /// Запись изменили в другом месте, пока она была открыта здесь, и правки
    /// оказались с обеих сторон. Своя правка положена рядом; человеку надо
    /// сказать, где она (решение P183).
    @Published var conflict: String?

    /// «Править этот день» — открывает прошедший день плана для правки.
    /// Включается вручную в меню страницы и гаснет при уходе со дня — чтобы
    /// нельзя было забыть его включённым.
    ///
    /// Прежде это был режим изменений для любого дня и обеих вкладок
    /// (P211). Теперь перенос, порядок, удаление и отметка «сделано» —
    /// долгим нажатием, без всякого режима (P362), и режим остался только
    /// там, где он и правда что-то открывает: в прошедшем плане.
    @Published var editingTabs: Set<Shell.Tab> = []

    func editing(_ tab: Shell.Tab) -> Bool { editingTabs.contains(tab) }

    func setEditing(_ tab: Shell.Tab, _ on: Bool) {
        if on, tab == .plan, isPast { editingTabs.insert(tab) } else if !on { editingTabs.remove(tab) }
    }

    /// Почему в этот день писать нельзя.
    var closedReason: String {
        if !away.isEmpty {
            return T("Запись ещё загружается из iCloud. Как только придёт — её можно будет править.",
                     "This entry is still downloading from iCloud. You can edit it once it arrives.")
        }
        return T("Этот день ещё не наступил.", "This day has not come yet.")
    }

    /// Заголовок дня: ближние дни зовутся по имени, дальние — днём недели.
    var title: String {
        let n = Calendar.current.dateComponents([.day], from: DayStore.today(), to: date).day ?? 0
        switch n {
        case -2: return T("Позавчера", "Two days ago")
        case -1: return T("Вчера", "Yesterday")
        case  0: return T("Сегодня", "Today")
        case  1: return T("Завтра", "Tomorrow")
        case  2: return T("Послезавтра", "In two days")
        default: return Ru.weekday(date).capitalized
        }
    }

    /// Граница суток: до этого часа день считается вчерашним (решение P17).
    static var boundaryHour = 0

    /// Через столько без правки дневник ставит новую отметку времени.
    static let stampGap: TimeInterval = 60 * 60

    @Published var date: Date {
        // Полоска над клавиатурой — в цвет открытого дня (P297).
        didSet { KeyboardBar.day.date = date }
    }
    @Published var planRows: [PlanRow] = [] {
        didSet { notePlanChange(from: oldValue) }
    }

    // MARK: Шаг назад и вперёд в плане (P261)

    /// Прежние состояния плана — для «шага назад», и отменённые — для
    /// «шага вперёд». Только открытый день и пока он открыт.
    @Published private(set) var planBack: [[PlanRow]] = []
    @Published private(set) var planAhead: [[PlanRow]] = []
    /// Чтение с диска и сами шаги в историю не пишутся.
    private var quietPlan = false
    private var planTouched = Date.distantPast

    /// Правка плана — в историю. Буквы, набранные без остановки, — один
    /// шаг, а не по шагу на букву.
    private func notePlanChange(from old: [PlanRow]) {
        guard !quietPlan, old != planRows else { return }
        let now = Date()
        if now.timeIntervalSince(planTouched) > 1.2 {
            planBack.append(old)
            if planBack.count > 60 { planBack.removeFirst() }
            stepped(.plan)
        }
        planTouched = now
    }

    // MARK: Шаг назад и вперёд по всей странице (P408)

    /// План и дневник — одна страница: стрелка шага отменяет последнюю
    /// правку, где бы она ни была. Какая сторона правилась в каком
    /// порядке — здесь; сами прежние состояния — в своих стопках.
    private var backOrder: [Shell.Tab] = []
    private var aheadOrder: [Shell.Tab] = []

    /// Новая правка: шаги вперёд больше некуда делать — ни в плане, ни в
    /// дневнике.
    private func stepped(_ tab: Shell.Tab) {
        backOrder.append(tab)
        if backOrder.count > 120 { backOrder.removeFirst() }
        planAhead = []
        diaryAhead = []
        aheadOrder = []
    }

    var canUndo: Bool {
        (!planBack.isEmpty && canEditPlan) || (!diaryBack.isEmpty && canEditDiary)
    }
    var canRedo: Bool {
        (!planAhead.isEmpty && canEditPlan) || (!diaryAhead.isEmpty && canEditDiary)
    }

    /// Шаг назад — там, где правили последним.
    func undo() {
        while let tab = backOrder.popLast() {
            if tab == .plan, !planBack.isEmpty { undoPlan(); aheadOrder.append(.plan); return }
            if tab == .diary, !diaryBack.isEmpty { undoDiary(); aheadOrder.append(.diary); return }
        }
        // Порядок потерян (стопки обрезались) — что осталось.
        if !diaryBack.isEmpty { undoDiary(); aheadOrder.append(.diary) }
        else if !planBack.isEmpty { undoPlan(); aheadOrder.append(.plan) }
    }

    /// Шаг вперёд — то, что отменили последним.
    func redo() {
        while let tab = aheadOrder.popLast() {
            if tab == .plan, !planAhead.isEmpty { redoPlan(); backOrder.append(.plan); return }
            if tab == .diary, !diaryAhead.isEmpty { redoDiary(); backOrder.append(.diary); return }
        }
        if !diaryAhead.isEmpty { redoDiary(); backOrder.append(.diary) }
        else if !planAhead.isEmpty { redoPlan(); backOrder.append(.plan) }
    }

    func undoPlan() {
        guard canEditPlan, let back = planBack.popLast() else { return }
        quietPlan = true
        planAhead.append(planRows)
        planRows = back
        quietPlan = false
        planTouched = .distantPast
        save()
    }

    func redoPlan() {
        guard canEditPlan, let ahead = planAhead.popLast() else { return }
        quietPlan = true
        planBack.append(planRows)
        planRows = ahead
        quietPlan = false
        planTouched = .distantPast
        save()
    }

    @Published var diaryTitle: String = ""
    @Published var diaryText: String = "" {
        didSet { noteDiaryChange(from: DiarySnap(text: oldValue, answers: answers)) }
    }

    // MARK: Шаг назад и вперёд в дневнике (P312)

    /// То же самое, что шаг назад и вперёд в плане (P261), но для текста
    /// записи. Только открытый день и пока он открыт.
    /// Запись и ответы «Как прошло?» — одна тетрадь, один шаг (P439).
    struct DiarySnap: Equatable {
        var text: String
        var answers: [String: String]
    }
    @Published private(set) var diaryBack: [DiarySnap] = []
    @Published private(set) var diaryAhead: [DiarySnap] = []
    private var quietDiary = false
    private var diaryTouched = Date.distantPast

    /// Правка записи — в историю. Буквы, набранные без остановки, — один
    /// шаг, а не по шагу на букву.
    private func noteDiaryChange(from old: DiarySnap) {
        guard !quietDiary, old != DiarySnap(text: diaryText, answers: answers) else { return }
        let now = Date()
        if now.timeIntervalSince(diaryTouched) > 1.2 {
            diaryBack.append(old)
            if diaryBack.count > 60 { diaryBack.removeFirst() }
            stepped(.diary)
        }
        diaryTouched = now
    }

    func undoDiary() {
        guard canEditDiary, let back = diaryBack.popLast() else { return }
        quietDiary = true
        diaryAhead.append(DiarySnap(text: diaryText, answers: answers))
        keepAttachments(from: diaryText, to: back.text)
        diaryText = back.text
        answers = back.answers
        quietDiary = false
        diaryTouched = .distantPast
        save()
    }

    /// Шаг назад или вперёд убирает из текста снимок, голос или файл —
    /// они возвращаются в полоску, а не пропадают со страницы (P380):
    /// бросок из полоски в текст и его отмена — одна пара шагов.
    private func keepAttachments(from old: String, to new: String) {
        let gone = DayStore.attachmentLinks(in: old).filter {
            !DayStore.attachmentLinks(in: new).contains($0) && !photos.contains($0)
        }
        photos.append(contentsOf: gone)
    }

    /// Все вложения записи: своей строкой, рядом и посреди фразы.
    static func attachmentLinks(in text: String) -> [String] {
        var out: [String] = []
        for line in text.components(separatedBy: "\n") {
            for link in Diary.links(in: line) + Diary.anywhere(in: line).map(\.link) where !out.contains(link) {
                out.append(link)
            }
        }
        return out
    }

    func redoDiary() {
        guard canEditDiary, let ahead = diaryAhead.popLast() else { return }
        quietDiary = true
        diaryBack.append(DiarySnap(text: diaryText, answers: answers))
        keepAttachments(from: diaryText, to: ahead.text)
        diaryText = ahead.text
        answers = ahead.answers
        quietDiary = false
        diaryTouched = .distantPast
        save()
    }

    @Published var answers: [String: String] = [:] {
        didSet { noteDiaryChange(from: DiarySnap(text: diaryText, answers: oldValue)) }
    }
    /// Ссылки на фотографии дня, как они записаны в файле (P200).
    @Published var photos: [String] = []
    /// Фотографии плана — свои, отдельно от дневника (P203).
    @Published var planPhotos: [String] = []
    /// Где человек был в этот день — «широта, долгота» в шапке дневника
    /// (A9, P207). Ставится только его рукой, кнопкой на карте.
    @Published var place: String?
    /// Погода, когда отмечено место: «+12°, туман» (P208).
    @Published var weather: String?

    /// Когда дневник правили в последний раз. Лежит в шапке файла, чтобы
    /// отметка времени вела себя одинаково и после перезапуска приложения.
    private var lastEdit: Date?

    private let vault: Vault

    init(vault: Vault, date: Date = DayStore.today()) {
        self.vault = vault
        self.date = date
        load()
    }

    static func today(_ now: Date = Date()) -> Date {
        let cal = Calendar.current
        let shifted = cal.component(.hour, from: now) < boundaryHour
            ? cal.date(byAdding: .day, value: -1, to: now) ?? now
            : now
        return cal.startOfDay(for: shifted)
    }

    // MARK: - Дела

    /// Дела дня — без строк, которые приложение не разбирало.
    var tasks: [PlanRow] { planRows.filter { $0.isTask } }
    var doneCount: Int { tasks.filter { $0.done }.count }

    func index(of id: UUID) -> Int? { planRows.firstIndex { $0.id == id } }

    func addTask() -> UUID? {
        guard canEditPlan else { return nil }
        let row = PlanRow.task("")
        planRows.append(row)
        return row.id
    }

    // MARK: - События Календаря (P376)

    /// Записать отметку события: сделано или убрано из плана этого дня.
    /// Строка с тем же ключом заменяется, иначе добавляется в конец.
    func setMark(_ mark: DayEvents.Mark) {
        guard canEditPlan else { return }
        if let i = planRows.firstIndex(where: { $0.verbatim.flatMap(DayEvents.Mark.parse)?.key == mark.key }) {
            planRows[i].verbatim = mark.line
        } else {
            planRows.append(.verbatim(mark.line))
        }
        save()
    }

    /// Событие Календаря становится своим делом — на место `index` среди
    /// дел (в конец, если дальше дел нет).
    func insertTask(_ row: PlanRow, beforeTask index: Int) {
        guard canEditPlan else { return }
        let list = tasks
        if index < list.count, let at = self.index(of: list[index].id) {
            planRows.insert(row, at: at)
        } else if let last = list.last, var at = self.index(of: last.id) {
            // После последнего дела и строк под ним (снимки, точки).
            at += 1
            while at < planRows.count, let line = planRows[at].verbatim,
                  Diary.picture(in: line) != nil || Geo.point(in: line) != nil || Plan.isPhotoRow(line) {
                at += 1
            }
            planRows.insert(row, at: at)
        } else {
            planRows.insert(row, at: 0)
        }
        save()
    }

    /// Перенести дело в план другого дня (P383) — вместе со снимками и
    /// точками под ним. Сперва дело вписывается в файл того дня, и только
    /// когда запись удалась, уходит отсюда: при сбое дело остаётся на
    /// месте, а не пропадает. Перенос трогает два файла, поэтому «шаг
    /// назад» после него начинается заново: иначе он вернул бы дело сюда,
    /// не убрав его оттуда, — и дело стало бы двумя.
    func moveTask(_ id: UUID, to day: Date) -> Bool {
        guard canEditPlan, let i = index(of: id), planRows[i].isTask,
              !Calendar.current.isDate(day, inSameDayAs: date) else { return false }
        var end = i + 1
        while end < planRows.count, let line = planRows[end].verbatim,
              Diary.picture(in: line) != nil || Geo.point(in: line) != nil || Plan.isPhotoRow(line) {
            end += 1
        }
        var block = Array(planRows[i..<end])
        // В другой день дело уходит само по себе, без серии: повтор
        // остаётся в своих днях.
        block[0].repeats = nil
        guard Repeats.add(block, on: day, vault: vault) else { return false }
        quietPlan = true
        planRows.removeSubrange(i..<end)
        quietPlan = false
        planBack = []
        planAhead = []
        save()
        return true
    }

    func delete(_ id: UUID) {
        guard canEditPlan, let i = index(of: id) else { return }
        // Дело из серии — спросить: только этот день или и следующие (P359).
        if planRows[i].repeats != nil {
            seriesAsk = SeriesAsk(row: id, delete: true)
            return
        }
        planRows.remove(at: i)
        save()
    }

    // MARK: - Повторяющиеся дела (P359)

    /// Вопрос «только этот день или этот и все следующие».
    struct SeriesAsk: Identifiable {
        let id = UUID()
        let row: UUID
        let delete: Bool
    }
    @Published var seriesAsk: SeriesAsk?

    /// Каким дело серии было, когда день читали или когда о нём спросили в
    /// последний раз: по нему видно, что его поправили.
    private var seriesSeen: [UUID: PlanRow] = [:]

    private func noteSeries() {
        seriesSeen = Dictionary(uniqueKeysWithValues:
            planRows.filter { $0.repeats != nil }.map { ($0.id, $0) })
    }

    /// Дальний край: на год вперёд от сегодня или от открытого дня, что
    /// позже.
    private func seriesHorizon(_ every: Repeat.Every) -> Date {
        let cal = Calendar.current
        let base = max(cal.startOfDay(for: Date()), date)
        return cal.date(byAdding: .day, value: Repeats.horizon(for: every), to: base) ?? base
    }

    /// Поставить делу повтор: оно само встанет в файлы будущих дней на год
    /// вперёд. Возвращает, во сколько дней вписано.
    @discardableResult
    func startSeries(_ id: UUID, every: Repeat.Every) -> Int {
        guard canEditPlan, let was = index(of: id) else { return 0 }
        if planRows[was].repeats != nil { stopSeries(id) }
        guard let i = index(of: id) else { return 0 }
        let row = planRows[i]
        let series = Repeats.newID()
        planRows[i].repeats = Repeat(every: every, series: series)
        save()
        var s = Series(id: series, every: every.rawValue, anchor: Vault.stamp(date),
                       until: Vault.stamp(date), time: row.time, bell: row.bell,
                       text: row.text, missed: nil)
        Repeats.extend(&s, through: seriesHorizon(every), vault: vault, open: date)
        // Список не прочитался — не пишем поверх (P427): дела в файлах дней
        // уже стоят, без списка их только не будут дописывать дальше.
        if let list = Repeats.list(vault) { Repeats.save(list + [s], vault) }
        noteSeries()
        syncUpcomingReminders()
        return Repeats.written(s, after: date).count - (s.missed?.count ?? 0)
    }

    /// Перестать повторять: будущие повторы уходят из файлов, этот день
    /// остаётся обычным делом.
    func stopSeries(_ id: UUID) {
        guard canEditPlan, let i = index(of: id), let r = planRows[i].repeats else { return }
        dropFuture(r.series)
        planRows[i].repeats = nil
        save()
        noteSeries()
        syncUpcomingReminders()
    }

    /// Убрать будущие повторы серии и саму серию.
    private func dropFuture(_ series: String) {
        let list = Repeats.list(vault)
        // Дни берутся и из списка серий, и из самих файлов: списка могло не
        // оказаться (не перенесли с архивом, ещё в iCloud) — тогда прежде
        // удалялся только этот день (P427).
        var days = Set(Repeats.scan(series, after: date, vault: vault))
        if let s = list?.first(where: { $0.id == series }) {
            days.formUnion(Repeats.written(s, after: date))
        }
        for day in days.sorted() {
            _ = Repeats.edit(series, on: day, vault: vault) { rows, k in _ = rows.remove(at: k) }
        }
        if var list, list.contains(where: { $0.id == series }) {
            list.removeAll { $0.id == series }
            Repeats.save(list, vault)
        }
    }

    /// Дело серии поправили — название, время, напоминание. Спросить,
    /// только ли здесь (P359).
    func checkSeries(_ id: UUID) {
        guard let i = index(of: id), planRows[i].repeats != nil,
              let seen = seriesSeen[id] else { return }
        let now = planRows[i]
        guard now.text != seen.text || now.time != seen.time || now.bell != seen.bell else { return }
        seriesAsk = SeriesAsk(row: id, delete: false)
    }

    /// Ответ на вопрос: `all` — этот день и все следующие. Вопрос
    /// передаётся сам: окно вопроса могло уже закрыться и забыть его.
    func answerSeries(_ ask: SeriesAsk, all: Bool) {
        seriesAsk = nil
        guard canEditPlan, let i = index(of: ask.row), let r = planRows[i].repeats else { return }
        if ask.delete {
            planRows.remove(at: i)
            save()
            if all { dropFuture(r.series) }
        } else if all {
            let row = planRows[i]
            var list = Repeats.list(vault)
            let k = list?.firstIndex(where: { $0.id == r.series })
            var days = Set(Repeats.scan(r.series, after: date, vault: vault))
            if let list, let k { days.formUnion(Repeats.written(list[k], after: date)) }
            for day in days.sorted() {
                _ = Repeats.edit(r.series, on: day, vault: vault) { rows, j in
                    rows[j].text = row.text
                    rows[j].time = row.time
                    rows[j].bell = row.bell
                }
            }
            if let k, list != nil {
                list![k].text = row.text
                list![k].time = row.time
                list![k].bell = row.bell
                Repeats.save(list!, vault)
            }
        }
        noteSeries()
        syncUpcomingReminders()
    }

    /// Переставить дело выше или ниже соседнего дела.
    func move(_ id: UUID, by step: Int) {
        guard canEditPlan, let i = index(of: id) else { return }
        var j = i + step
        while j >= 0 && j < planRows.count && !planRows[j].isTask { j += step }
        guard j >= 0, j < planRows.count else { return }
        planRows.swapAt(i, j)
        save()
    }

    /// Переставить строку-точку или снимок между делами — на столько
    /// видимых строк, на сколько её протащили (P226). Невидимые строки
    /// файла остаются, где были.
    /// Строки плана, которые видно на странице и между которыми ходят
    /// точки и снимки: дела, снимки и точки — по порядку.
    var shownRowIDs: [UUID] { shownIndices.map { planRows[$0].id } }

    private var shownIndices: [Int] {
        planRows.indices.filter { k in
            planRows[k].isTask || planRows[k].verbatim.map {
                Diary.picture(in: $0) != nil || Geo.point(in: $0) != nil
            } ?? false
        }
    }

    func moveLine(_ id: UUID, by steps: Int) {
        guard canEditPlan, steps != 0, let i = index(of: id) else { return }
        let shown = shownIndices
        guard let p = shown.firstIndex(of: i) else { return }
        let q = min(max(p + steps, 0), shown.count - 1)
        guard q != p else { return }
        let row = planRows.remove(at: i)
        var target = shown[q]
        if target > i { target -= 1 }
        planRows.insert(row, at: steps > 0 ? target + 1 : target)
        save()
    }

    /// День словами — чтобы поделиться им в сообщении или письме (P249).
    /// Строки-вложения не передаются: это пути в папке, другому человеку
    /// они ничего не скажут; точки — словами и координатами.
    func shareText() -> String {
        var out = Ru.weekday(date).capitalized + ", " + Ru.longDate(date)
        let plan = tasks.filter { !$0.text.isEmpty }
        if !plan.isEmpty {
            out += T("\n\nПлан:\n", "\n\nPlan:\n") + plan.map { row in
                (row.done ? "✓ " : "• ") + (row.time.map { $0 + " " } ?? "") + row.text
            }.joined(separator: "\n")
        }
        let lines = diaryText.components(separatedBy: "\n").compactMap { line -> String? in
            if !Diary.links(in: line).isEmpty { return nil }
            if let point = Geo.point(in: line) { return "📍 " + point.label }
            return line
        }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !diaryTitle.isEmpty || !text.isEmpty {
            out += T("\n\nДневник", "\n\nDiary")
            if !diaryTitle.isEmpty { out += " — " + diaryTitle }
            out += ":\n" + text
        }
        return out
    }

    // MARK: - Дни

    func go(to newDate: Date) {
        prune()
        save()
        editingTabs = []
        weatherAsked = false
        planBack = []
        planAhead = []
        diaryBack = []
        diaryAhead = []
        backOrder = []
        aheadOrder = []
        diaryCaret = nil
        lastPlanRow = nil
        caretRequest = nil
        leftCaret = nil
        leftRow = nil
        date = Calendar.current.startOfDay(for: newDate)
        retries = 0
        load()
    }

    func move(by days: Int) {
        go(to: Calendar.current.date(byAdding: .day, value: days, to: date) ?? date)
    }

    /// Пустые дела убираются только при уходе со дня: иначе новое дело
    /// исчезает, едва человек коснулся другого места на экране.
    func prune() {
        // Дело с одним временем или напоминанием — уже дело (P406).
        // Только если есть что убирать (P491): `removeAll` даже вхолостую
        // сообщал экрану об изменении — на каждом касании внизу всё
        // перерисовывалось до смены раздела.
        if planRows.contains(where: PlanRow.blank) { planRows.removeAll(where: PlanRow.blank) }
    }

    // MARK: - Отметка времени в дневнике

    /// Нужна ли новая отметка времени перед тем, как человек начнёт писать.
    ///
    /// Нужна, если запись пуста или к ней не возвращались больше часа. Смысл
    /// отметок — показать, что день писался в несколько заходов, а не залпом.
    ///
    /// Возвращает `true`, если отметка поставлена: тогда курсор надо
    /// перенести за неё — писать человек будет там (решение P137).
    @discardableResult
    func stampIfNeeded() -> Bool {
        guard canEditDiary else { return false }
        let body = diaryText.replacingOccurrences(of: "\\s+$", with: "",
                                                  options: .regularExpression)
        let stale = lastEdit.map { Date().timeIntervalSince($0) > DayStore.stampGap } ?? true
        guard body.isEmpty || stale else { return false }

        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        // Дописывая прошедший день, человек пишет не в тот день, о котором
        // запись: за временем встаёт и дата, когда писал (P227, P232).
        f.dateFormat = isToday ? "HH:mm" : "HH:mm dd.MM.yy"
        diaryText = (body.isEmpty ? "" : body + "\n\n") + f.string(from: Date()) + " "
        lastEdit = Date()
        save()
        return true
    }

    /// Прежде здесь отмечалась любая правка дневника — даже снимок или
    /// открытие страницы. Теперь час до новой отметки времени считается
    /// только от того, как человек писал текст в конце записи (P519,
    /// `noteWriting`); правка плана, ответов «Как прошло?» и прежних
    /// строк в счёт не идёт. Вызовы оставлены, но ничего не делают.
    func touchDiary() {}

    /// Человек набрал текст в конце записи.
    func noteWriting() { lastEdit = Date() }

    // MARK: - Открыл — пишешь (P403)

    /// Отметка времени ждёт первой буквы новой строки. Сбрасывается, когда
    /// открывают другой день.
    private(set) var stampPending = false

    /// Курсор — в начало новой пустой строки под записью; отметки времени
    /// там ещё нет — она встанет с первой буквой (P403; прежде ставилась
    /// сразу, как только курсор попадал в запись, P137). Пора новой
    /// отметки (запись пуста или с правки прошёл час) — под записью пустая
    /// строка и новая; иначе, если `always` (приложение открыли на
    /// дневнике), — просто новая строка. `true` — курсор надо перенести в
    /// конец.
    func openNewLine(always: Bool) -> Bool {
        guard canEditDiary else { return false }
        let body = diaryText.replacingOccurrences(of: "\\s+$", with: "",
                                                  options: .regularExpression)
        let stale = lastEdit.map { Date().timeIntervalSince($0) > DayStore.stampGap } ?? true
        if body.isEmpty || stale || stampPending {
            let wanted = body.isEmpty ? "" : body + "\n\n"
            let changed = diaryText != wanted
            if changed { quietly(wanted) }
            stampPending = true
            return changed || always
        }
        guard always else { return false }
        let wanted = body + "\n"
        if diaryText != wanted { quietly(wanted) }
        return true
    }

    /// Пустая строка под записью — не правка человека: в историю «шага
    /// назад» она не идёт, и стрелка не загорается сама (P403).
    private func quietly(_ text: String) {
        quietDiary = true
        diaryText = text
        quietDiary = false
    }

    /// Отметка времени для первой буквы новой строки — один раз (P403).
    func takeStamp() -> String? {
        guard canEditDiary else { return nil }
        // Курсор мог встать в конец записи без «открытия» (клавиатура уже
        // была поднята, когда перешли на другой день) — тогда `stampPending`
        // не взведён; отметку решает и сам час с последнего набора (P520).
        let stale = lastEdit.map { Date().timeIntervalSince($0) > DayStore.stampGap } ?? true
        guard stampPending || stale else { return nil }
        stampPending = false
        lastEdit = Date()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        // Дописывая прошедший день — с датой, когда писал (P227, P232).
        f.dateFormat = isToday ? "HH:mm" : "HH:mm dd.MM.yy"
        return f.string(from: Date()) + " "
    }

    /// Строка «Здоровья» — касанием, в конец записи (P378).
    func addHealthLine(_ line: String) {
        guard canEditDiary else { return }
        let body = diaryText.trimmingCharacters(in: .whitespacesAndNewlines)
        diaryText = (body.isEmpty ? "" : body + "\n\n") + "♥ " + line
        touchDiary()
        save()
    }

    /// Расшифровка голоса (P378): под строкой записи, если она в тексте;
    /// иначе — новым абзацем в конце записи.
    func addTranscript(_ text: String, after link: String) {
        guard canEditDiary else { return }
        let line = Diary.line(link)
        var lines = diaryText.components(separatedBy: "\n")
        if let i = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == line }) {
            lines.insert(text, at: i + 1)
            diaryText = lines.joined(separator: "\n")
        } else {
            let body = diaryText.trimmingCharacters(in: .whitespacesAndNewlines)
            diaryText = (body.isEmpty ? "" : body + "\n\n") + text
        }
        touchDiary()
        save()
    }

    /// Положить фотографию в папку и сослаться на неё из файла дня — плана
    /// или дневника, смотря на какой вкладке её положили.
    ///
    /// Правила те же, что у правки вкладки: в закрытый день, в будущий
    /// дневник и в день, который ещё не скачан из iCloud, её не положить
    /// (P182, P200, P203).
    @discardableResult
    func addPhoto(_ data: Data, to tab: Shell.Tab, camera: Bool = false) -> Bool {
        guard canEdit(tab), let link = vault.addPhoto(data, for: date) else { return false }
        if camera { CameraShots.mark(link) }
        attach(link, to: tab)
        Hints.shared.photoAdded()
        return true
    }

    /// Положить голос или документ в его папку и сослаться на него из файла
    /// дня — там же, где лежат фотографии (P209).
    @discardableResult
    func addAttachment(_ data: Data, to kind: Vault.Folder, name: String,
                       tab: Shell.Tab) -> Bool {
        guard canEdit(tab),
              let link = vault.addAttachment(data, to: kind, name: name, for: date)
        else { return false }
        attach(link, to: tab)
        return true
    }

    private func attach(_ link: String, to tab: Shell.Tab) {
        switch tab {
        case .diary:
            photos.append(link)
            touchDiary()
        case .plan:
            planPhotos.append(link)
        }
        save()
    }

    /// Убрать фотографию из файла дня. Сам снимок остаётся в папке:
    /// удалять файлы человека приложение не берётся — это делают в «Файлах».
    func removePhoto(at index: Int, from tab: Shell.Tab) {
        guard canEdit(tab) else { return }
        switch tab {
        case .diary:
            guard photos.indices.contains(index) else { return }
            photos.remove(at: index)
            touchDiary()
        case .plan:
            guard planPhotos.indices.contains(index) else { return }
            planPhotos.remove(at: index)
        }
        save()
    }

    /// Убрать вложение со страницы и, если просят, удалить сам файл — в
    /// корзину на 30 дней (P371). Возвращает, что сказать человеку.
    func removeAttachment(at index: Int, from tab: Shell.Tab, delete: Bool) -> String {
        let links = self.links(tab)
        guard canEdit(tab), links.indices.contains(index) else { return closedReason }
        let link = links[index]
        removePhoto(at: index, from: tab)
        guard delete else {
            return T("Убрано со страницы. Сам файл остался в папке.", "Removed from the page. The file stays in the folder.")
        }
        switch FileTrash.put(link, from: date, tab: tab == .plan ? "plan" : "diary", vault: vault) {
        case .trashed:
            return T("Файл в корзине на 30 дней. Вернуть — Настройки → Корзина.",
                     "The file is in the trash for 30 days. Restore it in Settings → Trash.")
        case .stillUsed(let day):
            return T("Убрано со страницы. Файл нужен ещё в записи за \(day) — он остался в папке.",
                     "Removed from the page. The file is still used on \(day), so it stays in the folder.")
        case .failed:
            return T("Убрано со страницы. Файл удалить не вышло — он остался в папке.",
                     "Removed from the page. The file could not be deleted — it stays in the folder.")
        }
    }

    /// Снимок, брошенный из полоски в текст, уходит из полоски: он теперь
    /// стоит на своём месте в записи, и дважды его показывать незачем (P204).
    func settlePhotos() {
        // И в ответах «Как прошло?»: снимок встал в строку ответа (P407).
        let said = answers.values.filter { $0.contains("](") }
        guard !photos.isEmpty, diaryText.contains("](") || !said.isEmpty else { return }
        let placed = photos.filter { link in
            diaryText.contains(Diary.line(link)) || said.contains { $0.contains(Diary.line(link)) }
        }
        guard !placed.isEmpty else { return }
        photos.removeAll { placed.contains($0) }
    }

    /// Снимок из прежней полоски плана встал в запись или в ответ — из
    /// полоски он уходит: полоска одна на страницу (P408).
    func dropFromPlanStrip(_ link: String) {
        guard canEditPlan, let k = planPhotos.firstIndex(of: link) else { return }
        planPhotos.remove(at: k)
        save()
    }

    /// Отметить, где человек был в этот день. Место — часть дневника:
    /// в будущий день его не поставить (A9, P207).
    @discardableResult
    func mark(_ where_: CLLocationCoordinate2D) -> Bool {
        guard canEditDiary else { return false }
        place = Geo.text(where_)
        touchDiary()
        save()
        return true
    }

    /// Где стоял курсор в записи дневника — отступом от начала текста.
    /// Туда встаёт точка с карты (P213). Пусто — курсора не было, и точка
    /// ложится в конец записи.
    var diaryCaret: Int?

    /// Пишет ли человек сейчас в дневник и в какое дело плана. Нужно, чтобы
    /// точка встала туда, где был курсор (P240).
    var diaryTyping = false
    /// В каком деле «Как прошло?» сейчас пишут (P407): «место» встаёт в
    /// конец этого ответа, в ту же строку.
    var answerTyping: String?
    var planTyping: UUID? {
        didSet { if let planTyping { lastPlanRow = planTyping } }
    }

    /// Дело плана, в котором курсор стоял последним, — даже если
    /// клавиатуру уже убрали. Туда геоточка кладёт место (P253).
    private(set) var lastPlanRow: UUID?

    /// Просьба полю дневника поставить курсор за вписанной точкой (P253).
    @Published var caretRequest: Int?

    /// Где был курсор, когда ушли на карту: место в дневнике и дело в плане.
    /// Пусто — курсора не было (P240).
    private(set) var leftCaret: Int?
    private(set) var leftRow: UUID?

    /// Запомнить, где был курсор, перед уходом на карту. Уходят не со
    /// страницы дня — курсора нет.
    func noteLeaving(fromToday: Bool) {
        leftCaret = fromToday && diaryTyping ? diaryCaret : nil
        // В плане — дело, в котором стоит курсор: точка ляжет в его строку,
        // на место курсора (P276). Курсора нет — строкой ниже всех (P285).
        leftRow = fromToday ? planTyping : nil
    }

    /// Записать точку с карты — туда, где был курсор перед уходом на карту.
    @discardableResult
    func writeFromMap(_ point: GeoPoint, to tab: Shell.Tab, here: Bool = false) -> Bool {
        writePoint(point, to: tab, here: here, caret: leftCaret, after: leftRow)
    }

    /// Записать точку своей строкой (P165, P213, P240). В дневник — туда,
    /// где стоит курсор, а без курсора — следующей строкой в конце. В план —
    /// после дела, в котором курсор, а без курсора — после последнего дела.
    @discardableResult
    func writePoint(_ point: GeoPoint, to tab: Shell.Tab, here: Bool = false,
                    caret: Int? = nil, after row: UUID? = nil, answer: String? = nil) -> Bool {
        guard canEdit(tab) else { return false }
        if here { notePlace(point) }
        let line = Geo.pointLine(point)
        // Писали в ответ «Как прошло?» — точка в конец этого ответа (P407).
        if tab == .diary, let task = answer {
            answers[task] = Diary.adding(line, to: answers[task] ?? "")
            touchDiary()
            save()
            return true
        }
        switch tab {
        case .plan:
            // Дело, за которым просили, могли уже удалить — тогда под последним.
            let asked = row.flatMap { index(of: $0) == nil ? nil : $0 }
            if let anchor = asked, index(of: anchor) != nil {
                // Курсор стоял в деле — точка своей строкой под ним, между
                // плашками, после снимков и точек, что уже там (P409;
                // прежде — в название дела, P259, P276).
                planRows.insert(.verbatim(line), at: afterBlock(of: anchor))
            } else if asked == nil {
                // Курсора нет — своей строкой ниже последней записи плана;
                // в нужное дело её переносят в режиме изменений (P285).
                var end = planRows.count
                while end > 0, planRows[end - 1].verbatim?.trimmingCharacters(in: .whitespaces) == "" {
                    end -= 1
                }
                planRows.insert(.verbatim(line), at: end)
            } else if let anchor = asked, var i = index(of: anchor) {
                // Точки, уже стоящие за этим делом, остаются перед новой.
                i += 1
                while i < planRows.count, let v = planRows[i].verbatim, Geo.point(in: v) != nil { i += 1 }
                planRows.insert(.verbatim(line), at: i)
            } else {
                planRows.append(.verbatim(line))
            }
        case .diary:
            let (text, at) = DayStore.insert(line, into: diaryText, at: caret)
            diaryText = text
            diaryCaret = at
            if diaryTyping { caretRequest = at }
            touchDiary()
        }
        save()
        return true
    }

    /// Куда встаёт строка под делом: после самого дела и его снимков и
    /// точек — перед следующим делом (P409).
    func afterBlock(of task: UUID) -> Int {
        guard var i = index(of: task) else { return planRows.count }
        i += 1
        while i < planRows.count, !planRows[i].isTask,
              let v = planRows[i].verbatim, !v.trimmingCharacters(in: .whitespaces).isEmpty { i += 1 }
        return i
    }

    /// Снимок в ряду под делом — на другое место в том же ряду (P409).
    /// `slot` — перед каким снимком встать (по ряду до переноса).
    func reorderPlanPhoto(_ link: String, in row: UUID, to slot: Int) {
        guard canEditPlan, let r = index(of: row), let line = planRows[r].verbatim else { return }
        var links = Diary.links(in: line)
        guard let from = links.firstIndex(of: link) else { return }
        let to = min(max(slot > from ? slot - 1 : slot, 0), links.count - 1)
        guard to != from else { return }
        links.remove(at: from)
        links.insert(link, at: to)
        planRows[r].verbatim = links.map(Diary.line).joined(separator: " ")
        save()
    }

    /// Вложение или точка из записи дневника — в план, под дело (P409).
    /// Снимок — в ряд снимков под делом, точка — своей строкой. `false` —
    /// не встало, и в записи оно остаётся.
    @discardableResult
    func textToPlan(_ piece: String, under task: UUID) -> Bool {
        guard canEditPlan, index(of: task) != nil else { return false }
        let line = piece.trimmingCharacters(in: .whitespaces)
        if let link = Diary.picture(in: line), Diary.kind(of: link) == .photo {
            let at = index(of: task)! + 1
            if at < planRows.count, let row = planRows[at].verbatim, Plan.isPhotoRow(row) {
                planRows[at].verbatim = row.trimmingCharacters(in: .whitespaces) + " " + line
            } else {
                planRows.insert(.verbatim(line), at: at)
            }
        } else if Geo.point(in: line) != nil {
            // Голос и файлы план не показывает — они остаются в записи.
            planRows.insert(.verbatim(line), at: afterBlock(of: task))
        } else {
            return false
        }
        save()
        return true
    }

    /// «Места дня» больше нет (P294): новые дни его не записывают. Уже
    /// записанное в файлах строкой «место:» остаётся нетронутым — файл
    /// принадлежит человеку.
    func notePlace(_ point: GeoPoint) {}

    /// Вставить точку в текст там, где стоит курсор, — прямо в строку,
    /// отделив пробелами (P259). Возвращает текст и место курсора за
    /// вставкой.
    static func insert(_ line: String, into text: String, at caret: Int?) -> (String, Int) {
        // Точка, снимок, голос — всегда своей строкой (P380): строку не
        // рвут пополам, точка встаёт следующей строкой за абзацем, где
        // стоит курсор; пустая строка под курсором занимается ею самой.
        let ns = text as NSString
        guard let caret, caret >= 0, caret <= ns.length else {
            let body = text.replacingOccurrences(of: "\\s+$", with: "",
                                                 options: .regularExpression)
            let out = body + (body.isEmpty ? "" : "\n") + line
            return (out, (out as NSString).length)
        }
        let para = ns.paragraphRange(for: NSRange(location: min(caret, ns.length), length: 0))
        var end = para.location + para.length
        if end > para.location, ns.character(at: end - 1) == 10 { end -= 1 }
        let content = ns.substring(with: NSRange(location: para.location, length: end - para.location))
        if content.trimmingCharacters(in: .whitespaces).isEmpty {
            let out = ns.replacingCharacters(in: NSRange(location: para.location,
                                                         length: end - para.location), with: line)
            return (out, para.location + (line as NSString).length)
        }
        let out = ns.replacingCharacters(in: NSRange(location: end, length: 0), with: "\n" + line)
        return (out, end + 1 + (line as NSString).length)
    }

    /// Снимок плана — под дело (P358): в строку снимков сразу под ним, в
    /// ряд с теми, что уже там. Откуда бы его ни взяли — из полоски или
    /// из-под другого дела, — там он больше не стоит.
    func putPlanPhoto(_ link: String, under id: UUID) {
        guard canEditPlan, takeOutPlanPhoto(link), let i = index(of: id) else { return }
        let next = i + 1
        if next < planRows.count, let line = planRows[next].verbatim, Plan.isPhotoRow(line) {
            planRows[next].verbatim = line.trimmingCharacters(in: .whitespaces) + " " + Diary.line(link)
        } else {
            planRows.insert(.verbatim(Diary.line(link)), at: next)
        }
        save()
    }

    /// Точку, стоявшую своей строкой, — в название дела, в конец (P358).
    func putPointIntoTask(_ pointRow: UUID, task: UUID) {
        guard canEditPlan, let r = index(of: pointRow),
              let line = planRows[r].verbatim, Geo.point(in: line) != nil,
              index(of: task) != nil else { return }
        planRows.remove(at: r)
        guard let t = index(of: task) else { return }
        let text = planRows[t].text.trimmingCharacters(in: .whitespaces)
        planRows[t].text = text.isEmpty ? line : text + " " + line
        save()
    }

    /// Снимок из-под дела — назад в полоску плана внизу (P358).
    /// Снимок из полоски внизу страницы — под дело плана (P408): полоска
    /// одна, в неё ложится всё новое, а под дело снимок переносят пальцем.
    func stripPhotoToPlan(_ link: String, under id: UUID) {
        guard canEditPlan, index(of: id) != nil else { return }
        if let k = photos.firstIndex(of: link) {
            guard canEditDiary else { return }
            photos.remove(at: k)
            touchDiary()
            planPhotos.append(link)
        }
        putPlanPhoto(link, under: id)
    }

    /// Всё, что лежит в полоске внизу страницы: снимки дневника, за ними —
    /// прежние снимки полоски плана (P408).
    var stripLinks: [String] { photos + planPhotos }

    func returnPlanPhoto(_ link: String) {
        guard canEditPlan, !planPhotos.contains(link), takeOutPlanPhoto(link) else { return }
        planPhotos.append(link)
        save()
    }

    /// Убрать снимок оттуда, где он стоит в плане. `false` — его там нет.
    private func takeOutPlanPhoto(_ link: String) -> Bool {
        if let k = planPhotos.firstIndex(of: link) {
            planPhotos.remove(at: k)
            return true
        }
        for r in planRows.indices {
            guard let line = planRows[r].verbatim else { continue }
            let links = Diary.links(in: line)
            guard links.contains(link) else { continue }
            let rest = links.filter { $0 != link }
            if rest.isEmpty {
                planRows.remove(at: r)
            } else {
                planRows[r].verbatim = rest.map(Diary.line).joined(separator: " ")
            }
            return true
        }
        return false
    }

    /// Точку из заголовка дня — назад в текст записи, в конец (P358).
    func pointFromTitle(_ line: String) {
        guard canEditDiary, let r = diaryTitle.range(of: line) else { return }
        diaryTitle.removeSubrange(r)
        diaryTitle = diaryTitle.replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
        diaryText = DayStore.insert(line, into: diaryText, at: nil).0
        touchDiary()
        save()
    }

    /// Вернуть снимок, стоящий посреди записи, в полоску внизу (P216).
    func returnToStrip(_ link: String) {
        guard canEditDiary else { return }
        // Из ответа «Как прошло?» — вместе с пробелом перед ним (P407).
        if !diaryText.contains(Diary.line(link)),
           let hit = answers.first(where: { $0.value.contains(Diary.line(link)) }) {
            answers[hit.key] = hit.value.replacingOccurrences(of: " " + Diary.line(link), with: "")
                .replacingOccurrences(of: Diary.line(link), with: "")
                .trimmingCharacters(in: .whitespaces)
            photos.append(link)
            touchDiary()
            save()
            return
        }
        // Снимок ищется где угодно: своей строкой, в ряду (P348) или
        // посреди фразы (P357). Уходит вместе с одним пробелом или переводом
        // строки рядом — остальное остаётся как было.
        let ns = diaryText as NSString
        // Голос и файл стоят своей строкой `[имя](…)` (P377).
        let whole = ns.range(of: Diary.line(link))
        guard var cut = Diary.anywhere(in: diaryText).first(where: { $0.link == link })?.range
            ?? (whole.location == NSNotFound ? nil : whole)
        else { return }
        let before = cut.location > 0 ? ns.character(at: cut.location - 1) : 10
        let after = NSMaxRange(cut) < ns.length ? ns.character(at: NSMaxRange(cut)) : 10
        if before == 10, after == 10 {
            if NSMaxRange(cut) < ns.length {
                cut.length += 1
            } else if cut.location > 0 {
                cut.location -= 1
                cut.length += 1
            }
        } else if after == 32 {
            cut.length += 1
        } else if before == 32 {
            cut.location -= 1
            cut.length += 1
        }
        diaryText = ns.replacingCharacters(in: cut, with: "")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        photos.append(link)
        touchDiary()
        save()
    }

    var placeCoordinate: CLLocationCoordinate2D? { place.flatMap(Geo.parse) }

    /// Записать погоду там, где человек сейчас. Только в сегодняшний день:
    /// погода — это «как было, когда писал», а не справка о прошлом (P208).
    /// Погода сегодняшнего дня — сама, без кнопки (P280). Её раньше
    /// приносила «геоточка»; кнопки нет (P264) — и погода пропала. Место
    /// нужно для погоды: iPhone один раз спросит разрешение; запретили —
    /// погоды нет, и больше не спрашиваем.
    func fetchWeatherIfNeeded() {
        guard Prefs.weatherOn, isToday, canEditDiary, weather == nil, !weatherAsked else { return }
        let status = CLLocationManager().authorizationStatus
        guard status != .denied, status != .restricted else {
            weatherTrouble = T("Приложению не разрешено знать, где вы, — а погода нужна для "
                + "места. Настройки iPhone → Graphomanus → Геопозиция → «При использовании».",
                "The app may not know where you are, and weather needs a place. "
                + "iPhone Settings → Graphomanus → Location → “While Using the App”.")
            return
        }
        weatherAsked = true
        Locator.shared.current { [weak self] location in
            guard let self else { return }
            guard let location else {
                self.weatherTrouble = T("iPhone не сказал, где вы сейчас. Попробую снова, "
                    + "когда вернётесь в приложение.",
                    "The iPhone did not say where you are. I will try again when you come back.")
                self.weatherAsked = false
                return
            }
            self.noteWeather(at: location)
        }
    }
    private var weatherAsked = false

    /// Почему погоды нет — показывается в настройках под строкой «Погода»
    /// (P354). Пусто — всё в порядке или ещё не спрашивали.
    @Published var weatherTrouble: String?

    func noteWeather(at location: CLLocation) {
        guard isToday, canEditDiary else { return }
        let day = date
        Task { [weak self] in
            let got = await WeatherNote.now(at: location)
            await MainActor.run {
                guard let self else { return }
                switch got {
                case .success(let words):
                    self.weatherTrouble = nil
                    guard self.date == day else { return }
                    self.weather = words
                    self.save()
                case .failure(let error):
                    // Не вышло — спросим снова при следующем возвращении в
                    // приложение, а не никогда.
                    self.weatherTrouble = WeatherNote.explain(error)
                    self.weatherAsked = false
                }
            }
        }
    }

    /// Переставить вложение в полоске — перетаскиванием вбок в режиме
    /// изменений (P210).
    func movePhoto(from: Int, to: Int, in tab: Shell.Tab) {
        guard canEdit(tab), from != to else { return }
        switch tab {
        case .diary:
            guard photos.indices.contains(from), photos.indices.contains(to) else { return }
            photos.insert(photos.remove(at: from), at: to)
            touchDiary()
        case .plan:
            guard planPhotos.indices.contains(from), planPhotos.indices.contains(to) else { return }
            planPhotos.insert(planPhotos.remove(at: from), at: to)
        }
        save()
    }

    func links(_ tab: Shell.Tab) -> [String] { tab == .diary ? photos : planPhotos }

    func canEdit(_ tab: Shell.Tab) -> Bool { tab == .diary ? canEditDiary : canEditPlan }

    /// Где лежит фотография дня.
    func photoURL(_ link: String) -> URL? { vault.mediaURL(link, for: date) }

    // MARK: - Диск

    // Что лежало на диске, когда день читали или писали в последний раз, и
    // как приложение тогда же видело этот день. По первому узнаётся чужая
    // правка, по второму — своя (решения P182, P183).
    private var seen: [Vault.Folder: String] = [:]
    private var mine: [Vault.Folder: String] = [:]
    private var retries = 0

    func load() {
        stampPending = false
        let plan = vault.reading(.planner, for: date)
        let diaryFile = vault.reading(.diary, for: date)
        var gone: Set<Vault.Folder> = []
        if plan == .away { gone.insert(.planner) }
        if diaryFile == .away { gone.insert(.diary) }
        away = gone

        quietPlan = true
        (planRows, planPhotos) = Plan.splitPhotos(Plan.rows(from: DayFile(text: plan.text).body))
        quietPlan = false
        noteSeries()

        let file = DayFile(text: diaryFile.text)
        // План читается первым, поэтому названия дел уже известны — по ним
        // ответы «Как прошло?» разбираются без догадок (P155).
        let diary = Diary(body: file.body, known: planRows.map(\.text))
        diaryTitle = file.value("title") ?? ""
        // Загрузка с диска — не правка человека: как и план строкой выше,
        // в историю шага назад/вперёд не попадает (P327). Без этого первое
        // открытие дня (пустая запись до чтения файла) само вставало в
        // историю, и один шаг назад стирал всё написанное.
        quietDiary = true
        diaryText = diary.text
        answers = diary.answers
        quietDiary = false
        photos = diary.photos
        place = file.value("place")
        weather = file.value("weather")
        lastEdit = file.value("edited").flatMap(DayStore.moment(from:))

        seen = [.planner: plan.text, .diary: diaryFile.text]
        mine = [.planner: planFile().text, .diary: diaryFileNow().text]
        if away.isEmpty { retries = 0 } else { waitForCloud() }
    }

    /// Сверить открытый день с диском.
    ///
    /// Зовётся, когда человек возвращается в приложение, и пока запись
    /// докачивается из iCloud. Сначала своё — записать, потом чужое —
    /// перечитать: так своя правка не пропадёт, а чужая не затрётся.
    func refresh() {
        guard vault.root != nil else { return }
        save()
        let stale = [Vault.Folder.planner, .diary].contains { folder in
            let now = vault.reading(folder, for: date)
            if now == .away { return false }
            return away.contains(folder) || now.text != (seen[folder] ?? "")
        }
        if stale { load() } else if !away.isEmpty { waitForCloud() }
    }

    /// Пока файл дня едет из iCloud, заглядывать за ним каждые две секунды.
    private func waitForCloud() {
        guard retries < 60 else { return }
        retries += 1
        let day = date
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.date == day, !self.away.isEmpty else { return }
            self.refresh()
        }
    }

    private var pendingSave: DispatchWorkItem?
    /// Растёт с каждой записью дня на диск: соседние страницы перечитывают
    /// свои дни, чтобы не показывать устаревшее (P439).
    @Published private(set) var savedTick = 0

    /// Запись не на каждую букву: иначе файл в iCloud переписывается
    /// десятки раз в минуту. Полсекунды тишины — и день на диске.
    func scheduleSave() {
        pendingSave?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func save() {
        pendingSave?.cancel()
        pendingSave = nil
        guard vault.root != nil else { return }
        // Оба файла собираются до записи: если один из них изменили в другом
        // месте и день придётся перечитать, правка во втором не должна
        // пропасть вместе с перечитыванием.
        let plan = planFile()
        let diary = diaryFileNow()
        let a = write(plan, to: .planner, keep: false)
        // Заголовок дня — это уже запись, даже если под ним пока нет ни строчки.
        let b = write(diary, to: .diary, keep: !diaryTitle.isEmpty || place != nil || weather != nil)
        if a || b { load() }
        savedTick += 1
        // Напоминания дня — по тому, что теперь в плане (P260). Недокачанный
        // план не трогаем: пустой список снял бы настоящие напоминания.
        if !away.contains(.planner) { Reminders.sync(day: date, rows: planRows) }
        // Дела сегодняшнего дня — виджету (P382).
        if isToday, !away.contains(.planner) { WidgetShare.publish(day: date, rows: planRows) }
        // Сегодня записали — вечернее «запишите день» не придёт (P444).
        if isToday, Reminders.eveningHour >= 0 { Reminders.evening(todayWritten: todayWritten) }
    }

    /// В сегодняшнем дневнике есть хоть что-то: запись или ответ «Как прошло?».
    private var todayWritten: Bool {
        !diaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || answers.values.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Расставить напоминания на две недели вперёд — по файлам: колокольчик
    /// могли поставить на другом устройстве или в редакторе на Mac.
    func syncUpcomingReminders() {
        guard vault.root != nil else { return }
        let cal = Calendar.current
        for k in 0..<14 {
            guard let day = cal.date(byAdding: .day, value: k, to: DayStore.today()) else { continue }
            let reading = vault.reading(.planner, for: day)
            if reading == .away { continue }
            Reminders.sync(day: day, rows: Plan.rows(from: DayFile(text: reading.text).body))
        }
    }

    /// Человек вернулся в приложение: сверить день с диском заново.
    func comeBack() {
        retries = 0
        // Сутки могли смениться, пока приложение стояло в фоне, — тогда
        // открытый день уже не сегодняшний. Возвращаемся на настоящее
        // сегодня, а не остаёмся на вчерашней странице (P330).
        let now = DayStore.today()
        if date != now { go(to: now) } else { refresh() }
        // Вечерние напоминания — на неделю вперёд от нынешнего дня (P444).
        planEvening()
    }

    /// Расставить вечерние «запишите день» заново (P444); выключены — снять.
    func planEvening() {
        Reminders.evening(todayWritten: isToday && todayWritten)
    }

    /// План дня таким, каким он ляжет в файл.
    private func planFile() -> DayFile {
        var plan = DayFile(body: Plan.body(from: planRows, photos: planPhotos))
        plan.set("date", Vault.stamp(date))
        return plan
    }

    /// Дневник дня таким, каким он ляжет в файл.
    private func diaryFileNow() -> DayFile {
        let order = tasks.map(\.text)
        var diary = DayFile(body: Diary(answers: answers, text: diaryText,
                                     photos: photos).body(order: order))
        diary.set("date", Vault.stamp(date))
        if !diaryTitle.isEmpty { diary.set("title", diaryTitle) }
        if let place { diary.set("place", place) }
        if let weather { diary.set("weather", weather) }
        if let lastEdit { diary.set("edited", DayStore.moment(lastEdit)) }
        return diary
    }

    /// Записать день — но никогда не поверх того, чего приложение не видело.
    ///
    /// Три правила, и каждое закрывает свою дыру:
    ///
    /// 1. Файл не прочитался (ещё в iCloud) — не пишем вовсе. Пустая
    ///    страница на экране не значит пустой файл на диске (P182).
    /// 2. Файл изменили в другом месте, пока он был открыт здесь, — не
    ///    затираем. Своей правки нет — перечитываем чужую; есть — кладём
    ///    свою рядом и перечитываем чужую (P183).
    /// 3. Ничего не менялось — не переписываем: лишняя запись в iCloud
    ///    плодит версии и столкновения.
    ///
    /// Пустой день не оставляет следов: файл заводится, только когда в нём
    /// что-то есть. Иначе пролистывание недели вперёд засеяло бы папку
    /// десятком пустых файлов — а папка не наша, чтобы её засорять.
    ///
    /// `keep` — для того, что живёт в шапке, а не в тексте: день, у которого
    /// есть только заголовок, всё равно записан человеком и пропасть не должен.
    ///
    /// Возвращает `true`, если на диске оказалось не то, что приложение
    /// видело, и день надо перечитать.
    @discardableResult
    private func write(_ file: DayFile, to folder: Vault.Folder, keep: Bool) -> Bool {
        guard !away.contains(folder) else { return false }
        let ours = file.text
        guard ours != mine[folder] else { return false }

        let now = vault.reading(folder, for: date)
        if now == .away {
            away.insert(folder)
            waitForCloud()
            return false
        }
        if now.text != (seen[folder] ?? "") {
            // Та же правка пришла с другой стороны — делить нечего.
            if now.text == ours {
                seen[folder] = ours
                mine[folder] = ours
                return false
            }
            // Своя правка кладётся рядом. Не легла — день не перечитываем,
            // иначе она пропадёт: пусть остаётся на экране до следующей попытки.
            guard let name = vault.writeAside(ours, folder: folder, for: date) else {
                return false
            }
            conflict = name
            return true
        }

        let empty = file.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if empty && !keep && now.text.isEmpty { return false }
        vault.write(ours, to: folder, for: date)
        if vault.problem == nil {
            seen[folder] = ours
            mine[folder] = ours
        }
        return false
    }

    /// То, что действительно лежит на диске — а не то, что помнит приложение.
    /// Нужно, чтобы проверять обещание: файлы источник, приложение только окно.
    func onDisk() -> String {
        let p = vault.read(.planner, for: date)
        let d = vault.read(.diary, for: date)
        return "\(Vault.Folder.planner.rawValue)\n\n\(p.isEmpty ? "(файла нет)\n" : p)\n"
             + "\(Vault.Folder.diary.rawValue)\n\n\(d.isEmpty ? "(файла нет)\n" : d)"
    }

    // MARK: - Мгновения

    private static let momentFormat = "yyyy-MM-dd'T'HH:mm"

    static func moment(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = momentFormat
        return f.string(from: date)
    }

    static func moment(from text: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = momentFormat
        return f.date(from: text)
    }
}
