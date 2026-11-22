import SwiftUI

/// Первое знакомство — пять жестов по очереди (P1036, автор: «вместо
/// стикеров на первых действиях человеку нужно пройти минимальный курс
/// молодого бойца: активная стрелочка с надписью предлагает сделать
/// свайп»; отменяет жёлтые стикеры P427, P452, P688 — «не в нашей
/// стилистике»). Сперва то, чего не найти самому: лист «Сегодня» вниз —
/// прошлое, вверх — будущее (автор согласился начинать с них); потом
/// календарь, карта и обратно в день. Шаг засчитывается, когда жест
/// сделан, — нажимать «понятно» не нужно. Как обращаться с делами и
/// записью, рассказывают образцы дней (P1035).
///
/// Помнит телефон, а не папка: это удобство приложения, а не запись
/// человека, и в архив оно не пишется.
final class Hints: ObservableObject {

    enum Step: Int, CaseIterable {
        case past, future, calendar, map, back

        var text: String {
            switch self {
            case .past: return T("Потяните лист вниз — прошлое", "Pull the sheet down for the past")
            case .future: return T("Потяните лист вверх — будущее", "Pull the sheet up for the future")
            case .calendar: return T("Смахните влево — календарь", "Swipe left for the calendar")
            case .map: return T("Смахните вправо — карта", "Swipe right for the map")
            case .back: return T("Ведите влево от правого края — обратно в день",
                                 "Drag left from the right edge to get back to the day")
            }
        }

        /// Куда показывает стрелка.
        var arrow: String {
            switch self {
            case .past: return "arrow.down"
            case .future: return "arrow.up"
            case .calendar, .back: return "arrow.left"
            case .map: return "arrow.right"
            }
        }

        var shift: CGSize {
            switch self {
            case .past: return CGSize(width: 0, height: 10)
            case .future: return CGSize(width: 0, height: -10)
            case .calendar, .back: return CGSize(width: -10, height: 0)
            case .map: return CGSize(width: 10, height: 0)
            }
        }
    }

    static let shared = Hints()

    private static let stepKey = "coach.step"

    /// Какой шаг впереди; все пройдены — `nil`.
    @Published private(set) var step: Step?
    /// Для снимков экрана: показать первый шаг сразу.
    @Published private(set) var forced = false

    private init() {
        let at = UserDefaults.standard.object(forKey: Self.stepKey) as? Int ?? 0
        step = Step(rawValue: at)
    }

    /// Жест сделан: если это ждали — следующий шаг.
    func did(_ done: Step) {
        guard step == done else { return }
        set(Step(rawValue: done.rawValue + 1))
    }

    /// «Пропустить»: курс больше не показывается.
    func skip() { set(nil) }

    /// Из настроек и пробной папки: всё сначала.
    func startOver() { set(.past) }

    private func set(_ next: Step?) {
        step = next
        UserDefaults.standard.set(next?.rawValue ?? Step.allCases.count, forKey: Self.stepKey)
    }

    /// Для снимков экрана: первый шаг, как его увидят при первом запуске.
    func showFirstForPreview() {
        step = .past
        forced = true
    }
}

/// Слой курса поверх приложения: стрелка, которая сама показывает жест, и
/// одна строка; внизу — «Пропустить». Палец проходит сквозь — жест делают
/// по самому экрану. Появляется, когда экран спокоен и стоит там, где жест
/// можно сделать; уходит, как только жест сделан, — плавно (P893).
struct HintLayer: View {

    @ObservedObject private var hints = Hints.shared
    let screen: Shell.Screen
    /// Лист дня стоит, картотека закрыта, на листе сегодня.
    let restingToday: Bool
    /// Открыта картотека — с какой стороны; `nil` — закрыта.
    let file: Deck.Side?
    let quiet: Bool

    @State private var ready = false
    @State private var swing = false

    var body: some View {
        let step = hints.step
        let fits = step.map(fitsHere) ?? false
        let shown = (hints.forced || (fits && quiet && ready)) && step != nil
        ZStack {
            if shown, let step {
                VStack(spacing: 14) {
                    // Стрелка и строка пропускают палец: жест делают прямо
                    // по ним.
                    Image(systemName: step.arrow)
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(Look.accent)
                        .offset(swing ? step.shift : .zero)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: swing)
                        .allowsHitTesting(false)
                    Text(step.text)
                        .font(Look.sans(16, weight: .medium))
                        .foregroundStyle(Look.ink)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .allowsHitTesting(false)
                    // «Пропустить» — единственное, что нажимается.
                    Button(T("Пропустить", "Skip")) {
                        withAnimation(.easeOut(duration: 0.25)) { hints.skip() }
                    }
                    .font(Look.sans(13))
                    .foregroundStyle(Look.inkSoft)
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .background {
                    RoundedRectangle(cornerRadius: 16).fill(Look.sticker.opacity(0.96))
                        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Look.stickerEdge, lineWidth: 0.8))
                        .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                        .allowsHitTesting(false)
                }
                .padding(.horizontal, 40)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .onAppear { swing = true }
                .onDisappear { swing = false }
                .accessibilityElement(children: .contain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.3), value: shown)
        .animation(.easeOut(duration: 0.3), value: step)
        .onChange(of: screen, initial: true) { _, now in
            switch now {
            case .calendar: hints.did(.calendar)
            case .map: hints.did(.map)
            case .today: hints.did(.back)
            default: break
            }
        }
        .onChange(of: file, initial: true) { _, side in
            if side == .past { hints.did(.past) }
            if side == .future { hints.did(.future) }
        }
        // Экран успокоился — подсказка через мгновение, а не посреди хода.
        .task(id: "\(screen)|\(restingToday)|\(file.map { "\($0.rawValue)" } ?? "-")|\(step?.rawValue ?? -1)") {
            ready = false
            try? await Task.sleep(nanoseconds: 900_000_000)
            guard !Task.isCancelled else { return }
            ready = true
        }
    }

    /// Шаг можно сделать отсюда.
    private func fitsHere(_ step: Hints.Step) -> Bool {
        // Ни в проверках, ни на снимках экрана (и для App Store) — только
        // на снимке самого курса.
        guard (!Vault.isUITest && !Vault.isPreview) || hints.forced else { return false }
        switch step {
        case .past, .future, .calendar: return screen == .today && restingToday && file == nil
        case .map: return screen == .calendar || (screen == .today && restingToday && file == nil)
        case .back: return screen == .map
        }
    }
}
