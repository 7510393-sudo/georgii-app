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
    private func launch(_ screen: String = "") {
        app = XCUIApplication()
        app.launchEnvironment["CHRONOTHECA_PREVIEW"] = "1"
        app.launchEnvironment["CHRONOTHECA_UITEST"] = "1"
        if !screen.isEmpty { app.launchEnvironment["CHRONOTHECA_SCREEN"] = screen }
        app.launch()
        sleep(5)
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

    private var topBar: XCUIElement {
        app.descendants(matching: .any)["topBar"].firstMatch
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
        app.buttons["top.today"].firstMatch.tap()
        XCTAssertTrue(waitDay { $0 == "today" }, "«Сегодня» не вернуло на сегодня: \(openDay)")
        save("01-сегодня-после-вчера")
    }

    /// Верхняя строка не сдвигается, когда поднимается клавиатура (P548),
    /// и над клавиатурой одна строка вложений (P546, P547).
    func testKeyboardKeepsScreen() {
        launch("diary")
        let before = topBar.frame
        XCTAssertFalse(before.isEmpty, "верхняя строка не найдена")
        XCTAssertTrue(raiseKeyboard(), "клавиатура не поднялась")
        save("02-клавиатура-дневник")
        XCTAssertEqual(topBar.frame.minY, before.minY, accuracy: 1, "верхняя строка сдвинулась с клавиатурой")
        let keyboardRow = app.buttons.matching(identifier: "keyboard.camera").allElementsBoundByIndex
            .filter { $0.isHittable }
        XCTAssertEqual(keyboardRow.count, 1, "кнопок «камера» над клавиатурой: \(keyboardRow.count)")
        let pageRow = app.buttons.matching(identifier: "strip.camera").allElementsBoundByIndex
            .filter { $0.isHittable }
        XCTAssertEqual(pageRow.count, 0, "строка вложений страницы видна вместе с клавиатурой")
    }

    /// Лист берут за край (P532) — и без клавиатуры в любом месте (P549).
    func testPagingWithoutKeyboard() {
        launch()
        XCTAssertEqual(openDay, "today")
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.97, dy: 0.55))
        edge.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.55)))
        XCTAssertTrue(waitDay { $0 != "today" }, "от края лист не перевернулся")
        app.buttons["top.today"].firstMatch.tap()
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
}
