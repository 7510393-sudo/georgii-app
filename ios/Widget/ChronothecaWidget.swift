import SwiftUI
import WidgetKit

/// Виджет «Сегодня» (P382): дата дня и вход в план или дневник одним
/// касанием. Дела дня виджет показывает, только если приложение может
/// оставить ему их список в общей папке (группа приложений) — её заводит
/// автор на developer.apple.com. Нет её — виджет показывает дату и входы.
///
/// Записи виджет не читает и не хранит: папка человека ему недоступна,
/// он видит только короткий список дел на сегодня, который кладёт само
/// приложение.
@main
struct ChronothecaWidgets: WidgetBundle {
    var body: some Widget {
        TodayWidget()
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "today", provider: TodayProvider()) { entry in
            TodayView(entry: entry)
        }
        .configurationDisplayName(Words.ru ? "Сегодня" : "Today")
        .description(Words.ru ? "Дата и дела дня; касание — план или дневник."
                              : "The date and today’s tasks; tap for the plan or the diary.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular])
    }
}

/// Слова виджета — по-русски или по-английски, по языку телефона: свои
/// переводы приложения виджету не видны.
enum Words {
    static var ru: Bool { Locale.preferredLanguages.first?.hasPrefix("ru") == true }
    static var plan: String { ru ? "План" : "Plan" }
    static var diary: String { ru ? "Дневник" : "Diary" }
    static var empty: String { ru ? "Дел на сегодня нет" : "Nothing planned today" }
}

/// То, что кладёт приложение: дела сегодняшнего дня.
struct Shared: Codable {
    struct Task: Codable { var text: String; var time: String?; var done: Bool }
    var day: String
    var tasks: [Task]

    static let group = "group.com.kobiashvili.diary"

    static func load() -> Shared? {
        guard let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
              let data = try? Data(contentsOf: dir.appendingPathComponent("today.json")),
              let got = try? JSONDecoder().decode(Shared.self, from: data)
        else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return got.day == f.string(from: Date()) ? got : nil
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let shared: Shared?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { TodayEntry(date: Date(), shared: nil) }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: Date(), shared: Shared.load()))
    }

    /// Новая запись — в полночь: виджет сам переходит на следующий день.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let midnight = Calendar.current.date(byAdding: .day, value: 1,
                                             to: Calendar.current.startOfDay(for: now)) ?? now
        completion(Timeline(entries: [TodayEntry(date: now, shared: Shared.load())],
                            policy: .after(midnight)))
    }
}

struct TodayView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private static let paper = Color(red: 0.98, green: 0.92, blue: 0.86)
    private static let ink = Color(red: 0.16, green: 0.2, blue: 0.27)
    private static let accent = Color(red: 0.2, green: 0.29, blue: 0.43)
    /// Сколько дел помещается в большой виджет — строка с чертой под ней.
    private static let largeRows = 9

    private var weekday: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("EEEE")
        return f.string(from: entry.date).capitalized
    }

    private var dayMonth: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate("d MMMM")
        return f.string(from: entry.date)
    }

    private var day: String { "\(Calendar.current.component(.day, from: entry.date))" }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Text(day)
                .font(.system(size: 26, weight: .semibold, design: .serif))
                .widgetURL(URL(string: "chronotheca://today/plan"))
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text(weekday + ", " + dayMonth).font(.headline)
                Text(summary).font(.caption).lineLimit(2)
            }
            .widgetURL(URL(string: "chronotheca://today/plan"))
            .containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            HStack(alignment: .top, spacing: 14) {
                dateBlock
                VStack(alignment: .leading, spacing: 6) {
                    if let tasks = entry.shared?.tasks {
                        if tasks.isEmpty {
                            Text(Words.empty).font(.subheadline).foregroundStyle(Self.ink.opacity(0.6))
                        }
                        ForEach(Array(tasks.prefix(4).enumerated()), id: \.offset) { _, t in
                            HStack(spacing: 6) {
                                Image(systemName: t.done ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(Self.accent)
                                if let time = t.time {
                                    Text(time).font(.caption.monospacedDigit()).foregroundStyle(Self.ink.opacity(0.6))
                                }
                                Text(t.text).font(.subheadline).lineLimit(1)
                                    .strikethrough(t.done)
                                    .foregroundStyle(Self.ink.opacity(t.done ? 0.5 : 1))
                            }
                        }
                        Spacer(minLength: 0)
                    } else {
                        Spacer(minLength: 0)
                        door(Words.plan, "checklist", "plan")
                        door(Words.diary, "book", "diary")
                        Spacer(minLength: 0)
                    }
                }
                Spacer(minLength: 0)
            }
            .widgetURL(URL(string: "chronotheca://today/plan"))
            .containerBackground(for: .widget) { Self.paper }
        case .systemLarge:
            // Большой виджет (P470): дата сверху, ниже дела дня — по строке
            // на дело, только текст, без времени. Сделанное — зачёркнуто.
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(day)
                        .font(.system(size: 34, weight: .semibold, design: .serif))
                        .foregroundStyle(Self.ink)
                    Text(dayMonth + ", " + weekday.lowercased())
                        .font(.system(size: 15))
                        .foregroundStyle(Self.ink.opacity(0.65))
                }
                if let tasks = entry.shared?.tasks {
                    if tasks.isEmpty {
                        Text(Words.empty).font(.subheadline).foregroundStyle(Self.ink.opacity(0.6))
                    }
                    ForEach(Array(tasks.prefix(Self.largeRows).enumerated()), id: \.offset) { _, t in
                        Text(t.text)
                            .font(.system(size: 16))
                            .lineLimit(1)
                            .strikethrough(t.done)
                            .foregroundStyle(Self.ink.opacity(t.done ? 0.45 : 1))
                        Divider().overlay(Self.ink.opacity(0.08))
                    }
                    if tasks.count > Self.largeRows {
                        Text("+\(tasks.count - Self.largeRows)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Self.accent)
                    }
                } else {
                    door(Words.plan, "checklist", "plan")
                    door(Words.diary, "book", "diary")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .widgetURL(URL(string: "chronotheca://today/plan"))
            .containerBackground(for: .widget) { Self.paper }
        default:
            dateBlock
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .widgetURL(URL(string: "chronotheca://today/plan"))
                .containerBackground(for: .widget) { Self.paper }
        }
    }

    private var summary: String {
        guard let tasks = entry.shared?.tasks else { return "Chronotheca" }
        guard !tasks.isEmpty else { return Words.empty }
        let done = tasks.filter(\.done).count
        return "\(done)/\(tasks.count) · " + (tasks.first { !$0.done }?.text ?? tasks[0].text)
    }

    private var dateBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(weekday)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color(red: 0.7, green: 0.25, blue: 0.22))
            Text(day)
                .font(.system(size: 46, weight: .semibold, design: .serif))
                .foregroundStyle(Self.ink)
            Text(dayMonth)
                .font(.system(size: 13))
                .foregroundStyle(Self.ink.opacity(0.65))
            if family == .systemSmall, let tasks = entry.shared?.tasks, !tasks.isEmpty {
                Text("\(tasks.filter(\.done).count)/\(tasks.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Self.accent)
            }
        }
    }

    private func door(_ title: String, _ icon: String, _ tab: String) -> some View {
        Link(destination: URL(string: "chronotheca://today/" + tab)!) {
            Label(title, systemImage: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Self.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Self.accent.opacity(0.1), in: Capsule())
        }
    }
}
