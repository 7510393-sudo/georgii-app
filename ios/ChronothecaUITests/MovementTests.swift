import XCTest

/// Проверки движения (P552): то, что прежде ломалось незаметно для снимков —
/// ход экрана с клавиатурой, «Сегодня», свайп разделов, лишние строки кнопок.
/// Приложение запускается на образцах дней, как для снимков экрана.
///
/// Снимки экрана с клавиатурой кладутся в папку, которую называет
/// переменная `MOTION_DIR` (в CI — `TEST_RUNNER_MOTION_DIR`): CI переносит
/// их в `docs/motion/`.
final class MovementTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
    }

    /// Запуск на образцах. Экран снимков ставится ещё раз через 1,5 и 4
    /// секунды (P448) — поэтому трогать приложение только после этого.
    /// `trace` — имя файла следа жестов в папке снимков (P787).
    private func launch(_ screen: String = "", big: Bool = false, trace: String = "") {
        app = XCUIApplication()
        app.launchEnvironment["CHRONOTHECA_PREVIEW"] = "1"
        app.launchEnvironment["CHRONOTHECA_UITEST"] = "1"
        if big {
            app.launchEnvironment["CHRONOTHECA_BIG"] = "1"
            // Замирания экрана — изнутри приложения (P573).
            if let dir = ProcessInfo.processInfo.environment["MOTION_DIR"], !dir.isEmpty {
                app.launchEnvironment["CHRONOTHECA_TRACE"] = dir + "/замирания.txt"
            }
        }
        if !screen.isEmpty { app.launchEnvironment["CHRONOTHECA_SCREEN"] = screen }
        if !trace.isEmpty, let dir = ProcessInfo.processInfo.environment["MOTION_DIR"], !dir.isEmpty {
            app.launchEnvironment["CHRONOTHECA_TRACE"] = dir + "/" + trace + ".txt"
        }
        app.launch()
        sleep(5)
    }

    private var openScreen: String {
        app.staticTexts["openScreen"].firstMatch.label
    }

    private func wait(_ seconds: TimeInterval, until check: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if check() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return check()
    }

    private func note(_ name: String, _ text: String) {
        print("ЗАМЕР \(name): \(text)")
        guard let dir = ProcessInfo.processInfo.environment["MOTION_DIR"], !dir.isEmpty else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("замеры.txt")
        let line = name + ": " + text + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Какой день открыт: «today» или число секунд.
    private var openDay: String {
        app.staticTexts["openDay"].firstMatch.label
    }

    private func waitDay(_ check: @escaping (String) -> Bool, _ seconds: TimeInterval = 6) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if check(openDay) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return check(openDay)
    }

    private func raiseKeyboard() -> Bool {
        let text = app.textViews["diaryText"].firstMatch
        guard text.waitForExistence(timeout: 5) else { return false }
        text.tap()
        guard app.keyboards.firstMatch.waitForExistence(timeout: 5) else { return false }
        sleep(2)
        return true
    }

    private func save(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let keep = XCTAttachment(screenshot: shot)
        keep.name = name
        keep.lifetime = .keepAlways
        add(keep)
        guard let dir = ProcessInfo.processInfo.environment["MOTION_DIR"], !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try? shot.pngRepresentation.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
    }

    /// «Сегодня» с прошедшего дня возвращает на сегодня (P548).
    func testTodayReturnsFromPast() {
        launch("past")
        XCTAssertNotEqual(openDay, "today", "образец «вчера» не открылся")
        app.buttons["bottom.today"].firstMatch.tap()
        XCTAssertTrue(waitDay { $0 == "today" }, "«Сегодня» не вернуло на сегодня: \(openDay)")
        save("01-сегодня-после-вчера")
    }

    /// Раздел помнит, где его оставили (P576): с прошлого дня — на карту и
    /// обратно, день тот же; второе нажатие — на сегодня.
    func testTodayRemembersDay() {
        launch("past")
        let past = openDay
        XCTAssertNotEqual(past, "today", "образец «вчера» не открылся")
        app.buttons["bottom.map"].firstMatch.tap()
        XCTAssertTrue(wait(6) { openScreen == "map" }, "карта не открылась")
        app.buttons["bottom.today"].firstMatch.tap()
        XCTAssertTrue(wait(6) { openScreen == "today" }, "«Сегодня» не открылось")
        sleep(1)
        XCTAssertEqual(openDay, past, "после карты «Сегодня» не вернуло на прежний день")
        app.buttons["bottom.today"].firstMatch.tap()
        XCTAssertTrue(waitDay { $0 == "today" }, "второе нажатие не вернуло на сегодня: \(openDay)")
    }

    /// С клавиатурой над ней только «＋» (P615, P799: строки разделов нет).
    func testKeyboardKeepsScreen() {
        launch("diary")
        XCTAssertTrue(raiseKeyboard(), "клавиатура не поднялась")
        save("02-клавиатура-дневник")
        // Где приставка и уголки над клавиатурой (P614).
        let why = app.staticTexts["cornerWhy"].firstMatch
        note("уголки", why.exists ? why.label : "нет строки")
        // Разделов над клавиатурой больше нет — только «＋» (P799).
        let keys = app.buttons.matching(identifier: "keys.today").allElementsBoundByIndex
        XCTAssertEqual(keys.count, 0, "разделы над клавиатурой: \(keys.count)")
        let keyboardPlus = app.buttons.matching(identifier: "keyboard.plus").allElementsBoundByIndex
            .filter { $0.isHittable }
        XCTAssertEqual(keyboardPlus.count, 1, "«＋» над клавиатурой: \(keyboardPlus.count)")
        let pagePlus = app.buttons.matching(identifier: "strip.plus").allElementsBoundByIndex
            .filter { $0.isHittable }
        XCTAssertEqual(pagePlus.count, 0, "«＋» страницы виден вместе с клавиатурой")
    }

    /// Лента картотеки (P777) тянется из дня настоящим пальцем: вниз за
    /// верх — прошлое, к дню через порог (P779) — назад в день, вверх за низ —
    /// будущее. Снимки — чтобы видеть стык дня и карточек.
    func testRibbonFromDay() {
        launch(trace: "след-лента")
        XCTAssertEqual(openDay, "today")
        let top = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
        top.press(forDuration: 0.05,
                  thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)),
                  withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(wait(4) { openScreen == "search" }, "лента прошлого не открылась: \(openScreen)")
        sleep(1)
        save("07-лента-прошлое")
        // К дню — через порог (P779): чуть потянули — лента у стены, день
        // не выехал; дотянули — назад в день.
        let low = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        low.press(forDuration: 0.05,
                  thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.66)),
                  withVelocity: .slow, thenHoldForDuration: 0.1)
        sleep(1)
        XCTAssertEqual(openScreen, "search", "день выехал без порога")
        save("08-лента-у-стены")
        low.press(forDuration: 0.05,
                  thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)),
                  withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(wait(4) { openScreen == "today" }, "за порогом лента не вернула в день: \(openScreen)")
        sleep(1)
        save("09-лента-снова-день")
        // Будущее — вверх за низ листа: сперва долистать лист до конца.
        for _ in 0..<4 { app.swipeUp() }
        sleep(1)
        let bottom = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
        bottom.press(forDuration: 0.05,
                     thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)),
                     withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(wait(4) { openScreen == "search" }, "лента будущего не открылась: \(openScreen)")
        sleep(1)
        save("10-лента-будущее")
    }

    /// Разделы — лента вбок (P799, без круга; P805 — карта слева): с
    /// «Дневника» влево — календарь, с календаря вправо — снова «Дневник»;
    /// вправо — карта; на карте с середины — ничего (палец двигает карту);
    /// от правого края влево — «Дневник». День при этом не перелистывается.
    func testSwipeSections() {
        launch(trace: "след-свайп")
        XCTAssertEqual(openScreen, "today")
        func swipe(_ from: CGFloat, _ to: CGFloat) {
            app.coordinate(withNormalizedOffset: CGVector(dx: from, dy: 0.55))
                .press(forDuration: 0.05,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: to, dy: 0.55)),
                       withVelocity: 1500,
                       thenHoldForDuration: 0)
        }
        swipe(0.8, 0.1)
        XCTAssertTrue(wait(6) { openScreen == "calendar" }, "свайп влево не открыл календарь: \(openScreen)")
        XCTAssertEqual(openDay, "today", "свайп перелистнул день")
        sleep(1)
        save("02-свайп-календарь")
        swipe(0.2, 0.9)
        XCTAssertTrue(wait(6) { openScreen == "today" }, "с календаря свайп не вернул «Дневник»: \(openScreen)")
        sleep(1)
        swipe(0.2, 0.9)
        XCTAssertTrue(wait(6) { openScreen == "map" }, "свайп вправо не открыл карту: \(openScreen)")
        sleep(2)
        save("02-свайп-карта")
        swipe(0.5, 0.95)
        sleep(1)
        XCTAssertEqual(openScreen, "map", "с середины карты свайп увёл с карты")
        swipe(0.985, 0.1)
        XCTAssertTrue(wait(6) { openScreen == "today" }, "от правого края карты не вернулся «Дневник»: \(openScreen)")
        XCTAssertEqual(openDay, "today", "свайп перелистнул день")
    }

    /// Свайп как живым пальцем (P787): палец лёг и чуть постоял, ведут с
    /// обычной скоростью — с дела в плане и с записи дневника. На телефоне
    /// свайп почти не брался, а быстрый свайп проверки проходил.
    func testSwipeLikeFinger() {
        launch(trace: "след-свайп-палец")
        XCTAssertEqual(openScreen, "today")
        for (row, name) in [(0.3, "дело"), (0.62, "запись")] {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: row))
                .press(forDuration: 0.12,
                       thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: row + 0.01)),
                       withVelocity: 500,
                       thenHoldForDuration: 0)
            XCTAssertTrue(wait(6) { openScreen == "calendar" }, "свайп с места «\(name)» не открыл календарь: \(openScreen)")
            sleep(1)
            app.buttons["bottom.today"].firstMatch.tap()
            XCTAssertTrue(wait(6) { openScreen == "today" }, "«День» не вернул")
            sleep(2)
        }
    }

    /// Пока пишут, быстрый свайп вбок тоже меняет раздел, клавиатура
    /// уходит (P778).
    func testSwipeWithKeyboard() {
        launch("diary")
        XCTAssertTrue(raiseKeyboard(), "клавиатура не поднялась")
        let start = openDay
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.3))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.3)),
                   withVelocity: 1500,
                   thenHoldForDuration: 0)
        XCTAssertTrue(wait(6) { openScreen == "calendar" }, "с клавиатурой свайп не открыл календарь: \(openScreen)")
        XCTAssertEqual(openDay, start, "свайп перелистнул день")
        sleep(2)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "клавиатура осталась в календаре")
        save("03-свайп-с-клавиатурой")
    }

    /// Вложения в конце записи — рядом внизу страницы (P665): снимок
    /// образца стоит в ряду, справа внизу — «＋», и её меню открывается.
    func testPlusOpensMenu() {
        launch("diary")
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Photo 1")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "снимка записи нет в ряду внизу")
        let plus = app.buttons["strip.plus"].firstMatch
        XCTAssertTrue(plus.waitForExistence(timeout: 5), "нет «＋» на странице")
        plus.tap()
        let camera = app.buttons.matching(NSPredicate(format: "label == %@", "Camera")).firstMatch
        XCTAssertTrue(camera.waitForExistence(timeout: 3), "меню «＋» не открылось")
        save("04-плюс-меню")
    }

    /// Большой архив (P567): десять лет дней. Приложение открывается и
    /// разделы отвечают так же быстро, как на маленьком.
    func testBigArchiveStaysQuick() {
        // Первый запуск складывает архив — его не мерим.
        launch(big: true)
        // Архив со вложениями пишется в стороне (P589) — ждать его.
        XCTAssertTrue(app.staticTexts["bigReady"].waitForExistence(timeout: 900), "архив не сложился")
        sleep(3)
        app.terminate()

        let start = Date()
        app.launch()
        XCTAssertTrue(app.buttons["bottom.calendar"].firstMatch.waitForExistence(timeout: 60))
        let opened = Date().timeIntervalSince(start)
        note("запуск", String(format: "%.2f с", opened))
        sleep(3)

        for (button, screen) in [("bottom.calendar", "calendar"),
                                 ("bottom.map", "map"), ("bottom.today", "today")] {
            let tap = Date()
            app.buttons[button].firstMatch.tap()
            XCTAssertTrue(wait(10) { openScreen == screen }, "\(screen) не открылся")
            let took = Date().timeIntervalSince(tap)
            note(screen, String(format: "%.2f с", took))
            XCTAssertLessThan(took, 1.5, "\(screen) открывался \(took) с")
            sleep(2)
        }
        save("06-большой-архив")
        XCTAssertLessThan(opened, 8, "запуск занял \(opened) с")
    }
}
