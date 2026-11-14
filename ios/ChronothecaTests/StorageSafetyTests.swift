import XCTest
@testable import Chronotheca

/// Сохранность записей: три беды, каждая из которых однажды могла стереть
/// написанное, — и проверка на каждую.
///
/// Все проверки идут на настоящих файлах во временной папке. Если какая-то
/// из них упала — значит, приложение снова может затереть запись, и
/// выпускать его нельзя (решения P182, P183, P184).
final class StorageSafetyTests: XCTestCase {

    private var folder: URL!
    private var vault: Vault!
    private let fm = FileManager.default

    override func setUp() {
        super.setUp()
        folder = fm.temporaryDirectory.appendingPathComponent("сохранность-\(UUID().uuidString)")
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        Pending.home = fm.temporaryDirectory.appendingPathComponent("страховка-\(UUID().uuidString)")
        Vault.brokenWrites = nil
        PendingMedia.home = fm.temporaryDirectory.appendingPathComponent("страховка-вложений-\(UUID().uuidString)")
        vault = Vault()
        vault.adopt(folder)
        vault.acceptProposal()
        XCTAssertNotNil(vault.root, "папка не открылась: \(vault.problem ?? "")")
    }

    override func tearDown() {
        vault.forget()
        Vault.brokenWrites = nil
        if let home = Pending.home { try? fm.removeItem(at: home) }
        Pending.home = nil
        if let home = PendingMedia.home { try? fm.removeItem(at: home) }
        PendingMedia.home = nil
        try? fm.removeItem(at: folder)
        super.tearDown()
    }

    private var today: Date { DayStore.today() }

    private func planURL() -> URL { vault.file(.planner, for: today)! }
    private func diaryURL() -> URL { vault.file(.diary, for: today)! }

    /// Невидимая заглушка, которую iCloud оставляет вместо выгруженного файла.
    private func putStub(for url: URL) {
        try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        let stub = url.deletingLastPathComponent()
            .appendingPathComponent("." + url.lastPathComponent + ".icloud")
        try? Data("заглушка".utf8).write(to: stub)
    }

    private func put(_ text: String, at url: URL) {
        try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        try? Data(text.utf8).write(to: url)
    }

    private func contents(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) }
    }

    /// Файлы, положенные рядом с днём как вторая версия.
    private func asides(near url: URL) -> [URL] {
        let all = (try? fm.contentsOfDirectory(at: url.deletingLastPathComponent(),
                                               includingPropertiesForKeys: nil)) ?? []
        return all.filter {
            $0.lastPathComponent.contains("вторая версия") || $0.lastPathComponent.contains("second version")
        }
    }

    // MARK: - Беда 1: файл ещё в iCloud (P182)

    func testЧитаемыйФайлВсегдаЧитается() {
        // Сборка 58: приложение сперва спрашивало iCloud, скачан ли файл,
        // и на телефоне все дни разом объявились «ещё в облаке» — записи
        // пропали с экрана. Файл, который читается, должен читаться всегда,
        // что бы ни думало о нём облако (решение P187).
        let текст = "- [ ] дело\n"
        put(текст, at: planURL())
        XCTAssertEqual(Vault.reading(at: planURL()), .text(текст))
        XCTAssertEqual(Vault.reading(at: planURL(), coordinated: false), .text(текст))
        let день = DayStore(vault: vault, date: today)
        XCTAssertTrue(день.away.isEmpty, "прочитанный день объявлен недоступным")
        XCTAssertEqual(день.tasks.map(\.text), ["дело"])
    }

    func testНескачанныйФайлНеПринимаетсяЗаПустой() {
        putStub(for: planURL())
        XCTAssertEqual(vault.reading(.planner, for: today), .away,
                       "заглушка iCloud — не пустой день")
    }

    func testВНескачанныйДеньНельзяПисать() {
        putStub(for: planURL())
        let день = DayStore(vault: vault, date: today)
        XCTAssertTrue(день.away.contains(.planner))
        XCTAssertFalse(день.canEditPlan, "пустая страница — не пустой файл")
        XCTAssertTrue(день.closedReason.contains("iCloud"))
    }

    func testПоверхНескачанногоФайлаНеПишется() {
        // Главная проверка: человек видит пустую страницу, пишет — и
        // настоящая запись в облаке не должна быть затёрта.
        putStub(for: planURL())
        let день = DayStore(vault: vault, date: today)
        день.planRows = [.task("написано поверх")]
        день.save()
        XCTAssertFalse(fm.fileExists(atPath: planURL().path),
                       "приложение записало поверх файла, которого не видело")
    }

    func testНечитаемыйФайлНеЗатирается() {
        // Файл есть, но это не текст в UTF-8. Пусть лучше день будет
        // закрыт, чем файл будет переписан.
        let url = planURL()
        try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        let bytes = Data([0xFF, 0xFE, 0xFD, 0x00, 0x41])
        try? bytes.write(to: url)

        let день = DayStore(vault: vault, date: today)
        XCTAssertTrue(день.away.contains(.planner))
        день.planRows = [.task("написано поверх")]
        день.save()
        XCTAssertEqual(try? Data(contentsOf: url), bytes, "нечитаемый файл переписан")
    }

    func testНескачанныйДеньВиденВКалендаре() {
        // Раньше такие дни молча выпадали из календаря и поиска.
        putStub(for: diaryURL())
        let опись = Archive(vault: vault)
        опись.reload()
        let день = опись.day(Vault.stamp(today))
        XCTAssertEqual(день?.inCloud, true)
        XCTAssertEqual(день?.hasSomething, true)
    }

    // MARK: - Беда 2: файл поправили в другом месте (P183)

    func testЧужаяПравкаНеЗатираетсяСвоей() {
        let день = DayStore(vault: vault, date: today)
        день.planRows = [.task("утреннее")]
        день.save()

        // Пока день открыт здесь, файл правят на Mac.
        let сMac = "- [ ] поправлено на Mac\n"
        put(сMac, at: planURL())

        // А здесь тем временем дописывают своё.
        день.planRows.append(.task("дописано на телефоне"))
        день.save()

        XCTAssertEqual(contents(planURL()), сMac, "правка с Mac затёрта")
        let рядом = asides(near: planURL())
        XCTAssertEqual(рядом.count, 1, "своя правка не положена рядом")
        XCTAssertTrue(рядом.first.flatMap(contents)?.contains("дописано на телефоне") == true,
                      "своя правка пропала")
        XCTAssertNotNil(день.conflict, "человеку не сказали, где его правка")
        XCTAssertTrue(день.tasks.contains { $0.text == "поправлено на Mac" },
                      "на экране не та версия, что в файле")
    }

    func testЧужаяПравкаПодхватываетсяПриВозвращении() {
        let день = DayStore(vault: vault, date: today)
        день.planRows = [.task("утреннее")]
        день.save()

        put("- [ ] поправлено на Mac\n", at: planURL())
        день.comeBack(newDay: false)

        XCTAssertEqual(день.tasks.map(\.text), ["поправлено на Mac"])
        XCTAssertTrue(asides(near: planURL()).isEmpty, "своей правки не было — класть рядом нечего")
        XCTAssertNil(день.conflict)
    }

    func testПравкаВоВторомФайлеНеПропадаетПриПеречитывании() {
        // План поправили на Mac, а в дневнике тем временем набрали фразу.
        // Перечитывание дня из-за плана не должно унести фразу.
        let день = DayStore(vault: vault, date: today)
        день.planRows = [.task("утреннее")]
        день.save()

        put("- [ ] поправлено на Mac\n", at: planURL())
        день.planRows.append(.task("дописано на телефоне"))
        день.diaryText = "Фраза, набранная только что."
        день.save()

        XCTAssertEqual(день.diaryText, "Фраза, набранная только что.")
        XCTAssertTrue(contents(diaryURL())?.contains("Фраза, набранная только что.") == true)
    }

    func testБезПравкиФайлНеПереписывается() {
        // Файл, написанный рукой, со своими пробелами. Приложение его
        // открыло и ничего не меняло — значит, и переписывать не должно.
        let рукой = "- [ ]    лишние пробелы\n\n\n"
        put(рукой, at: planURL())
        let день = DayStore(vault: vault, date: today)
        день.save()
        XCTAssertEqual(contents(planURL()), рукой, "нетронутый файл переписан")
    }

    func testВтораяВерсияНеСчитаетсяДнём() {
        // Файл второй версии лежит рядом с днём, но днём не притворяется:
        // иначе календарь показал бы один день дважды.
        XCTAssertNil(Vault.date(from: "2026-09-24 — вторая версия 10.00.00"))
    }

    // MARK: - Беда 3: последние слова (P184)

    func testЗаписьНеЖдётПаузы() {
        // Приложение пишет через полсекунды после последней буквы. Уходя с
        // экрана, оно зовёт запись немедленно — и она должна лечь сразу, не
        // дожидаясь отложенной.
        let день = DayStore(vault: vault, date: today)
        день.diaryText = "Последние слова перед тем, как смахнуть."
        день.scheduleSave()
        день.save()
        XCTAssertTrue(contents(diaryURL())?.contains("Последние слова") == true)
    }

    // MARK: - Беда 4: запись не дошла до папки (P900)

    func testНезаписанноеВидноИЛежитВСтраховке() {
        let день = DayStore(vault: vault, date: today)
        день.diaryText = "Первая строка."
        день.save()
        XCTAssertNil(день.unsaved)

        Vault.brokenWrites = "нет места"
        день.diaryText = "Первая строка.\nВторая, которой некуда лечь."
        день.save()

        XCTAssertNotNil(день.unsaved, "человеку не сказали, что запись не дошла")
        XCTAssertFalse(contents(diaryURL())?.contains("Вторая") == true)
        XCTAssertTrue(Pending.draft(.diary, date: today, root: vault.root!)?.text.contains("Вторая") == true,
                      "незаписанного нет в страховке")
        XCTAssertTrue(день.diaryText.contains("Вторая"), "текст пропал с экрана")
    }

    func testНезаписанноеДоходитКогдаПапкаВернулась() {
        let день = DayStore(vault: vault, date: today)
        Vault.brokenWrites = "нет места"
        день.diaryText = "Писал, пока облако молчало."
        день.save()
        XCTAssertNotNil(день.unsaved)

        Vault.brokenWrites = nil
        день.save()

        XCTAssertNil(день.unsaved, "строка не погасла, хотя запись дошла")
        XCTAssertTrue(contents(diaryURL())?.contains("облако молчало") == true)
        XCTAssertNil(Pending.draft(.diary, date: today, root: vault.root!), "страховка не стёрта")
    }

    func testНезаписанноеПереживаетЗакрытиеПриложения() {
        let прежде = DayStore(vault: vault, date: today)
        прежде.diaryText = "Было в файле."
        прежде.save()
        Vault.brokenWrites = "нет места"
        прежде.diaryText = "Было в файле.\nДописано перед тем, как приложение закрыли."
        прежде.save()

        // Новый запуск: папка снова доступна.
        Vault.brokenWrites = nil
        let после = DayStore(vault: vault, date: today)
        XCTAssertTrue(после.diaryText.contains("Дописано перед"), "день открыт без недописанного")
        после.save()
        XCTAssertTrue(contents(diaryURL())?.contains("Дописано перед") == true, "недописанное не дошло до папки")
        XCTAssertNil(Pending.draft(.diary, date: today, root: vault.root!))
    }

    func testНезаписанноеДругогоДняДоходитСамо() {
        let вчера = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let день = DayStore(vault: vault, date: вчера)
        Vault.brokenWrites = "нет места"
        день.diaryText = "Вчерашняя запись, не дошедшая до папки."
        день.go(to: today)
        XCTAssertNotNil(день.unsaved, "ушли со дня — и строка погасла, хотя запись в страховке")

        Vault.brokenWrites = nil
        день.comeBack(newDay: false)
        let файл = vault.file(.diary, for: вчера)!
        XCTAssertTrue(contents(файл)?.contains("Вчерашняя запись") == true)
        XCTAssertNil(день.unsaved)
    }

    func testНезаписанноеНеЗатираетЧужуюПравку() {
        let прежде = DayStore(vault: vault, date: today)
        прежде.diaryText = "Было в файле."
        прежде.save()
        Vault.brokenWrites = "нет места"
        прежде.diaryText = "Своё, недописанное."
        прежде.save()

        // Пока папка была недоступна здесь, файл поправили на Mac.
        Vault.brokenWrites = nil
        put("Поправлено на Mac.\n", at: diaryURL())
        let после = DayStore(vault: vault, date: today)
        после.save()

        XCTAssertEqual(contents(diaryURL()), "Поправлено на Mac.\n", "правка с Mac затёрта")
        XCTAssertTrue(asides(near: diaryURL()).contains { contents($0)?.contains("Своё, недописанное") == true },
                      "недописанное не положено рядом")
    }

    // MARK: - Беда 5: вложение не легло в папку (P904)

    func testГолосНеТеряетсяИДоходитСам() {
        let день = DayStore(vault: vault, date: today)
        Vault.brokenWrites = "нет места"
        let голос = Data("надиктовано".utf8)
        XCTAssertFalse(день.addAttachment(голос, to: .audio, name: "voice-note.m4a", tab: .diary))
        XCTAssertTrue(день.keepForLater(голос, kind: .audio, name: "voice-note.m4a", tab: .diary),
                      "голос не оставлен в страховке")
        XCTAssertNotNil(день.unsaved, "человеку не сказано, что голос не дошёл")
        XCTAssertEqual(PendingMedia.items(root: vault.root!).count, 1)

        Vault.brokenWrites = nil
        день.comeBack(newDay: false)

        XCTAssertTrue(PendingMedia.items(root: vault.root!).isEmpty, "страховка не стёрта")
        XCTAssertTrue(contents(diaryURL())?.contains("voice-note") == true, "ссылки на голос нет в дне")
        let год = String(Vault.stamp(today).prefix(4))
        let файл = Vault.folder(.audio, in: vault.root!).appendingPathComponent(год).appendingPathComponent("voice-note.m4a")
        XCTAssertEqual(try? Data(contentsOf: файл), голос, "голос не лёг в папку")
        XCTAssertNil(день.unsaved)
    }

    func testВложениеДругогоДняДоходитВСвойДень() {
        let вчера = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let день = DayStore(vault: vault, date: вчера)
        Vault.brokenWrites = "нет места"
        XCTAssertTrue(день.keepForLater(Data("вчерашний голос".utf8), kind: .audio, name: "yesterday-note.m4a", tab: .diary))
        день.go(to: today)

        Vault.brokenWrites = nil
        день.comeBack(newDay: false)

        let файл = vault.file(.diary, for: вчера)!
        XCTAssertTrue(contents(файл)?.contains("yesterday-note.m4a") == true, "ссылка легла не в свой день")
        XCTAssertFalse(contents(diaryURL())?.contains("yesterday-note.m4a") == true)
    }

    // MARK: - Беда 6: архив новее приложения (P952, P953)

    /// Папка-архив с меткой и одним днём плана.
    private func archive(mark: String, plan: String? = nil) -> URL {
        let other = fm.temporaryDirectory.appendingPathComponent("архив-\(UUID().uuidString)")
        put(mark, at: Vault.folder(.service, in: other).appendingPathComponent(Vault.markerName))
        if let plan {
            put(plan, at: Vault.folder(.planner, in: other)
                .appendingPathComponent(String(Vault.stamp(today).prefix(4)))
                .appendingPathComponent(Vault.stamp(today) + ".md"))
        }
        return other
    }

    func testНоваяМеткаСАнглийскимиКлючами() throws {
        let url = Vault.folder(.service, in: vault.root!).appendingPathComponent(Vault.markerName)
        let text = try XCTUnwrap(contents(url))
        let mark = try XCTUnwrap(ArchiveMark.parse(text))
        XCTAssertFalse(mark.russian)
        XCTAssertEqual(mark.format, ArchiveMark.format)
        XCTAssertEqual(mark.app, "Graphomanus")
        XCTAssertFalse(text.contains("версия формата"))
        XCTAssertFalse(Vault.newer)
    }

    func testПрежняяМеткаПереписываетсяАнглийскими() throws {
        let other = archive(mark: """
        {
          "приложение": "Graphomanus",
          "версия формата": 1,
          "заведено": "2025-03-01"
        }
        """, plan: "- [ ] дело\n")
        defer { try? fm.removeItem(at: other) }
        vault.adopt(other)
        XCTAssertNotNil(vault.root)
        let url = Vault.folder(.service, in: other).appendingPathComponent(Vault.markerName)
        let mark = try XCTUnwrap(contents(url).flatMap(ArchiveMark.parse))
        XCTAssertFalse(mark.russian, "метка осталась с русскими ключами")
        XCTAssertEqual(mark.created, "2025-03-01", "дата заведения потерялась")
        XCTAssertEqual(mark.format, 1)
        XCTAssertFalse(Vault.newer)
    }

    func testНечитаемаяМеткаНеПереписывается() {
        // Метка не JSON — не наша забота её чинить: файл человека.
        let other = archive(mark: "{ приложение: Graphomanus", plan: "- [ ] дело\n")
        defer { try? fm.removeItem(at: other) }
        vault.adopt(other)
        let url = Vault.folder(.service, in: other).appendingPathComponent(Vault.markerName)
        XCTAssertEqual(contents(url), "{ приложение: Graphomanus")
        XCTAssertFalse(Vault.newer)
    }

    func testАрхивНовееПриложенияТолькоЧитается() {
        let plan = "- [ ] дело из будущего\n"
        let mark = ArchiveMark.text(format: ArchiveMark.format + 1, created: "2030-01-01")
        let other = archive(mark: mark, plan: plan)
        defer { try? fm.removeItem(at: other) }
        vault.adopt(other)
        XCTAssertNotNil(vault.root)
        XCTAssertTrue(Vault.newer, "архив новее приложения не узнан")

        // Читается.
        let день = DayStore(vault: vault, date: today)
        XCTAssertEqual(день.tasks.map(\.text), ["дело из будущего"])
        // Не пишется: ни правкой дня, ни мимо неё.
        XCTAssertFalse(день.canEditPlan)
        XCTAssertFalse(день.canEditDiary)
        день.planRows = [.task("написано старым приложением")]
        день.save()
        XCTAssertEqual(contents(vault.file(.planner, for: today)!), plan, "старое приложение переписало день")
        let завтра = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        XCTAssertNotNil(Vault.write("- [ ] новое\n", to: vault.file(.planner, for: завтра)!))
        XCTAssertFalse(fm.fileExists(atPath: vault.file(.planner, for: завтра)!.path))
        XCTAssertFalse(Trash.put(today, parts: [.planner], in: vault), "день ушёл в корзину")
        XCTAssertEqual(contents(vault.file(.planner, for: today)!), plan)
        // Метка нового архива не трогается.
        let url = Vault.folder(.service, in: other).appendingPathComponent(Vault.markerName)
        XCTAssertEqual(contents(url), mark)

        // Другая папка — запрет снят.
        vault.adopt(folder)
        XCTAssertFalse(Vault.newer)
    }
}
