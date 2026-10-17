import Foundation
import WidgetKit

/// Дела сегодняшнего дня — виджету (P382). Виджет не видит папку человека;
/// приложение оставляет ему короткий список в общей папке группы
/// приложений. Группы нет (её заводят на developer.apple.com) — ничего не
/// пишется, виджет показывает дату и входы.
enum WidgetShare {

    static let group = "group.com.kobiashvili.diary"

    struct Shared: Codable {
        struct Task: Codable { var text: String; var time: String?; var done: Bool }
        var day: String
        var tasks: [Task]
    }

    static func publish(day: Date, rows: [PlanRow]) {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)
        else { return }
        // Пустые дела (только начатые) виджету не нужны (P470).
        let tasks = rows.filter { $0.isTask && !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }.map { Shared.Task(text: $0.text, time: $0.time, done: $0.done) }
        let shared = Shared(day: Vault.stamp(day), tasks: tasks)
        guard let data = try? JSONEncoder().encode(shared) else { return }
        try? data.write(to: dir.appendingPathComponent("today.json"), options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
