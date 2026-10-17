import SwiftUI

/// Подсказки для первого знакомства (P427).
///
/// Самое нужное в приложении спрятано в жестах: касание по номеру дела,
/// долгое нажатие, перенос снимка в текст, уголки сверху. Сам человек их
/// не найдёт. Поэтому при первых встречах с экраном на нём появляется
/// жёлтый стикер — по одному за раз, пока человек не скажет «понятно».
/// Показанные помнятся; все разом выключаются и включаются снова в
/// настройках.
///
/// Помнит их телефон, а не папка: это удобство приложения, а не запись
/// человека, и в архив оно не пишется.
final class Hints: ObservableObject {

    struct Hint: Equatable {
        let id: String
        let screen: Shell.Screen
        let title: String
        let text: String
        /// Когда показывать — не просто «экран открыт», а к месту (P452).
        var when: When = .always
    }

    enum When { case always, evening, afterPhoto }

    static let shared = Hints()

    /// По одной и к месту (P452): на странице дня сразу — только «листайте»:
    /// как обращаться с делами и записью, рассказывают образцы дней. Итоги
    /// дня — вечером, перенос снимка — после первого снимка, карта,
    /// календарь и поиск — при первом заходе туда.
    static var all: [Hint] {
        [
            Hint(id: "pages", screen: .today,
                 title: T("Листайте дни", "Turn the days"),
                 text: T("Проведите пальцем вбок — вчера и завтра. Там уже лежат образцы: так выглядит заполненный день. «Сегодня» внизу вернёт обратно.",
                         "Swipe sideways for yesterday and tomorrow. There are samples there: this is what a filled-in day looks like. “Today” at the bottom brings you back.")),
            Hint(id: "outcome", screen: .today,
                 title: T("Итоги дня", "How the day went"),
                 text: T("В дневнике под каждым делом — строка для итога: что вышло. Одно слово или фраза — и вечер записан.",
                         "In the diary, each task has a line for its outcome: how it went. A word or a phrase — and the evening is written."),
                 when: .evening),
            Hint(id: "photo", screen: .today,
                 title: T("Снимок — куда угодно", "Put a photo anywhere"),
                 text: T("Подержите снимок в полоске внизу и перенесите пальцем прямо в текст или под дело.",
                         "Hold a photo in the strip at the bottom and drag it straight into your text or under a task."),
                 when: .afterPhoto),
            Hint(id: "map", screen: .map,
                 title: T("Свои места", "Your places"),
                 text: T("Подержите палец на карте — встанет точка. Её можно назвать, выбрать значок и записать в день. Справа сверху — «Записи»: дни на карте с превью снимков.",
                         "Hold your finger on the map to drop a pin. Name it, pick an icon and add it to the day. At the top right — “Entries”: days on the map with photo previews.")),
            Hint(id: "calendar", screen: .calendar,
                 title: T("Все дни", "All your days"),
                 text: T("Точки под числом — в этот день есть записи. Коснитесь дня — откроется его страница.",
                         "Dots under a date mean entries that day. Tap a day to open its page.")),
            Hint(id: "search", screen: .search,
                 title: T("Где искать", "Where to search"),
                 text: T("Три точки справа сверху — искать только в плане или в дневнике, только снимки, видео, голос, файлы или места.",
                         "The three dots at top right: search only the plan or the diary, or only photos, video, voice, files or places.")),
        ]
    }

    private static let photoKey = "hints.photo"

    /// Человек положил первый снимок — пора подсказать, что его можно
    /// перенести пальцем.
    func photoAdded() {
        guard !UserDefaults.standard.bool(forKey: Self.photoKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.photoKey)
        photoTick += 1
    }
    @Published private(set) var photoTick = 0

    private static let seenKey = "hints.seen"
    private static let offKey = "hints.off"

    @Published private(set) var seen: Set<String>
    @Published private(set) var off: Bool
    /// Что на экране сейчас.
    @Published var shown: Hint?

    private init() {
        let d = UserDefaults.standard
        seen = Set(d.stringArray(forKey: Self.seenKey) ?? [])
        off = d.bool(forKey: Self.offKey)
    }

    /// Следующая непоказанная подсказка этого экрана.
    func next(for screen: Shell.Screen) -> Hint? {
        guard !off else { return nil }
        return Self.all.first { $0.screen == screen && !seen.contains($0.id) && ready($0) }
    }

    private func ready(_ hint: Hint) -> Bool {
        switch hint.when {
        case .always: return true
        case .evening: return Calendar.current.component(.hour, from: Date()) >= 18
        case .afterPhoto: return UserDefaults.standard.bool(forKey: Self.photoKey)
        }
    }

    /// «3 из 6» — сколько подсказок у этого экрана и какая по счёту.
    func place(of hint: Hint) -> (Int, Int) {
        // Подсказки приходят по одной и к месту — счёта «3 из 6» нет (P452).
        (1, 1)
    }

    func done(_ hint: Hint) {
        seen.insert(hint.id)
        UserDefaults.standard.set(Array(seen), forKey: Self.seenKey)
        shown = nil
    }

    func turnOff() {
        off = true
        UserDefaults.standard.set(true, forKey: Self.offKey)
        shown = nil
    }

    /// Из настроек: показать всё сначала.
    func startOver() {
        seen = []
        off = false
        UserDefaults.standard.removeObject(forKey: Self.seenKey)
        UserDefaults.standard.removeObject(forKey: Self.photoKey)
        UserDefaults.standard.set(false, forKey: Self.offKey)
    }

    /// Для снимков экрана: первая подсказка, как её увидят при первом запуске.
    func showFirstForPreview() {
        shown = Self.all.first
    }
}

/// Жёлтый стикер с подсказкой — приклеен полоской скотча, чуть наискось.
struct HintSticker: View {

    @ObservedObject var hints: Hints
    let hint: Hints.Hint

    var body: some View {
        let (n, total) = hints.place(of: hint)
        VStack(alignment: .leading, spacing: 8) {
            Text(hint.title)
                .font(Look.serif(17, weight: .semibold))
                .foregroundStyle(Look.ink)
            Text(hint.text)
                .font(Look.sans(14.5))
                .foregroundStyle(Look.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                Button(T("Больше не показывать", "Don’t show tips")) {
                    withAnimation(.easeOut(duration: 0.2)) { hints.turnOff() }
                }
                .font(Look.sans(12.5))
                .foregroundStyle(Look.inkFaint)
                Spacer(minLength: 4)
                if total > 1 {
                    Text(T("\(n) из \(total)", "\(n) of \(total)"))
                        .font(Look.mono(11.5))
                        .foregroundStyle(Look.inkFaint)
                }
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { hints.done(hint) }
                } label: {
                    Text(n < total ? T("Дальше", "Next") : T("Понятно", "Got it"))
                        .font(Look.sans(14, weight: .semibold))
                        .foregroundStyle(Look.accent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .overlay(Capsule().strokeBorder(Look.accent.opacity(0.6), lineWidth: 1.2))
                }
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .frame(maxWidth: 320, alignment: .leading)
        .background(Look.sticker)
        .overlay(Rectangle().strokeBorder(Look.stickerEdge, lineWidth: 1))
        // Полоска скотча сверху.
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.white.opacity(0.55))
                .overlay(Rectangle().strokeBorder(Color.black.opacity(0.06), lineWidth: 0.6))
                .frame(width: 74, height: 18)
                .rotationEffect(.degrees(-3))
                .offset(y: -9)
        }
        .shadow(color: .black.opacity(0.28), radius: 12, y: 6)
        .rotationEffect(.degrees(-1.5))
        .accessibilityElement(children: .contain)
    }
}

/// Слой подсказок поверх приложения. Подсказка появляется, только когда
/// экран спокоен: не открыты меню, настройки, листок переноса и клавиатура.
struct HintLayer: View {

    @ObservedObject private var hints = Hints.shared
    let screen: Shell.Screen
    let quiet: Bool

    var body: some View {
        ZStack {
            if let hint = hints.shown {
                // Касание мимо стикера — то же «понятно»: подсказка не
                // держит человека.
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.2)) { hints.done(hint) }
                    }
                HintSticker(hints: hints, hint: hint)
                    .padding(.horizontal, 28)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(hints.shown != nil)
        // Ушли на другой экран — его подсказка убирается, не считаясь
        // прочитанной: покажется, когда вернутся.
        .onChange(of: screen) { _, now in
            if let shown = hints.shown, shown.screen != now, !Vault.isPreview {
                hints.shown = nil
            }
        }
        .task(id: "\(screen)|\(quiet)|\(hints.shown?.id ?? "")|\(hints.seen.count)|\(hints.off)|\(hints.photoTick)") {
            await pick()
        }
    }

    /// Подождать, пока экран откроется и успокоится, — и показать следующую.
    @MainActor private func pick() async {
        guard hints.shown == nil, !Vault.isPreview else { return }
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        guard !Task.isCancelled, quiet, hints.shown == nil,
              let next = hints.next(for: screen) else { return }
        withAnimation(.easeOut(duration: 0.25)) { hints.shown = next }
    }
}
