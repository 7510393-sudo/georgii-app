import XCTest
@testable import Chronotheca

/// Перенос из Diarium и Journey (P444): дата — числом или строкой, текст —
/// из HTML обычным, место — точкой, снимки — по именам файлов.
final class JsonImportTests: XCTestCase {

    /// Как Journey: файл на запись, дата в миллисекундах, текст HTML,
    /// «нет места» — огромным числом.
    private let journey = """
    {"id":"1700000000000-abc","date_journal":1709595000000,"timezone":"Europe/London",
     "text":"<p>Утро в парке</p><p>Кофе &amp; булка<br>Солнце</p>",
     "tags":["прогулка"],"photos":["1700000000000-abc-1.jpg"],
     "lat":1.7976931348623157e308,"lon":1.7976931348623157e308,"address":""}
    """

    /// Похоже на Diarium: массив записей, заголовок отдельно, дата строкой.
    private let diarium = """
    {"entries":[
     {"date":"2024-05-17 21:40:00","heading":"Поездка","text":"Доехали до моря.",
      "tags":[{"name":"отпуск"}],"location":{"latitude":43.58,"longitude":39.72,"name":"Сочи"}},
     {"date":"2024-05-18 08:05:00","heading":"","text":"Дождь."}
    ]}
    """

    func testJourney() {
        let list = JsonImport.entries(from: Data(journey.utf8), app: "Journey")
        XCTAssertEqual(list.count, 1)
        let e = list[0]
        XCTAssertEqual(e.day, "2024-03-04")
        XCTAssertEqual(e.time, "23:30")
        XCTAssertEqual(e.text, "Утро в парке\nКофе & булка\nСолнце")
        XCTAssertNil(e.place, "огромное число — это «места нет»")
        XCTAssertEqual(e.tags, ["прогулка"])
        XCTAssertEqual(e.media["1700000000000-abc-1.jpg"]?.folder, "photos")
        XCTAssertEqual(e.uuid, "Journey:1700000000000-abc")
    }

    func testDiarium() {
        let list = JsonImport.entries(from: Data(diarium.utf8), app: "Diarium")
        XCTAssertEqual(list.count, 2)
        XCTAssertEqual(list[0].day, "2024-05-17")
        XCTAssertEqual(list[0].text, "Поездка\nДоехали до моря.")
        XCTAssertEqual(list[0].tags, ["отпуск"])
        XCTAssertEqual(list[0].place, "[Сочи](geo:43.58000,39.72000)")
        XCTAssertEqual(list[1].text, "Дождь.")
    }

    func testБезНомераЗаписьУзнаётсяСнова() {
        let a = JsonImport.entries(from: Data(diarium.utf8), app: "Diarium").map(\.uuid)
        let b = JsonImport.entries(from: Data(diarium.utf8), app: "Diarium").map(\.uuid)
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set(a).count, 2)
    }

    func testОбычныйТекстНеТрогается() {
        XCTAssertEqual(JsonImport.plain("3 < 5, и всё"), "3 < 5, и всё")
    }
}
