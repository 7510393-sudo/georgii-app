import Foundation

// Нижний слой (P970): без экрана, только Foundation.

/// След жестов для проверок движения (P787): только когда приложение
/// запустила проверка и назвала файл. По нему видно, на каком шаге свайп
/// или порог ленты отказали, а не гадать.
enum Trace {
    private static var last = ""

    static func note(_ line: String) {
        guard Vault.isUITest,
              let path = ProcessInfo.processInfo.environment["CHRONOTHECA_TRACE"], !path.isEmpty,
              line != last
        else { return }
        last = line
        let url = URL(fileURLWithPath: path)
        let text = String(format: "%.2f ", Date().timeIntervalSince(LaunchClock.start)) + line + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// Сколько шёл запуск и открывались разделы — по шагам (P581).
///
/// Видно в «Проверке скорости» (долгое нажатие на «Версия» в настройках)
/// и пишется в итог проверок движения: по шагам видно, на чём стоит
/// экран, а не только сколько всего.
enum LaunchClock {
    /// Начало отсчёта — создание приложения.
    static let start = Date()
    private(set) static var lines: [String] = []

    static func step(_ name: String) {
        let line = String(format: "%@: %.2f с", name, Date().timeIntervalSince(start))
        record(line)
    }

    /// Раздел открыт: от касания до первого такта после смены экрана.
    static func opened(_ name: String, since tap: Date) {
        DispatchQueue.main.async {
            record(String(format: "%@: %.2f с", name, Date().timeIntervalSince(tap)))
        }
    }

    private static func record(_ line: String) {
        lines.append(line)
        if lines.count > 40 { lines.removeFirst(lines.count - 40) }
        guard Vault.isUITest,
              let path = ProcessInfo.processInfo.environment["CHRONOTHECA_TRACE"], !path.isEmpty
        else { return }
        let url = URL(fileURLWithPath: path)
        let text = "шаг " + line + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
