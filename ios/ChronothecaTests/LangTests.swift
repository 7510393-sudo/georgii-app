import XCTest
@testable import Chronotheca

/// Десять языков (P369): перевод по английской надписи, вставки на своих
/// местах, нет перевода — английская.
final class LangTests: XCTestCase {

    private var was: Any?

    override func setUp() {
        super.setUp()
        was = UserDefaults.standard.object(forKey: Lang.key)
    }

    override func tearDown() {
        UserDefaults.standard.set(was, forKey: Lang.key)
        super.tearDown()
    }

    func testВставкиНаСвоихМестах() {
        let t = Strings(["Files: %@ of %@": "Dateien: %@ von %@",
                         "%@ of %@": "%2$@ / %1$@",
                         "Close": "Schließen"])
        XCTAssertEqual(t.translate("Close"), "Schließen")
        XCTAssertEqual(t.translate("Files: 3 of 12"), "Dateien: 3 von 12", "длинный образец раньше короткого")
        XCTAssertEqual(t.translate("3 of 12"), "12 / 3", "вставки по номерам")
        XCTAssertEqual(t.translate("Something new"), "Something new", "нет перевода — английская")
    }

    func testПереводыЕстьВПриложении() {
        for code in ["uk", "de", "fr", "es", "it", "pt", "nl", "ja"] {
            let t = Strings(code: code)
            XCTAssertNotEqual(t.translate("Settings"), "Settings", code)
        }
        XCTAssertEqual(Strings(code: "de").translate("Planned 2 · done 1"), "Geplant 2 · erledigt 1")
    }

    func testЯзыкВыбранныйИЯзыкТелефона() {
        UserDefaults.standard.set("ja", forKey: Lang.key)
        XCTAssertEqual(Lang.code, "ja")
        XCTAssertEqual(T("Закрыть", "Close"), "閉じる")
        UserDefaults.standard.set("ru", forKey: Lang.key)
        XCTAssertEqual(T("Закрыть", "Close"), "Закрыть")
        UserDefaults.standard.set("xx", forKey: Lang.key)
        XCTAssertEqual(Lang.code, Lang.phone, "неизвестный — как у телефона")
        XCTAssertTrue(Lang.all.contains { $0.code == Lang.phone })
    }
}
