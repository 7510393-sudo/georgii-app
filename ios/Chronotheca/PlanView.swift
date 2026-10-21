import EventKit
import SwiftUI
import UIKit
import CoreLocation
import UniformTypeIdentifiers

/// Дело подняли долгим нажатием и ведут пальцем (P362): вверх-вниз —
/// переставить, влево — удалить, вправо — перенести на другой день (P383;
/// прежде вправо было «сделано» — теперь это касание по номеру).
/// Ход пальца — от места, где дело подняли, по экрану.
enum Lift {
    case began
    case moved(CGSize)
    case ended(CGSize)
    case cancelled
}

/// Строка дела.
///
/// Одна и та же вещь рисует и открытую страницу, и соседние: разойдутся хоть
/// на точку — при перелистывании строки прыгнут. Правка включается ключами,
/// вид от этого не меняется.
struct PlanRowLine: View {

    let number: Int
    let row: PlanRow
    var faded = false
    var bellColor: Color = Look.inkFaint
    /// Событие Календаря (P376): полоска цвета его календаря у номера.
    var stripe: Color? = nil

    var text: Binding<String>?
    var typing = false

    var onTime: (() -> Void)?
    var onBell: (() -> Void)?
    /// Касание по номеру — сделано или снова не сделано (P383).
    var onCheck: (() -> Void)?
    /// Правка названия кончилась.
    var onDone: () -> Void = {}
    /// «Ввод» в названии: ввод переходит к делу ниже.
    var onNext: () -> Void = {}

    /// Долгое нажатие на дело — на текст или на номер — поднимает его, и
    /// дальше его ведут пальцем (P362). Отклик — сразу, как нажатие стало
    /// долгим, а не когда палец убрали (P361).
    var onLift: ((Lift) -> Void)?

    /// Дело поднято (P362): контур синий и ярче (P374).
    var lifted = false
    /// Пустая плашка следующего дела (P406): всё бледное, номер — обычной
    /// яркости.
    var ghost = false
    /// Прошедший день (P421): плашка цвета подложки, без кромки и блика —
    /// от неё остаётся только тень.
    var past = false

    /// Высота строки без подробностей. По ней считается перестановка.
    /// Две клетки листа, а не три (P465): четыре дела занимали полэкрана,
    /// дневник уезжал вниз.
    static let height: CGFloat = 36

    // MARK: - Мера строки
    //
    // Ширины головы заданы числами, а не меряются по содержимому: ровно на
    // ширину головы отступает первая строка названия, и разойдись они хоть
    // на точку — название наползёт на колокольчик или отскочит от него.

    static let badgeWidth: CGFloat = 24
    static let timeWidth: CGFloat = 64
    static let bellWidth: CGFloat = 40
    static let gap: CGFloat = 8
    /// Высота площадки для пальца у номера, времени и колокольчика (P465).
    static let reach: CGFloat = 44

    /// Голова строки: номер, время, колокольчик.
    static let headWidth = badgeWidth + gap + timeWidth + gap + bellWidth

    /// Отступ первой строки названия: за головой, через просвет.
    static let indent = headWidth + gap

    /// Откуда идут строки ниже первой: из-под времени, правее номера.
    /// Номера остаются столбиком — за них дело берут, — а название
    /// занимает всю остальную ширину (решение P177).
    static let wrap = badgeWidth + gap

    /// Дело сейчас держат за номер. Сбрасывается и тогда, когда жест
    /// оборвался сам, — тогда дело опускается на место.
    @GestureState private var holding = false
    /// Подъём уже объявлен — второй раз не объявлять.
    @State private var told = false

    var body: some View {
        // Строка — целое число клеток листа, и плашка во всю её высоту:
        // промежутки между плашками ложатся на линии клетки (P413).
        GridSnap {
        VStack(alignment: .leading, spacing: 2) {
            // Голова стоит поверх отступа первой строки названия, а не
            // рядом с ним: тогда вторая и третья строки идут во всю ширину,
            // а не складываются в столбик (решение P177).
            ZStack(alignment: Alignment(horizontal: .leading,
                                        vertical: .firstTextBaseline)) {
                title
                head
            }
            // Шторки «Подробности» больше нет (P408): записанное в ней
            // прежде видно бледными строками под делом и лежит в файле, как
            // лежало.
            ForEach(Array(row.details.enumerated()), id: \.offset) { _, line in
                Text(line)
                    .font(Look.sans(13))
                    // Подробности — запись человека, а не подсказка (P465).
                    .foregroundStyle(Look.inkSoft)
                    .lineLimit(2)
                    .padding(.leading, Self.wrap)
            }
        }
        // Корешка «Детали» справа нет — название идёт до контура (P408).
        // Плашка уже с боков — и содержимое отступает вместе с ней (P413).
        .padding(.trailing, 20)
        .padding(.leading, 18)
        // Поля плашки тоньше (P465): строка в одну строчку — две клетки.
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Каждое дело на своей плашке (P374, P413).
        .background { contour }
    }

    /// Сделанное дело (P383): текст и кнопки бледнеют, а номер остаётся
    /// ярким и перечёркнут косой чертой — по нему видно, что отмечено и
    /// куда нажать, чтобы снять отметку.
    // Пустая плашка — ярче прежнего (P465: на 0,3 подсказка не читалась).
    private var dim: Double { ghost ? 0.55 : (row.done ? 0.42 : 1) }

    /// Плашка дела (P413): выпуклая, как листок стикера, — свет падает с
    /// левого верхнего угла: там она светлее и с бликом по кромке, а тень
    /// ложится вправо вниз. Пустая плашка следующего дела — бледнее.
    private var contour: some View {
        let shape = RoundedRectangle(cornerRadius: 9)
        // Плашка сплошная: клетка листа сквозь неё не видна (P415) — и у
        // пустой плашки следующего дела тоже; та лишь бледнее цветом, тенью
        // и кромкой.
        // Пустая плашка — того же цвета, что все, отличается только
        // бледными линиями (P421): светлая пестрила.
        return shape
            .fill(LinearGradient(colors: past ? [Ru.pastTint, Ru.pastTint]
                                              : [Look.plateLight, Look.plateDark],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(past ? 0 : 0.9), .white.opacity(0)],
                                                       startPoint: .topLeading, endPoint: .center),
                                        lineWidth: 1.2))
            .overlay(shape.strokeBorder(lifted ? Look.glow
                                               : (past ? .clear : Look.inkFaint.opacity(ghost ? 0.2 : 0.4)),
                                        lineWidth: lifted ? 3.25 : 0.8))
            .shadow(color: .black.opacity(0.16), radius: 2.5, x: 1.5, y: 2)
            .shadow(color: Look.glow.opacity(lifted ? 0.9 : 0), radius: 5)
            // Плашка уже с боков (P413).
            .padding(.leading, 10)
            .padding(.trailing, 10)
            .padding(.vertical, 2)
            .allowsHitTesting(false)
    }

    /// Номер: коснуться — сделано (P383), подержать — поднять дело и вести
    /// (P362). Один простой жест, который сам отличает касание от долгого
    /// нажатия по времени и ходу пальца (P410). Прежде это были два жеста,
    /// один «исключительно перед» другим (P394); на общей странице плана и
    /// дневника касание до номера перестало доходить.
    private var handle: some Gesture {
        // Ход пальца меряется по экрану, а не по самому номеру: номер едет
        // вместе с делом, и мерка от него дёргала бы дело взад-вперёд
        // (решение P195).
        DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .updating($holding) { _, state, _ in state = true }
            .onChanged { value in
                if pressStart == nil {
                    pressStart = Date()
                    let wait = DispatchWorkItem {
                        guard !told else { return }
                        told = true
                        onLift?(.began)
                    }
                    pressTimer = wait
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdTime, execute: wait)
                }
                if told {
                    onLift?(.moved(value.translation))
                } else if hypot(value.translation.width, value.translation.height) > 10 {
                    // Повели, не подержав, — ни касания, ни подъёма.
                    pressTimer?.cancel()
                }
            }
            .onEnded { value in
                pressTimer?.cancel()
                pressTimer = nil
                let quick = Date().timeIntervalSince(pressStart ?? .distantPast) < Self.holdTime
                pressStart = nil
                if told {
                    told = false
                    onLift?(.ended(value.translation))
                } else if quick, hypot(value.translation.width, value.translation.height) <= 10 {
                    onCheck?()
                }
            }
    }

    /// Сколько держать номер, чтобы дело поднялось.
    private static let holdTime: TimeInterval = 0.35

    /// Когда палец лёг на номер и отложенный подъём дела.
    @State private var pressStart: Date?
    @State private var pressTimer: DispatchWorkItem?

    private var head: some View {
        HStack(alignment: .firstTextBaseline, spacing: Self.gap) {
            badge
            time
            bell
        }
    }

    // MARK: - Части строки

    /// Номер в выпуклом квадратике: за него, как и за текст, дело берут
    /// долгим нажатием (P362).
    private var badge: some View {
        face
        // Номер — рукоять, а не текст: касание по нему не ставит курсор
        // в строку (решение P167), а отмечает дело сделанным (P383).
        // Попасть можно и чуть мимо квадратика: площадка для пальца — 44
        // в высоту, как советует Apple (P465); рисунок прежний.
        .contentShape(Rectangle().size(width: PlanRowLine.badgeWidth + Self.gap,
                                       height: PlanRowLine.reach)
                                 .offset(x: -Self.gap / 2,
                                         y: -(PlanRowLine.reach - PlanRowLine.badgeWidth) / 2))
        .accessibilityAction { onCheck?() }
        .accessibilityLabel(row.done ? T("Дело \(number): сделано", "Task \(number): done")
                                     : T("Дело \(number)", "Task \(number)"))
        .accessibilityAddTraits(onCheck != nil ? .isButton : [])
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 6 }
        .highPriorityGesture(onLift != nil || onCheck != nil ? handle : nil)
        // Жест оборвался сам (палец увела прокрутка) — дело опускается.
        .onChange(of: holding) { _, now in
            guard !now else { return }
            DispatchQueue.main.async {
                pressTimer?.cancel()
                pressTimer = nil
                pressStart = nil
                guard told else { return }
                told = false
                onLift?(.cancelled)
            }
        }
    }

    private var face: some View {
        Text("\(number)")
            .font(Look.mono(14))
            .foregroundStyle(Look.inkSoft)
            .frame(width: PlanRowLine.badgeWidth, height: PlanRowLine.badgeWidth)
            .modifier(Panel())
            // Событие Календаря — подчёркнуто снизу цветом своего
            // календаря (P381; прежде — полоской слева).
            .overlay(alignment: .bottom) {
                if let stripe {
                    Capsule().fill(stripe).frame(width: 16, height: 3).padding(.bottom, 3)
                }
            }
            .overlay {
                if row.done { Strike().stroke(Look.ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round)) }
            }
            // У пустой плашки следующего дела и номер бледный (P417; прежде
            // — обычной яркости, P406).
            .opacity(ghost ? 0.55 : 1)
    }

    private var time: some View {
        Button { onTime?() } label: {
            Text(row.time ?? "--:--")
                .font(Look.mono(17))
                .tracking(row.time == nil ? 0.6 : 0)
                // Время — всегда одна строка. «--:--» с разрядкой не
                // умещалось в отведённую ширину и переносилось надвое:
                // на странице оставался висеть один прочерк.
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(row.time == nil || faded ? Look.inkFaint : Look.inkSoft)
                // Время — на такой же панельке, как номер (P374), вместо
                // прежней пунктирной черты. Ширина задана числом: по ней
                // считается отступ названия, и она не должна зависеть от
                // того, назначено время или нет.
                .frame(width: PlanRowLine.timeWidth, height: PlanRowLine.badgeWidth)
                .modifier(Panel())
                // Площадка для пальца — 44 в высоту (P465).
                .contentShape(Rectangle().size(width: PlanRowLine.timeWidth + PlanRowLine.gap,
                                               height: PlanRowLine.reach)
                                         .offset(x: -PlanRowLine.gap / 2,
                                                 y: -(PlanRowLine.reach - PlanRowLine.badgeWidth) / 2))
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 6 }
        }
        .opacity(dim)
        .buttonStyle(.plain)
        // Не .disabled: система рисует выключенную кнопку бледнее, и время
        // на соседней странице выцветало, а после поворота «загоралось».
        // Вид не должен зависеть от того, можно ли нажать (P130).
        .allowsHitTesting(onTime != nil)
    }

    private var bell: some View {
        Button { onBell?() } label: {
            Image(systemName: row.bell == nil ? "bell" : "bell.fill")
                .font(.system(size: 20))
                .foregroundStyle(row.bell == nil ? Look.inkFaint : bellColor)
                // Дело из серии — значок повтора у колокольчика (P359).
                .overlay(alignment: .bottomTrailing) {
                    if row.repeats != nil {
                        Image(systemName: "arrow.2.circlepath")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Look.accent)
                            .offset(x: 5, y: 3)
                    }
                }
                // Колокольчик — на панельке, как номер (P374); площадка
                // для пальца вокруг неё прежняя.
                .frame(width: PlanRowLine.bellWidth - 4, height: PlanRowLine.badgeWidth)
                .modifier(Panel())
                // Площадка колокольчика — той же высоты, что номер (P465:
                // прежние 38 не давали строке стать двумя клетками); для
                // пальца — 44, как у номера и времени.
                .frame(width: PlanRowLine.bellWidth, height: PlanRowLine.badgeWidth)
                .contentShape(Rectangle().size(width: PlanRowLine.bellWidth + PlanRowLine.gap / 2,
                                               height: PlanRowLine.reach)
                                         .offset(x: -PlanRowLine.gap / 4,
                                                 y: -(PlanRowLine.reach - PlanRowLine.badgeWidth) / 2))
                // Середины у колокольчика и номера общие: иначе голова
                // строки выглядит нестройно.
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 6 }
        }
        .buttonStyle(.plain)
        .opacity(dim)
        .allowsHitTesting(onBell != nil)
        .accessibilityLabel(row.bell.map { T("Напомнить в \($0)", "Remind at \($0)") }
                                ?? T("Напоминание не назначено", "No reminder"))
    }

    /// Название — одно и то же поле и на открытой странице, и на соседних:
    /// соседняя лишь не правится. Строчка письма задана числом, одним и тем
    /// же, что бы ни было внутри (решение P171).
    private var title: some View {
        PlanTitle(text: text ?? .constant(row.text),
                  rowID: text == nil ? nil : row.id,
                  indent: Self.indent,
                  wrap: Self.wrap,
                  faded: faded,
                  editable: text != nil && typing,
                  typing: typing,
                  onDone: onDone,
                  onNext: onNext,
                  onLift: onLift)
            .opacity(dim)
            .alignmentGuide(.firstTextBaseline) { _ in PlanTitle.baseline }
    }

}

/// Косая черта через номер сделанного дела (P383): снизу слева вверх
/// направо, с отступом от краёв панельки.
struct Strike: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        let inset: CGFloat = 5
        p.move(to: CGPoint(x: r.minX + inset, y: r.maxY - inset))
        p.addLine(to: CGPoint(x: r.maxX - inset, y: r.minY + inset))
        return p
    }
}

/// Выпуклая панелька номера, времени и колокольчика (P364, P374). Контур —
/// заметной чертой, как у вкладок и корешка «Детали»: прежний, цвета
/// линовки, на бумаге было не разглядеть.
struct Panel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(Look.chrome, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Look.inkFaint, lineWidth: 1))
            .shadow(color: .black.opacity(0.06), radius: 1, y: 1)
    }
}

/// Черта конца недели: прямая, у которой концы загнуты вверх.
///
/// Так она выглядела в прототипе: там это был нижний край скруглённой рамки
/// строки, и загиб получался сам собой. Здесь его приходится рисовать
/// нарочно — но без него неделя не отбивается, а просто подчёркивается.
struct WeekEnd: Shape {

    /// Насколько концы уходят вверх. Чуть-чуть: это намёк, а не скоба.
    var rise: CGFloat = 6

    func path(in r: CGRect) -> Path {
        var p = Path()
        let низ = r.maxY
        p.move(to: CGPoint(x: r.minX, y: низ - rise))
        p.addQuadCurve(to: CGPoint(x: r.minX + rise, y: низ),
                       control: CGPoint(x: r.minX, y: низ))
        p.addLine(to: CGPoint(x: r.maxX - rise, y: низ))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: низ - rise),
                       control: CGPoint(x: r.maxX, y: низ))
        return p
    }
}


// MARK: - Открытая страница

/// Вкладка «План»: дела на день.
struct PlanView: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell

    /// Строка, в которой сейчас правят название. Одна на всю страницу:
    /// поле само берёт ввод, когда строка названа, и само отдаёт его,
    /// когда клавиатура уходит.
    @State private var typingIn: UUID?
    /// Дело, поднятое долгим нажатием (P362): оно обведено синим и идёт
    /// за пальцем. Куда его ведут — решает первый заметный ход пальца.
    @State private var lifted: UUID?
    @State private var liftAxis: Axis?
    /// Насколько поднятое дело отведено вбок: влево — удалить, вправо —
    /// сделано.
    @State private var slide: CGFloat = 0
    /// Точка в плане, у которой после долгого нажатия виден крестик.
    @State private var armedLine: UUID?
    /// Дело отвели влево — сперва вопрос (P458).
    @State private var askingDelete: UUID?
    /// Точка, которую несут пальцем (P374), откуда и куда: места — в
    /// порядке видимых строк. Строки между ними расступаются на её высоту.
    @State private var lineDrag: UUID?
    @State private var lineFrom = 0
    @State private var lineTo = 0
    @State private var lineHeight: CGFloat = 0
    /// Где стояли строки, когда точку подняли: по ним, а не по
    /// расступившимся, ищется место — иначе строки дрожали бы под пальцем.
    @State private var lineSpots: [UUID: CGRect] = [:]

    /// Снимок из ряда под делом, который несут пальцем (P377): что, откуда,
    /// где палец и куда ляжет — под дело или назад в полоску.
    struct PhotoCarry: Equatable {
        let link: String
        let from: UUID
    }
    @State private var photoCarry: PhotoCarry?
    @State private var photoSpot: CGPoint = .zero
    @State private var photoTo: UUID?
    @State private var photoBack = false
    @State private var photoSpots: [UUID: CGRect] = [:]
    @State private var photoStripTop: CGFloat = .infinity
    /// Снимок ведут вдоль своего же ряда — на какое место в ряду он встанет
    /// (P409): так снимки под делом меняются местами.
    @State private var photoSlot: Int?

    /// События Календаря этого дня (P376).
    @State private var events: [DayEvents.Item] = []
    /// Событие, поднятое долгим нажатием, и как его ведут.
    @State private var liftedEvent: String?
    @State private var eventAxis: Axis?
    @State private var eventSlide: CGFloat = 0
    @State private var eventDrag: CGFloat = 0
    /// Куда среди дел встанет событие, если отпустить, — ниже блока
    /// событий; выше — никуда.
    @State private var eventTo: Int?
    @State private var eventHeight: CGFloat = 0
    @State private var eventStart: CGFloat = 0
    @State private var eventBlockEnd: CGFloat = 0
    @State private var eventSpots: [UUID: CGRect] = [:]
    /// Событие, о котором спрашиваем: убрать из плана или удалить.
    @State private var askingEvent: DayEvents.Shown?
    @State private var openedEvent: OpenedEvent?

    struct OpenedEvent: Identifiable {
        let id = UUID()
        let event: EKEvent
    }

    /// Сколько отвести дело вбок, чтобы отпущенное оно удалилось или
    /// отметилось.
    static let swipe: CGFloat = 90

    /// Дело, которое сейчас ведут вверх-вниз, и на сколько оно сдвинуто.
    @State private var dragged: UUID?
    @State private var dragBy = 0

    /// Сколько пальец прошёл от начала. Взятое дело идёт за пальцем
    /// вплотную, а расступаются соседи уже по целым строкам.
    @State private var dragOffset: CGFloat = 0

    /// Насколько клавиатура закрывает страницу: строку, в которой пишут,
    /// страница держит над ней.
    @State private var keyboard: CGFloat = 0

    var body: some View {
        // План — верхняя часть страницы дня, без своей прокрутки: страница
        // едет целиком, план и дневник вместе (P408).
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                if store.away.contains(.planner) {
                    PlanEmpty(inCloud: true)
                } else {
                    eventBlock
                    list
                }
                // Касание по пустому месту под планом убирает клавиатуру и
                // крестик у точки: выход — там, куда рука тянется сама.
                Color.clear
                    .frame(height: 18)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        hideKeyboard()
                        withAnimation(.easeOut(duration: 0.15)) { armedLine = nil }
                    }
            }
            .onChange(of: typingIn) { _, id in show(id, proxy) }
            .onChange(of: keyboard) { _, _ in show(typingIn, proxy) }
        }
        .keyboardHeight($keyboard)
        // Точка в названии дела открывает карту, как точка строкой (P256).
        .environment(\.openPoint, { point in shell.showPoint(point) })
        .onChange(of: store.date) { _, _ in
            typingIn = nil
            armedLine = nil
            reloadEvents()
        }
        // События Календаря (P376): при появлении, после правки в
        // Календаре и при возвращении в приложение.
        .onAppear(perform: startEvents)
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            reloadEvents()
        }
        .confirmationDialog(T("Удалить дело?", "Delete the task?"),
                            isPresented: Binding(get: { askingDelete != nil },
                                                 set: { if !$0 { askingDelete = nil } }),
                            titleVisibility: .visible, presenting: askingDelete) { id in
            Button(T("Удалить", "Delete"), role: .destructive) {
                askingDelete = nil
                withAnimation(.easeOut(duration: 0.2)) { store.delete(id) }
                Feel.light()
            }
            Button(T("Оставить", "Keep"), role: .cancel) { askingDelete = nil }
        } message: { id in
            Text(store.index(of: id).map { store.planRows[$0].text } ?? "")
        }
        .confirmationDialog(T("Событие Календаря", "Calendar event"),
                            isPresented: Binding(get: { askingEvent != nil },
                                                 set: { if !$0 { askingEvent = nil } }),
                            titleVisibility: .visible, presenting: askingEvent) { e in
            eventChoices(e)
        } message: { _ in
            Text(T("«Убрать» — событие останется в Календаре, уйдёт только из плана этого дня. "
                   + "Удалённое из Календаря шагом назад не вернуть.",
                   "“Remove” keeps the event in Calendar and only takes it off this day’s plan. "
                   + "Deleting from Calendar cannot be undone here."))
        }
        .sheet(item: $openedEvent) { o in
            EventSheet(event: o.event) {
                openedEvent = nil
                reloadEvents()
            }
            .ignoresSafeArea()
        }
        // Копия несомого снимка — над пальцем, в синей рамке (P377).
        .overlay {
            if let c = photoCarry, photoSpot != .zero {
                GeometryReader { g in
                    let o = g.frame(in: .global).origin
                    PlanPhotoThumb(url: store.photoURL(c.link))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Look.glow, lineWidth: 2.6))
                        .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                        .scaleEffect(1.08)
                        .position(x: photoSpot.x - o.x, y: photoSpot.y - o.y - 48)
                }
                .allowsHitTesting(false)
            }
        }
        .onChange(of: typingIn) { _, now in if now != nil { armedLine = nil } }
        // Дело из серии поправили или убирают — только здесь или дальше
        // тоже (P359).
        .modifier(SeriesQuestion())
        // Где пишут — там «где был» для «Открывать на» (P408).
        .onChange(of: typingIn) { _, now in if now != nil { shell.tab = .plan } }
        // Прошедший день не бледнеет: он правится, как любой (P381).
    }

    /// Довести строку до глаз. С задержкой в один оборот: пока клавиатура
    /// не встала на место, высота ещё не та, и прокрутка уедет не туда.
    private func show(_ id: UUID?, _ proxy: ScrollViewProxy) {
        guard let id else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    /// Пустая плашка следующего дела (P406): «плюса» больше нет. Касание
    /// по ней — новое дело и курсор в нём; по времени или колокольчику —
    /// новое дело и сразу ролик.
    private func add(then kind: Shell.Roller.Kind? = nil) {
        guard let id = store.addTask() else { return shell.say(store.closedReason) }
        if let kind { openRoller(id, kind) } else { typingIn = id }
    }

    /// Пустая плашка видна, пока все дела чем-то заполнены: начали писать в
    /// новом — под ним появляется следующая (P406).
    private var ghostShown: Bool {
        // В прошедших днях пустой плашки нет (P421).
        store.canEditPlan && !store.isPast && !store.tasks.contains(where: PlanRow.blank)
    }

    private var ghost: some View {
        VStack(spacing: 0) {
            // Не «Без названия», а предложение помощи (P452).
            PlanRowLine(number: shownEvents.count + store.tasks.count + 1,
                        row: .task(PlanRow.ghostTitle),
                        bellColor: Look.accent,
                        onTime: { add(then: .time) },
                        onBell: { add(then: .bell) },
                        ghost: true)
        }
        .contentShape(Rectangle())
        .onTapGesture { add() }
        .accessibilityLabel(T("Новое дело", "New task"))
    }

    @ViewBuilder private var list: some View {
        ForEach($store.planRows) { row in
            let id = row.wrappedValue.id
            if row.wrappedValue.isTask {
                // Дело и черта под ним — одним куском: пока несут точку,
                // они расступаются вместе (P374).
                VStack(spacing: 0) {
                    taskRow(row)
                }
                .modifier(Zone(id: id))
                .offset(y: lineShift(id) + eventShift(id) + photoShift(id))
                .animation(.easeOut(duration: 0.16), value: lineShift(id) + eventShift(id) + photoShift(id))
                .zIndex(dragged == id || lifted == id ? 1 : 0)
            } else if let line = row.wrappedValue.verbatim {
                PlanExtraLine(line: line, resolve: store.photoURL,
                              open: { url in
                                  shell.openedPhoto = .init(tab: .plan, index: 0, url: url)
                              },
                              openPoint: { shell.showPoint($0) },
                              onCarry: store.canEditPlan
                                  ? { carryLine(id, $0, at: $1) } : nil,
                              onDelete: store.canEditPlan
                                  ? {
                                      armedLine = nil
                                      withAnimation(.easeOut(duration: 0.2)) { store.delete(id) }
                                  } : nil,
                              armed: armedLine == id,
                              carried: lineDrag == id,
                              onArm: { on in
                                  withAnimation(.easeOut(duration: 0.15)) { armedLine = on ? id : nil }
                              },
                              onPhoto: store.canEditPlan
                                  ? { carryPhoto($0, from: id, $1, at: $2) } : nil,
                              carriedPhoto: photoCarry?.from == id ? photoCarry?.link : nil)
                .modifier(Zone(id: id))
                .offset(y: lineShift(id) + eventShift(id) + photoShift(id))
                .animation(.easeOut(duration: 0.16), value: lineShift(id) + eventShift(id) + photoShift(id))
                .zIndex(lineDrag == id ? 1 : 0)
            }
        }
        if ghostShown { ghost }
        // Счёта «запланировано · сделано» больше нет (P425).
    }

    private func taskRow(_ row: Binding<PlanRow>) -> some View {
        let id = row.wrappedValue.id
        // События Календаря стоят первыми — дела считаются после них.
        let shown = shownEvents.count + number(of: id) + (dragged == id ? carried : displaced(id))
        let up = lifted == id

        return PlanRowLine(
            number: shown,
            row: row.wrappedValue,
            faded: false,
            bellColor: Look.accent,
            text: row.text,
            typing: typingIn == id,
            onTime: { openRoller(id, .time) },
            onBell: { openRoller(id, .bell) },
            onCheck: { toggle(row) },
            // Правку кончила эта самая строка, а не соседняя, которой
            // только что отдали ввод: иначе курсор гас бы сразу после
            // перехода в следующее дело.
            onDone: {
                if typingIn == id { typingIn = nil }
                store.save()
                store.checkSeries(id)
            },
            onNext: { next(after: id) },
            onLift: { lift(row, $0) },
            // Поднятое дело обведено синим — тем же, что и всё, что можно
            // взять пальцем (P203, P362); и дело, под которое ляжет
            // несомый снимок (P377).
            lifted: up || photoTo == id || shell.planHover?.id == id,
            past: store.isPast)
            // Снимок из полоски или из-под другого дела — под это дело, в
            // ряд с теми, что уже там (P358).
            .onDrop(of: store.canEditPlan ? [UTType.plainText] : [],
                    isTargeted: nil) { providers in
                PhotoDrop.read(providers) { store.putPlanPhoto($0, under: id) }
            }
            // Взятое дело идёт за пальцем, остальные расступаются по целым
            // строкам — так под ним открывается место, и видно, куда оно
            // встанет (решение P163). Вбок оно идёт только своё (P362).
            .id(id)
            .offset(x: up ? slide : 0,
                    y: dragged == id
                    ? dragOffset
                    : CGFloat(displaced(id)) * PlanRowLine.height)
            .animation(dragged == id ? nil : .easeOut(duration: 0.16),
                       value: displaced(id))
            .background { underneath(id) }
            .shadow(color: .black.opacity(dragged == id ? 0.18 : 0),
                    radius: 8, y: 3)
            .zIndex(dragged == id || up ? 1 : 0)
            .contentShape(Rectangle())
            // Короткое нажатие ставит курсор в текст дела. Сделано —
            // касанием по номеру (P383; прежде — сдвигом вправо, P362, а
            // ещё раньше — самим долгим нажатием, P156).
            .onTapGesture {
                armedLine = nil
                guard store.canEditPlan, typingIn != id else { return }
                typingIn = id
            }
    }

    /// Что открывается под делом, отведённым вбок: справа — красная
    /// корзина (P362), слева — синий календарик «на другой день» (P383).
    @ViewBuilder private func underneath(_ id: UUID) -> some View {
        if lifted == id, slide != 0 {
            Self.swipeBack(slide)
        }
    }

    /// Под значком — подпись словами (P465): жесты вбок угадать нельзя,
    /// подпись говорит, что случится, если отпустить.
    static func swipeBack(_ slide: CGFloat,
                          left: String = T("Удалить", "Delete")) -> some View {
        let far = abs(slide) >= Self.swipe
        let wide = abs(slide) >= 64
        return HStack(spacing: 0) {
            if slide > 0 {
                swipeMark("calendar.badge.clock", T("На другой день", "Another day"),
                          words: wide)
                    .frame(width: slide)
                    .frame(maxHeight: .infinity)
                    .background(Look.accent.opacity(far ? 0.9 : 0.45))
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                swipeMark("trash", left, words: wide)
                    .frame(width: -slide)
                    .frame(maxHeight: .infinity)
                    .background(Color.red.opacity(far ? 0.85 : 0.4))
            }
        }
        .foregroundStyle(.white)
        .allowsHitTesting(false)
    }

    private static func swipeMark(_ icon: String, _ words: String, words show: Bool) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: show ? 15 : 19, weight: .semibold))
            if show {
                Text(words)
                    .font(Look.sans(11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 4)
            }
        }
    }

    /// Дело подняли долгим нажатием и ведут (P362). Первый заметный ход
    /// пальца решает, куда: вверх-вниз — переставить, влево — удалить,
    /// вправо — перенести на другой день (P383). Дальше направление не меняется: дело, которое вели вниз,
    /// не удалится от случайного ухода пальца вбок.
    private func lift(_ row: Binding<PlanRow>, _ phase: Lift) {
        let id = row.wrappedValue.id
        switch phase {
        case .began:
            guard store.canEditPlan else { return shell.say(store.closedReason) }
            if typingIn != nil {
                hideKeyboard()
                typingIn = nil
            }
            Feel.lift()
            liftAxis = nil
            slide = 0
            armedLine = nil
            withAnimation(.easeOut(duration: 0.12)) { lifted = id }
        case .moved(let way):
            guard lifted == id else { return }
            if liftAxis == nil {
                if abs(way.width) > 14, abs(way.width) > abs(way.height) * 1.2 {
                    liftAxis = .horizontal
                } else if abs(way.height) > 10 {
                    liftAxis = .vertical
                }
            }
            switch liftAxis {
            case .vertical:
                dragged = id
                dragOffset = way.height
                dragBy = Int((way.height / PlanRowLine.height).rounded())
            case .horizontal:
                let was = abs(slide) >= Self.swipe
                slide = way.width
                // Порог пройден — щелчок: отпустить здесь значит сделать.
                if (abs(slide) >= Self.swipe) != was { Feel.tick() }
            case nil:
                break
            }
        case .ended, .cancelled:
            guard lifted == id else { return }
            let axis = liftAxis
            let by = slide
            let real: Bool
            if case .ended = phase { real = true } else { real = false }
            if axis == .vertical {
                drop(id)
                Feel.thud()
            }
            liftAxis = nil
            withAnimation(.easeOut(duration: 0.2)) {
                lifted = nil
                slide = 0
            }
            guard real, axis == .horizontal else { return }
            if by <= -Self.swipe {
                // Предохранитель (P458): пустое дело и дело из серии (у него
                // свой вопрос, P359) — сразу; остальное — после вопроса.
                let r = row.wrappedValue
                if r.repeats != nil || (r.text.isEmpty && r.details.isEmpty) {
                    withAnimation(.easeOut(duration: 0.2)) { store.delete(id) }
                    Feel.light()
                } else {
                    askingDelete = id
                }
            } else if by >= Self.swipe {
                Feel.paper()
                withAnimation(.pull) {
                    shell.movingTask = MovingTask(id: id, title: row.wrappedValue.text)
                }
            }
        }
    }

    /// Точку подержали и несут (P374). Подержали — сразу крупнее и с
    /// крестиком, с толчком; повели — крестик уходит, строки под пальцем
    /// расступаются, и видно, куда она встанет. Встаёт она только своей
    /// строкой между делами: в название дела — нет.
    private func carryLine(_ id: UUID, _ phase: Lift, at spot: CGPoint) {
        switch phase {
        case .began:
            if typingIn != nil {
                hideKeyboard()
                typingIn = nil
            }
            Feel.lift()
            lineDrag = nil
            withAnimation(.easeOut(duration: 0.15)) { armedLine = id }
        case .moved:
            let order = store.shownRowIDs
            if lineDrag == nil {
                guard let from = order.firstIndex(of: id) else { return }
                lineSpots = PlanZones.rows
                lineFrom = from
                lineTo = from
                lineHeight = lineSpots[id]?.height ?? 41
                withAnimation(.easeOut(duration: 0.15)) { armedLine = nil }
                lineDrag = id
            }
            // Место — сколько прочих строк выше пальца. Над первым делом
            // точке не стоять: она всегда под каким-нибудь делом.
            let others = order.filter { $0 != id }
            var to = others.filter { (lineSpots[$0]?.midY ?? .infinity) < spot.y }.count
            if let first = others.first, store.planRows.first(where: { $0.id == first })?.isTask == true {
                to = max(to, 1)
            }
            if to != lineTo {
                lineTo = to
                Feel.tick()
            }
        case .ended:
            PlanHold.ended = Date()
            guard lineDrag == id else { return }
            let by = lineTo - lineFrom
            lineDrag = nil
            if by != 0 {
                store.moveLine(id, by: by)
                Feel.thud()
            }
        case .cancelled:
            PlanHold.ended = Date()
            lineDrag = nil
        }
    }

    /// На сколько сдвинута строка, пока над ней несут точку.
    private func lineShift(_ id: UUID) -> CGFloat {
        guard let lineDrag, lineDrag != id, lineTo != lineFrom,
              let mine = store.shownRowIDs.firstIndex(of: id)
        else { return 0 }
        if lineTo > lineFrom, mine > lineFrom, mine <= lineTo { return -lineHeight }
        if lineTo < lineFrom, mine < lineFrom, mine >= lineTo { return lineHeight }
        return 0
    }

    // MARK: - События Календаря (P376)

    private var shownEvents: [DayEvents.Shown] {
        DayEvents.shown(events, marks: DayEvents.marks(in: store.planRows))
    }

    private func startEvents() {
        if DayEvents.on, !Vault.isPreview, DayEvents.status == .notDetermined {
            DayEvents.ask { _ in reloadEvents() }
        } else {
            reloadEvents()
        }
    }

    private func reloadEvents() {
        events = DayEvents.items(for: store.date)
    }

    /// События — каждое своим блоком, как дело, над делами (P376).
    @ViewBuilder private var eventBlock: some View {
        let list = shownEvents
        ForEach(Array(list.enumerated()), id: \.element.key) { i, e in
            eventRow(e, number: i + 1)
        }
    }

    private func eventRow(_ e: DayEvents.Shown, number: Int) -> some View {
        let up = liftedEvent == e.key
        return VStack(spacing: 0) {
            PlanRowLine(number: number,
                        row: e.row,
                        faded: false,
                        bellColor: Look.accent,
                        stripe: e.color,
                        onTime: { open(e) },
                        onBell: { open(e) },
                        onCheck: { checkEvent(e) },
                        onLift: { eventLift(e, $0) },
                        lifted: up,
                        past: store.isPast)
        }
        .background(GeometryReader { geo in
            let frame = geo.frame(in: .global)
            Color.clear
                .onAppear { PlanZones.events[e.key] = frame }
                .onChange(of: frame) { _, now in PlanZones.events[e.key] = now }
                .onDisappear { PlanZones.events[e.key] = nil }
        })
        .offset(x: up ? eventSlide : 0, y: up ? eventDrag : 0)
        .background {
            if up, eventSlide < 0 { Self.swipeBack(eventSlide, left: T("Убрать", "Remove")) }
        }
        .shadow(color: .black.opacity(up && eventDrag != 0 ? 0.18 : 0), radius: 8, y: 3)
        .zIndex(up ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { open(e) }
    }

    /// Событие в окне Календаря: посмотреть, поправить, напоминание.
    private func open(_ e: DayEvents.Shown) {
        guard let event = DayEvents.event(e.key, on: store.date) else {
            return shell.say(T("Этого события уже нет в Календаре.", "This event is no longer in Calendar."))
        }
        hideKeyboard()
        openedEvent = OpenedEvent(event: event)
    }

    /// Событие сделано или снова не сделано — касанием по номеру, как
    /// дело (P383).
    private func checkEvent(_ e: DayEvents.Shown) {
        guard store.canEditPlan else { return shell.say(store.closedReason) }
        markEvent(e) { $0.done.toggle() }
        if !e.row.done { Feel.done() } else { Feel.light() }
    }

    /// Событие подняли долгим нажатием (P376) — как дело: влево — убрать
    /// или удалить, вниз под блок событий — в свои дела, на то место, где
    /// расступились строки. Вправо событие не ходит: его день назначен в
    /// Календаре, а сделано — касанием по номеру (P383).
    private func eventLift(_ e: DayEvents.Shown, _ phase: Lift) {
        switch phase {
        case .began:
            guard store.canEditPlan else { return shell.say(store.closedReason) }
            if typingIn != nil {
                hideKeyboard()
                typingIn = nil
            }
            Feel.lift()
            eventAxis = nil
            eventSlide = 0
            eventDrag = 0
            eventTo = nil
            armedLine = nil
            eventSpots = PlanZones.rows
            let frame = PlanZones.events[e.key]
            eventHeight = frame?.height ?? PlanRowLine.height
            eventStart = frame?.midY ?? 0
            eventBlockEnd = PlanZones.events.values.map(\.maxY).max() ?? 0
            withAnimation(.easeOut(duration: 0.12)) { liftedEvent = e.key }
        case .moved(let way):
            guard liftedEvent == e.key else { return }
            if eventAxis == nil {
                if abs(way.width) > 14, abs(way.width) > abs(way.height) * 1.2 {
                    eventAxis = .horizontal
                } else if abs(way.height) > 10 {
                    eventAxis = .vertical
                }
            }
            switch eventAxis {
            case .vertical:
                eventDrag = way.height
                let y = eventStart + way.height
                var to: Int?
                if y > eventBlockEnd {
                    to = store.tasks.filter { (eventSpots[$0.id]?.midY ?? .infinity) < y }.count
                }
                if to != eventTo {
                    eventTo = to
                    if to != nil { Feel.tick() }
                }
            case .horizontal:
                let was = abs(eventSlide) >= Self.swipe
                eventSlide = min(0, way.width)
                if (abs(eventSlide) >= Self.swipe) != was { Feel.tick() }
            case nil:
                break
            }
        case .ended, .cancelled:
            guard liftedEvent == e.key else { return }
            let axis = eventAxis
            let by = eventSlide
            let to = eventTo
            let real: Bool
            if case .ended = phase { real = true } else { real = false }
            eventAxis = nil
            withAnimation(.easeOut(duration: 0.2)) {
                liftedEvent = nil
                eventSlide = 0
                eventDrag = 0
                eventTo = nil
            }
            guard real else { return }
            if axis == .horizontal {
                if by <= -Self.swipe {
                    askingEvent = e
                }
            } else if axis == .vertical, let to {
                var row = PlanRow.task(time: e.row.time, e.row.text)
                row.done = e.row.done
                withAnimation(.easeOut(duration: 0.2)) {
                    store.insertTask(row, beforeTask: to)
                    markEvent(e) { $0.hidden = true }
                }
                Feel.thud()
            }
        }
    }

    // MARK: - Снимки под делами (P377)

    /// Снимок из ряда под делом подняли и ведут: под какое дело он ляжет —
    /// то, чей верх выше пальца; ниже всех строк, над полоской, — назад в
    /// полоску. Строки под выбранным делом расступаются под новый ряд.
    private func carryPhoto(_ link: String, from row: UUID, _ phase: Lift, at spot: CGPoint) {
        switch phase {
        case .began:
            guard store.canEditPlan else { return shell.say(store.closedReason) }
            if typingIn != nil {
                hideKeyboard()
                typingIn = nil
            }
            Feel.lift()
            armedLine = nil
            photoSpots = PlanZones.rows
            photoStripTop = PlanZones.strip?.minY ?? .infinity
            photoTo = nil
            photoBack = false
            photoSlot = nil
            photoSpot = spot
            photoCarry = PhotoCarry(link: link, from: row)
        case .moved:
            guard photoCarry?.link == link else { return }
            photoSpot = spot
            let back = spot.y >= photoStripTop - 8
            // Вдоль своего ряда — переставить в ряду (P409).
            let slot = back ? nil : slotInRow(row, at: spot)
            if slot != photoSlot {
                photoSlot = slot
                if slot != nil { Feel.tick() }
            }
            var to: UUID?
            if !back, slot == nil {
                let list = store.tasks
                to = list.last { (photoSpots[$0.id]?.minY ?? .infinity) < spot.y }?.id ?? list.first?.id
                if to == owner(of: row) { to = nil }
            }
            if to != photoTo || back != photoBack {
                withAnimation(.easeOut(duration: 0.16)) {
                    photoTo = to
                    photoBack = back
                }
                if to != nil || back { Feel.tick() }
            }
        case .ended, .cancelled:
            guard photoCarry?.link == link else { return }
            let to = photoTo
            let back = photoBack
            let slot = photoSlot
            let real: Bool
            if case .ended = phase { real = true } else { real = false }
            withAnimation(.easeOut(duration: 0.2)) {
                photoCarry = nil
                photoTo = nil
                photoBack = false
                photoSlot = nil
                photoSpot = .zero
                guard real else { return }
                if let slot {
                    store.reorderPlanPhoto(link, in: row, to: slot)
                } else if back {
                    store.returnPlanPhoto(link)
                } else if let to {
                    store.putPlanPhoto(link, under: to)
                }
            }
            if real, back || to != nil || slot != nil { Feel.thud() }
        }
    }

    /// Место в своём ряду снимков под пальцем: перед каким снимком встать.
    /// `nil` — палец не над этим рядом.
    private func slotInRow(_ row: UUID, at spot: CGPoint) -> Int? {
        guard let frame = photoSpots[row], frame.insetBy(dx: 0, dy: -6).contains(spot),
              let line = store.planRows.first(where: { $0.id == row })?.verbatim
        else { return nil }
        let count = Diary.links(in: line).count
        guard count > 1 else { return nil }
        let cell = DiaryEditor.photoSize.width + 8
        let slot = Int(((spot.x - frame.minX - 14) + cell / 2) / cell)
        return min(max(slot, 0), count)
    }

    /// Дело, под которым стоит строка.
    private func owner(of row: UUID) -> UUID? {
        guard let i = store.index(of: row) else { return nil }
        return store.planRows[..<i].last { $0.isTask }?.id
    }

    /// На сколько сдвинута строка, пока несут снимок: под выбранным делом
    /// открывается место под новый ряд — если ряда снимков там ещё нет.
    private func photoShift(_ id: UUID) -> CGFloat {
        // Свой снимок из-под дела — или снимок из дневника и полоски (P409).
        let target = photoCarry != nil ? photoTo
            : (shell.planHover?.photo == true ? shell.planHover?.id : nil)
        guard let to = target, let t = store.index(of: to),
              let mine = store.index(of: id), mine > t else { return 0 }
        let next = t + 1
        if next < store.planRows.count, store.planRows[next].verbatim.map(Plan.isPhotoRow) == true {
            return 0
        }
        return PlanPhotoLine.height + 1
    }

    /// На сколько сдвинута строка, пока событие несут к делам.
    private func eventShift(_ id: UUID) -> CGFloat {
        guard let to = eventTo else { return 0 }
        let list = store.tasks
        guard to < list.count, let anchor = store.index(of: list[to].id),
              let mine = store.index(of: id) else { return 0 }
        return mine >= anchor ? eventHeight : 0
    }

    /// Поправить отметку события в файле плана.
    private func markEvent(_ e: DayEvents.Shown, _ change: (inout DayEvents.Mark) -> Void) {
        var mark = DayEvents.marks(in: store.planRows).first { $0.key == e.key }
            ?? DayEvents.Mark(key: e.key, time: e.row.time, title: e.row.text)
        mark.time = e.row.time
        mark.title = e.row.text
        change(&mark)
        store.setMark(mark)
    }

    @ViewBuilder private func eventChoices(_ e: DayEvents.Shown) -> some View {
        Button(T("Убрать из плана этого дня", "Remove from this day’s plan")) {
            withAnimation(.easeOut(duration: 0.2)) { markEvent(e) { $0.hidden = true } }
        }
        if let event = DayEvents.event(e.key, on: store.date), event.calendar.allowsContentModifications {
            if event.hasRecurrenceRules {
                Button(T("Удалить из Календаря: только это", "Delete from Calendar: this one only"),
                       role: .destructive) { remove(event, .thisEvent) }
                Button(T("Удалить из Календаря: это и все следующие", "Delete from Calendar: this and all following"),
                       role: .destructive) { remove(event, .futureEvents) }
            } else {
                Button(T("Удалить из Календаря iPhone", "Delete from iPhone Calendar"),
                       role: .destructive) { remove(event, .thisEvent) }
            }
        }
        Button(T("Отмена", "Cancel"), role: .cancel) { }
    }

    private func remove(_ event: EKEvent, _ span: EKSpan) {
        do {
            try DayEvents.store.remove(event, span: span, commit: true)
            Feel.light()
        } catch {
            shell.say(T("Календарь не дал удалить событие: ", "Calendar did not let the event be deleted: ")
                      + error.localizedDescription)
        }
        reloadEvents()
    }

    /// Дело отпустили: оно встаёт туда, куда его донесли.
    private func drop(_ id: UUID) {
        let by = dragBy
        dragged = nil
        dragBy = 0
        dragOffset = 0
        guard by != 0 else { return }
        for _ in 0..<abs(by) { store.move(id, by: by > 0 ? 1 : -1) }
    }

    /// «Ввод» в названии: ввод переходит к делу ниже.
    ///
    /// Клавиша «Ввод» уводит на строку ниже, к следующему делу. У
    /// последнего дела правка кончается: новое дело заводится только
    /// плюсом. Дело, которое завелось само от «Ввода», — это движение
    /// помимо воли человека (решение P193, уточняет P180).
    private func next(after id: UUID) {
        let дела = store.tasks
        guard let i = дела.firstIndex(where: { $0.id == id }) else { return }
        if i + 1 < дела.count {
            typingIn = дела[i + 1].id
            return
        }
        typingIn = nil
    }

    private func openRoller(_ id: UUID, _ kind: Shell.Roller.Kind) {
        guard store.canEditPlan else { return shell.say(store.closedReason) }
        // Ролик встаёт на место клавиатуры, а не поверх неё: два разных
        // способа ввода разом на экране не помещаются, и человеку пришлось
        // бы сперва убирать клавиатуру самому (решение P176).
        hideKeyboard()
        shell.roller = .init(id: id, kind: kind)
    }


    private func toggle(_ row: Binding<PlanRow>) {
        guard store.canEditPlan else { return shell.say(store.closedReason) }
        row.wrappedValue.done.toggle()
        // Сделано — довольный толчок; снято — лёгкий (P267).
        if row.wrappedValue.done { Feel.done() } else { Feel.light() }
        store.save()
    }

    /// Куда встанет взятое дело: столько строк оно пройдёт на самом деле.
    /// За края списка вынести его нельзя, поэтому ход подрезан.
    private var carried: Int {
        guard let dragged,
              let from = store.tasks.firstIndex(where: { $0.id == dragged })
        else { return 0 }
        let to = min(max(from + dragBy, 0), store.tasks.count - 1)
        return to - from
    }

    /// На сколько строк отодвигается соседнее дело, пока над ним проносят
    /// другое. Место под взятым делом должно освобождаться: иначе человек
    /// отпускает его поверх чужой строки и не понимает, куда оно встанет.
    private func displaced(_ id: UUID) -> Int {
        guard let dragged, dragged != id,
              let from = store.tasks.firstIndex(where: { $0.id == dragged }),
              let mine = store.tasks.firstIndex(where: { $0.id == id })
        else { return 0 }
        let to = min(max(from + dragBy, 0), store.tasks.count - 1)
        if to > from, mine > from, mine <= to { return -1 }
        if to < from, mine < from, mine >= to { return 1 }
        return 0
    }

    private func number(of id: UUID) -> Int {
        (store.tasks.firstIndex { $0.id == id } ?? 0) + 1
    }
}

extension View {
    /// Убрать клавиатуру. Поднявшуюся клавиатуру должно быть чем опустить,
    /// иначе экран заперт.
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

/// Пустой день. Общий для открытой страницы и соседних.
struct PlanEmpty: View {
    /// Файл плана лежит в iCloud и ещё не скачан. Пустая страница здесь
    /// не значит пустой день — так и надо сказать (решение P182).
    var inCloud = false

    var body: some View {
        VStack(spacing: 4) {
            if inCloud {
                Text(T("План этого дня ещё загружается из iCloud.", "This plan is still downloading from iCloud."))
                Text(T("Как только придёт, он появится здесь.", "It will appear here as soon as it arrives."))
            } else {
                Text(T("На этот день ничего не запланировано.", "Nothing planned for this day."))
                Text(T("Нажмите «+», чтобы вписать дело.", "Tap “+” to add a task."))
            }
        }
        .font(Look.sans(14))
        .lineSpacing(5)
        .foregroundStyle(Look.inkFaint)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.horizontal, 22)
    }
}

/// Строка плана, которая не дело: снимок, поставленный между делами в
/// прежних сборках, или точка с карты. Прочие строки файла не рисуются,
/// но в файле остаются (P210, P213).
struct PlanExtraLine: View {
    let line: String
    var resolve: ((String) -> URL?)?
    var open: ((URL?) -> Void)?
    /// Касание по точке — карта на ней. Пусто — на соседних страницах.
    var openPoint: ((GeoPoint) -> Void)?
    /// Точку цепляют долгим нажатием и несут к нужному делу (P226, P241,
    /// P362, P374): ход пальца и где он на экране.
    var onCarry: ((Lift, CGPoint) -> Void)?
    /// Крестик у точки — строка уходит из плана (P352). Запомненное место
    /// остаётся на карте: из плана уходит только ссылка на него.
    var onDelete: (() -> Void)?
    /// Точку подержали и отпустили, не сдвинув: она крупнее, у неё крестик
    /// (P362). Касание по ней — крестик убрать.
    var armed = false
    /// Точку несут пальцем — она обведена синим.
    var carried = false
    var onArm: ((Bool) -> Void)?
    /// Снимок из ряда под делом несут пальцем (P377).
    var onPhoto: ((String, Lift, CGPoint) -> Void)? = nil
    var carriedPhoto: String? = nil

    var body: some View {
        if Plan.isPhotoRow(line) {
            // Снимки под делом — в ряд; каждый несут пальцем под другое
            // дело или назад в полоску (P358, P362).
            // Ряд — целое число клеток листа (P413).
            GridSnap {
                PlanPhotoRow(links: Diary.links(in: line), resolve: resolve, open: open,
                             onCarry: onPhoto, carried: carriedPhoto)
            }
        } else if let point = Geo.point(in: line) {
            GridSnap {
                PlanPointLine(point: point, open: tapPoint, armed: armed, glowing: armed || carried,
                              onDelete: onDelete)
            }
            .modifier(Carry(report: onCarry))
        }
    }

    /// Касание по точке: с крестиком — убрать крестик, без него — карта.
    /// Касание, которое на деле было концом долгого нажатия, — ни то ни
    /// другое: прежде после него открывалась карта (P374).
    private var tapPoint: ((GeoPoint) -> Void)? {
        guard let openPoint else { return nil }
        return { point in
            guard Date().timeIntervalSince(PlanHold.ended) > 0.4 else { return }
            if armed { onArm?(false) } else { openPoint(point) }
        }
    }
}

/// Вопрос о деле из серии: только этот день или этот и все следующие
/// (P359). Отдельно от плана: его цепочка и так длинная.
private struct SeriesQuestion: ViewModifier {
    @EnvironmentObject private var store: DayStore

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: shown, titleVisibility: .visible,
                                   presenting: store.seriesAsk) { ask in
            Button(only(ask)) { store.answerSeries(ask, all: false) }
            if ask.delete {
                Button(all(ask), role: .destructive) { store.answerSeries(ask, all: true) }
            } else {
                Button(all(ask)) { store.answerSeries(ask, all: true) }
            }
            Button(T("Отмена", "Cancel"), role: .cancel) { cancel(ask) }
        }
    }

    private var title: String { T("Это повторяющееся дело", "This is a repeating task") }

    private var shown: Binding<Bool> {
        Binding(get: { store.seriesAsk != nil }, set: { if !$0 { store.seriesAsk = nil } })
    }

    private func only(_ ask: DayStore.SeriesAsk) -> String {
        ask.delete ? T("Удалить только в этот день", "Delete this day only")
                   : T("Изменить только этот день", "Change this day only")
    }

    private func all(_ ask: DayStore.SeriesAsk) -> String {
        ask.delete ? T("Удалить этот и все следующие", "Delete this and all following")
                   : T("Изменить этот и все следующие", "Change this and all following")
    }

    /// Правку уже не отменить — она остаётся только в этом дне.
    private func cancel(_ ask: DayStore.SeriesAsk) {
        if ask.delete { store.seriesAsk = nil } else { store.answerSeries(ask, all: false) }
    }
}

/// Где на экране строки открытой страницы плана — дела, снимки и точки:
/// по ним ищется, куда встанет несомая точка (P374).
enum PlanZones {
    static var rows: [UUID: CGRect] = [:]

    /// Дело, под которое встанет принесённое из дневника или полоски
    /// (P409): последнее дело выше пальца. `nil` — палец не над планом.
    static func task(at spot: CGPoint, tasks: [PlanRow]) -> UUID? {
        guard spot != .zero else { return nil }
        let frames = tasks.compactMap { t in rows[t.id].map { (t.id, $0) } }
        guard let top = frames.map(\.1.minY).min() else { return nil }
        let bottom = rows.values.map(\.maxY).max() ?? top
        guard spot.y >= top - 8, spot.y <= bottom + 24 else { return nil }
        return frames.last { $0.1.minY < spot.y }?.0 ?? frames.first?.0
    }
    /// События Календаря (P376) — по их ключам.
    static var events: [String: CGRect] = [:]
    /// Полоска снимков внизу — туда снимок возвращают (P377).
    static var strip: CGRect?
}

/// Записать, где строка на экране.
private struct Zone: ViewModifier {
    let id: UUID

    func body(content: Content) -> some View {
        content.background(GeometryReader { geo in
            let frame = geo.frame(in: .global)
            Color.clear
                .onAppear { PlanZones.rows[id] = frame }
                .onChange(of: frame) { _, now in PlanZones.rows[id] = now }
                .onDisappear { PlanZones.rows[id] = nil }
        })
    }
}

/// Когда кончилось последнее долгое нажатие на точку: касание сразу после
/// него — это тот же палец, а не просьба открыть карту (P374).
enum PlanHold {
    static var ended = Date.distantPast
}

/// Точку в плане цепляют долгим нажатием и несут вверх-вниз (P374).
/// Толчок и отклик — в тот миг, когда нажатие стало долгим, а не когда
/// палец убрали. Точка едет за пальцем; куда она встанет, решает план.
private struct Carry: ViewModifier {
    let report: ((Lift, CGPoint) -> Void)?

    /// Подъём уже объявлен.
    @State private var lifted = false
    /// Палец повёл — это перенос, а не просьба о крестике.
    @State private var moved = false
    @State private var dragged: CGFloat = 0
    /// Жест жив. Оборвался сам (палец увела прокрутка) — точка встаёт на
    /// место.
    @GestureState private var holding = false

    func body(content: Content) -> some View {
        if let report {
            content
                .offset(y: dragged)
                .shadow(color: .black.opacity(dragged == 0 ? 0 : 0.18), radius: 8, y: 3)
                .gesture(LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .updating($holding) { value, state, _ in
                        if case .second(true, _) = value { state = true }
                    }
                    .onChanged { value in
                        guard case .second(true, let drag) = value else { return }
                        if !lifted {
                            lifted = true
                            moved = false
                            report(.began, .zero)
                        }
                        guard let drag else { return }
                        if !moved, abs(drag.translation.height) > 10 || abs(drag.translation.width) > 10 {
                            moved = true
                        }
                        guard moved else { return }
                        dragged = drag.translation.height
                        report(.moved(drag.translation), drag.location)
                    }
                    .onEnded { value in
                        guard lifted else { return }
                        lifted = false
                        dragged = 0
                        var way = CGSize.zero
                        if case .second(true, let drag) = value, let drag { way = drag.translation }
                        report(.ended(way), .zero)
                    })
                .onChange(of: holding) { _, now in
                    guard !now else { return }
                    DispatchQueue.main.async {
                        guard lifted else { return }
                        lifted = false
                        dragged = 0
                        report(.cancelled, .zero)
                    }
                }
                .accessibilityHint(T("Долгое нажатие — перетащить к другому делу", "Long press to drag next to another task"))
        } else {
            content
        }
    }
}

/// Точка в плане — та же кнопочка, что в дневнике: булавка и название, без
/// координат (P345); касание открывает карту на ней (P213). Подержали —
/// крупнее и с крестиком «удалить», как значок на экране «Домой» (P362).
struct PlanPointLine: View {
    let point: GeoPoint
    var open: ((GeoPoint) -> Void)?
    var armed = false
    /// Синий контур: точку несут или у неё крестик (P374).
    var glowing = false
    var onDelete: (() -> Void)?

    var body: some View {
        HStack(spacing: 0) {
            // Такой же квадрат, как снимок и точка в дневнике (P587).
            PointSquare(point: point)
                .frame(width: DiaryEditor.photoSize.width, height: DiaryEditor.photoSize.height)
                .scaleEffect(armed ? 1.1 : 1, anchor: .leading)
                .contentShape(Rectangle())
                .onTapGesture { open?(point) }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(T("Точка на карте: ", "Place on the map: ") + point.label)
            Spacer(minLength: 0)
            // Крестик — крупный, в той же строке справа (P380): маленький
            // на углу точки было плохо видно.
            if armed, let onDelete { DeleteBadge(action: onDelete) }
        }
        .padding(.horizontal, 14)
        .frame(height: PlanPhotoLine.height)
        // Строка точки — в тонкой синей рамке, пока точку держат или у
        // неё крестик; рамка едет вместе с точкой (P380).
        .background {
            if glowing {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Look.planBg.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Look.glow, lineWidth: 1.5))
                    .shadow(color: Look.glow.opacity(0.5), radius: 4)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Крестик «удалить» на углу поднятой точки (P362): красный кружок с белым
/// крестом — его видно на любой бумаге.
struct DeleteBadge: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // Выразительнее (P386): крест толще, белая кайма и тень —
            // отделяют кружок от снимка или бумаги под ним.
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Look.pin)
                .font(.system(size: 31, weight: .bold))
                .background(Circle().fill(.white).padding(-2.5))
                .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                .frame(width: 48, height: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(T("Удалить", "Delete"))
    }
}

/// Кнопочка точки для SwiftUI — нарисована тем же кодом, что в тексте
/// дневника, чтобы не расходилась с ним.
struct PointChipView: View {
    let point: GeoPoint

    /// Ширина кнопочки — по ней крестик встаёт на угол.
    static func width(_ point: GeoPoint) -> CGFloat {
        PointChip.mark(glowing: false, title: point.title).size.width
    }

    var body: some View {
        // Как в тексте дневника: булавка, у точки с названием — и название,
        // без координат; координаты — на карте, куда ведёт касание (P345).
        let picture = PointChip.mark(glowing: false, title: point.title)
        Image(uiImage: picture)
            .frame(width: picture.size.width, height: picture.size.height)
    }
}
