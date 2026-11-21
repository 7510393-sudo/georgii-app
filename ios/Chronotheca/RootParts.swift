import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Мелкие виды оболочки: уголок настроек, полоска и корешок «Сегодня»,
/// шов страниц, сдвиг вбок. Вынесено из `RootView.swift` без правок (P919).

/// Уголок листка, заложенного выше экрана: слева торчит его правый нижний
/// угол с шестерёнкой (P229, P236); у него тень — он лежит поверх
/// страницы. С P735 — старая бумага, как прошлое.
struct Corner: View {
    static let size: CGFloat = 58
    /// Насколько верх уголка спрятан за верхним краем (P496).
    static let lift: CGFloat = 2
    /// Листок заходит за левый край экрана и под верх: рваными видны только
    /// правый и нижний края (P735).
    private static let hidden: CGFloat = 10

    let icon: String
    let tint: Color
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Prefs.plainPast) private var plainPast = false
    @State private var art: PageTexture.AgedArt?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Уголок — справа (P793): листок зеркально, рваные — левый и
            // нижний края, за правый край экрана он заходит.
            sticker
                .scaleEffect(x: -1, y: 1)
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 30, height: 26)
                .padding(.trailing, 9)
                .padding(.top, 7)
        }
        .frame(width: Corner.size, height: Corner.size, alignment: .topTrailing)
        // Сверху листок уходит под край ровно — без растворения (P735:
        // переход цвета сверху выбивался из старой бумаги).
        .clipShape(BelowTop())
        .contentShape(CornerShape())
    }

    /// Старая бумага, потрёпанная сильнее карточек — за уголок берутся
    /// часто (P735, по слову автора): шире охра и подпалина, рваный край.
    /// Лист — из пачки заготовок (P732); пока его нет — ровная бумага.
    private var sticker: some View {
        let w = (Corner.size * 0.86 + Corner.hidden).rounded()
        let h = (Corner.size * 0.80 + Corner.hidden).rounded()
        let order = PageTexture.agedOrder(size: CGSize(width: w, height: h), band: 16, seed: 5)
        let ready = plainPast ? nil : (art ?? PageTexture.agedReady(order))
        return ZStack {
            // Без «Ретро» (P737) — прежняя белая бумага листков, ровная.
            if plainPast {
                // Как листок настроек, который за него тянут (P757).
                Desk()
            } else {
                Scheme.current.past
                Image(uiImage: PageTexture.paper)
                    .resizable(resizingMode: .tile)
                    .opacity(scheme == .dark ? 0.2 : 0.3)
            }
            if let ready {
                Image(uiImage: ready.frame)
                    .resizable()
                    .opacity(scheme == .dark ? 0.35 : 1)
            }
        }
        .frame(width: w, height: h)
        .mask {
            if let ready { Image(uiImage: ready.cut).resizable() } else { Rectangle() }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.4), radius: 4, x: 3, y: 3.5)
        .offset(x: -Corner.hidden, y: -Corner.hidden)
        .task(id: order) {
            guard !plainPast else { return }
            art = await PageTexture.aged(order)
        }
    }
}

/// Всё, что ниже верхнего края уголка: тень и бумага справа и снизу не
/// обрезаются, сверху листок уходит под край.
struct BelowTop: Shape {
    func path(in r: CGRect) -> Path {
        Path(CGRect(x: r.minX - 40, y: r.minY, width: r.width + 80, height: r.height + 40))
    }
}

/// Видимая часть уголка — для касаний.
struct CornerShape: Shape {
    func path(in r: CGRect) -> Path {
        // Уголок справа (P793).
        Path(CGRect(x: r.maxX - r.width * 0.86, y: r.minY, width: r.width * 0.86, height: r.height * 0.80))
    }
}

/// Голосовая запись открывается небольшой шторкой снизу: имя, ход
/// записи, «играть» и «убрать» — весь экран ей ни к чему (P360).
struct VoiceShown: ViewModifier {
    @EnvironmentObject private var overlays: Overlays
    @EnvironmentObject private var store: DayStore

    static func isVoice(_ opened: Overlays.OpenedPhoto, _ store: DayStore) -> Bool {
        let links = store.photos
        let name = opened.url?.lastPathComponent
            ?? (links.indices.contains(opened.index) ? links[opened.index] : "")
        return Diary.kind(of: name) == .audio
    }

    private var shown: Binding<Overlays.OpenedPhoto?> {
        Binding(get: { overlays.openedPhoto.flatMap { Self.isVoice($0, store) ? $0 : nil } },
                set: { overlays.openedPhoto = $0 })
    }

    func body(content: Content) -> some View {
        content.sheet(item: shown) { opened in
            VoiceSheet(opened: opened)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
    }
}

struct VoiceSheet: View {
    let opened: Overlays.OpenedPhoto
    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var store: DayStore

    private var url: URL? {
        if let url = opened.url { return url }
        let links = store.photos
        return links.indices.contains(opened.index) ? store.photoURL(links[opened.index]) : nil
    }

    var body: some View {
        AttachmentViewer(
            url: url,
            onRemove: opened.url == nil && store.canEditStrip ? { remove($0) } : nil,
            close: { shell.overlays.openedPhoto = nil },
            // Под делом плана голос открыт по месту (`url`) — расшифровка
            // ложится в запись только у голоса из ряда или из текста.
            onTranscript: store.canEditDiary && link != nil
                ? { store.addTranscript($0, after: link ?? "") } : nil)
    }

    /// Ссылка на запись: из текста — своя, из полоски — по месту в ней.
    private var link: String? {
        if let l = opened.link { return l }
        guard opened.url == nil else { return nil }
        return store.photos.indices.contains(opened.index) ? store.photos[opened.index] : nil
    }

    private func remove(_ delete: Bool) {
        shell.overlays.openedPhoto = nil
        shell.say(store.removeAttachment(at: opened.index, delete: delete))
    }
}

/// Кнопка, которая срабатывает в миг касания, а не когда палец отпустили
/// (P565). Обычная кнопка iPhone ждёт отпускания — и раздел начинал ехать
/// с опозданием.
struct TouchDownStyle: ButtonStyle {
    let action: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, pressed in
                guard pressed else { return }
                TouchDown.pressed = Date()
                action()
            }
    }
}

enum TouchDown {
    /// Когда кнопка сработала от касания и ещё не отпущена.
    static var pressed: Date?

    /// Срабатывать ли кнопке при отпускании. Нет, если она уже сработала
    /// от касания этого же пальца (P578): прежде мерили 0,6 с от касания —
    /// подержал палец дольше или телефон замешкался, и кнопка срабатывала
    /// дважды; у «Дня» второе срабатывание уводило на сегодня. Касания не
    /// было (VoiceOver) — срабатывает сама. Давнее касание, после которого
    /// отпускания не пришло (палец ушёл с кнопки), не в счёт.
    static func takeRelease() -> Bool {
        defer { pressed = nil }
        guard let pressed else { return true }
        return Date().timeIntervalSince(pressed) > 10
    }
}

/// Рамка без нижней стороны (P744): всё, что ниже, может выходить под
/// нижнюю строку.
struct OpenBelow: Shape {
    func path(in r: CGRect) -> Path {
        Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height + 400))
    }
}

/// Лента страниц (разделы, месяцы календаря) под пальцем (P800).
/// Толчок — когда страница перевалила за середину, перемена — когда лента
/// встала. Прежде её место читали прямо в виде, и он перестраивался посреди
/// хода: лента подтягивала новую страницу к краю рывком, в миг толчка.
/// Здесь место читается только в откликах, и вид посреди хода не трогается.
struct PageWatch<ID: Hashable>: ViewModifier {
    @Binding var at: ID?
    /// Эту страницу не отмечать толчком (уже открыта кнопкой).
    let skip: (ID) -> Bool
    /// Какой толчок: у разделов — потвёрже, у месяцев — лёгкий.
    let feel: () -> Void
    let landed: (ID) -> Void

    final class Seen { var last: AnyHashable? }
    @State private var seen = Seen()

    init(at: Binding<ID?>, skip: @escaping (ID) -> Bool = { _ in false },
         feel: @escaping () -> Void = { Feel.light() }, landed: @escaping (ID) -> Void) {
        _at = at
        self.skip = skip
        self.feel = feel
        self.landed = landed
    }

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content
                .onScrollTargetVisibilityChange(idType: ID.self, threshold: 0.5) { ids in
                    guard let id = ids.first else { return }
                    if let last = seen.last, last != AnyHashable(id), !skip(id) { feel() }
                    seen.last = AnyHashable(id)
                }
                .onScrollPhaseChange { _, now in
                    // Палец лёг — отклик будится заранее (P829).
                    if now == .interacting { Feel.warm() }
                    if now == .idle, let at { landed(at) }
                }
        } else {
            content.onChange(of: at) { old, now in
                guard let now else { return }
                if old != nil && old != now && !skip(now) { feel() }
                landed(now)
            }
        }
    }
}

/// Черта между соседними разделами ленты (P818): тонкая линия и лёгкая тень
/// на левом соседе. Стоит за левым краем раздела — в покое за экраном, видна
/// только на ходу. Касаний не ловит.
struct PageSeam: View {
    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black.opacity(0.12)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 8)
            Rectangle()
                .fill(Look.ink.opacity(0.35))
                .frame(width: 1)
        }
        .offset(x: -9)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Сдвиг ленты разделов за пальцем у края карты (P857).
final class SidePull: ObservableObject {
    @Published var x: CGFloat = 0
    /// Скорость пальца и ширина страницы в миг отпускания.
    var speed: CGFloat = 0
    var width: CGFloat = 0
}

/// Сдвиг читается только здесь — экран целиком не перерисовывается.
struct PullShift: ViewModifier {
    @ObservedObject var pull: SidePull
    func body(content: Content) -> some View {
        content.offset(x: pull.x)
    }
}

/// Картотека под листом проступает по мере тяги (P858): в покое её нет —
/// так легче телефону, — а с первыми точками хода место справа от корешка
/// плавно рассеивается и из него выходят карточки.
struct RibbonFade: ViewModifier {
    @ObservedObject var ribbon: Ribbon
    /// Карточка раскрывается (P995): лента стоит под растущей схемой, пока
    /// та не закроет её целиком.
    @ObservedObject var unfold: Unfold
    let live: Bool
    let card: Bool
    /// Тянут не сегодняшний лист (P907): картотека под ним не проступает и
    /// не едет следом — лист закроется в карточку, и она откроется уже на
    /// месте (автор: «за листом зачем-то тянется картотека; убрать лишнее
    /// движение»).
    var quiet = false

    func body(content: Content) -> some View {
        let shown: Double = unfold.from != nil ? 1 : !live || quiet ? 0 : card ? 1 : Double(min(1, abs(ribbon.y) / 90))
        content
            .opacity(shown)
            // Под садящейся карточкой проступает, когда лента встала (P913,
            // P923): ступени посадки «летит» и «ждёт ленту».
            .animation(.easeInOut(duration: 0.2)) { $0.opacity(ribbon.deck.isVeiled ? 0 : 1) }
    }
}

/// Где «Сегодня» и где за него взяться (P860, P896): лист «Сегодня» с
/// экрана не уходит. Со стороны прошлого — корешок внизу, со стороны
/// будущего — низ листа у верха с именем, датой и днём недели; карточки
/// заходят под него (P896, автор: «надо отказаться от кольцевого положения
/// сегодняшнего листа»; отменяет кольцо P876 и P884). Открыт не сегодняшний
/// день — или он закрыт в карточку — «Сегодня» лежит над ним сам по себе:
/// у прошедшего корешком снизу (P862), у будущего низом листа сверху.
/// Касание или тяга к середине — в день.
struct TodayPeek: View {
    @ObservedObject var ribbon: Ribbon
    /// Картотеку тянут или она открыта.
    let live: Bool
    /// Лента открыта и стоит — за лист можно взяться.
    let open: Bool
    /// Не сегодняшний день закрыт в карточку.
    let card: Bool
    /// На листе — сегодняшний день.
    let todaySheet: Bool
    /// На листе — будущий день.
    let future: Bool
    /// Лист «Сегодня» уже поднимается с открытого дня (P924): его корешок
    /// и полоска — на нём самом, свои здесь не нужны.
    var lifting = false
    let size: CGSize
    let go: () -> Void

    var body: some View {
        let low = size.height - FollowRibbon.peekBottom
        // «Сегодня» сам по себе — когда на листе не сегодня или листа нет.
        let alone = card || !todaySheet
        // С какой стороны: будущее — сверху, прошлое — снизу.
        let above = future || (card && ribbon.deck.folding == .future)
        let aloneTop = alone && above
        let aloneBottom = alone && !above
        let shown = FollowRibbon.shown(live ? ribbon.y : 0, height: size.height)
        let sheet = todaySheet && !card && live
        let sheetLow = sheet && ribbon.y > 0 && shown >= low - 0.5
        // Лист «Сегодня» уходит вверх: надпись едет на его низу и проступает
        // за первые 80 точек хода — ничего не вспыхивает (P893).
        let rising = sheet && ribbon.y < 0
        let sheetHigh = rising && shown <= FollowRibbon.topClamp(size.height) + 0.5
        let bottomEdge = shown + size.height + DayPage.under
        let topY = aloneTop ? 0 : bottomEdge - FollowRibbon.peekTop
        let topShown: Double = aloneTop ? (lifting ? 0 : 1) : rising ? Double(min(1, -ribbon.y / 80)) : 0
        ZStack(alignment: .topLeading) {
            TodayTab()
                .frame(width: size.width)
                .offset(y: low)
                .opacity(aloneBottom && !lifting ? 1 : 0)
                .animation(.easeOut(duration: 0.35), value: aloneBottom)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            // На листе, который уходит вверх, — только надпись на его чистом
            // нижнем поле, без своей бумаги и черты (P907); сама по себе —
            // полоской низа листа.
            TodayTop(bare: !aloneTop)
                .frame(width: size.width, height: FollowRibbon.peekTop)
                .offset(y: topY)
                .opacity(topShown)
                .animation(.easeOut(duration: 0.35), value: aloneTop)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if (aloneBottom && (open || !live)) || (open && sheetLow) {
                TodayGrip(up: true, go: go)
                    .frame(width: size.width * DayPage.folder.tabShare, height: FollowRibbon.peekBottom)
                    .offset(y: low)
            } else if (aloneTop && (open || !live)) || (open && sheetHigh) {
                // Справа вверху — шестерёнка настроек: полоска до неё.
                TodayGrip(up: false, go: go)
                    .frame(width: max(0, size.width - 70), height: FollowRibbon.peekTop)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// Низ листа «Сегодня» у верха экрана (P896, вместо полоски в 44 точки
/// P860/P865): тот же цвет и обвод, скруглённый низ; «Сегодня» крупно, под
/// ним дата и день недели — как в шапке листа.
struct TodayTop: View {
    /// Только надпись — бумага и край под ней свои, у листа.
    var bare = false

    var body: some View {
        let today = DayStore.today()
        let shape = UnevenRoundedRectangle(bottomLeadingRadius: 16, bottomTrailingRadius: 16)
        ZStack(alignment: .bottomLeading) {
            if bare { Color.clear } else { Ru.tint(today) }
            VStack(alignment: .leading, spacing: 0) {
                Text(DayPage.title(for: today))
                    .font(.system(size: 19, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Look.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                (Text(Ru.headDate(today))
                    .foregroundColor(Look.inkSoft)
                 + Text(",  " + Ru.weekday(today))
                    .foregroundColor(Ru.dayColor(today))
                    .tracking(0.4))
                    .font(Look.sans(12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.leading, 22)
            .padding(.bottom, 7)
        }
        .clipShape(shape)
        .overlay { if !bare { shape.stroke(DayPage.edge, lineWidth: 1) } }
    }
}

/// Схема карточки (P886, автор: «не нужно рисовать карточку со всем
/// текстом — как только смахивают открытую страницу прошлого или будущего,
/// она после виброотклика плавно превращается в схематичное изображение
/// карточки, уменьшается и вставляется в нужное место картотеки; это
/// изображение для всех карточек одинаковое»; вместо сжатия самого листа
/// P883). Пустой контур карточки цвета бумаги: в миг закрытия он во весь
/// лист — лист над ним тает, — потом сжимается в рамку карточки в ряду и
/// тает над ней.
struct FoldGhost: View {
    @ObservedObject var ribbon: Ribbon
    /// Ступени посадки: схема видна, пока летит.
    @ObservedObject var landing: Landing
    let size: CGSize

    var body: some View {
        // День закрывается в карточку — с какой он стороны от «Сегодня».
        let side = ribbon.deck.folding
        let folding = side != nil
        let top = FollowRibbon.shown(ribbon.deck.isLive ? ribbon.y : 0, height: size.height, stick: ribbon.stick)
        // Будущий лист начинается под полоской «Сегодня» — и схема с него же (P913).
        let under: CGFloat = side == .future ? FollowRibbon.futureTop : 0
        let start = CGRect(x: 0, y: top + under, width: size.width, height: size.height - under)
        let r = ribbon.foldTo ?? start
        // Из листа к гнезду — одним плавным движением (P895); ход задаёт
        // посадка (P923): по его концу она и узнаёт, что схема долетела.
        FoldSchema(aged: side == .past)
            .frame(width: r.width, height: r.height)
            .offset(x: r.minX, y: r.minY)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            // Долетела — дальше садится сама карточка в своём ряду (P895):
            // схема над лентой уходит в тот же кадр, без таяния поверх.
            .opacity(folding && !landing.flown ? 1 : 0)
            // В полёте схема светлеет до той же прозрачности, с какой ляжет
            // на карточку (P906).
            .animation(ribbon.foldTo == nil ? nil : .easeIn(duration: SearchView.flight)) {
                $0.opacity(ribbon.foldTo == nil ? 1 : 0.6)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Схема раскрываемой карточки (P995): от рамки карточки — чуть вверх, как
/// карточку вынимают из ряда, — и до целого листа. Та же схема, в которую
/// лист складывается при закрытии (P886).
struct UnfoldGhost: View {
    @ObservedObject var unfold: Unfold
    @ObservedObject var move: RiseMove
    let size: CGSize

    var body: some View {
        if let card = unfold.from {
            // Пока растёт, картотеку под ней не трогают (P998): день
            // откроется, когда схема вырастет.
            Color.clear
                .contentShape(Rectangle())
                .frame(width: size.width, height: size.height)
            let p = move.p
            // Первая четверть хода — подскок на высоту, с какой карточка
            // при посадке ждёт над гнездом; дальше — рост до листа.
            let up = min(1, p / 0.25)
            let grow = max(0, (p - 0.25) / 0.75)
            let raised = card.offsetBy(dx: 0, dy: -Landing.lift * up)
            let sheet = CGRect(x: 0, y: unfold.top, width: size.width, height: size.height - unfold.top)
            let r = CGRect(x: raised.minX + (sheet.minX - raised.minX) * grow,
                           y: raised.minY + (sheet.minY - raised.minY) * grow,
                           width: raised.width + (sheet.width - raised.width) * grow,
                           height: raised.height + (sheet.height - raised.height) * grow)
            FoldSchema(aged: unfold.aged)
                .frame(width: r.width, height: r.height)
                .shadow(color: .black.opacity(0.12 * Double(up) * Double(1 - grow)), radius: 6, y: 3)
                .offset(x: r.minX, y: r.minY)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

/// Лист дня не виден, пока растёт схема раскрываемой карточки (P995), и
/// проступает поверх неё, когда она выросла.
struct UnfoldVeil: ViewModifier {
    @ObservedObject var unfold: Unfold

    func body(content: Content) -> some View {
        content.opacity(unfold.veiled ? 0 : 1)
    }
}

/// «Сегодня» с открытого прошедшего или будущего дня — сразу (P924, автор
/// по 290: «сначала закрывается карточка с тем же мельканием, а потом
/// экран картотеки закрывается сегодняшним днём; надо, чтобы сразу
/// поднимался экран сегодняшнего дня, а всё остальное происходило
/// невидимо»; отменяет «сперва открытый день складывается в карточку»
/// P879). Сегодняшний лист выходит оттуда, где торчит, — корешком снизу
/// или полоской сверху — и ложится поверх открытого дня; нарисован он тем
/// же кодом, что соседняя страница при перелистывании (P114). Лёг — под
/// ним день сменился на сегодня, и этот лист убран: подмены не видно.
struct TodayRise: View {
    /// Откуда: 1 — снизу, корешком; −1 — сверху, низом листа.
    let from: Int
    let size: CGSize
    /// Насколько лист уже лёг: ход по кадрам (P926).
    @ObservedObject var move: RiseMove

    var body: some View {
        let start: CGFloat = from > 0 ? size.height - FollowRibbon.peekBottom
            : FollowRibbon.topClamp(size.height)
        let left: CGFloat = 1 - move.p
        DayPage(date: DayStore.today(), live: false)
            .frame(width: size.width, height: size.height)
            // Сверху лист выходит низом: на нём та же надпись, что была на
            // полоске, — она уезжает вместе с ним и тает.
            .overlay(alignment: .topLeading) {
                if from < 0 {
                    TodayTop(bare: true)
                        .frame(width: size.width, height: FollowRibbon.peekTop)
                        .offset(y: size.height + DayPage.under - FollowRibbon.peekTop)
                        .opacity(Double(left))
                }
            }
            .offset(y: start * left)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// За что взяться (P860): касание — в день; тяга от края к середине — тоже.
struct TodayGrip: View {
    let up: Bool
    let go: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { go() }
            .gesture(DragGesture(minimumDistance: 10).onEnded { drag in
                let pulled = up ? -drag.translation.height : drag.translation.height
                if pulled > 30 { go() }
            })
            .accessibilityElement()
            .accessibilityLabel(T("Вернуться в день", "Back to the day"))
            .accessibilityAddTraits(.isButton)
    }
}

/// Корешок «Сегодня» сам по себе (P860) — когда листа нет: прошедший день
/// закрыт в карточку. Тот же контур, цвет, имя и дата, что у шапки листа.
struct TodayTab: View {
    var body: some View {
        let today = DayStore.today()
        ZStack(alignment: .topLeading) {
            Ru.tint(today)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(DayPage.title(for: today))
                        .font(.system(size: 21, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Look.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    (Text(Ru.headDate(today))
                        .foregroundColor(Look.inkSoft)
                     + Text(",  " + Ru.weekday(today))
                        .foregroundColor(Ru.dayColor(today))
                        .tracking(0.4))
                        .font(Look.sans(12.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.leading, 14)
                .padding(.top, 4)
                .frame(height: DayPage.headLine + 8)
                Spacer(minLength: 6)
            }
            .padding(.leading, 8)
            .padding(.top, 2)
        }
        .frame(height: FollowRibbon.peekBottom + DayPage.under)
        .clipShape(DayPage.folder)
        .overlay { DayPage.folder.stroke(DayPage.edge, lineWidth: 1) }
    }
}
