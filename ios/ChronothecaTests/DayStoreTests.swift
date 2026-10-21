import XCTest
import CoreLocation
@testable import Chronotheca

/// Правила дня: куда можно писать, а куда нельзя.
///
/// Это не украшение интерфейса, а обещание: план не переписывают задним
/// числом, а дневник не пишут наперёд. Проверяем на настоящих файлах во
/// временной папке — как в жизни.
final class DayStoreTests: XCTestCase {

    private var folder: URL!
    private var vault: Vault!

    override func setUp() {
        super.setUp()
        folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("день-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        vault = Vault()
        vault.adopt(folder)
        // Приложение больше не заводит папку само (P97) — соглашаемся за
        // человека, как он сделал бы в окне вопроса.
        XCTAssertNotNil(vault.proposal, "в пустом месте должно быть предложение")
        vault.acceptProposal()
        XCTAssertNil(vault.problem, "папка не открылась: \(vault.problem ?? "")")
        XCTAssertNotNil(vault.root)
    }

    override func tearDown() {
        vault.forget()
        try? FileManager.default.removeItem(at: folder)
        super.tearDown()
    }

    private func store(_ shift: Int) -> DayStore {
        let date = Calendar.current.date(byAdding: .day, value: shift, to: DayStore.today())!
        return DayStore(vault: vault, date: date)
    }

    /// P381: прошедший план правится так же, как сегодняшний — без режима.
    func testПланПрошедшегоДняПравится() {
        let вчера = store(-1)
        XCTAssertTrue(вчера.isPast)
        XCTAssertTrue(вчера.canEditPlan)
        XCTAssertNotNil(вчера.addTask())
    }

    func testПланБудущегоДняОткрыт() {
        // Ради этого планировщик и нужен: дела заводят заранее.
        let завтра = store(1)
        XCTAssertTrue(завтра.canEditPlan)
        XCTAssertTrue(store(0).canEditPlan)
    }

    func testДневникПишетсяЗаднимЧислом() {
        // Решение P63: вчерашнее дописывают и через неделю.
        XCTAssertTrue(store(-1).canEditDiary)
        XCTAssertTrue(store(-30).canEditDiary)
    }

    func testДневникБудущегоДняЗакрыт() {
        let завтра = store(1)
        XCTAssertFalse(завтра.canEditDiary)
        XCTAssertTrue(завтра.closedReason.contains(T("не наступил", "not come yet")))
    }

    func testЗаголовкиБлижнихДней() {
        XCTAssertEqual(store(0).title, T("Сегодня", "Today"))
        XCTAssertEqual(store(-1).title, T("Вчера", "Yesterday"))
        XCTAssertEqual(store(-2).title, T("Позавчера", "Two days ago"))
        XCTAssertEqual(store(1).title, T("Завтра", "Tomorrow"))
        XCTAssertEqual(store(2).title, T("Послезавтра", "In two days"))
    }

    func testПустойДеньНеОставляетФайлов() {
        // Пролистывание недели вперёд не должно засевать чужую папку
        // пустыми файлами: папка не наша.
        let день = store(3)
        день.save()
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vault.file(.planner, for: день.date)!.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vault.file(.diary, for: день.date)!.path))
    }

    func testНаписанноеПереживаетУходИВозврат() {
        let день = store(0)
        день.planRows = [.task(time: "09:00", "Отвезти документы")]
        день.diaryText = "Был туман."
        день.save()

        день.move(by: 1)          // ушли на завтра
        день.move(by: -1)         // вернулись
        XCTAssertEqual(день.planRows.count, 1)
        XCTAssertEqual(день.planRows.first?.text, "Отвезти документы")
        XCTAssertEqual(день.planRows.first?.time, "09:00")
        XCTAssertEqual(день.diaryText, "Был туман.")
    }
}

extension DayStoreTests {

    func testЗаголовокИОтветыЛожатсяВФайлДневника() {
        let день = store(0)
        день.planRows = [.task("Позвонить в поликлинику")]
        день.diaryTitle = "Туман"
        день.answers = ["Позвонить в поликлинику": "так и не собрался"]
        день.diaryText = "08:15 Проснулся раньше будильника."
        день.save()

        let на_диске = день.onDisk()
        XCTAssertTrue(на_диске.contains("title: Туман"))
        XCTAssertTrue(на_диске.contains(Diary.heading))
        XCTAssertTrue(на_диске.contains("- Позвонить в поликлинику: так и не собрался"))

        день.move(by: 1)
        день.move(by: -1)
        XCTAssertEqual(день.diaryTitle, "Туман")
        XCTAssertEqual(день.answers["Позвонить в поликлинику"], "так и не собрался")
        XCTAssertEqual(день.diaryText, "08:15 Проснулся раньше будильника.")
    }

    func testОписьВидитТоЧтоНаписано() {
        let день = store(0)
        день.planRows = [.task(time: "09:00", "Отвезти документы")]
        день.diaryTitle = "Туман"
        день.save()

        let опись = Archive(vault: vault)
        опись.reload()
        let стамп = Vault.stamp(день.date)
        XCTAssertEqual(опись.tasks(стамп).count, 1)
        XCTAssertEqual(опись.day(стамп)?.title, "Туман")
        XCTAssertEqual(опись.newestFirst.count, 1)
    }

    /// P566: опись перечитывает только изменённое — но правку файла в
    /// другом месте видит всегда: файл главнее описи.
    func testОписьВидитПравкуСнаружи() throws {
        let день = store(0)
        день.diaryTitle = "Туман"
        день.save()
        let опись = Archive(vault: vault)
        опись.reload()
        let стамп = Vault.stamp(день.date)
        XCTAssertEqual(опись.day(стамп)?.title, "Туман")

        // Правка «на Mac»: файл переписан мимо приложения.
        let файл = try XCTUnwrap(vault.file(.diary, for: день.date))
        let было = try String(contentsOf: файл, encoding: .utf8)
        Thread.sleep(forTimeInterval: 0.05)
        try было.replacingOccurrences(of: "Туман", with: "Ясно, солнце")
            .write(to: файл, atomically: true, encoding: .utf8)
        опись.reload()
        XCTAssertEqual(опись.day(стамп)?.title, "Ясно, солнце")

        // Новая опись с той же папкой — из временного хранилища, но тоже свежая.
        let снова = Archive(vault: vault)
        снова.reload()
        XCTAssertEqual(снова.day(стамп)?.title, "Ясно, солнце")
    }
}

extension DayStoreTests {

    func testДеньСОднимЗаголовкомНеПропадает() {
        // Заголовок — это уже запись. Проверка «день пустой» однажды смотрела
        // только на текст и молча выбрасывала такой день.
        let день = store(0)
        день.diaryTitle = "Туман"
        день.save()

        день.move(by: 1)
        день.move(by: -1)
        XCTAssertEqual(день.diaryTitle, "Туман")
    }
}

extension DayStoreTests {

    func testПапкаВнутриАрхиваНеПлодитВторойАрхив() {
        // Человек, ищущий свою папку, заходит внутрь неё. Заводить там второй
        // архив — значит разорвать записи надвое. Именно это однажды и вышло.
        let внутри = vault.root!.appendingPathComponent(Vault.Folder.diary.rawValue)
        let корень = vault.root!
        let другой = Vault()
        другой.forget()
        другой.adopt(внутри)

        XCTAssertNil(другой.proposal, "предлагать заводить папку здесь нельзя")
        XCTAssertEqual(другой.root?.standardizedFileURL, корень.standardizedFileURL,
                       "должен найтись тот же архив, а не новый")
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: внутри.appendingPathComponent(Vault.folderName).path),
            "внутри «Дневника» не должно появиться новой папки")
        другой.forget()
    }

    func testНоваяПапкаНеЗаводитсяБезСогласия() {
        let пустое = FileManager.default.temporaryDirectory
            .appendingPathComponent("пусто-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: пустое, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: пустое) }

        // Начинаем с чистого листа: проверки делят одну память настроек,
        // и закладка соседней проверки подхватилась бы при запуске.
        let v = Vault()
        v.forget()
        v.adopt(пустое)

        XCTAssertNotNil(v.proposal, "должно быть предложение, а не молчаливое создание")
        XCTAssertNil(v.root, "до согласия ничего не выбрано")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: пустое.appendingPathComponent(Vault.folderName).path),
            "до согласия ничего не создано")

        v.acceptProposal()
        XCTAssertNotNil(v.root)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: пустое.appendingPathComponent(Vault.folderName).path))
        v.forget()
    }

    /// «Места дня» больше нет (P294): точка «где я» ложится в ленту внизу
    /// страницы (P588), а строка «место:» в файле не заводится.
    func testТочкаГдеЯНеЗаводитМестаДня() {
        let день = store(0)
        let дом = CLLocationCoordinate2D(latitude: 54.3211, longitude: -2.7456)
        день.writePoint(GeoPoint(title: "", at: дом), to: .diary, here: true)
        XCTAssertNil(день.place)
        XCTAssertEqual(день.photos, ["geo:54.32110,-2.74560"])
        XCTAssertFalse(день.diaryText.contains("geo:"))
    }

    /// Точка в ленте записывается в файл своей строкой и читается обратно
    /// в ленту, а не в текст (P588).
    func testТочкаВЛентеПереживаетЗапись() {
        let d = Diary(text: "Утро", photos: ["[Дом](geo:54.32110,-2.74560)", "a.jpg"])
        let back = Diary(body: d.body(order: []))
        XCTAssertEqual(back.text, "Утро")
        XCTAssertEqual(back.photos, ["[Дом](geo:54.32110,-2.74560)", "a.jpg"])
    }

    /// Точку в плане переставляют между делами; скрытые строки файла
    /// остаются на месте (P226).
    func testТочкаПереставляетсяМеждуДелами() {
        let день = store(0)
        день.planRows = [.task("Первое"), .task("Второе"),
                         .verbatim("[Дом](geo:54.32110,-2.74560)"), .verbatim("")]
        let точка = день.planRows[2].id
        день.moveLine(точка, by: -2)
        XCTAssertEqual(день.planRows.map { $0.verbatim ?? $0.text },
                       ["[Дом](geo:54.32110,-2.74560)", "Первое", "Второе", ""])
        день.moveLine(точка, by: 1)
        XCTAssertEqual(день.planRows.map { $0.verbatim ?? $0.text },
                       ["Первое", "[Дом](geo:54.32110,-2.74560)", "Второе", ""])
    }

    /// Дописывая вчерашний день, человек видит, когда дописал: к времени
    /// встаёт короткая дата (P227). В сегодняшнем — только время.
    func testВПрошедшийДеньОтметкаСДатой() {
        let вчера = store(-1)
        XCTAssertTrue(вчера.stampIfNeeded())
        XCTAssertNotNil(вчера.diaryText.range(
            of: #"^\d{2}:\d{2} \d{2}\.\d{2}\.\d{2} $"#, options: .regularExpression))
        let сегодня = store(0)
        XCTAssertTrue(сегодня.stampIfNeeded())
        XCTAssertNotNil(сегодня.diaryText.range(
            of: #"^\d{2}:\d{2} $"#, options: .regularExpression))
        let строка = "08:15 25.09.26 Дописал"
        XCTAssertEqual(DiaryEditor.stamp.firstMatch(
            in: строка, range: NSRange(location: 0, length: (строка as NSString).length))?
            .numberOfRanges, 2)
    }

    /// Точка в план — в ленту плана внизу страницы (P588), а не строкой
    /// под делом: под дело её переносят пальцем.
    func testТочкаВПланВЛенту() {
        let день = store(0)
        день.planRows = [.task("Первое"), .task("Второе"), .verbatim("")]
        let c = CLLocationCoordinate2D(latitude: 1, longitude: 2)
        день.writePoint(GeoPoint(title: "", at: c), to: .plan)
        день.writePoint(GeoPoint(title: "Дом", at: c), to: .plan)
        XCTAssertEqual(день.planRows.map { $0.verbatim ?? $0.text }, ["Первое", "Второе", ""])
        XCTAssertEqual(день.planPhotos, ["geo:1.00000,2.00000", "[Дом](geo:1.00000,2.00000)"])
        XCTAssertEqual(Geo.stripped("Второе geo:1.00000,2.00000"), "Второе")
    }

    /// Шаг назад возвращает план, каким он был; шаг вперёд — обратно (P261).
    func testШагНазадИВперёдВПлане() {
        let день = store(0)
        let было = день.planRows
        день.planRows = было + [.task("Новое")]
        XCTAssertEqual(день.planBack.count, 1)
        день.undoPlan()
        XCTAssertEqual(день.planRows, было)
        XCTAssertEqual(день.planAhead.count, 1)
        день.redoPlan()
        XCTAssertEqual(день.planRows.last?.text, "Новое")
        XCTAssertTrue(день.planAhead.isEmpty)
    }

    // P357: снимок, оказавшийся посреди фразы, возвращается в полоску, а
    // фраза снова целая.
    func testСнимокИзСерединыФразыВозвращаетсяВниз() {
        let день = store(0)
        день.diaryText = "она воо![](../../Photos/2026/a.jpg)бще толкует!\nДальше."
        день.returnToStrip("../../Photos/2026/a.jpg")
        XCTAssertEqual(день.diaryText, "она вообще толкует!\nДальше.")
        XCTAssertEqual(день.photos, ["../../Photos/2026/a.jpg"])

        день.diaryText = "Утро.\n![](../../Photos/2026/b.jpg)\nВечер."
        день.returnToStrip("../../Photos/2026/b.jpg")
        XCTAssertEqual(день.diaryText, "Утро.\nВечер.")
    }

    // P383: свайп вправо — дело уходит в план другого дня вместе со
    // снимком под ним; здесь его больше нет, и «шаг назад» не вернёт его
    // вторым экземпляром.
    func testДелоПереноситсяНаДругойДень() {
        let день = store(0)
        день.planRows = [.task(time: "09:00", "Отвезти документы"),
                         .verbatim("![](../../Photos/2026/a.jpg)"),
                         .task("Позвонить")]
        день.save()
        let через3 = Calendar.current.date(byAdding: .day, value: 3, to: день.date)!
        XCTAssertTrue(день.moveTask(день.planRows[0].id, to: через3))
        XCTAssertEqual(день.planRows.map(\.text), ["Позвонить"])
        XCTAssertTrue(день.planBack.isEmpty)

        let там = store(3)
        XCTAssertEqual(там.planRows.first?.text, "Отвезти документы")
        XCTAssertEqual(там.planRows.first?.time, "09:00")
        XCTAssertTrue(там.planRows.contains { $0.verbatim == "![](../../Photos/2026/a.jpg)" },
                      "снимок под делом переехал вместе с ним")
        // На тот же день не переносится.
        XCTAssertFalse(день.moveTask(день.planRows[0].id, to: день.date))
    }

    // P403: открыл — пишешь. Курсор в новой строке, время — только с
    // первой буквой и один раз.
    func testОткрылИПишешь() {
        let день = store(0)
        день.diaryText = "Утро."
        день.noteWriting()
        // Писали только что — новая строка без отметки.
        XCTAssertTrue(день.openNewLine(always: true))
        XCTAssertEqual(день.diaryText, "Утро.\n")
        XCTAssertNil(день.takeStamp())

        // Пустая запись прошедшего дня: строки не прибавляется, отметка ждёт
        // первой буквы — с датой, когда писали.
        let вчера = store(-2)
        XCTAssertFalse(вчера.openNewLine(always: false))
        XCTAssertEqual(вчера.diaryText, "")
        let отметка = вчера.takeStamp()
        XCTAssertNotNil(отметка?.range(of: #"^\d{2}:\d{2} \d{2}\.\d{2}\.\d{2} $"#,
                                       options: .regularExpression))
        XCTAssertNil(вчера.takeStamp(), "отметка — один раз")
    }

    // P520: клавиатура уже была поднята — страница сменилась без «открытия»;
    // отметку всё равно решает час с последнего набора.
    func testОтметкаБезОткрытияПоЧасу() {
        let вчера = store(-1)
        вчера.diaryText = "Вечер."
        XCTAssertNotNil(вчера.takeStamp(), "давно не писали — отметка нужна")
        XCTAssertNil(вчера.takeStamp(), "только что — отметки нет")
        вчера.noteWriting()
        XCTAssertNil(вчера.takeStamp())
    }
}
