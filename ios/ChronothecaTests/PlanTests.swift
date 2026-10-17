import XCTest
@testable import Chronotheca

/// Проверки формата плана.
///
/// Единственное, что в этом приложении не имеет права сломаться, — чтение и
/// запись записей. Поломка формата обнаруживается через месяцы, когда чинить
/// уже нечего. Поэтому каждое изменение формата приезжает вместе с проверкой.
final class PlanTests: XCTestCase {

    func testПростоеДелоТудаИОбратно() {
        let text = "- [ ] Позвонить в поликлинику"
        let rows = Plan.rows(from: text)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].isTask)
        XCTAssertFalse(rows[0].done)
        XCTAssertNil(rows[0].time)
        XCTAssertEqual(rows[0].text, "Позвонить в поликлинику")
        XCTAssertEqual(Plan.body(from: rows), text)
    }

    func testДелоСоВременемИПодробностями() {
        let text = """
        - [x] 09:00 Отвезти документы нотариусу
              Малая Бронная 12, второй этаж.
              Взять оригинал доверенности.
        """
        let rows = Plan.rows(from: text)
        XCTAssertEqual(rows.count, 1)
        XCTAssertTrue(rows[0].done)
        XCTAssertEqual(rows[0].time, "09:00")
        XCTAssertEqual(rows[0].text, "Отвезти документы нотариусу")
        XCTAssertEqual(rows[0].details.count, 2)
        XCTAssertEqual(Plan.body(from: rows), text)
    }

    /// Главная проверка: непонятое сохраняется нетронутым и на своём месте.
    func testЧужоеСохраняетсяКакЕсть() {
        let text = """
        ## Утро
        - [ ] Позвонить в поликлинику

        Произвольная строка, которую я дописал в текстовом редакторе.
        - [x] 15:00 Дописать вторую главу
        > цитата
        """
        let rows = Plan.rows(from: text)
        XCTAssertEqual(Plan.body(from: rows), text,
                       "Файл должен вернуться посимвольно таким же")
    }

    func testПометкаВыполненияНеТрогаетОстальное() {
        let text = """
        ## Утро
        - [ ] Позвонить в поликлинику
        Заметка сбоку
        """
        var rows = Plan.rows(from: text)
        guard let i = rows.firstIndex(where: { $0.isTask }) else {
            return XCTFail("дело не найдено")
        }
        rows[i].done = true

        XCTAssertEqual(Plan.body(from: rows), """
        ## Утро
        - [x] Позвонить в поликлинику
        Заметка сбоку
        """)
    }

    func testВремяРазбираетсяТолькоНастоящее() {
        XCTAssertEqual(Plan.rows(from: "- [ ] 25:00 не время")[0].text, "25:00 не время")
        XCTAssertEqual(Plan.rows(from: "- [ ] 09:60 не время")[0].text, "09:60 не время")
        XCTAssertEqual(Plan.rows(from: "- [ ] 09:00 время")[0].time, "09:00")
    }

    func testПустойПланДаётПустойФайл() {
        XCTAssertEqual(Plan.body(from: Plan.rows(from: "")), "")
    }

    // MARK: - Фотографии плана (P203)

    func testФотографииПланаОтдельноОтДел() {
        let body = """
        - [ ] 09:00 Отвезти документы
        - [ ] Позвонить

        ![](../../Фотографии/2026/a.jpg)
        """
        let (rows, photos) = Plan.splitPhotos(Plan.rows(from: body))
        XCTAssertEqual(photos, ["../../Фотографии/2026/a.jpg"])
        XCTAssertEqual(rows.filter(\.isTask).count, 2)
        XCTAssertEqual(Plan.body(from: rows, photos: photos), body)
    }

    func testПланБезФотографийНеМеняется() {
        let body = "- [ ] Позвонить\n\nЗаметка в конце"
        let (rows, photos) = Plan.splitPhotos(Plan.rows(from: body))
        XCTAssertTrue(photos.isEmpty)
        XCTAssertEqual(Plan.body(from: rows, photos: photos), body)
    }
}
