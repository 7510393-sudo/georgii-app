import MapKit
import SwiftUI

/// Мультфильм первого запуска (P1057: самым первым, до папки, на языке
/// телефона; **отменяет** курс жестов P1036). С P1065 (автор: «сейчас это
/// неподвижная схема; нужна рамка-телефон, рука делает свайпы, крест
/// под рамкой ездит; экраны — настоящие, узнаваемые, только меньше»):
/// крест из уменьшенных настоящих экранов — над «Сегодня» прошлое, под ним
/// будущее, слева карта, справа календарь; посередине неподвижная
/// прозрачная рамка-телефон; рука смахивает, и крест едет под рамкой:
/// календарь, «Сегодня», прошлое, «Сегодня», будущее, «Сегодня», карта — и
/// на карте встаёт точка. Около 11 с. Касание — пропустить.
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
    @State private var start = Date()

    /// Длина, с: семь смахиваний, точка на карте, растворение.
    static let length: Double = IntroPlan.end
    /// Для снимка CI: середина первого смахивания — видны рука и ход креста.
    static let snapshotMoment: Double = IntroPlan.first + IntroPlan.reach + IntroPlan.swipe / 2

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(paused: intro.still)) { line in
                IntroFrame(t: time(at: line.date), size: geo.size)
            }
        }
        .background(Desk())
        .overlay(alignment: .bottom) {
            Text(T("Пропустить", "Skip"))
                .font(Look.sans(14))
                .foregroundStyle(Look.inkSoft)
                .padding(.bottom, 30)
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
            // Ход — всегда, и при «Уменьшении движения» (P1069): это урок,
            // который человек открыл сам, а не украшение; неподвижный кадр
            // ничего не объяснял.
            try? await Task.sleep(nanoseconds: UInt64(Self.length * 1_000_000_000))
            guard !Task.isCancelled else { return }
            intro.finish()
        }
    }

    private func time(at date: Date) -> Double {
        if intro.still { return Self.snapshotMoment }
        return min(Self.length, max(0, date.timeIntervalSince(start)))
    }
}

/// Раскадровка (P1065): где крест в каждый миг и что делает рука. Всё
/// считается от времени — ход ровный, ничего не появляется разом (P893).
enum IntroPlan {

    /// Место экрана в кресте, в экранах: x вправо, y вниз.
    typealias Spot = CGPoint

    static let today = Spot(x: 0, y: 0)
    static let calendar = Spot(x: 1, y: 0)
    static let map = Spot(x: -1, y: 0)
    static let past = Spot(x: 0, y: -1)
    static let future = Spot(x: 0, y: 1)

    /// Куда встаёт рамка после каждого смахивания. Влево — календарь,
    /// вправо — обратно; вниз — прошлое, вверх — «Сегодня», ещё вверх —
    /// будущее, вниз — «Сегодня»; вправо — карта.
    static let stops: [Spot] = [calendar, today, past, today, future, today, map]

    /// Крест проступает, с.
    static let first: Double = 0.8
    /// Рука подходит к экрану, с.
    static let reach: Double = 0.3
    /// Само смахивание, с.
    static let swipe: Double = 0.6
    /// Рука уходит, экран стоит, с.
    static let rest: Double = 0.55
    static var step: Double { reach + swipe + rest }
    /// Точка падает на карту.
    static var pinStart: Double { first + Double(stops.count) * step }
    static var pinEnd: Double { pinStart + 0.6 }
    /// Растворение в выбор папки.
    static var fadeStart: Double { pinEnd + 0.7 }
    static var end: Double { fadeStart + 0.35 }

    /// Где рамка в миг `t`.
    static func camera(_ t: Double) -> Spot {
        var from = today
        for (i, to) in stops.enumerated() {
            let s = first + Double(i) * step + reach
            if t < s { return from }
            if t < s + swipe {
                let p = ease((t - s) / swipe)
                return Spot(x: from.x + (to.x - from.x) * p, y: from.y + (to.y - from.y) * p)
            }
            from = to
        }
        return from
    }

    /// Рука: где она (доля от рамки, от середины), видна ли, прижата ли.
    static func hand(_ t: Double) -> (at: CGPoint, shown: CGFloat, pressed: CGFloat)? {
        var from = today
        for (i, to) in stops.enumerated() {
            let s = first + Double(i) * step
            // Смахивают туда, откуда приходит новый экран: крест едет
            // против движения рамки.
            let dir = CGPoint(x: -(to.x - from.x), y: -(to.y - from.y))
            if t >= s, t < s + step {
                let local = t - s
                let travel = local < reach ? 0 : min(1, (local - reach) / swipe)
                let p = ease(travel)
                let span: CGFloat = 0.28
                let at = CGPoint(x: dir.x * span * (2 * p - 1), y: dir.y * span * (2 * p - 1))
                let shown = ease(local / reach) * (1 - ease((local - reach - swipe) / 0.25))
                let pressed = local < reach ? ease(local / reach) : (1 - ease((local - reach - swipe) / 0.15))
                return (at, shown, pressed)
            }
            from = to
        }
        return nil
    }

    /// Плавно от 0 до 1, без рывка в начале и в конце.
    static func ease(_ x: Double) -> CGFloat {
        let x = min(1, max(0, x))
        return CGFloat(x * x * (3 - 2 * x))
    }

    static func ease(_ t: Double, _ a: Double, _ b: Double) -> CGFloat {
        ease((t - a) / (b - a))
    }
}

/// Один кадр мультфильма в миг `t`.
private struct IntroFrame: View {
    let t: Double
    let size: CGSize

    /// Настоящий экран, который уменьшается: ширина iPhone в точках.
    static let screenW: CGFloat = 390
    static let screenH: CGFloat = 800
    /// Промежуток между экранами креста.
    static let gap: CGFloat = 26

    var body: some View {
        let W = Self.screenW, H = Self.screenH
        let frameW = min(size.width * 0.48, 205)
        let k = frameW / W
        let frameH = H * k
        let cam = IntroPlan.camera(t)
        let born = IntroPlan.ease(t, 0, IntroPlan.first)
        let gone = 1 - IntroPlan.ease(t, IntroPlan.fadeStart, IntroPlan.end)
        let pin = IntroPlan.ease(t, IntroPlan.pinStart, IntroPlan.pinEnd)
        let stepX = W + Self.gap, stepY = H + Self.gap
        let corner = 46 * k
        // Рамка чуть выше середины: под ней подпись и «Пропустить».
        let lift = -size.height * 0.03

        ZStack {
            // Крест — настоящие экраны в натуральную величину, уменьшенные
            // разом: так они узнаются, а шрифты и бумага те же, что в деле.
            ZStack {
                IntroScreen.place(MiniPast(), IntroPlan.past, stepX, stepY)
                IntroScreen.place(MiniFuture(), IntroPlan.future, stepX, stepY)
                IntroScreen.place(MiniMap(pin: pin), IntroPlan.map, stepX, stepY)
                IntroScreen.place(MiniCalendar(), IntroPlan.calendar, stepX, stepY)
                IntroScreen.place(MiniToday(), IntroPlan.today, stepX, stepY)
            }
            .frame(width: W, height: H)
            .offset(x: -cam.x * stepX, y: -cam.y * stepY)
            .scaleEffect(k)
            .frame(width: frameW, height: frameH)

            // Вне рамки крест притушен: видно, где он лежит, а смотреть —
            // в рамку.
            Veil(hole: CGSize(width: frameW, height: frameH), corner: corner)
                .fill(Look.chrome.opacity(0.5), style: FillStyle(eoFill: true))
                .frame(width: size.width * 3, height: size.height * 3)
                .allowsHitTesting(false)

            // Неподвижное в телефоне: нижняя строка разделов и уголок с
            // шестерёнкой — как в приложении, крест едет под ними.
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    IntroGear()
                }
                Spacer(minLength: 0)
                IntroBar(at: cam.x)
            }
            .frame(width: W, height: H)
            .scaleEffect(k)
            .frame(width: frameW, height: frameH)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))

            // Сама рамка — прозрачная, с ободком телефона.
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(Look.ink.opacity(0.8), lineWidth: 3.5)
                .frame(width: frameW + 7, height: frameH + 7)
                .shadow(color: .black.opacity(0.18), radius: 10, y: 4)

            if let hand = IntroPlan.hand(t) {
                IntroHand(pressed: hand.pressed)
                    .offset(x: hand.at.x * frameW, y: hand.at.y * frameH)
                    .opacity(Double(hand.shown))
            }

            // Имя того, что в рамке, — на языке телефона, под рамкой.
            ZStack {
                caption(T("Сегодня", "Today"), IntroPlan.today, cam)
                caption(T("Календарь", "Calendar"), IntroPlan.calendar, cam)
                caption(T("Карта", "Map"), IntroPlan.map, cam)
                caption(T("Прошлое", "Past"), IntroPlan.past, cam)
                caption(T("Будущее", "Future"), IntroPlan.future, cam)
            }
            .offset(y: frameH / 2 + 30)
        }
        .offset(y: lift)
        .opacity(Double(born * gone))
        .scaleEffect(0.96 + 0.04 * born)
        .frame(width: size.width, height: size.height)
        .clipped()
    }

    /// Подпись проступает, пока рамка подъезжает к своему экрану.
    private func caption(_ text: String, _ spot: CGPoint, _ cam: CGPoint) -> some View {
        let d = Double(hypot(cam.x - spot.x, cam.y - spot.y))
        return Text(text)
            .font(Look.sans(17, weight: .medium))
            .foregroundStyle(Look.ink)
            .opacity(max(0, 1 - d * 2.5))
    }
}

/// Вырез под рамку в покрывале.
private struct Veil: Shape {
    let hole: CGSize
    let corner: CGFloat

    func path(in r: CGRect) -> Path {
        var p = Path(r)
        p.addRoundedRect(in: CGRect(x: r.midX - hole.width / 2, y: r.midY - hole.height / 2,
                                    width: hole.width, height: hole.height),
                         cornerSize: CGSize(width: corner, height: corner), style: .continuous)
        return p
    }
}

private enum IntroScreen {
    /// Экран — на своё место в кресте.
    static func place<V: View>(_ v: V, _ spot: CGPoint, _ stepX: CGFloat, _ stepY: CGFloat) -> some View {
        v.frame(width: IntroFrame.screenW, height: IntroFrame.screenH)
            .clipped()
            .offset(x: spot.x * stepX, y: spot.y * stepY)
    }
}

/// Условная рука: палец и след касания под ним.
private struct IntroHand: View {
    let pressed: CGFloat

    var body: some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(Look.accent.opacity(0.32 * Double(pressed)))
                .frame(width: 44, height: 44)
                .offset(x: -22, y: -22)
            // Крупнее (P1070): на пёстром кресте рука не теряется — тёмная,
            // с белой обводкой.
            Image(systemName: "hand.point.up.left.fill")
                .font(.system(size: 64))
                .foregroundStyle(Look.ink)
                .shadow(color: .white, radius: 0, x: 1.5, y: 1.5)
                .shadow(color: .white, radius: 0, x: -1.5, y: -1.5)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                // Кончик пальца — в точке касания.
                .offset(x: -6, y: -4)
                .scaleEffect(1 - 0.08 * pressed, anchor: .topLeading)
        }
        .frame(width: 0, height: 0, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

/// Нижняя строка разделов: кожа и три значка, открытый — на подушке.
private struct IntroBar: View {
    /// Где рамка по горизонтали: −1 карта, 0 дневник, 1 календарь.
    let at: CGFloat

    var body: some View {
        GeometryReader { geo in
            let third = geo.size.width / 3
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.28))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Leather.ink.opacity(0.5), lineWidth: 1))
                    .frame(width: third * 0.62, height: 62)
                    .position(x: third * (1.5 + at), y: 44)
                HStack(spacing: 0) {
                    item("карта", T("Карта", "Map"))
                    item("сегодня", T("Дневник", "Diary"))
                    item("календарь", T("Календарь", "Calendar"))
                }
                .frame(height: 88, alignment: .top)
                .padding(.top, 14)
            }
        }
        .frame(height: 96)
        .background(alignment: .top) { BarCover() }
    }

    private func item(_ icon: String, _ name: String) -> some View {
        VStack(spacing: 3) {
            Image(icon).renderingMode(.template).resizable().scaledToFit()
                .frame(width: 28, height: 28)
            Text(name).font(Look.sans(13)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(Leather.ink)
        .frame(maxWidth: .infinity)
    }
}

/// Уголок с шестерёнкой сверху справа.
private struct IntroGear: View {
    var body: some View {
        OldPaper(seed: 7, base: Scheme.current.past)
            .frame(width: 50, height: 46)
            .overlay(Image(systemName: "gearshape").font(.system(size: 20)).foregroundStyle(Look.inkSoft))
            .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 8))
            .shadow(color: .black.opacity(0.18), radius: 3, x: -1, y: 2)
            .padding(.top, 8)
    }
}

// MARK: - Образцы — те же, что ложатся в новый архив (P1035)

private enum IntroSample {

    struct Task { let time: String?; let title: String; let done: Bool }

    /// Дела из образца плана: «- [ ] 09:00 Название», продолжения — мимо.
    static func tasks(_ plan: String) -> [Task] {
        plan.split(separator: "\n").compactMap { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("- ["), line.count > 6 else { return nil }
            let done = line.hasPrefix("- [x]")
            var rest = String(line.dropFirst(6))
            var time: String?
            if rest.count >= 5, rest.prefix(5).allSatisfy({ $0.isNumber || $0 == ":" }), rest.dropFirst(2).first == ":" {
                time = String(rest.prefix(5))
                rest = String(rest.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            }
            if let r = rest.range(of: " (remind") { rest = String(rest[..<r.lowerBound]) }
            return Task(time: time, title: rest, done: done)
        }
    }

    /// Строки записи без заголовков, списков и ссылок — то, что видно на
    /// карточке.
    static func prose(_ text: String) -> String {
        text.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("-") && !$0.hasPrefix("[") && !$0.hasPrefix("!") }
            .joined(separator: "\n")
    }

    static func day(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: n, to: DayStore.today()) ?? DayStore.today()
    }
}

// MARK: - Уменьшаемые экраны

/// Бумага листа «Сегодня» с фактурой.
private struct TodayPaper: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack {
            Scheme.current.today
            Image(uiImage: PageTexture.paper)
                .resizable(resizingMode: .tile)
                .opacity(scheme == .dark ? 0.2 : 0.3)
        }
    }
}

/// Шапка листа «Сегодня»: имя дня и дата на корешке.
private struct TodayHead: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(T("Сегодня", "Today"))
                .font(Look.sans(30, weight: .semibold))
                .foregroundStyle(Look.ink)
            Text(Ru.dayLine(DayStore.today()))
                .font(Look.sans(15))
                .foregroundStyle(Look.inkSoft)
                .lineLimit(1)
        }
        .padding(.leading, 22)
        .padding(.top, 14)
    }
}

/// «Сегодня»: план на клетчатой бумаге, под ним дневник.
private struct MiniToday: View {
    var body: some View {
        let tab: CGFloat = 92
        let shape = FolderShape(tabHeight: tab, tabShare: Search.tabShare, roundBottom: true, soft: true)
        ZStack(alignment: .topLeading) {
            Desk()
            TodayPaper()
                .clipShape(shape)
                .overlay(shape.stroke(Look.kraftEdge.opacity(0.4), lineWidth: 1))
                .padding(.top, 8)
            TodayHead().padding(.top, 8)
            // Клетка — под планом, до дневника.
            GridPaper()
                .frame(height: 300)
                .padding(.top, tab + 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(T("План", "Plan").uppercased())
                    .font(Look.sans(26, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Look.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 14)
                ForEach(Array(IntroSample.tasks(Samples.todayPlan).enumerated()), id: \.offset) { i, task in
                    IntroTaskRow(number: i + 1, task: task)
                        .padding(.bottom, 16)
                }
                IntroTaskRow(number: IntroSample.tasks(Samples.todayPlan).count + 1,
                             task: .init(time: nil, title: "", done: false))
                    .opacity(0.6)
                Text(T("Дневник", "Diary").uppercased())
                    .font(Look.sans(26, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Look.inkSoft)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 30)
                    .padding(.bottom, 12)
                Text(Samples.todayTitle)
                    .font(Look.serif(20, weight: .bold))
                    .foregroundStyle(Look.ink)
                    .padding(.bottom, 6)
                Text(IntroSample.prose(Samples.todayDiary))
                    .font(Look.serif(18))
                    .foregroundStyle(Look.ink)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 20)
            .padding(.top, tab + 26)
        }
    }
}

/// Клетка плана.
private struct GridPaper: View {
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            let step: CGFloat = 25
            var x: CGFloat = 0
            while x <= size.width { p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            ctx.stroke(p, with: .color(Look.rule.opacity(0.9)), lineWidth: 0.7)
        }
    }
}

/// Строка дела: номер, время, название — как в плане.
private struct IntroTaskRow: View {
    let number: Int
    let task: IntroSample.Task

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(task.done ? "✓" : "\(number)")
                .font(Look.mono(16))
                .foregroundStyle(Look.inkSoft)
                .frame(width: 26, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Look.inkFaint, lineWidth: 1.2))
            Text(task.time ?? "--:--")
                .font(Look.mono(15))
                .foregroundStyle(task.time == nil ? Look.inkFaint : Look.ink)
                .frame(width: 64, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Look.inkFaint, lineWidth: 1.2))
            Text(task.title)
                .font(Look.sans(18))
                .foregroundStyle(task.done ? Look.inkSoft : Look.ink)
                .lineLimit(3)
                .padding(.top, 2)
            Spacer(minLength: 0)
        }
    }
}

/// Карточка картотеки: корешок с датой, бумага прошлого или будущего.
private struct IntroCard<Content: View>: View {
    let date: Date
    let past: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        let tab: CGFloat = 34
        let shape = FolderShape(tabHeight: tab, tabShare: Search.tabShare)
        let weekend = Ru.dayColor(date) == Ru.weekendColour
        VStack(alignment: .leading, spacing: 0) {
            (Text(Search.stamp(date)).foregroundColor(Look.dateBlue)
             + Text(" " + Search.weekday(date)).foregroundColor(!past && weekend ? Ru.weekendColour : Look.dateBlue))
                .font(Look.mono(15, weight: .medium))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.horizontal, 10)
                .frame(height: tab)
            content()
                .padding(.horizontal, 26)
                .padding(.top, 6)
                .padding(.bottom, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background {
            ZStack {
                if past {
                    OldPaper(seed: Calendar.current.component(.day, from: date), base: Scheme.current.past)
                } else {
                    TodayPaper()
                }
            }
            .clipShape(shape)
            .overlay(shape.stroke(Look.kraftEdge.opacity(past ? 0.55 : 0.4), lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 4, x: 2, y: 3)
        }
        .padding(.horizontal, 22)
    }
}

/// Прошлое: карточки прожитых дней, внизу — корешок «Сегодня».
private struct MiniPast: View {
    var body: some View {
        let walkLines = IntroSample.prose(Samples.walk)
        let howLines = IntroSample.prose(Samples.howto)
        ZStack(alignment: .bottom) {
            Desk()
            VStack(spacing: -14) {
                Spacer(minLength: 0)
                ForEach([-6, -5, -4, -3], id: \.self) { n in
                    IntroCard(date: IntroSample.day(n), past: true) { Color.clear.frame(height: 18) }
                }
                IntroCard(date: IntroSample.day(-2), past: true) {
                    entry(Samples.howtoTitle, howLines)
                }
                IntroCard(date: IntroSample.day(-1), past: true) {
                    entry(Samples.walkTitle, walkLines)
                }
            }
            .padding(.bottom, 150)
            // Корешок листа «Сегодня» — у нижнего края, как в картотеке.
            ZStack(alignment: .topLeading) {
                let shape = FolderShape(tabHeight: 92, tabShare: Search.tabShare, roundBottom: true, soft: true)
                TodayPaper().clipShape(shape)
                    .overlay(shape.stroke(Look.kraftEdge.opacity(0.4), lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: -2)
                TodayHead()
            }
            .frame(height: 200)
            .offset(y: 50)
        }
    }

    private func entry(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(Look.serif(19, weight: .bold)).foregroundStyle(Look.ink)
            Text(text).font(Look.serif(16)).foregroundStyle(Look.ink).lineLimit(3)
        }
    }
}

/// Будущее: сверху шапка «Сегодня», под ней карточки дней с делами.
private struct MiniFuture: View {
    var body: some View {
        ZStack(alignment: .top) {
            Desk()
            VStack(spacing: -14) {
                IntroCard(date: IntroSample.day(1), past: false) { tasks(Samples.tomorrowPlan) }
                IntroCard(date: IntroSample.day(2), past: false) { tasks(Samples.laterPlan) }
                ForEach(3...7, id: \.self) { n in
                    IntroCard(date: IntroSample.day(n), past: false) { Color.clear.frame(height: 18) }
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 100)
            ZStack(alignment: .topLeading) {
                let shape = FolderShape(tabHeight: 92, tabShare: Search.tabShare, roundBottom: true, soft: true)
                TodayPaper().clipShape(shape)
                    .overlay(shape.stroke(Look.kraftEdge.opacity(0.4), lineWidth: 1))
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                TodayHead()
            }
            .frame(height: 104)
            .padding(.top, 8)
        }
    }

    private func tasks(_ plan: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(IntroSample.tasks(plan).enumerated()), id: \.offset) { _, task in
                HStack(alignment: .top, spacing: 10) {
                    Text(task.time ?? "")
                        .font(Look.sans(16))
                        .foregroundStyle(Look.ink)
                        .frame(width: 52, alignment: .leading)
                    Text(task.title)
                        .font(Look.sans(16))
                        .foregroundStyle(Look.ink)
                        .lineLimit(2)
                }
            }
        }
    }
}

/// Календарь: шапка с месяцем, «Год / Месяц», сетка нынешнего месяца, дела
/// сегодняшнего дня.
private struct MiniCalendar: View {
    var body: some View {
        let cal = Prefs.calendar
        let today = DayStore.today()
        let cells = MonthGrid.cells(of: today, calendar: cal, firstWeekday: cal.firstWeekday)
        let header = cal.firstWeekday == 1 ? [Ru.weekHeader.last ?? ""] + Array(Ru.weekHeader.dropLast()) : Ru.weekHeader
        ZStack(alignment: .top) {
            Desk()
            VStack(spacing: 0) {
                HStack {
                    Text("‹").font(Look.sans(26)).foregroundStyle(Look.inkFaint)
                    Spacer()
                    Text(Ru.monthTitle(today))
                        .font(Look.sans(20, weight: .semibold))
                        .foregroundStyle(Look.ink)
                    Spacer()
                    Text("›").font(Look.sans(26)).foregroundStyle(Look.inkFaint)
                }
                .padding(.horizontal, 70)
                .padding(.top, 20)
                HStack(spacing: 6) {
                    kind(T("Год", "Year"), on: false)
                    kind(T("Месяц", "Month"), on: true)
                }
                .padding(.horizontal, 12)
                .padding(.top, 18)
                .padding(.bottom, 14)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 1) {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, name in
                        Text(name.uppercased())
                            .font(Look.sans(12, weight: .semibold))
                            .foregroundStyle(Look.inkSoft)
                            .padding(.bottom, 4)
                    }
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                        if let day { cell(day, today: today, cal: cal) } else { Color.clear.aspectRatio(1, contentMode: .fit) }
                    }
                }
                .padding(.horizontal, 3)
                Rectangle().fill(Look.rule).frame(height: 1).padding(.vertical, 12)
                VStack(alignment: .leading, spacing: 10) {
                    Text(Ru.dayLine(today))
                        .font(Look.sans(17))
                        .foregroundStyle(Look.ink)
                    ForEach(Array(IntroSample.tasks(Samples.todayPlan).enumerated()), id: \.offset) { _, task in
                        HStack(alignment: .top, spacing: 10) {
                            Text(task.time ?? "--:--").font(Look.mono(15)).foregroundStyle(Look.inkFaint)
                            Text(task.title).font(Look.sans(17)).foregroundStyle(Look.ink).lineLimit(2)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                Spacer(minLength: 0)
            }
        }
    }

    private func kind(_ title: String, on: Bool) -> some View {
        Text(title)
            .font(Look.sans(15))
            .foregroundStyle(on ? Look.planBg : Look.inkSoft)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .background(on ? Look.accent : .clear, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? Look.accent : Look.rule))
    }

    private func cell(_ date: Date, today: Date, cal: Calendar) -> some View {
        let isToday = cal.isDate(date, inSameDayAs: today)
        let past = !isToday && Ru.isPast(date)
        let n = cal.component(.day, from: date)
        return Text("\(n)")
            .font(Look.sans(isToday ? 17 : 15, weight: isToday ? .bold : .medium))
            .foregroundStyle(isToday ? Color.white : Look.ink)
            .padding(.trailing, 6)
            .padding(.bottom, 3)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .aspectRatio(1, contentMode: .fit)
            .background {
                if past {
                    OldPaper(seed: n, base: Ru.tint(date))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(isToday ? Look.accent : Ru.tint(date))
                }
            }
    }
}

/// Карта — настоящая карта iPhone; в конце на неё падает точка.
private struct MiniMap: View {
    let pin: CGFloat

    var body: some View {
        ZStack {
            IntroMapView()
            // Точка падает сверху и чуть подпрыгивает; круг расходится.
            let drop = IntroPlan.ease(Double(pin) / 0.7)
            let settle = IntroPlan.ease((Double(pin) - 0.7) / 0.3)
            Circle()
                .stroke(Look.pin.opacity(0.5 * sin(Double.pi * Double(settle))), lineWidth: 3)
                .frame(width: 30 + 70 * settle, height: 30 + 70 * settle)
            Circle()
                .fill(Look.pin)
                .overlay(Circle().stroke(Color.white, lineWidth: 3))
                .frame(width: 30, height: 30)
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
                .offset(y: -220 * (1 - drop) - 10 * CGFloat(sin(Double.pi * Double(settle))))
                .opacity(Double(min(1, pin * 4)))
        }
    }
}

/// Карта iPhone без касаний — над Гайд-парком из образцов дня (P1035).
private struct IntroMapView: UIViewRepresentable {
    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.isUserInteractionEnabled = false
        map.showsCompass = false
        map.pointOfInterestFilter = .excludingAll
        map.setRegion(MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 51.50731, longitude: -0.16573),
                                         latitudinalMeters: 2200, longitudinalMeters: 1100),
                      animated: false)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {}
}
