import SwiftUI

/// Мультфильм первого запуска (P1057, автор: «первое — подходит
/// раскадровка; подписи — на соответствующем языке; показывать самым
/// первым, до папки; курс жестов убрать»; **отменяет** курс жестов P1036
/// и его строку в настройках P1041). Четыре секунды из той же бумаги, что
/// приложение: лист «Сегодня»; вверх из него выезжает прошлое, вниз —
/// будущее; влево — карта, вправо — календарь; крест чуть ходит вверх и
/// влево, показывая, что по нему ездят; лист «Сегодня» приближается во
/// весь экран — и мультфильм тает. Касание — пропустить.
///
/// Рисуется самим приложением, а не видеофайлом: по гамме, в ночном виде,
/// на языке телефона. Помнит телефон, а не папка: это не запись человека.
final class Intro: ObservableObject {

    static let shared = Intro()

    private static let seenKey = "intro.seen"

    /// Мультфильм уже видели (или пропустили).
    @Published private(set) var seen: Bool
    /// Запущен вручную — из настроек или пробы первого запуска.
    @Published private(set) var playing = false
    /// Для снимков экрана: собранный крест, без хода.
    @Published private(set) var still = false

    /// Что сделать, когда мультфильм кончился (проба первого запуска).
    private var then: (() -> Void)?

    private init() {
        seen = UserDefaults.standard.bool(forKey: Self.seenKey)
    }

    /// Показывать ли сейчас. Самым первым — пока папки нет и мультфильм не
    /// видели; в проверках и на снимках — только на своём снимке.
    func shown(noFolder: Bool) -> Bool {
        playing || (noFolder && !seen && !Vault.isUITest && !Vault.isPreview)
    }

    /// Из настроек и пробы первого запуска: сначала.
    func play(then: (() -> Void)? = nil) {
        self.then = then
        still = false
        playing = true
    }

    /// Досмотрели или пропустили.
    func finish() {
        guard !still else { return }
        playing = false
        if !seen {
            seen = true
            UserDefaults.standard.set(true, forKey: Self.seenKey)
        }
        let next = then
        then = nil
        next?()
    }

    /// Для снимков экрана: крест собран и стоит.
    func showStillForPreview() {
        still = true
        playing = true
    }

    /// Снимок мультфильма кончился — на других снимках его нет.
    func endPreview() {
        guard still else { return }
        still = false
        playing = false
    }
}

/// Сам мультфильм — поверх всего, во весь экран.
struct IntroFilm: View {

    @ObservedObject private var intro = Intro.shared
    /// «Уменьшение движения» в iPhone: вместо хода — неподвижный крест.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    /// Длина, с: собрать крест, показать ход, приблизить «Сегодня».
    static let length: Double = 4.0
    /// Крест собран и стоит — для «Уменьшения движения» и снимков.
    static let assembled: Double = 2.6
    /// Сколько стоит неподвижный крест при «Уменьшении движения», с.
    private static let stillHold: Double = 3.0

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: intro.still || reduceMotion)) { line in
                IntroFrame(t: time(at: line.date), size: geo.size)
            }
        }
        .background(Desk())
        .overlay(alignment: .bottom) {
            Text(T("Пропустить", "Skip"))
                .font(Look.sans(14))
                .foregroundStyle(Look.inkSoft)
                .padding(.bottom, 44)
                .allowsHitTesting(false)
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        .onTapGesture { intro.finish() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(T("Как устроено: вверху прошлое, внизу будущее, слева карта, справа календарь. Коснитесь, чтобы начать.",
                              "How it works: the past is above, the future below, the map on the left, the calendar on the right. Tap to begin."))
        .accessibilityAddTraits(.isButton)
        .onAppear { start = Date() }
        .task {
            guard !intro.still else { return }
            let hold = reduceMotion ? Self.stillHold : Self.length
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            guard !Task.isCancelled else { return }
            intro.finish()
        }
    }

    private func time(at date: Date) -> Double {
        if intro.still || reduceMotion { return Self.assembled }
        return min(Self.length, max(0, date.timeIntervalSince(start)))
    }
}

/// Один кадр мультфильма в миг `t` (с). Всё считается от `t`, без своих
/// анимаций: ход ровный, ничего не появляется разом (P893).
private struct IntroFrame: View {
    let t: Double
    let size: CGSize

    var body: some View {
        let w = min(size.width * 0.3, 140)
        let h = w * 1.42
        let gap: CGFloat = 14
        let cardH = h * 0.42
        let cardStep = cardH * 0.3

        // Раскадровка (P1057): 0–0,6 «Сегодня»; 0,6–1,6 прошлое и будущее;
        // 1,6–2,6 карта и календарь; 2,6–3,4 ход креста; 3,4–4 приближение.
        let born = ease(t, 0, 0.6)
        let row = ease(t, 1.6, 2.6)
        let up = bump(t, 2.6, 3.0)
        let left = bump(t, 3.0, 3.4)
        let zoom = ease(t, 3.4, 4.0)
        let rest = 1 - zoom

        let fill = max(size.width / w, size.height / h) * 1.15
        let scale = 1 + (fill - 1) * zoom
        let pan = CGSize(width: -left * w * 0.35, height: -up * h * 0.3)

        // Ближняя карточка — сразу над листом, дальние — выше и за ней.
        let nearPast = -(h / 2 + gap + cardH / 2)
        let pastTop = nearPast - 2 * cardStep - cardH / 2
        let side = w + gap

        ZStack {
            // Прошлое и будущее выезжают из-под листа, по очереди.
            ForEach((0..<3).reversed(), id: \.self) { i in
                let p = ease(t, 0.6 + 0.12 * Double(i), 1.36 + 0.12 * Double(i))
                IntroCard(past: true, tab: tabHeight(w))
                    .frame(width: w, height: cardH)
                    .offset(y: (nearPast - CGFloat(i) * cardStep) * p)
                    .opacity(Double(p * rest))
                IntroCard(past: false, tab: tabHeight(w))
                    .frame(width: w, height: cardH)
                    .offset(y: (-nearPast + CGFloat(i) * cardStep) * p)
                    .opacity(Double(p * rest))
            }
            IntroMap()
                .frame(width: w, height: h)
                .offset(x: -side * row)
                .opacity(Double(row * rest))
            IntroCalendar()
                .frame(width: w, height: h)
                .offset(x: side * row)
                .opacity(Double(row * rest))

            IntroToday(lines: Double(rest), tab: tabHeight(w) * 1.6)
                .frame(width: w, height: h)
                .scaleEffect(0.9 + 0.1 * born)
                .opacity(Double(born))

            // Подписи — на языке телефона, под своими частями.
            label(T("Прошлое", "Past"), width: w + gap)
                .offset(y: pastTop - 16)
                .opacity(Double(ease(t, 1.2, 1.6) * rest))
            label(T("Будущее", "Future"), width: w + gap)
                .offset(y: -pastTop + 16)
                .opacity(Double(ease(t, 1.2, 1.6) * rest))
            label(T("Карта", "Map"), width: w + gap)
                .offset(x: -side, y: h / 2 + 18)
                .opacity(Double(ease(t, 2.2, 2.6) * rest))
            label(T("Календарь", "Calendar"), width: w + gap)
                .offset(x: side, y: h / 2 + 18)
                .opacity(Double(ease(t, 2.2, 2.6) * rest))
        }
        .offset(pan)
        .scaleEffect(scale)
        .frame(width: size.width, height: size.height)
    }

    private func tabHeight(_ w: CGFloat) -> CGFloat { max(8, w * 0.08) }

    private func label(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(Look.sans(15, weight: .medium))
            .foregroundStyle(Look.inkSoft)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(width: width)
    }

    /// Плавно от 0 до 1 между `a` и `b`, без рывка в начале и в конце.
    private func ease(_ t: Double, _ a: Double, _ b: Double) -> CGFloat {
        let x = min(1, max(0, (t - a) / (b - a)))
        return CGFloat(x * x * (3 - 2 * x))
    }

    /// Туда и обратно между `a` и `b`: 0 → 1 → 0, без рывков.
    private func bump(_ t: Double, _ a: Double, _ b: Double) -> CGFloat {
        let x = min(1, max(0, (t - a) / (b - a)))
        return CGFloat((1 - cos(2 * .pi * x)) / 2)
    }
}

/// Лист «Сегодня» — той же формы, что лист «Дня» (P1051): корешок, мягкие
/// углы. Строчки плана тают, когда лист приближается.
private struct IntroToday: View {
    let lines: Double
    let tab: CGFloat
    private static let widths: [CGFloat] = [0.62, 0.48, 0.7, 0.4]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let shape = FolderShape(tabHeight: tab, tabShare: Search.tabShare, roundBottom: true, soft: true)
        ZStack(alignment: .topLeading) {
            ZStack {
                Scheme.current.today
                Image(uiImage: PageTexture.paper)
                    .resizable(resizingMode: .tile)
                    .opacity(scheme == .dark ? 0.2 : 0.3)
            }
            .clipShape(shape)
            GeometryReader { geo in
                VStack(alignment: .leading, spacing: geo.size.height * 0.09) {
                    ForEach(0..<4, id: \.self) { i in
                        Capsule()
                            .fill(Look.inkFaint.opacity(0.6))
                            .frame(width: geo.size.width * Self.widths[i], height: 3)
                    }
                }
                .padding(.top, tab + geo.size.height * 0.12)
                .padding(.leading, geo.size.width * 0.12)
                .opacity(lines)
            }
        }
        .shadow(color: .black.opacity(0.14), radius: 7, y: 3)
    }
}

/// Карточка картотеки: прошлое — старой бумагой, будущее — цвета
/// «сегодня» (P1050).
private struct IntroCard: View {
    let past: Bool
    let tab: CGFloat

    var body: some View {
        let shape = FolderShape(tabHeight: tab, tabShare: Search.tabShare, soft: true)
        shape
            .fill(past ? Scheme.current.past : Scheme.current.today)
            .overlay(shape.stroke(Scheme.current.kraftEdge.opacity(past ? 0.6 : 0.35), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.1), radius: 3, y: 1)
    }
}

/// Карта: зелень, две дороги и булавка.
private struct IntroMap: View {
    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Color(light: 0xE3E9D6, dark: 0x262A21)
                Path { p in
                    p.move(to: CGPoint(x: -4, y: h * 0.3))
                    p.addCurve(to: CGPoint(x: w + 4, y: h * 0.62),
                               control1: CGPoint(x: w * 0.4, y: h * 0.2),
                               control2: CGPoint(x: w * 0.5, y: h * 0.7))
                    p.move(to: CGPoint(x: w * 0.3, y: -4))
                    p.addCurve(to: CGPoint(x: w * 0.55, y: h + 4),
                               control1: CGPoint(x: w * 0.2, y: h * 0.4),
                               control2: CGPoint(x: w * 0.7, y: h * 0.6))
                }
                .stroke(Color.white.opacity(0.85), lineWidth: 3)
                Circle()
                    .fill(Look.pin)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .frame(width: 11, height: 11)
                    .position(x: w * 0.62, y: h * 0.42)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
    }
}

/// Календарь: месяц клетками, сегодня — чернилами.
private struct IntroCalendar: View {
    var body: some View {
        GeometryReader { geo in
            let pad = geo.size.width * 0.1
            let cell = (geo.size.width - pad * 2) / 7
            ZStack(alignment: .topLeading) {
                Scheme.current.today
                Capsule()
                    .fill(Look.inkFaint.opacity(0.6))
                    .frame(width: geo.size.width * 0.4, height: 3)
                    .offset(x: pad, y: pad * 1.4)
                VStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(0..<7, id: \.self) { c in
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(r == 2 && c == 3 ? Look.accent : Scheme.current.past)
                                    .padding(1.5)
                                    .frame(width: cell, height: cell * 1.25)
                            }
                        }
                    }
                }
                .offset(x: pad, y: pad * 2.6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .shadow(color: .black.opacity(0.12), radius: 5, y: 2)
    }
}
