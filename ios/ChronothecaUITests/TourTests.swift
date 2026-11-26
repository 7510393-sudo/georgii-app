import XCTest

/// Робот-тестировщик (P1085, автор: «можешь сделать тест приложения, как
/// тестировщик?»). Проходит приложение, как человек, — календарь и месяцы
/// туда-сюда, свайп вбок, картотеку прошлого и будущего, будущий день,
/// карту, настройки поверх календаря, — а прогон «Тестировщик» пишет видео
/// симулятора. По видео разбираются скачки, перелёты и запоздания кадр за
/// кадром. Каждый шаг отмечается временем в `шаги.txt` (папка `TOUR_DIR`),
/// чтобы найти его на видео. Тур не судит — только проходит и отмечает;
/// судят постоянные проверки в `MovementTests`.
final class TourTests: XCTestCase {

    private var app: XCUIApplication!
    private var started = Date()

    override func setUp() {
        continueAfterFailure = true
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

    /// Шаг тура: время от начала, время на часах и что сделано.
    private func step(_ what: String) {
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = String(format: "%6.1f с  %@  %@\n", Date().timeIntervalSince(started), stamp, what)
        print("ШАГ " + line, terminator: "")
        guard let dir = ProcessInfo.processInfo.environment["TOUR_DIR"], !dir.isEmpty else { return }
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let url = URL(fileURLWithPath: dir).appendingPathComponent("шаги.txt")
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    /// Провести пальцем от точки до точки (доли экрана), как живой палец.
    private func drag(_ from: CGVector, _ to: CGVector, speed: CGFloat = 900) {
        app.coordinate(withNormalizedOffset: from)
            .press(forDuration: 0.08,
                   thenDragTo: app.coordinate(withNormalizedOffset: to),
                   withVelocity: XCUIGestureVelocity(speed), thenHoldForDuration: 0)
    }

    private func calendarTitle() -> String {
        app.staticTexts["calendarTitle"].firstMatch.label
    }

    func testTour() {
        app = XCUIApplication()
        app.launchEnvironment["CHRONOTHECA_PREVIEW"] = "1"
        app.launchEnvironment["CHRONOTHECA_UITEST"] = "1"
        app.launch()
        sleep(5)
        started = Date()
        step("начало: «Сегодня»")

        // Календарь — свайпом влево.
        drag(CGVector(dx: 0.85, dy: 0.55), CGVector(dx: 0.15, dy: 0.55))
        _ = wait(6) { openScreen == "calendar" }
        sleep(2)
        step("календарь открыт: \(calendarTitle())")

        // Месяцы — по сетке, туда-сюда, быстро и медленно.
        let moves: [(String, CGFloat, CGFloat, CGFloat)] = [
            ("вверх быстро", 0.55, 0.30, 1400), ("вверх быстро", 0.55, 0.30, 1400),
            ("вниз быстро", 0.30, 0.55, 1400), ("вниз медленно", 0.28, 0.58, 400),
            ("вниз коротко и быстро", 0.35, 0.42, 1600), ("вверх наполовину медленно", 0.50, 0.38, 300),
        ]
        for (what, from, to, speed) in moves {
            drag(CGVector(dx: 0.5, dy: from), CGVector(dx: 0.5, dy: to), speed: speed)
            sleep(2)
            step("месяц \(what) → \(calendarTitle())")
        }

        // Касание клетки — выбор дня.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.36, dy: 0.40)).tap()
        sleep(2)
        step("касание клетки")

        // Вбок поверх клеток — к «Сегодня».
        drag(CGVector(dx: 0.15, dy: 0.40), CGVector(dx: 0.85, dy: 0.40))
        _ = wait(6) { openScreen == "today" }
        sleep(2)
        step("свайп вбок по клеткам → \(openScreen)")

        // Картотека прошлого: лист вниз, карточка, закрыть.
        app.buttons["bottom.today"].firstMatch.tap()
        sleep(2)
        drag(CGVector(dx: 0.5, dy: 0.30), CGVector(dx: 0.5, dy: 0.85), speed: 700)
        sleep(3)
        step("картотека прошлого: \(openScreen)")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.45)).tap()
        sleep(3)
        step("карточка прошлого открыта: \(openScreen)")
        for _ in 0..<3 where openScreen != "search" {
            drag(CGVector(dx: 0.5, dy: 0.25), CGVector(dx: 0.5, dy: 0.75), speed: 1200)
            sleep(2)
        }
        step("карточка закрыта: \(openScreen)")
        app.buttons["bottom.today"].firstMatch.tap()
        sleep(3)
        step("«Сегодня» кнопкой: \(openScreen)")

        // Картотека будущего: лист вверх, карточка, касание дневника.
        drag(CGVector(dx: 0.5, dy: 0.80), CGVector(dx: 0.5, dy: 0.20), speed: 700)
        sleep(3)
        step("картотека будущего: \(openScreen)")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35)).tap()
        sleep(3)
        step("будущий день открыт: \(openScreen)")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.72)).tap()
        sleep(3)
        step("касание дневника будущего дня; клавиатура: \(app.keyboards.firstMatch.exists ? "да" : "нет")")
        app.buttons["bottom.today"].firstMatch.tap()
        sleep(3)
        step("«Сегодня»: \(openScreen)")

        // Карта и обратно.
        drag(CGVector(dx: 0.15, dy: 0.55), CGVector(dx: 0.85, dy: 0.55))
        _ = wait(6) { openScreen == "map" }
        sleep(3)
        step("карта: \(openScreen)")
        drag(CGVector(dx: 0.97, dy: 0.50), CGVector(dx: 0.30, dy: 0.50))
        sleep(3)
        step("с карты к дню: \(openScreen)")

        // Настройки поверх календаря: свайп по ним месяц не листает.
        app.buttons["bottom.calendar"].firstMatch.tap()
        _ = wait(6) { openScreen == "calendar" }
        sleep(2)
        let month = calendarTitle()
        app.buttons["corner.settings"].firstMatch.tap()
        sleep(3)
        step("настройки поверх календаря")
        drag(CGVector(dx: 0.5, dy: 0.55), CGVector(dx: 0.5, dy: 0.30), speed: 900)
        sleep(2)
        step("свайп по настройкам; месяц был \(month)")
        app.buttons["corner.settings"].firstMatch.tap()
        sleep(3)
        step("настройки закрыты; месяц \(calendarTitle())")
        step("конец")
    }
}
