import XCTest
import CoreLocation
@testable import Chronotheca

/// Места своей карты — обычные файлы, и координаты в них читаются
/// обратно без потерь (решение P207).
final class PlaceTests: XCTestCase {

    func testМестоТудаИОбратно() {
        let дом = Place(name: "Мой дом в Петербурге",
                        coordinate: CLLocationCoordinate2D(latitude: 59.93863, longitude: 30.31413),
                        text: "Жил здесь с 2004 по 2011 год.")
        let файл = дом.fileText
        XCTAssertTrue(файл.contains("name: Мой дом в Петербурге"))
        XCTAssertTrue(файл.contains("place: 59.93863, 30.31413"))
        let обратно = Place(text: файл, file: "Мой дом в Петербурге.md")
        XCTAssertEqual(обратно?.name, "Мой дом в Петербурге")
        XCTAssertEqual(обратно?.text, "Жил здесь с 2004 по 2011 год.")
        XCTAssertEqual(обратно?.latitude ?? 0, 59.93863, accuracy: 0.000001)
        XCTAssertEqual(обратно?.longitude ?? 0, 30.31413, accuracy: 0.000001)
    }

    func testБезКоординатНеМесто() {
        XCTAssertNil(Place(text: "Просто заметка", file: "заметка.md"))
    }

    func testИмяФайлаБезОпасныхЗнаков() {
        XCTAssertEqual(Place.fileName(for: "Дача: у озера / летом"), "Дача- у озера - летом.md")
        XCTAssertEqual(Place.fileName(for: "   "), T("Место", "Place") + ".md")
    }

    func testКоординатыСловами() {
        let c = CLLocationCoordinate2D(latitude: 54.3211, longitude: -2.7456)
        XCTAssertEqual(Geo.line(c), "geo:54.32110,-2.74560")
        XCTAssertEqual(Geo.parse("geo:54.32110,-2.74560")?.longitude ?? 0, -2.7456, accuracy: 0.00001)
        XCTAssertEqual(Geo.parse("54.3, 20")?.latitude ?? 0, 54.3, accuracy: 0.00001)
        XCTAssertNil(Geo.parse("geo:200,10"))
        XCTAssertNil(Geo.parse("не место"))
    }

    /// Точка в тексте дня: с названием — ссылкой, без — просто `geo:` (P213).
    func testТочкаВТекстеТудаИОбратно() {
        let c = CLLocationCoordinate2D(latitude: 59.93863, longitude: 30.31413)
        let строка = Geo.pointLine(GeoPoint(title: "Дом [старый]", at: c))
        XCTAssertEqual(строка, "[Дом (старый)](geo:59.93863,30.31413)")
        let обратно = Geo.point(in: строка)
        XCTAssertEqual(обратно?.title, "Дом (старый)")
        XCTAssertEqual(обратно?.at.latitude ?? 0, 59.93863, accuracy: 0.000001)
        XCTAssertEqual(Geo.pointLine(GeoPoint(title: " ", at: c)), "geo:59.93863,30.31413")
        XCTAssertEqual(Geo.point(in: "geo:59.93863,30.31413")?.title, "")
        XCTAssertNil(Geo.point(in: "[Дом](../../Фотографии/2026/x.jpg)"))
        XCTAssertNil(Geo.point(in: "Были у [Дом](geo:1,2) вечером"))
        // Точка — не вложение: она остаётся в тексте, а не уходит в полоску.
        XCTAssertNil(Diary.picture(in: строка))
        let запись = Diary(body: "Гуляли.\n\n" + строка)
        XCTAssertEqual(запись.photos, [])
        XCTAssertTrue(запись.text.hasSuffix(строка))
    }

    /// Точка с карты встаёт своей строкой — следующей за абзацем, где
    /// стоял курсор (P213, P380); пустую строку под курсором занимает сама.
    func testТочкаВстаётСвоейСтрокой() {
        let (посреди, курсор) = DayStore.insert("geo:1.00000,2.00000",
                                                into: "Утром туман. Днём солнце.\nВечер.", at: 12)
        XCTAssertEqual(посреди, "Утром туман. Днём солнце.\ngeo:1.00000,2.00000\nВечер.")
        XCTAssertEqual(курсор, ("Утром туман. Днём солнце.\ngeo:1.00000,2.00000" as NSString).length)
        let (вКонце, _) = DayStore.insert("geo:1.00000,2.00000", into: "Туман.\n", at: nil)
        XCTAssertEqual(вКонце, "Туман.\ngeo:1.00000,2.00000")
        let (сНачала, _) = DayStore.insert("geo:1.00000,2.00000", into: "", at: 0)
        XCTAssertEqual(сНачала, "geo:1.00000,2.00000")
        let (вПустую, _) = DayStore.insert("geo:1.00000,2.00000", into: "Туман.\n\nВечер.", at: 7)
        XCTAssertEqual(вПустую, "Туман.\ngeo:1.00000,2.00000\nВечер.")
    }

    /// Значок места лежит в шапке файла словом и читается обратно; чужое
    /// слово — обычная точка (P234).
    func testЗначокМестаВФайле() {
        var дача = Place(name: "Дача", coordinate: CLLocationCoordinate2D(latitude: 55, longitude: 37))
        дача.mark = "личное"
        let файл = дача.fileText
        XCTAssertTrue(файл.contains("icon: private"))
        XCTAssertEqual(Place(text: файл, file: "Дача.md")?.mark, "личное")
        let чужое = файл.replacingOccurrences(of: "icon: private", with: "icon: ракета")
        XCTAssertEqual(Place(text: чужое, file: "Дача.md")?.mark, Glyph.standard)
        // Файл, записанный до P353, — русскими словами — читается так же.
        let прежний = "---\nназвание: Дача\nместо: 55, 37\nзначок: личное\n---\n"
        XCTAssertEqual(Place(text: прежний, file: "Дача.md")?.mark, "личное")
        XCTAssertEqual(Place(text: прежний, file: "Дача.md")?.name, "Дача")
    }

    /// Курсор после вписанной точки встаёт за ней: в поле точка — один
    /// знак, в файле — целая строка (P253).
    func testКурсорЗаТочкойВПоле() {
        let строка = "geo:1.00000,2.00000"
        let поле = NSMutableAttributedString(string: "Туман.\n")
        поле.append(NSAttributedString(string: "\u{FFFC}", attributes: [DiaryEditor.lineKey: строка]))
        поле.append(NSAttributedString(string: "\nСолнце."))
        let вФайле = ("Туман.\n" + строка as NSString).length
        XCTAssertEqual(DiaryEditor.viewOffset(plain: вФайле, in: поле), 8)
        XCTAssertEqual(DiaryEditor.viewOffset(plain: 3, in: поле), 3)
        XCTAssertEqual(DiaryEditor.viewOffset(plain: 10_000, in: поле), поле.length)
    }

    /// Точки посреди строки находятся и с названием, и без (P256).
    func testТочкиПосредиСтроки() {
        let строка = "Встреча [Кафе](geo:51.50000,-0.12000) потом geo:51.60000,-0.20000 дальше"
        let точки = Geo.points(inText: строка)
        XCTAssertEqual(точки.count, 2)
        XCTAssertEqual(точки[0].point.title, "Кафе")
        XCTAssertEqual((строка as NSString).substring(with: точки[0].range),
                       "[Кафе](geo:51.50000,-0.12000)")
        XCTAssertEqual(точки[1].point.title, "")
        XCTAssertEqual(точки[1].point.at.latitude, 51.6, accuracy: 0.00001)
        XCTAssertTrue(Geo.points(inText: "просто текст").isEmpty)
    }

    /// Буква, набранная вплотную за кнопочкой, остаётся буквой (P256).
    func testБукваЗаТочкойНеТочка() {
        let строка = "geo:1.00000,2.00000"
        let поле = NSMutableAttributedString(string: "\u{FFFC}я", attributes: [DiaryEditor.lineKey: строка])
        XCTAssertEqual(DiaryEditor.plain(поле), строка + "я")
    }

    /// Координаты, скопированные из Карт Google и Apple, в любом виде (P258).
    func testКоординатыИзЧужихКарт() {
        func check(_ text: String, _ lat: Double, _ lon: Double, line: UInt = #line) {
            guard let f = Pasted.find(text) else { return XCTFail("не понято: \(text)", line: line) }
            XCTAssertEqual(f.at.latitude, lat, accuracy: 0.0001, line: line)
            XCTAssertEqual(f.at.longitude, lon, accuracy: 0.0001, line: line)
        }
        check("51.500729, -0.124625", 51.500729, -0.124625)
        check("51.50073° N, 0.12462° W", 51.50073, -0.12462)
        check("51,50073° с. ш., 0,12462° з. д.", 51.50073, -0.12462)
        check("51°30'02.6\"N 0°07'28.7\"W", 51.50072, -0.12464)
        check("geo:51.5,-0.12", 51.5, -0.12)
        check("51,5007 -0,1246", 51.5007, -0.1246)
        check("https://maps.apple.com/?ll=51.500729,-0.124625&q=Big%20Ben", 51.500729, -0.124625)
        check("https://www.google.com/maps/place/Big+Ben/@51.5007292,-0.1246254,17z", 51.5007292, -0.1246254)
        check("https://maps.google.com/?q=51.5007,-0.1246", 51.5007, -0.1246)
        // Google Карты (P292).
        check("51.500729,+-0.124625", 51.500729, -0.124625)
        check("\u{200E}51.500729, -0.124625\u{200E}", 51.500729, -0.124625)
        check("https://www.google.com/maps/search/51.500729,+-0.124625?entry=tts", 51.500729, -0.124625)
        XCTAssertEqual(Pasted.find("https://maps.apple.com/?ll=51.5,-0.12&q=Big%20Ben")?.title, "Big Ben")
        XCTAssertNil(Pasted.find("10 Downing St, London"))
        XCTAssertNotNil(Pasted.shortLink(in: "Биг-Бен https://maps.app.goo.gl/abc123"))
    }

    /// P380: шаг назад после броска снимка из полоски в текст возвращает
    /// снимок в полоску — со страницы он не пропадает.
    func testШагНазадВозвращаетСнимокВПолоску() {
        XCTAssertEqual(DayStore.attachmentLinks(in: "Утро\n![](../../Photos/a.heic)\n[Голос](../../Audio/b.m4a)"),
                       ["../../Photos/a.heic", "../../Audio/b.m4a"])
    }

    /// P380: из полоски в текст — своей строкой за абзацем; снимок к
    /// снимкам — рядом в ту же строку; на пустую строку — на неё саму.
    func testИзПолоскиВТекстСвоейСтрокой() {
        let голос = "[Голос](../../Audio/b.m4a)"
        XCTAssertEqual(DiaryEditor.putting(голос, at: 3, into: "Утро.\nВечер.").0,
                       "Утро.\n" + голос + "\nВечер.")
        let снимок = "![](../../Photos/c.heic)"
        XCTAssertEqual(DiaryEditor.putting(снимок, at: 2, into: "![](../../Photos/a.heic)\nВечер.").0,
                       "![](../../Photos/a.heic) " + снимок + "\nВечер.")
        XCTAssertEqual(DiaryEditor.putting(голос, at: 6, into: "Утро.\n\nВечер.").0,
                       "Утро.\n" + голос + "\nВечер.")
    }

    // P392: одно вложение — одна строка. Строка, где кроме вложения
    // только пробелы, — чистая; с буквами — нет.
    func testВложениеСвоейСтрокой() {
        let clean = "Утро.\n\u{FFFC}\nВечер." as NSString
        XCTAssertFalse(DiaryEditor.Coordinator.mixed(
            clean, objects: [6], in: clean.paragraphRange(for: NSRange(location: 6, length: 0))))
        let twoPhotos = "\u{FFFC} \u{FFFC}\n" as NSString
        XCTAssertFalse(DiaryEditor.Coordinator.mixed(
            twoPhotos, objects: [0, 2], in: twoPhotos.paragraphRange(for: NSRange(location: 0, length: 0))))
        let typed = "Утро.\n\u{FFFC}ы\nВечер." as NSString
        XCTAssertTrue(DiaryEditor.Coordinator.mixed(
            typed, objects: [6], in: typed.paragraphRange(for: NSRange(location: 6, length: 0))))
    }
}
