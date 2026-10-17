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
        vault = Vault()
        vault.adopt(folder)
        vault.acceptProposal()
        XCTAssertNotNil(vault.root, "папка не открылась: \(vault.problem ?? "")")
    }

    override func tearDown() {
        vault.forget()
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
        день.comeBack()

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
}
