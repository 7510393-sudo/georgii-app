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
    static let height: CGFloat = PageTexture.cell * 2

    // MARK: - Мера строки
    //
    // Ширины головы заданы числами, а не меряются по содержимому: ровно на
    // ширину головы отступает первая строка названия, и разойдись они хоть
    // на точку — название наползёт на колокольчик или отскочит от него.

    /// Квадратики головы — в клетку листа (P797): на точку внутри клетки с
    /// каждой стороны.
    static let badgeWidth: CGFloat = PageTexture.cell - 2
    static let timeWidth: CGFloat = 64
    /// Место за временем (P874): полторы клетки. В первой — колокольчик,
    /// если напоминание есть; нет — клетка пустая. Своего квадратика у
    /// колокольчика больше нет.
    static let bellWidth: CGFloat = PageTexture.cell * 1.5
    static let gap: CGFloat = 8
    /// Высота площадки для пальца у номера и времени (P465).
    static let reach: CGFloat = 44

    /// Голова строки: номер, время.
    static let headWidth = badgeWidth + gap + timeWidth

    /// Отступ первой строки названия: через полторы клетки за временем (P874).
    static let indent = headWidth + bellWidth

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
        GridSnap(top: true) {
        VStack(alignment: .leading, spacing: 2) {
            // Голова стоит поверх отступа первой строки названия, а не
            // рядом с ним: тогда вторая и третья строки идут во всю ширину,
            // а не складываются в столбик (решение P177).
            ZStack(alignment: Alignment(horizontal: .leading,
                                        vertical: .firstTextBaseline)) {
                title.opacity(ghost ? 0 : 1)
                head
            }
        }
        // Корешка «Детали» справа нет — название идёт до контура (P408).
        // Плашка уже с боков — и содержимое отступает вместе с ней (P413).
        .padding(.trailing, 20)
        .padding(.leading, 18)
        // Строчка письма — на линии клетки (P795): сверху ровно столько,
        // чтобы низ букв лёг на первую линию; строка в одну строчку — две
        // клетки, вторая — просвет до следующего дела.
        .padding(.top, PlanTitle.lead)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Плашка — только у поднятого дела (P793).
        .background { contour }
    }

    /// Сделанное дело (P383): текст и кнопки бледнеют, а номер остаётся
    /// ярким и перечёркнут косой чертой — по нему видно, что отмечено и
    /// куда нажать, чтобы снять отметку.
    // Пустая плашка — ярче прежнего (P465: на 0,3 подсказка не читалась).
    private var dim: Double { ghost ? 0.55 : (row.done ? 0.42 : 1) }

    /// Дело пишется прямо по клетке листа, без жёлтой плашки (P793, вместо
    /// плашек P374, P413, P415, P421, P678): лист дня не похож на стопку
    /// карточек над и под ним. Плашка появляется, только пока дело подняли
    /// и несут (P362), — синей рамкой, чтобы было видно, что в руке.
    @ViewBuilder private var contour: some View {
        if lifted {
            let shape = RoundedRectangle(cornerRadius: 9)
            shape
                .fill(past ? Ru.pastTint : Look.plateLight)
                .overlay(shape.strokeBorder(Look.glow, lineWidth: 3.25))
                .shadow(color: Look.glow.opacity(0.9), radius: 5)
                .padding(.leading, 10)
                .padding(.trailing, 10)
                .padding(.vertical, 2)
                .allowsHitTesting(false)
        }
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
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            badge
                .padding(.trailing, Self.gap)
            // Пустая строка следующего дела — только бледный номер (P797):
            // время и подсказка появляются, когда по ней коснулись и дело
            // завелось.
            time.opacity(ghost ? 0 : 1).allowsHitTesting(!ghost)
            bell.opacity(ghost ? 0 : 1).allowsHitTesting(!ghost)
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
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - PlanTitle.above + 1 }
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
            // 12 или 24 часа — как выбрано (P602); в файле — «21:30».
            Text(row.time.map(Clock.show) ?? "--:--")
                // «9:00 AM» на два знака длиннее «09:00» — мельче, чтобы
                // плашка не росла (по ней отсчитан отступ названия).
                .font(Look.mono(row.time != nil && Clock.twelve ? 12.5 : 17))
                .tracking(row.time == nil ? 0.6 : 0)
                // Время — всегда одна строка. «--:--» с разрядкой не
                // умещалось в отведённую ширину и переносилось надвое:
                // на странице оставался висеть один прочерк.
                .lineLimit(1)
                .minimumScaleFactor(Clock.twelve ? 0.6 : 0.8)
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
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - PlanTitle.above + 1 }
        }
        .opacity(dim)
        .buttonStyle(.plain)
        // Не .disabled: система рисует выключенную кнопку бледнее, и время
        // на соседней странице выцветало, а после поворота «загоралось».
        // Вид не должен зависеть от того, можно ли нажать (P130).
        .allowsHitTesting(onTime != nil)
    }

    /// Колокольчик — в клетке за временем, только если напоминание есть
    /// (P874); дело из серии — значок повтора там же (P359). Без них клетка
    /// пустая. Касание — то же окно «Время».
    private var bell: some View {
        Button { onBell?() } label: {
            ZStack {
                if row.bell != nil {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(bellColor)
                }
                if row.repeats != nil {
                    Image(systemName: "arrow.2.circlepath")
                        .font(.system(size: row.bell == nil ? 12 : 8, weight: .bold))
                        .foregroundStyle(Look.accent)
                        .offset(x: row.bell == nil ? 0 : 7, y: row.bell == nil ? 0 : 6)
                }
            }
            .frame(width: PageTexture.cell, height: PlanRowLine.badgeWidth)
            .frame(width: PlanRowLine.bellWidth, height: PlanRowLine.badgeWidth, alignment: .leading)
            .contentShape(Rectangle().size(width: PageTexture.cell,
                                           height: PlanRowLine.reach)
                                     .offset(y: -(PlanRowLine.reach - PlanRowLine.badgeWidth) / 2))
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - PlanTitle.above + 1 }
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
        // Строки подробностей — продолжение названия тем же шрифтом (P652;
        // прежде — бледными строками под делом, P408).
        PlanTitle(text: text ?? .constant(row.fullTitle),
                  indent: Self.indent,
                  wrap: Self.wrap,
                  faded: faded,
                  editable: text != nil && typing,
                  typing: typing,
                  onDone: onDone,
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
            .shadow(color: .black.opacity(0.06), radius: 1, x: 1, y: 1)
    }
}
