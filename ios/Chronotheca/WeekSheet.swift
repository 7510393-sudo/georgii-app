import SwiftUI

/// Неделя одним взглядом (P466): семь дней недели, в которой открытый
/// день, — сколько дел сделано, заголовок записи и снимки недели сверху.
/// Без оценок и упрёков: пустой день — просто пустая строка.
struct WeekSheet: View {
    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var archive: Archive
    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var shell: Shell

    private var cal: Calendar { Prefs.calendar }

    private var days: [Date] {
        guard let week = cal.dateInterval(of: .weekOfYear, for: store.date) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: week.start) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    photos
                    ForEach(days, id: \.self) { date in row(date) }
                }
                .padding(18)
            }
            .background(Look.diaryBg)
            .navigationTitle(T("Неделя", "The week"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("Закрыть", "Close")) { shell.showingWeek = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Три снимка недели — первые попавшиеся по порядку дней.
    @ViewBuilder private var photos: some View {
        let shots: [(link: String, date: Date)] = days.flatMap { date in
            (archive.day(Vault.stamp(date))?.attachments ?? [])
                .filter { Diary.kind(of: $0) == .photo }
                .map { (link: $0, date: date) }
        }
        if !shots.isEmpty {
            HStack(spacing: 8) {
                ForEach(Array(shots.prefix(3).enumerated()), id: \.offset) { _, shot in
                    PhotoThumb(url: vault.mediaURL(shot.link, for: shot.date))
                        .frame(width: 100, height: 100)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }

    private func row(_ date: Date) -> some View {
        let day = archive.day(Vault.stamp(date))
        let tasks = (day?.tasks ?? []).filter { $0.isTask }
        let done = tasks.filter(\.done).count
        return Button {
            shell.showingWeek = false
            store.go(to: date)
            shell.landOnDiary = false
            shell.landing += 1
            shell.screen = .today
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                // Число, справа день недели — как в «Списке» (P467).
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(cal.component(.day, from: date))")
                        .font(Look.mono(15))
                        .foregroundStyle(Look.ink)
                    Text(Ru.weekdayShort(date))
                        .font(Look.sans(10))
                        .foregroundStyle(Ru.dayColor(date))
                }
                .frame(width: 56, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    if let title = day?.title, !title.isEmpty {
                        Text(Geo.stripped(title))
                            .font(Look.serif(16, weight: .semibold))
                            .foregroundStyle(Look.ink)
                            .lineLimit(1)
                    }
                    Text(tasks.isEmpty ? "—" : T("Дела: \(done) из \(tasks.count)",
                                                 "Tasks: \(done) of \(tasks.count)"))
                        .font(Look.sans(13))
                        .foregroundStyle(Look.inkSoft)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
