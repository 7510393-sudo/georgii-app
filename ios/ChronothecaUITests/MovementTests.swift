import XCTest

/// Проверки движения (P552): то, что прежде ломалось незаметно для снимков —
/// ход экрана с клавиатурой, «Сегодня», листание, лишние строки кнопок.
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
    private func launch(_ screen: String = "", big: Bool = false) {
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

    /// С клавиатурой разделы поднимаются над ней (P613; верхней строки нет):
    /// над клавиатурой одна строка разделов и одна строка вложений (P546).
    func testKeyboardKeepsScreen() {
        launch("diary")
        XCTAssertTrue(raiseKeyboard(), "клавиатура не поднялась")
        save("02-клавиатура-дневник")
        let keys = app.buttons.matching(identifier: "keys.today").allElementsBoundByIndex
            .filter { $0.isHittable }
        XCTAssertEqual(keys.count, 1, "разделов над клавиатурой: \(keys.count)")
        let keyboardRow = app.buttons.matching(identifier: "keyboard.camera").allElementsBoundByIndex
            .filter { $0.isHittable }
        XCTAssertEqual(keyboardRow.count, 1, "кнопок «камера» над клавиатурой: \(keyboardRow.count)")
        let pageRow = app.buttons.matching(identifier: "strip.camera").allElementsBoundByIndex
            .filter { $0.isHittable }
        XCTAssertEqual(pageRow.count, 0, "строка вложений страницы видна вместе с клавиатурой")
        // Раздел над клавиатурой открывается и убирает её.
        app.buttons["keys.map"].firstMatch.tap()
        XCTAssertTrue(wait(6) { openScreen == "map" }, "карта не открылась из строки над клавиатурой")
    }

    /// Лист берут за край (P532) — и без клавиатуры в любом месте (P549).
    func testPagingWithoutKeyboard() {
        launch()
        XCTAssertEqual(openDay, "today")
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.55))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.55)))
        XCTAssertTrue(waitDay { $0 != "today" }, "от края лист не перевернулся")
        app.buttons["bottom.today"].firstMatch.tap()
        XCTAssertTrue(waitDay { $0 == "today" }, "«Сегодня» после листания не вернуло")
        sleep(2)
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.55))
        middle.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.55)))
        XCTAssertTrue(waitDay { $0 != "today" }, "с середины без клавиатуры лист не перевернулся")
    }

    /// Пока пишут, быстрое движение с середины до края листает (P550).
    func testPagingWithKeyboard() {
        launch("diary")
        XCTAssertTrue(raiseKeyboard(), "клавиатура не поднялась")
        let start = openDay
        let middle = app.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.3))
        middle.press(forDuration: 0.05,
                     thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.3)),
                     withVelocity: 1500,
                     thenHoldForDuration: 0)
        XCTAssertTrue(waitDay { $0 != start }, "с клавиатурой быстрое движение к краю не перелистнуло")
        save("03-листание-с-клавиатурой")
    }

    /// Вложение в ленте (P561, P562): подержал — крестик, вложение не
    /// открылось; крестик — ровно одно окно вопроса; «убрать» — оно ушло, и
    /// второго окна нет.
    func testRemovingFromStripAsksOnce() {
        launch("diary")
        let photo = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Photo 1")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5), "в ленте нет снимка")
        for _ in 0..<4 where !photo.isHittable { app.swipeUp() }
        photo.press(forDuration: 0.8)
        let cross = app.buttons.matching(NSPredicate(format: "label == %@", "Remove")).firstMatch
        XCTAssertTrue(cross.waitForExistence(timeout: 3), "после долгого нажатия нет крестика")
        save("04-крестик-в-ленте")
        XCTAssertEqual(openScreen, "today", "долгое нажатие что-то открыло")
        cross.tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 3), "крестик не спросил")
        XCTAssertEqual(app.alerts.count, 1, "окон вопроса: \(app.alerts.count)")
        save("05-вопрос-об-удалении")
        app.alerts.firstMatch.buttons.matching(NSPredicate(format: "label == %@", "Remove from the page"))
            .firstMatch.tap()
        sleep(2)
        XCTAssertEqual(app.alerts.count, 0, "после ответа появилось ещё одно окно")
        XCTAssertFalse(photo.exists, "снимок остался в ленте")
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

        for (button, screen) in [("bottom.calendar", "calendar"), ("bottom.search", "search"),
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
