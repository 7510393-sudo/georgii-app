import XCTest
@testable import Chronotheca

/// Дневник: ответы «Как прошло?» и текст живут в одном файле и не портят
/// друг друга. Главное правило то же, что у плана: чужое — не трогаем.
final class DiaryTests: XCTestCase {

    func testТекстБезОтветовОстаётсяТекстом() {
        let d = Diary(body: "08:15 Туман над полем.\n\n23:40 Глава дописана.")
        XCTAssertTrue(d.answers.isEmpty)
        XCTAssertEqual(d.text, "08:15 Туман над полем.\n\n23:40 Глава дописана.")
    }

    func testОтветыОтделяютсяОтТекста() {
        let d = Diary(body: """
        ## Как прошло?

        - Отвезти документы: всё получилось
        - Позвонить в поликлинику: не собрался

        08:15 Туман над полем.
        """)
        XCTAssertEqual(d.answers["Отвезти документы"], "всё получилось")
        XCTAssertEqual(d.answers["Позвонить в поликлинику"], "не собрался")
        XCTAssertEqual(d.text, "08:15 Туман над полем.")
    }

    func testТудаИОбратноБезПотерь() {
        let order = ["Отвезти документы", "Позвонить в поликлинику"]
        let d = Diary(answers: ["Отвезти документы": "всё получилось",
                                "Позвонить в поликлинику": "не собрался"],
                      text: "08:15 Туман над полем.")
        XCTAssertEqual(Diary(body: d.body(order: order)), d)
    }

    func testПустыеОтветыВФайлНеПопадают() {
        let d = Diary(answers: ["Отвезти документы": ""], text: "Текст.")
        XCTAssertEqual(d.body(order: ["Отвезти документы"]), "Текст.")
    }

    func testЗаголовокНижеПоТекстуНеСчитаетсяНашим() {
        // Такая же строка в середине записи — часть текста человека.
        let body = "Сегодня думал вот о чём.\n\n## Как прошло?\n\n- всё странно"
        let d = Diary(body: body)
        XCTAssertTrue(d.answers.isEmpty)
        XCTAssertEqual(d.text, body)
    }

    // MARK: - Написанное не пропадает

    func testОтветБезСвоегоДелаНеВыбрасывается() {
        // Человек написал ответ, потом переименовал дело. Ответ остаётся:
        // написанное не исчезает оттого, что приложению неудобно.
        let d = Diary(answers: ["Отвезти документы": "всё получилось"], text: "Туман.")
        let body = d.body(order: ["Отвезти бумаги"])
        XCTAssertTrue(body.contains("всё получилось"), "ответ пропал:\n" + body)

        let назад = Diary(body: body)
        XCTAssertEqual(назад.answers["Отвезти документы"], "всё получилось")
        XCTAssertEqual(назад.text, "Туман.")
    }

    func testДвоеточиеВОтветеНеЛомаетРазбор() {
        // «сделал в 10:30» — самый обычный ответ.
        let d = Diary(answers: ["Позвонить": "сделал в 10:30"], text: "")
        let назад = Diary(body: d.body(order: ["Позвонить"]))
        XCTAssertEqual(назад.answers["Позвонить"], "сделал в 10:30")
        XCTAssertNil(назад.answers["Позвонить: сделал в 10"])
    }

    func testДвоеточиеВНазванииДелаРазбираетсяПоСписку() {
        let дело = "Позвонить в 10:00 врачу"
        let d = Diary(answers: [дело: "не собрался"], text: "")
        let назад = Diary(body: d.body(order: [дело]), known: [дело])
        XCTAssertEqual(назад.answers[дело], "не собрался")
    }

    func testОтветыПереживаютНесколькоЗаписейПодряд() {
        // Так выглядит день: написали ответ, переименовали дело, снова
        // сохранили. После трёх оборотов должно уцелеть всё.
        var d = Diary(answers: ["Первое": "да", "Второе": "нет"], text: "Запись.")
        for order in [["Первое", "Второе"], ["Первое"], []] {
            d = Diary(body: d.body(order: order))
        }
        XCTAssertEqual(d.answers["Первое"], "да")
        XCTAssertEqual(d.answers["Второе"], "нет")
        XCTAssertEqual(d.text, "Запись.")
    }

    // MARK: - Начало записи для поиска

    func testПустыеСтрокиВНаходкуНеПопадают() {
        let day = Archive.Day(stamp: "2026-09-21", date: Date(),
                              text: "08:15 Туман над полем.\n\n23:40 Глава дописана.")
        XCTAssertEqual(day.preview, "08:15 Туман над полем.\n23:40 Глава дописана.")
    }

    func testСтрокаИзОднихПробеловТожеПустая() {
        let day = Archive.Day(stamp: "2026-09-21", date: Date(),
                              text: "Первая\n   \n\nВторая")
        XCTAssertEqual(day.preview, "Первая\nВторая")
    }

    func testЗаписьБезПустыхСтрокНеМеняется() {
        let day = Archive.Day(stamp: "2026-09-21", date: Date(),
                              text: "Первая\nВторая")
        XCTAssertEqual(day.preview, "Первая\nВторая")
    }

    func testПустаяЗаписьДаётПустоеНачало() {
        let day = Archive.Day(stamp: "2026-09-21", date: Date(), text: "\n\n  \n")
        XCTAssertEqual(day.preview, "")
    }

    func testНапоминаниеЖивётВСтрокеДела() {
        let rows = Plan.rows(from: "- [ ] 09:00 Отвезти документы (remind 08:30)")
        XCTAssertEqual(rows.first?.text, "Отвезти документы")
        XCTAssertEqual(rows.first?.bell, "08:30")
        XCTAssertEqual(Plan.body(from: rows),
                       "- [ ] 09:00 Отвезти документы (remind 08:30)")
        // Записанное до P355 — по-русски — читается так же.
        let прежние = Plan.rows(from: "- [ ] 09:00 Отвезти документы (напомнить 08:30)")
        XCTAssertEqual(прежние.first?.text, "Отвезти документы")
        XCTAssertEqual(прежние.first?.bell, "08:30")
    }

    // MARK: - Фотографии (P200)

    func testФотографияОтделяетсяОтТекста() {
        let d = Diary(body: """
        08:15 Туман над полем.

        ![](../../Фотографии/2026/2026-09-24_08.15.30.jpg)
        """)
        XCTAssertEqual(d.text, "08:15 Туман над полем.")
        XCTAssertEqual(d.photos, ["../../Фотографии/2026/2026-09-24_08.15.30.jpg"])
    }

    func testФотографииВстаютВКонецЗаписи() {
        let d = Diary(answers: ["Отвезти документы": "всё получилось"],
                      text: "08:15 Туман.",
                      photos: ["../../Фотографии/2026/a.jpg", "../../Фотографии/2026/b.jpg"])
        let body = d.body(order: ["Отвезти документы"])
        XCTAssertTrue(body.hasSuffix("""
        08:15 Туман.

        ![](../../Фотографии/2026/a.jpg)
        ![](../../Фотографии/2026/b.jpg)
        """))
        XCTAssertEqual(Diary(body: body, known: ["Отвезти документы"]), d)
    }

    func testСсылкаПосредиФразыОстаётсяТекстом() {
        let body = "Вот снимок ![](a.jpg) — смотри."
        let d = Diary(body: body)
        XCTAssertEqual(d.text, body)
        XCTAssertTrue(d.photos.isEmpty)
    }

    func testПутьСПробеломВУгловыхСкобках() {
        let d = Diary(body: "![](<../../Фотографии/2026/мой снимок.jpg>)")
        XCTAssertEqual(d.photos, ["../../Фотографии/2026/мой снимок.jpg"])
        XCTAssertEqual(d.body(order: []), "![](<../../Фотографии/2026/мой снимок.jpg>)")
    }

    func testДеньТолькоСФотографией() {
        let d = Diary(photos: ["../../Фотографии/2026/a.jpg"])
        XCTAssertEqual(d.body(order: []), "![](../../Фотографии/2026/a.jpg)")
    }

    func testФотографияПосредиТекстаОстаётсяНаМесте() {
        let body = """
        08:15 Туман.
        ![](../../Фотографии/2026/a.jpg)
        23:40 Глава дописана.

        ![](../../Фотографии/2026/b.jpg)
        """
        let d = Diary(body: body)
        XCTAssertEqual(d.photos, ["../../Фотографии/2026/b.jpg"])
        XCTAssertTrue(d.text.contains("![](../../Фотографии/2026/a.jpg)"))
        XCTAssertEqual(d.body(order: []), body)
    }

    // MARK: - Снимок посреди текста в поле записи (P204)

    func testСнимокВПолеВозвращаетсяВФайлТойЖеСтрокой() {
        let text = """
        08:15 Туман.

        ![](../../Фотографии/2026/2026-09-24_08.15.30.jpg)

        23:40 Глава дописана.
        """
        let shown = DiaryEditor.styled(text, size: 15.5, serif: true, stamped: true,
                                       resolve: { _ in nil })
        // На экране строки-ссылки нет — на её месте картинка.
        XCTAssertFalse(shown.string.contains("![]("))
        XCTAssertEqual(DiaryEditor.plain(shown), text)
    }

    func testБезСнимковПолеНеМеняетТекст() {
        let text = "08:15 Туман.\n\n23:40 Глава."
        let shown = DiaryEditor.styled(text, size: 15.5, serif: true, stamped: true,
                                       resolve: { _ in nil })
        XCTAssertEqual(DiaryEditor.plain(shown), text)
    }

    func testЧужойЗаместительНеПопадаетВФайл() {
        let shown = NSAttributedString(string: "Текст\u{FFFC} дальше")
        XCTAssertEqual(DiaryEditor.plain(shown), "Текст дальше")
    }

    // MARK: - Голос и документы (P209)

    func testГолосИДокументСтрокамиСоСсылкой() {
        let голос = "../../Аудио/2026/2026-09-25_21.40.05.m4a"
        let справка = "../../Документы/2026/Справка из банка.pdf"
        XCTAssertEqual(Diary.line(голос), "[2026-09-25_21.40.05](../../Аудио/2026/2026-09-25_21.40.05.m4a)")
        XCTAssertEqual(Diary.line(справка), "[Справка из банка](<../../Документы/2026/Справка из банка.pdf>)")
        XCTAssertEqual(Diary.picture(in: Diary.line(голос)), голос)
        XCTAssertEqual(Diary.picture(in: Diary.line(справка)), справка)
        XCTAssertEqual(Diary.kind(of: голос), .audio)
        XCTAssertEqual(Diary.kind(of: справка), .file)
        XCTAssertEqual(Diary.kind(of: "a.JPG"), .photo)
    }

    func testВложенияВКонцеЗаписиВсеВПолоске() {
        let d = Diary(photos: ["../../Фотографии/2026/a.jpg", "../../Аудио/2026/b.m4a"])
        let обратно = Diary(body: d.body(order: []))
        XCTAssertEqual(обратно.photos, d.photos)
        XCTAssertEqual(обратно.text, "")
    }

    func testСсылкаНаСайтНеВложение() {
        let d = Diary(body: "Интересное:\n[статья](https://example.com/a)")
        XCTAssertTrue(d.photos.isEmpty)
        XCTAssertTrue(d.text.contains("https://example.com/a"))
    }

    // P348: снимки рядом в одной строке.
    func testРядСнимковВОднойСтроке() {
        let row = "![](../../Фотографии/2026/a.jpg) ![](<../../Фотографии/2026/b c.jpg>)"
        XCTAssertNil(Diary.picture(in: row))
        XCTAssertEqual(Diary.links(in: row),
                       ["../../Фотографии/2026/a.jpg", "../../Фотографии/2026/b c.jpg"])
        XCTAssertTrue(Diary.links(in: "Смотри ![](a.jpg) вот").isEmpty)
        XCTAssertEqual(Diary.links(in: "![](a.jpg)"), ["a.jpg"])
        // Ряд в конце записи — часть текста, а не полоска: его поставили сами.
        let d = Diary(body: "Текст\n" + row)
        XCTAssertTrue(d.photos.isEmpty)
        XCTAssertTrue(d.text.contains(row))
    }

    func testСнимокИзПолоскиВстаётРядом() {
        let was = "Утро\n![](a.jpg)\nВечер"
        let now = "Утро\n![](a.jpg)\n![](b.jpg)\nВечер"
        XCTAssertEqual(DiaryEditor.besideDropped(now, was: was),
                       "Утро\n![](a.jpg) ![](b.jpg)\nВечер")
        // Под текстом — своей строкой, как прежде.
        XCTAssertNil(DiaryEditor.besideDropped("Утро\n![](b.jpg)\n![](a.jpg)\nВечер", was: was))
    }

    // P357: снимок посреди фразы — картинкой, а не буквами.
    func testСнимокПосредиФразыОстаётсяКартинкой() {
        let строка = "понимаю, о чём она воо ![](../../Photos/2026/a.jpg) бще толкует!"
        XCTAssertEqual(Diary.anywhere(in: строка).map(\.link), ["../../Photos/2026/a.jpg"])
        XCTAssertTrue(Diary.links(in: строка).isEmpty, "в полоску сам по себе не уходит")
        let поле = DiaryEditor.styled(строка, size: 17, serif: true, stamped: true,
                                      resolve: { _ in nil })
        var снимков = 0
        поле.enumerateAttribute(DiaryEditor.photoKey,
                                in: NSRange(location: 0, length: поле.length)) { value, _, _ in
            if value != nil { снимков += 1 }
        }
        XCTAssertEqual(снимков, 1)
        XCTAssertEqual(DiaryEditor.plain(поле), строка, "в файл ложится как было")
    }

    /// Снимок, голос и точка в ответе «Как прошло?» (P407): ответ — одна
    /// строка в файле, туда и обратно без потерь, а поле отдаёт ровно то,
    /// что было.
    func testВложенияВОтветеОднойСтрокой() {
        let ответ = Diary.adding("[2026-10-04_08.15](../../Audio/2026/2026-10-04_08.15.m4a)",
                                 to: Diary.adding("![](../../Photos/2026/a.jpg)", to: "хорошо "))
        XCTAssertEqual(ответ, "хорошо ![](../../Photos/2026/a.jpg) [2026-10-04_08.15](../../Audio/2026/2026-10-04_08.15.m4a)")
        let день = Diary(answers: ["Сходить в парк": ответ], text: "запись")
        let файл = день.body(order: ["Сходить в парк"])
        XCTAssertEqual(файл.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }.count, 1)
        let прочли = Diary(body: файл, known: ["Сходить в парк"])
        XCTAssertEqual(прочли.answers["Сходить в парк"], ответ)
        XCTAssertTrue(прочли.photos.isEmpty, "снимок из ответа в полоску не уходит")
        let поле = AskLine.dressed(ответ + " geo:51.5,-0.12 и дальше", resolve: { _ in nil })
        XCTAssertEqual(DiaryEditor.plain(поле), ответ + " geo:51.5,-0.12 и дальше")
    }
}
