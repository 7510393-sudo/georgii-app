import Foundation

/// След отметки времени (P956): что поле решило про время — поставило,
/// убрало, не стало и почему. Отметка у надиктованной строки пропадала
/// снова и снова (P711, P766, P869, P881), а на сервере диктовку не
/// повторить: решения видны только на телефоне человека. Последние строки
/// — в «Замерах скорости» (долгое нажатие на «Версия»). Только в памяти,
/// в файл не пишется, текста записи не содержит.
enum StampTrace {
    private(set) static var lines: [String] = []
    private static var last = ""

    static func note(_ line: String) {
        guard line != last else { return }
        last = line
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        lines.append(f.string(from: Date()) + " " + line)
        if lines.count > 40 { lines.removeFirst(lines.count - 40) }
    }
}
