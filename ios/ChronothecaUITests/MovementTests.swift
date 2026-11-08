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

    /// Прошлый день, открытый из картотеки, долистан до конца (P823): у
    /// автора низ листа иногда вставал посреди экрана, под ним — полоса
    /// чужой бумаги. Снимок — глазами.
    func testPastCardBottom() {
        launch()
        XCTAssertEqual(openDay, "today")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(wait(4) { openScreen == "search" }, "лента прошлого не открылась: \(openScreen)")
        sleep(2)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.62)).tap()
        XCTAssertTrue(wait(5) { openScreen == "today" && openDay != "today" },
                      "карточка не открыла прошлый день: \(openScreen) \(openDay)")
        sleep(2)
        save("12-прошлый-день-верх")
        for _ in 0..<5 { app.swipeUp() }
        sleep(2)
        save("13-прошлый-день-низ")
        let past = openDay
        note("прошлый день", "открыт \(past)")
        // Снизу прошедшего дня — картотека на его месте, не сегодня (P826).
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)),
                   withVelocity: .slow, thenHoldForDuration: 0.1)
        XCTAssertTrue(wait(4) { openScreen == "search" }, "снизу прошедшего дня не открылась картотека: \(openScreen)")
        XCTAssertEqual(openDay, past, "тяга снизу сменила день")
        sleep(1)
        save("14-прошлый-день-картотека-снизу")
    }

    /// Календарь стоит, где его оставили (P821): по замечанию к 248 год и
    /// месяц сами уходили на 2020-й. В замеры пишется, что в шапке после
    /// каждого шага.
    func testCalendarStaysPut() {
        launch()
        app.buttons["bottom.calendar"].firstMatch.tap()
        XCTAssertTrue(wait(6) { openScreen == "calendar" }, "календарь не открылся")
        sleep(2)
        let title = app.staticTexts["calendarTitle"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5), "нет шапки календаря")
        var steps: [String] = []
        func mark(_ what: String) { steps.append(what + " — " + title.label) }
        func flick(up: Bool) {
            let a = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.72 : 0.38))
            let b = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: up ? 0.38 : 0.72))
            a.press(forDuration: 0.05, thenDragTo: b, withVelocity: 1200, thenHoldForDuration: 0)
            sleep(2)
        }
        mark("открыт")
        let month = title.label
        flick(up: true); mark("месяц вверх")
        flick(up: false); mark("месяц вниз")
        XCTAssertEqual(title.label, month, "месяц не вернулся: \(steps)")
        app.buttons["kind.Год"].firstMatch.tap()
        sleep(2); mark("год")
        let year = title.label
        flick(up: true); mark("год вверх")
        flick(up: false); mark("год вниз")
        XCTAssertEqual(title.label, year, "год не вернулся: \(steps)")
        app.buttons["bottom.today"].firstMatch.tap()
        XCTAssertTrue(wait(6) { openScreen == "today" }, "«Дневник» не открылся")
        sleep(1)
        app.buttons["bottom.calendar"].firstMatch.tap()
        XCTAssertTrue(wait(6) { openScreen == "calendar" }, "календарь не открылся снова")
        sleep(2); mark("после «Дневника»")
        XCTAssertEqual(title.label, year, "год сбился после «Дневника»: \(steps)")
        app.buttons["kind.Месяц"].firstMatch.tap()
        sleep(2); mark("снова месяц")
        XCTAssertEqual(title.label, month, "месяц сбился: \(steps)")
        save("11-календарь")
        note("календарь", steps.joined(separator: " · "))
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

        // Требования — по часам самого приложения (P810): от нажатия до
        // открытого раздела и замирания главного потока на разделе. Часы
        // робота и время запуска только записываются: снимки стека
        // показали, что на большом архиве робот медлит сам — при запуске
        // iOS подключает к приложению службы VoiceOver для робота, а пока
        // он «нажимает» календарь, приложение почти не работает.
        // Карта собирается при первом открытии (P814) — это её цена, а не
        // архива: открыть её один раз до замера, считать только после.
        app.buttons["bottom.map"].firstMatch.tap()
        XCTAssertTrue(wait(15) { openScreen == "map" }, "карта не открылась")
        sleep(3)
        app.buttons["bottom.today"].firstMatch.tap()
        XCTAssertTrue(wait(10) { openScreen == "today" }, "«Дневник» не вернулся")
        sleep(2)
        traceFrom = traceText().count
        _ = sections("", shot: "big")
        for screen in ["calendar", "map", "today"] {
            if let own = ownTime(screen) {
                XCTAssertLessThan(own, 0.5, "\(screen) открывался в приложении \(own) с")
            } else {
                XCTFail("приложение не записало, как открылся \(screen)")
            }
            let stall = longestStall(screen)
            note("замирание " + screen, String(format: "%.2f с", stall))
            // Карта рисуется MapKit, и в симуляторе он сам держит экран до
            // полутора секунд и на маленьком образце (P812) — ей запас шире.
            let limit = screen == "map" ? 2.5 : 1.5
            XCTAssertLessThan(stall, limit, "на разделе \(screen) экран стоял \(stall) с")
        }
        save("06-большой-архив")
    }

    /// С какого знака файла замираний считать (P814): раньше — разогрев.
    private var traceFrom = 0

    private func traceText() -> String {
        guard let dir = ProcessInfo.processInfo.environment["MOTION_DIR"], !dir.isEmpty,
              let text = try? String(contentsOf: URL(fileURLWithPath: dir).appendingPathComponent("замирания.txt"),
                                     encoding: .utf8)
        else { return "" }
        return text
    }

    /// Сколько, по часам приложения, открывался раздел последний раз
    /// (строка «шаг calendar: 0.26 с» в файле замираний, `LaunchClock`).
    private func ownTime(_ screen: String) -> Double? {
        let text = String(traceText().dropFirst(traceFrom))
        let prefix = "шаг \(screen): "
        guard let line = text.split(separator: "\n").last(where: { $0.hasPrefix(prefix) }) else { return nil }
        return Double(line.dropFirst(prefix.count).split(separator: " ").first ?? "")
    }

    /// Самое долгое «экран стоял … (раздел)» в файле замираний (`LagWatch`).
    private func longestStall(_ screen: String) -> Double {
        let text = String(traceText().dropFirst(traceFrom))
        return text.split(separator: "\n")
            .filter { $0.hasSuffix("(\(screen))") }
            .compactMap { line -> Double? in
                guard let r = line.range(of: "экран стоял ") else { return nil }
                return Double(line[r.upperBound...].split(separator: " ").first ?? "")
            }
            .max() ?? 0
    }

    /// Открыть по очереди календарь, карту, «Дневник» кнопками внизу и
    /// записать, на что уходит время (P806): найти кнопку, нажать (робот
    /// ждёт, пока приложение затихнет), увидеть смену раздела, прочесть
    /// надпись на уже открытом разделе.
    private func sections(_ tag: String, shot: String) -> [(String, Double)] {
        var out: [(String, Double)] = []
        for (button, screen) in [("bottom.calendar", "calendar"),
                                 ("bottom.map", "map"), ("bottom.today", "today")] {
            // Снимок стека ровно на нажатии (P808): CI снимает его по файлу.
            if let dir = ProcessInfo.processInfo.environment["MOTION_DIR"], !dir.isEmpty {
                let want = URL(fileURLWithPath: dir).appendingPathComponent("want-\(shot)-\(screen)")
                try? Data().write(to: want)
                Thread.sleep(forTimeInterval: 0.8)
            }
            let t0 = Date()
            let target = app.buttons[button].firstMatch
            _ = target.exists
            let t1 = Date()
            target.tap()
            let t2 = Date()
            XCTAssertTrue(wait(10) { openScreen == screen }, "\(screen) не открылся")
            let t3 = Date()
            sleep(2)
            let t4 = Date()
            _ = openScreen
            let t5 = Date()
            let took = t3.timeIntervalSince(t0)
            note(tag + screen, String(format: "%.2f с (найти %.2f, нажать %.2f, увидеть %.2f, прочесть потом %.2f)",
                                      took, t1.timeIntervalSince(t0), t2.timeIntervalSince(t1),
                                      t3.timeIntervalSince(t2), t5.timeIntervalSince(t4)))
            out.append((screen, took))
        }
        return out
    }
}
