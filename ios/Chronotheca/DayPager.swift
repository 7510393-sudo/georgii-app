import SwiftUI
import UIKit
import PhotosUI
import Photos
import UniformTypeIdentifiers
import CoreTransferable

/// Дни листаются как страницы книги.
///
/// Вместе со страницей едет всё, что к этому дню относится: имя дня, день
/// недели, дата, вкладки и полоска вложений. Неподвижны только шестерёнка,
/// три точки и три раздела внизу — то, что принадлежит приложению, а не дню.
struct DayPages: View {

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var archive: Archive

    @State private var plan: [Int] = []

    var body: some View {
        PageCurl(content: { offset in
            DayPage(date: shift(offset), live: offset == 0)
                .environmentObject(vault)
                .environmentObject(store)
                .environmentObject(shell)
                .environmentObject(archive)
        }, onTurn: { step in
            hideKeyboard()
            shell.turn(step, store)
        }, plan: $plan)
        // Лента превью и строка вложений — одна, у низа экрана, над всеми
        // страницами (P544): не листается с днём, а с клавиатурой едет вверх.
        .overlay { StripDock() }
        .onChange(of: shell.goHome) { _, want in
            guard want else { return }
            shell.goHome = false
            plan = DayPages.wayHome(from: store.date)
        }
        // Ушли со вкладки в режиме изменений — режим выключается сам, а не
        // остаётся включённым за спиной (P330).
        .onChange(of: shell.tab) { _, now in
            for t in Shell.Tab.allCases where t != now { store.setEditing(t, false) }
        }
    }

    /// Сколько дней до сегодняшнего и в какую сторону.
    static func wayHome(from date: Date, to home: Date = DayStore.today()) -> [Int] {
        let days = Calendar.current.dateComponents([.day], from: date, to: home).day ?? 0
        return Chronotheca.wayHome(days)
    }

    private func shift(_ days: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: days, to: store.date) ?? store.date
    }
}

/// Одна страница дня.
///
/// Открытый день (`live`) правится; соседние — только показываются, пока
/// едут. Правят тот день, на котором человек остановился.
struct DayPage: View {

    let date: Date
    let live: Bool

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var archive: Archive

    @State private var remembering = false

    /// Дни, чьи облачка уже прочитаны (решение P136).
    @AppStorage(Remembered.key) private var read = ""

    var body: some View {
        VStack(spacing: 0) {
            // Облачко «…помнишь?» — над заголовком «Дневник» (P436).
            heading
                .overlay { galleryCatcher }
                .zIndex(1)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                // План и дневник уходят под шапку мягко, тая (P435): у
                // верхнего края страницы — полоса её цвета, прозрачная
                // книзу. Касания проходят насквозь.
                .overlay(alignment: .top) {
                    LinearGradient(colors: [Ru.tint(date), Ru.tint(date).opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                        // Короче прежних 22 точек: слово «План» вверху
                        // страницы больше не тонет в дымке (P441).
                        .frame(height: 14)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .top) { if !Shell.appStoreShots { steps } }
                // Черты между шапкой и страницей больше нет (P434, прежде
                // P250): шапка — продолжение листа.
        }
        .background(background)
        // Фактура страницы и вкладок отсчитывается от одной точки — клетка
        // на вкладке продолжает клетку страницы (P246).
        .coordinateSpace(name: PageTexture.space)
        // Снимок «А вот когда-то…» (P530): листок открыт, как после нажатия.
        .onAppear { showRememberForPreview() }
        .onChange(of: shell.previewRemember) { _, _ in showRememberForPreview() }
        .onChange(of: live) { _, _ in showRememberForPreview() }
        .sheet(isPresented: $remembering, onDismiss: forget) {
            if let (day, ago) = archive.remembered(for: date) {
                RememberSheet(day: day, ago: ago, open: $remembering)
            }
        }
    }

    /// (P527) Накладка лежала поверх всей страницы, и с ней поверх самого ряда
    /// галереи: касание по «все фото» или по снимку не доходило до них, а
    /// закрывало ряд. Теперь она внутри листа, под полоской вложений.
    /// Пока открыт ряд снимков галереи, касание по странице только
    /// закрывает его — курсор не ставится, клавиатура не поднимается;
    /// второе касание уже делает своё (P344).
    @ViewBuilder private var galleryCatcher: some View {
        if live && shell.gallery {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.easeOut(duration: 0.2)) { shell.gallery = false }
                }
        }
    }

    /// Облачко «А вот когда-то…» — над заголовком «Дневник» (P436). Теперь
    /// оно есть и на соседних страницах, пока они едут (P484, P114): раньше
    /// его не было на странице, пока та не становилась открытой, и оно
    /// выскакивало через полсекунды. Нажимается только открытое.
    private var cloud: some View {
        DayCloud(date: date, live: live) {
            // Облачко уходит сразу по нажатию, не по закрытию открывшегося
            // листка (P330).
            forget()
            remembering = true
        }
    }

    private func showRememberForPreview() {
        guard shell.previewRemember > 0, live, !remembering,
              archive.remembered(for: date) != nil else { return }
        remembering = true
    }

    /// Листок прочитан — облачко уходит: оно своё дело сделало, а звать
    /// второй раз к той же записи нечестно, человек уже откликнулся (P136).
    /// Уходит не мигом, а угасая: резкое исчезновение читается как сбой.
    private func forget() {
        // Не гаснет резко, а тает в воздухе — полторы секунды (P334; было
        // 0.35, автор просил дольше и мягче).
        withAnimation(.easeOut(duration: 1.5)) {
            read = Remembered.adding(Vault.stamp(date), to: read)
        }
    }

    /// Цвет страницы — по удалённости от сегодня, одинаковый у плана и
    /// дневника; различаются они фактурой: план — в клетку, дневник — на
    /// бумаге с волокном (P245).
    private var background: some View {
        Ru.tint(date).overlay(PageTexture(tab: .diary))
    }

    // MARK: - Шапка дня

    /// Шапка дня: соседние дни названы, а стрелка в сторону сегодняшнего
    /// горит. Уйдя на неделю назад, человек видит, что «сейчас» — справа,
    /// и не гадает, в какую сторону возвращаться (то же правило, что в
    /// календаре, P127).
    private var heading: some View {
        VStack(spacing: 2) {
            // Соседние дни стоят на одной строке с нынешним, а не над и под
            // ним: иначе взгляд скачет вверх-вниз и всякий раз перестраивается
            // с крупного на мелкое. Строка задана ростом жёстко, чтобы шапка
            // была одной высоты на любой странице (P113).
            // Имя дня поднялось на место прежней верхней строки, между
            // уголками с шестерёнкой и тремя точками; по бокам — только
            // стрелки, слов «вчера / завтра» рядом больше нет (P229).
            // Имя дня и под ним день недели с датой — одним блоком между
            // стрелками (P434): шапка ниже на строку, под текст больше места.
            HStack(spacing: 0) {
                side(-1)
                VStack(spacing: 0) {
                    Text(live ? store.title : DayPage.title(for: date))
                        .font(.system(size: 21, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Look.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    // День недели — только у дней с именем («вчера»,
                    // «завтра»…): у дальних он и так написан крупно (P425).
                    // Сначала число, справа день недели (P467).
                    (Text(Ru.headDate(date))
                        .foregroundColor(Look.inkSoft)
                     + Text(DayPage.named(date) ? ",  " + Ru.weekday(date) : "")
                        .foregroundColor(Ru.dayColor(date))
                        .tracking(0.4))
                        .font(Look.sans(12.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity)
                side(1)
            }
            .frame(height: DayPage.headLine + 8)
        }
        // Шапка на 30% уже экрана: по бокам — уголки бумаги (P229).
        .padding(.horizontal, Corner.size + 4)
        // Верх поднят (P434): над шапкой воздуха меньше.
        .padding(.top, 2)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
        // Шапка — продолжение листа дня, того же цвета (P434).
        .background(Ru.tint(date).overlay(PageTexture(tab: .diary)))
        .contentShape(Rectangle())
        .onTapGesture { hideKeyboard() }
    }

    /// Шаг назад и вперёд по всей странице, плану и дневнику разом (P408) —
    /// на цветном поле страницы, у краёв, в полупрозрачных кружках; страница
    /// едет под ними, а они стоят (P413; прежде — под уголками шапки, P409).
    private var steps: some View {
        HStack {
            stepArrow("arrow.uturn.backward", ready: live && store.canUndo,
                      name: T("Шаг назад", "Undo")) { store.undo() }
            Spacer(minLength: 0)
            stepArrow("arrow.uturn.forward", ready: live && store.canRedo,
                      name: T("Шаг вперёд", "Redo")) { store.redo() }
        }
        .padding(.horizontal, 8)
        // В полосе заголовка «ПЛАН» (две клетки) — не наезжают на плашку.
        .padding(.top, 1)
    }

    /// Высота строки заголовка. Одна на всех страницах: шапка не должна
    /// менять рост от того, горит стрелка или нет (P113).
    /// Выше прежних 31: стрелки на 50% крупнее (P425).
    static let headLine: CGFloat = 38

    /// Стрелка к соседнему дню. Слова «вчера / завтра» рядом с ней убраны
    /// (P229): имя открытого дня и так говорит, где мы.
    ///
    /// Горит та стрелка, что показывает дорогу к сегодняшнему дню (P127).
    /// Размер у обеих одинаковый: разным он менял бы рост строки.
    private func side(_ step: Int) -> some View {
        let lit = toward == step
        let sign = step < 0 ? "‹" : "›"
        // На 50% крупнее; к сегодняшнему дню — в обводке, как открытый
        // раздел в нижней строке (P425).
        let arrow = Text(sign)
            .font(.system(size: 31.5, weight: lit ? .bold : .regular))
            .foregroundStyle(lit ? Look.accent : Look.inkFaint)
            .frame(width: 36, height: DayPage.headLine - 4)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(lit ? Color.black.opacity(0.08) : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(lit ? Look.accent.opacity(0.75) : .clear, lineWidth: 1.3)))

        return arrow
            .frame(width: 44)
        .contentShape(Rectangle())
        // Дорога домой одна, какой кнопкой её ни начинай (решение P168).
        .onLongPressGesture(minimumDuration: 0.4) {
            guard live, lit else { return }
            hideKeyboard()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            shell.say(T("Вернулись на сегодня", "Back to today"))
            shell.goHome = true
        } onPressingChanged: { _ in }
        .onTapGesture {
            guard live else { return }
            hideKeyboard()
            // Вперёд — чуть выше тоном, назад — чуть ниже (P330).
            Sounds.flip(rate: step > 0 ? 1.04 : 0.96)
            // Тот же поворот, что пальцем: куда встанет новая страница —
            // по тому же правилу (P441). Прежде стрелки шапки его не знали,
            // и день всегда открывался на плане.
            shell.turn(step, store)
        }
        .accessibilityLabel(lit ? neighbour(step) + T(". Долгое нажатие — на сегодня", ". Long press for today")
                                : neighbour(step))
    }

    /// В какой стороне сегодняшний день: −1 слева, +1 справа, 0 — мы на нём.
    private var toward: Int {
        let today = DayStore.today()
        if date < today { return 1 }
        if date > today { return -1 }
        return 0
    }

    /// Как зовут соседний день. Дальше послезавтра имён нет — там просто
    /// прошлое и будущее.
    private func neighbour(_ step: Int) -> String {
        let cal = Calendar.current
        guard let day = cal.date(byAdding: .day, value: step, to: date) else { return "" }
        let n = cal.dateComponents([.day], from: DayStore.today(), to: day).day ?? 0
        switch n {
        case -2: return T("позавчера", "two days ago")
        case -1: return T("вчера", "yesterday")
        case  0: return T("сегодня", "today")
        case  1: return T("завтра", "tomorrow")
        case  2: return T("послезавтра", "in two days")
        default: return step < 0 ? T("прошлое", "the past") : T("будущее", "the future")
        }
    }

    /// Воздух над названием экрана. Один на всех трёх экранах, чтобы
    /// название не прыгало по высоте при переходе между ними.
    static let airAbove: CGFloat = 12

    /// Есть ли у дня имя — позавчера … послезавтра (P425).
    static func named(_ date: Date) -> Bool {
        abs(Calendar.current.dateComponents([.day], from: DayStore.today(), to: date).day ?? 9) <= 2
    }

    static func title(for date: Date) -> String {
        let n = Calendar.current.dateComponents([.day], from: DayStore.today(), to: date).day ?? 0
        switch n {
        case -2: return T("Позавчера", "Two days ago")
        case -1: return T("Вчера", "Yesterday")
        case  0: return T("Сегодня", "Today")
        case  1: return T("Завтра", "Tomorrow")
        case  2: return T("Послезавтра", "In two days")
        default: return Ru.weekday(date).capitalized
        }
    }

    // MARK: - Шаг назад и вперёд

    private func stepArrow(_ icon: String, ready: Bool, name: String,
                           act: @escaping () -> Void) -> some View {
        Button {
            guard ready else { return }
            Feel.light()
            hideKeyboard()
            act()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Look.accent)
                .opacity(ready ? 1 : 0.3)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Look.chrome.opacity(0.62)))
                .overlay(Circle().strokeBorder(Look.inkFaint.opacity(0.35), lineWidth: 0.8))
                // Площадка для пальца 44, кружок прежний (P465).
                .contentShape(Circle().inset(by: -5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(name)
    }

    // MARK: - Содержимое

    @ViewBuilder private var content: some View {
        if shell.probingSide {
            // Только для снимков: страница, нарисованная соседским способом,
            // но в той же оправе. Два снимка ложатся друг на друга, и всякое
            // расхождение видно сразу, а не на ощупь при перелистывании.
            SideDay(date: date)
        } else if live {
            // План сверху, дневник ниже — одним листом (P408).
            DaySheet(date: date, home: shell.freshStart, toDiary: shell.tab == .diary,
                     diaryOpen: !store.isFuture,
                     land: shell.landing, landDiary: shell.landOnDiary,
                     onDiary: { [shell] in shell.lookingAtDiary = $0 },
                     diaryMark: AnyView(cloud),
                     catcher: AnyView(galleryCatcher)) {
                PlanView()
            } diary: {
                DiaryView()
            }
        } else {
            SideDay(date: date)
        }
    }
}

/// Фактура страницы: у плана — бледная клетка, как в тетради; у дневника —
/// волокно бумаги (P245). Рисуется один раз и кладётся плиткой.
struct PageTexture: View {
    let tab: Shell.Tab
    /// Кусок сдвинут при рисовании (открытая вкладка опущена на точку) —
    /// узор сдвигается обратно, чтобы клетка не разошлась.
    var shift: CGFloat = 0
    /// От чего отсчитывается узор. На листе дня — от самого листа, который
    /// едет при прокрутке: клетка идёт вместе с текстом (P412).
    var space: String = PageTexture.space

    /// Общая точка отсчёта фактуры — вся страница дня.
    static let space = "страница"

    var body: some View {
        let picture = tab == .plan ? PageTexture.grid : PageTexture.grain
        let tile = picture.size
        GeometryReader { geo in
            // Узор сдвигается так, будто он нарисован на всей странице
            // разом, а этот кусок — окно в него.
            let at = geo.frame(in: .named(space)).origin
            let dx = at.x.truncatingRemainder(dividingBy: tile.width)
            let dy = (at.y + shift).truncatingRemainder(dividingBy: tile.height)
            Image(uiImage: picture)
                .resizable(resizingMode: .tile)
                .frame(width: geo.size.width + tile.width * 2,
                       height: geo.size.height + tile.height * 2)
                .offset(x: -dx - tile.width, y: -dy - tile.height)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Сторона клетки — по ней же строки плана (P413).
    static let cell: CGFloat = 18

    /// Клетка в 18 точек — как в школьной тетради, но еле видная.
    static let grid: UIImage = {
        let side: CGFloat = cell
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            UIColor(Look.accent).withAlphaComponent(0.09).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: 0.6))
            ctx.fill(CGRect(x: 0, y: 0, width: 0.6, height: side))
        }
    }()

    /// Волокно бумаги: мелкие крапинки и короткие волоски, светлые и
    /// тёмные вперемешку. Узор один и тот же при каждом запуске — иначе
    /// соседние страницы различались бы на снимках (P114).
    static let grain: UIImage = {
        let side: CGFloat = 160
        var seed: UInt64 = 0x5EED_2026
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
        }
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            for _ in 0..<700 {
                let x = next() * side, y = next() * side
                let r = 0.3 + next() * 0.7
                let dark = next() < 0.6
                (dark ? UIColor(Look.ink).withAlphaComponent(0.035 + next() * 0.03)
                      : UIColor.white.withAlphaComponent(0.25 + next() * 0.2)).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
            for _ in 0..<40 {
                let x = next() * side, y = next() * side
                let angle = next() * .pi
                let length = 3 + next() * 6
                let fibre = UIBezierPath()
                fibre.move(to: CGPoint(x: x, y: y))
                fibre.addQuadCurve(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length),
                                   controlPoint: CGPoint(x: x + cos(angle + 0.6) * length / 2,
                                                         y: y + sin(angle + 0.6) * length / 2))
                fibre.lineWidth = 0.4
                UIColor(Look.ink).withAlphaComponent(0.05).setStroke()
                fibre.stroke()
            }
        }
    }()
}

/// Лицо кнопки в нижней полоске: значок и подпись. Общее для полоски
/// вложений и для полоски карты — кнопки стоят на одних и тех же местах
/// (P213).
struct BarFace: View {
    let icon: String
    let name: String
    var tint: Color = Look.inkSoft
    /// Только значок — для тонкой полоски вложений (P289).
    var compact = false
    /// Пятно под значком (P425): строка вложений полупрозрачная, и черты
    /// значка сливались с тем, что видно сквозь неё. Пятно цвета дня —
    /// плотное посередине, к краям тает.
    var spot: Color?

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: compact ? 18 : 17))
                .frame(height: compact ? 26 : nil)
                .background {
                    if let spot {
                        RadialGradient(colors: [spot.opacity(0.95), spot.opacity(0.7), spot.opacity(0)],
                                       center: .center, startRadius: 0, endRadius: 24)
                            .frame(width: 52, height: 40)
                    }
                }
            if !compact {
                Text(name.uppercased()).font(Look.sans(9)).tracking(0.45)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .accessibilityLabel(name)
        .frame(maxWidth: .infinity)
        .foregroundStyle(tint)
        .contentShape(Rectangle())
    }
}

/// Название вкладки. В режиме изменений каждая буква качается вокруг
/// своей оси, вправо-влево до 15°, каждая в своём ритме: режим виден
/// издалека, и забыть его включённым трудно (P211).
struct WobblyTitle: View {

    let text: String
    let wobbling: Bool
    let font: Font
    let color: Color

    var body: some View {
        if wobbling {
            TimelineView(.animation) { clock in
                let t = clock.date.timeIntervalSinceReferenceDate
                HStack(spacing: 0) {
                    ForEach(Array(text.enumerated()), id: \.offset) { i, letter in
                        Text(String(letter))
                            .font(font)
                            .tracking(1.56)
                            .foregroundStyle(color)
                            .rotationEffect(.degrees(WobblyTitle.angle(t, i)))
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text.capitalized + T(". Правка прошедшего дня, нажмите, чтобы выйти", ". Editing a past day, tap to leave"))
        } else {
            Text(text)
                .font(font)
                .tracking(1.56)
                .foregroundStyle(color)
        }
    }

    /// Наклон буквы в минуту `t`: две волны с несоразмерными частотами, у
    /// каждой буквы свои — со стороны это выглядит беспорядком.
    static func angle(_ t: TimeInterval, _ i: Int) -> Double {
        // Впятеро-вшестеро живее прежнего: буквы дрожат, а не покачиваются
        // (P227).
        let a = (2.3 + Double((i * 7) % 5) * 0.45) * 5.5
        let b = (3.7 + Double((i * 3) % 4) * 0.6) * 5.5
        let p = Double(i) * 1.9
        return 15 * (0.6 * sin(t * a + p) + 0.4 * sin(t * b + p * 0.7))
    }
}

/// Полоска вложений. Едет вместе со страницей: вложения принадлежат дню.
///
/// Пока открыта клавиатура, та же полоска стоит прямо над ней: курсор
/// остаётся на месте, а всё нужное под пальцем (P253). Справа тогда —
/// кнопка «убрать клавиатуру».
/// Лента превью и строка вложений открытого дня (P544): одна на экран, у
/// его низа, над нижней строкой разделов; с клавиатурой едет вверх и стоит
/// над ней. Прежде полоска была концом листа (P502), а над клавиатурой —
/// её копия (P541, P542).
struct StripDock: View {
    @EnvironmentObject private var store: DayStore
    @State private var keyboard: CGFloat = 0

    var body: some View {
        GeometryReader { outer in
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                KeyboardDock(date: store.date)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, keyboard > 0 ? covered(outer) : 10)
            }
        }
        .keyboardHeight($keyboard)
        .animation(.easeOut(duration: 0.25), value: keyboard)
    }

    /// Сколько клавиатура закрывает снизу — тот же счёт, что у листа.
    private func covered(_ outer: GeometryProxy) -> CGFloat {
        let safe = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
            .first ?? 0
        let top = UIScreen.main.bounds.height - keyboard - safe
        return max(0, outer.frame(in: .global).maxY - top)
    }
}

/// Сама полоса: лента превью дня с предложенными снимками и строка вложений.
/// Превью уносят в текст переносом дневника (`StripBridge`).
struct KeyboardDock: View {
    let date: Date

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell
    @StateObject private var suggest = DaySuggestions()
    @State private var removing: Int?

    static let thumb: CGFloat = 60
    /// Высота с запасом: превью с отступами и строка вложений.
    static var height: CGFloat { thumb + 16 + KeyboardBar.attachHeight + 14 }

    private var showsStrip: Bool {
        !store.stripLinks.isEmpty || Plan.hasPhotoRows(store.planRows)
            || (store.canEditDiary && suggest.shows)
    }

    var body: some View {
        VStack(spacing: 0) {
            if showsStrip {
                PhotoStrip(photos: store.stripLinks.map(store.photoURL),
                           onOpen: { i in
                               let n = store.photos.count
                               shell.openedPhoto = i < n ? .init(tab: .diary, index: i)
                                                         : .init(tab: .plan, index: i - n)
                           },
                           anyKind: true,
                           onCarry: store.canEditDiary
                               ? { (i: Int, phase: Lift, spot: CGPoint) in StripBridge.carry?(i, phase, spot) }
                               : nil,
                           onRemove: store.canEditDiary ? { removing = $0 } : nil,
                           extra: store.canEditDiary && suggest.shows
                               ? AnyView(SuggestedRow(model: suggest) { asset in
                                   GalleryRow.take([asset], store: store, tab: .diary) { shell.say($0) }
                               })
                               : nil,
                           size: Self.thumb)
                    // Отпущенное над полосой превью возвращается на место.
                    .background(GeometryReader { g in
                        let frame = g.frame(in: .global)
                        Color.clear
                            .onAppear { StripZones.strip = frame; PlanZones.strip = frame }
                            .onChange(of: frame) { _, now in
                                StripZones.strip = now
                                PlanZones.strip = now
                            }
                    })
                    .modifier(RemoveQuestion(
                        asking: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                        act: { delete in
                            if let i = removing {
                                let n = store.photos.count
                                shell.say(i < n ? store.removeAttachment(at: i, from: .diary, delete: delete)
                                                : store.removeAttachment(at: i - n, from: .plan, delete: delete))
                            }
                            removing = nil
                        }))
            }
            AttachBar(live: true, date: date)
                .frame(height: KeyboardBar.attachHeight)
                .padding(.bottom, 4)
        }
        .padding(.top, 2)
        .background {
            if showsStrip {
                Ru.tint(date).opacity(0.97)
                    .overlay(alignment: .top) { Rectangle().fill(Look.rule).frame(height: 0.6) }
            }
        }
        // Предложенные снимки — заново при смене дня, после взятия, при
        // возвращении в приложение (P538).
        .onAppear { suggest.reload(today: store.isToday) }
        .onChange(of: store.date) { _, _ in suggest.reload(today: store.isToday) }
        .onReceive(NotificationCenter.default.publisher(for: DaySuggestions.changed)) { _ in
            suggest.reload(today: store.isToday)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)) { _ in
            suggest.reload(today: store.isToday)
        }
    }
}

/// Перенос превью из ленты над клавиатурой ведёт тот же дневник, что и
/// перенос из ленты внизу страницы (P541).
enum StripBridge {
    static var carry: ((Int, Lift, CGPoint) -> Void)?
}

struct AttachBar: View {

    var overKeyboard = false
    /// Полоска открытой страницы: она исполняет просьбы кнопок над
    /// клавиатурой (P279).
    var live = false
    /// День страницы: полоска — нижний край его листа, в его цвет (P297).
    var date = DayStore.today()

    /// Сколько полоска занимает над клавиатурой, с запасом. Строка, в
    /// которой пишут, должна вставать выше неё, а не прятаться (P269).
    static let overKeyboardHeight: CGFloat = 58

    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var vault: Vault

    /// Куда ложится новое: полоска одна на страницу, всё — в дневник
    /// (P408). В будущий день дневника нет — тогда в план.
    private var into: Shell.Tab { store.canEditDiary ? .diary : .plan }

    @State private var choosing = false
    @State private var recording = false
    @State private var browsing = false
    @State private var shooting = false
    /// Где по ширине была нажата кнопка «аудио» — кнопка записи в панели
    /// встаёт ровно над ней (P330).
    @State private var recordAlign: CGFloat = 0.5

    var body: some View {
        HStack(spacing: 0) {
            // Камера — снимок прямо из приложения (P289); первой кнопкой
            // слева, она нужнее с ходу (P301).
            item("camera", T("камера", "camera"), ready: true) { open { shooting = true } }
            // «Фото» сразу открывает галерею (P537); прежде — ряд снимков
            // дня над полоской (P273), до галереи было на касание дольше.
            item("photo", T("фото", "photo"), ready: true) { open { choosing = true } }
            // Строка без клавиатуры — пять кнопок, «аудио» третья: центр
            // посередине (P330, P381).
            // Микрофон, а не волна: волна была безликой (P401).
            item("mic", T("аудио", "audio"), ready: true) {
                recordAlign = 0.5
                open { recording = true }
            }
            item("doc", T("файлы", "files"), ready: true) { open { browsing = true } }
            // «Место» — крайней справа (P496): касание — где вы сейчас,
            // долгое нажатие — карта.
            item("mappin.and.ellipse", T("место", "place"), ready: true,
                 hold: { openMap() }) { notePlaceHere() }
        }
        // Полоска как можно тоньше: одни значки, без подписей (P289).
        .padding(.top, 5)
        .padding(.bottom, 4)
        .background(DayStrip(date: date).opacity(KeyboardBar.see))
        // Бока скруглены целиком (P425).
        .clipShape(Capsule(style: .continuous))
        .overlay(Capsule(style: .continuous)
            .strokeBorder(Color.black.opacity(0.08), lineWidth: 0.6))
        .padding(.horizontal, KeyboardBar.inset)
        // Куда втекает строка над клавиатурой, когда та уходит (P440).
        // Уходящая страница не стирает место: новая открытая уже сообщила своё.
        .reportsY { [live] y in if live, let y { KeyboardBar.glide.pillTarget = y } }
        // Ряд галереи лежит над полоской, поверх страницы: страница под
        // ним не сдвигается (P113, P114).
        .overlay(alignment: .top) {
            if live && shell.gallery {
                GalleryRow(day: date, add: { addFromGallery($0, day: date) }, more: {
                    withAnimation(.easeOut(duration: 0.2)) { shell.gallery = false }
                    // Окно галереи — следом, когда ряд уже убран: в одном
                    // такте с его уходом окно не открывалось (P522).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { choosePhotos() }
                })
                .offset(y: -GalleryRow.height)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: shell.keyboardAsk) { _, ask in
            guard live, let ask else { return }
            shell.keyboardAsk = nil
            // В каком ответе «Как прошло?» писали — до того, как клавиатура
            // уйдёт и забудет это (P407).
            let answering = store.answerTyping
            let row = store.planTyping
            hideKeyboard()
            switch ask {
            case .photo: open { choosing = true }
            case .camera: open { shooting = true }
            // Полоска над клавиатурой — шесть кнопок, «аудио» третья: центр
            // на 5/12 ширины (P330, P381).
            case .audio:
                recordAlign = 5.0 / 12.0
                open { recording = true }
            case .files: open { browsing = true }
            case .place: notePlaceHere(answer: answering, row: row)
            case .map: openMap()
            }
        }
        .onChange(of: store.date) { _, _ in if live { shell.gallery = false } }
        // Системное окно галереи: приложению не нужно разрешение на всю
        // галерею — оно получает только те снимки, которые выбрал человек.
        // Снимки и видео вместе, без предела на число (P214).
        .sheet(isPresented: $choosing) {
            LibraryPicker { results in
                choosing = false
                if !results.isEmpty { take(results) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $recording) {
            Recorder(done: keepVoice, cancel: { recording = false }, align: recordAlign)
                .presentationDetents([.height(400)])
        }
        .fullScreenCover(isPresented: $shooting) {
            CameraPicker { data in
                shooting = false
                guard let data else { return }
                if store.addPhoto(data, to: into, camera: true) {
                    shell.say(T("Снимок положен в папку «", "Photo saved to the “") + vault.name(.photos) + T("»", "” folder"))
                } else {
                    shell.say(T("Снимок не сохранился", "The photo was not saved"))
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $browsing) {
            // Окно открывается там, где его оставили (P384): папку ему
            // больше не подсказываем — подсказанная папка уводила со
            // страницы «Обзор», с которой проще всего дойти до любого файла.
            DocumentPicker(pick: keepFiles)
        }
    }

    /// Вложение кладётся туда, где человек стоит, — в план или в дневник
    /// (P203). В закрытый день — нельзя, и об этом говорится.
    private func open(_ show: () -> Void) {
        guard store.canEdit(into) else { return shell.say(store.closedReason) }
        // Камера, голос или файлы — ряд снимков больше не нужен (P344).
        if shell.gallery { shell.gallery = false }
        show()
    }

    /// Голос готов: файл — в «Аудио», ссылка — в файл дня (P209).
    private func keepVoice(_ url: URL) {
        recording = false
        defer { try? FileManager.default.removeItem(at: url) }
        guard let data = try? Data(contentsOf: url), !data.isEmpty,
              store.addAttachment(data, to: .audio, name: Vault.moment(store.date) + ".m4a",
                                  tab: into)
        else { return shell.say(T("Запись не сохранилась.", "The recording was not saved.")) }
        shell.say(T("Голос положен в папку «", "Voice note saved to the “") + vault.name(.audio) + T("»", "” folder"))
    }

    /// Документы выбраны: копии — в «Документы» под своими именами (P209).
    private func keepFiles(_ urls: [URL]) {
        browsing = false
        guard !urls.isEmpty else { return }
        var kept = 0
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            if store.addAttachment(data, to: .documents, name: url.lastPathComponent,
                                   tab: into) { kept += 1 }
        }
        shell.say(kept == urls.count ? T("Положено в папку «", "Saved to the “") + vault.name(.documents)
                                        + T("»: \(kept)", "” folder: \(kept)")
                                     : T("Не удалось положить файлов: \(urls.count - kept)", "Files not saved: \(urls.count - kept)"))
    }

    /// Вписать место, где человек сейчас, — своей строкой у курсора; в
    /// плане — под делом, в котором пишут (P381). Место узнаётся только
    /// по этому нажатию (A9).
    private func notePlaceHere(answer: String? = nil, row asked: UUID? = nil) {
        // Пишут в деле плана — место встаёт под него; иначе — в дневник
        // (P381, P408).
        let row = asked ?? store.planTyping
        let tab: Shell.Tab = row != nil ? .plan : .diary
        guard store.canEdit(tab) else { return shell.say(store.closedReason) }
        let caret = store.diaryTyping ? store.diaryCaret : nil
        Feel.light()
        Locator.shared.current { location in
            DispatchQueue.main.async {
                guard let location else {
                    return shell.say(T("Место не определилось — разрешите приложению знать, где вы, в Настройках iPhone.",
                                       "Could not find where you are — allow location for the app in iPhone Settings."))
                }
                if store.writePoint(GeoPoint(title: "", at: location.coordinate), to: tab, here: true,
                                    caret: caret, after: row, answer: answer) {
                    shell.say(T("Место записано", "Place noted"))
                }
            }
        }
    }

    /// Долгое нажатие на «место» — карта; точка с неё ляжет туда, где был
    /// курсор.
    private func openMap() {
        hideKeyboard()
        store.noteLeaving(fromToday: true)
        shell.screen = .map
    }

    private func item(_ icon: String, _ name: String, ready: Bool = false,
                      hold: (() -> Void)? = nil,
                      act: @escaping () -> Void) -> some View {
        let face = BarFace(icon: icon, name: name, tint: ready ? Look.stripInk : Look.inkFaint,
                           compact: true, spot: Ru.tint(date))
        return Group {
            if let hold {
                // У кнопки два жеста: касание и долгое нажатие. Обычная
                // кнопка сработала бы и после долгого — поэтому жесты свои.
                face
                    .onTapGesture(perform: act)
                    .onLongPressGesture(minimumDuration: 0.5) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        hold()
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(T("Долгое нажатие — вписать, где вы", "Long press to note where you are"))
            } else {
                Button(action: act) { face }
            }
        }
    }

    /// Отмеченное в ряду галереи — в полоску этой вкладки, как из окна
    /// галереи (P273, P350). Ряд убрали, перелистнув на другой день, —
    /// в чужой день ничего не ложится, об этом говорится.
    private func addFromGallery(_ assets: [PHAsset], day: Date) {
        let tab = into
        guard Calendar.current.isDate(store.date, inSameDayAs: day), store.canEdit(tab) else {
            return shell.say(T("Отмеченное в галерее не добавлено: открыт другой день",
                                 "The selected photos were not added: another day is open"))
        }
        GalleryRow.take(assets, store: store, tab: tab) { shell.say($0) }
    }

    /// Фото кладутся туда, где человек стоит: на вкладке плана — в план,
    /// в дневнике — в дневник (решение P203).
    private func choosePhotos() {
        guard store.canEdit(into) else { return shell.say(store.closedReason) }
        choosing = true
    }

    /// Видео из окна галереи — копией во временный файл: система уберёт
    /// своё, как только окно закроется (P525).
    private static func copiedMovie(_ provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { (cont: CheckedContinuation<URL?, Never>) in
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, _ in
                guard let url else { return cont.resume(returning: nil) }
                let ext = url.pathExtension.isEmpty ? "mov" : url.pathExtension
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString + "." + ext)
                do {
                    try FileManager.default.copyItem(at: url, to: copy)
                    cont.resume(returning: copy)
                } catch {
                    cont.resume(returning: nil)
                }
            }
        }
    }

    /// Снимок из окна галереи — данными, как они лежат в галерее.
    private static func loadedImage(_ provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { (cont: CheckedContinuation<Data?, Never>) in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                cont.resume(returning: data)
            }
        }
    }

    /// Положить выбранные снимки в папку и показать их в дневнике дня.
    @MainActor
    private func take(_ items: [PHPickerResult]) {
        // Взятое из галереи больше не предлагается в ленте (P538).
        DaySuggestions.markTaken(items.compactMap(\.assetIdentifier))
        Task {
            let tab = into
            var added = 0
            var videos = 0
            if items.count > 3 { shell.say(T("Кладу в папку: \(items.count)…", "Saving to the folder: \(items.count)…")) }
            for item in items {
                if item.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    // Видео — в «Видео»; крупное — до 1080p, если так в
                    // настройках (P214, P365).
                    guard let source = await Self.copiedMovie(item.itemProvider)
                    else { continue }
                    let file = await Movie.shrunk(source)
                    defer {
                        try? FileManager.default.removeItem(at: source)
                        if file != source { try? FileManager.default.removeItem(at: file) }
                    }
                    let ext = file.pathExtension.isEmpty ? "mov" : file.pathExtension
                    guard let data = try? Data(contentsOf: file, options: .mappedIfSafe)
                    else { continue }
                    if store.addAttachment(data, to: .videos,
                                           name: Vault.moment(store.date) + "." + ext.lowercased(),
                                           tab: tab) {
                        added += 1
                        videos += 1
                    }
                    continue
                }
                guard let data = await Self.loadedImage(item.itemProvider) else { continue }
                if store.addPhoto(data, to: tab) { added += 1 }
            }
            if added == items.count {
                if added == 1 {
                    shell.say(videos == 1 ? T("Видео положено в папку «", "Video saved to the “") + vault.name(.videos) + T("»", "” folder")
                                          : T("Фотография положена в папку «", "Photo saved to the “") + vault.name(.photos) + T("»", "” folder"))
                } else {
                    shell.say(T("Положено в папку: \(added)", "Saved to the folder: \(added)"))
                }
            } else {
                shell.say(T("Не удалось положить: \(items.count - added)", "Not saved: \(items.count - added)"))
            }
        }
    }
}

/// Видео из галереи: система отдаёт его файлом, а не в память — ролик
/// может весить гигабайт. Файл сразу копируется к себе: чужой исчезнет,
/// как только окно галереи закроется.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "." + ext)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

/// Соседний день — только чтобы его было видно, пока он едет.
///
/// Рисует ровно те же страницы, что и открытый день, только без правки.
/// Иначе при повороте содержимое перескакивает: человек видел одно, а
/// получил другое.
struct SideDay: View {

    let date: Date

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var store: DayStore

    @State private var rows: [PlanRow] = []
    @State private var title = ""
    @State private var text = ""
    @State private var answers: [String: String] = [:]
    @State private var photos: [String] = []
    @State private var planPhotos: [String] = []
    @State private var weather: String?
    /// События Календаря этого дня (P376) — как на открытой странице.
    @State private var events: [DayEvents.Shown] = []
    /// День из «Здоровья» (P378) — как на открытой странице.
    @State private var health: String?

    var body: some View {
        // Та же страница, что у открытого дня: план сверху, дневник ниже
        // (P114, P408).
        // Вчерашняя страница, пока её тянут, стоит там же, где встанет
        // открытой: на дневнике, если смотрели в дневник (P424, P114).
        DaySheet(date: date, diaryOpen: date <= DayStore.today(),
                 landDiary: shell.lookingAtDiary,
                 diaryMark: AnyView(DayCloud(date: date, live: false)),
                 // Полоска вложений — конец страницы и у соседней (P502, P114).
                 strip: AnyView(AttachBar(live: false, date: date))) {
            plan
        } diary: {
            diary
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: load)
        // Страницу могли переиспользовать для другого дня, а запись открытого
        // дня — лечь на диск уже после первого чтения (P439).
        .onChange(of: date) { _, _ in load() }
        .onChange(of: store.savedTick) { _, _ in load() }
    }

    private var tasks: [PlanRow] { rows.filter { $0.isTask } }

    private var plan: some View {
        PlanPage(rows: rows, isPast: date < DayStore.today(),
                 bellColor: Look.accent,
                 events: events,
                 resolve: { [vault, date] in vault.mediaURL($0, for: date) })
    }

    private var diary: some View {
        DiaryPage(tasks: tasks,
                  answer: { answers[$0] ?? "" },
                  title: .constant(title),
                  text: .constant(text),
                  editable: false,
                  weather: weather,
                  // Одна полоска на страницу, как у открытого дня (P408).
                  photos: (photos + planPhotos).map { vault.mediaURL($0, for: date) },
                  takesBack: Plan.hasPhotoRows(rows),
                  resolve: { [vault, date] in vault.mediaURL($0, for: date) },
                  health: health)
        .task(id: date) { health = await HealthDay.summary(for: date) }
        .onReceive(NotificationCenter.default.publisher(for: HealthDay.note)) { _ in
            Task { health = await HealthDay.summary(for: date) }
        }
    }

    private func load() {
        (rows, planPhotos) = Plan.splitPhotos(
            Plan.rows(from: DayFile(text: vault.read(.planner, for: date)).body))
        let file = DayFile(text: vault.read(.diary, for: date))
        // Ответы «Как прошло?» — по настоящим названиям дел, как у открытой
        // страницы (P155): без них дело с двоеточием в названии («Звонок в
        // 10:30») теряло ответ на соседней странице, и он появлялся скачком,
        // когда страница становилась открытой (P441).
        let diary = Diary(body: file.body, known: rows.map(\.text))
        title = file.value("title") ?? ""
        text = diary.text
        answers = diary.answers
        photos = diary.photos
        weather = file.value("weather")
        events = DayEvents.shown(DayEvents.items(for: date), marks: DayEvents.marks(in: rows))
    }
}

/// Список дел без правки — для соседних страниц.
///
/// Та же оправа и те же строки, что у открытой страницы. Ничего своего.
struct PlanPage: View {

    let rows: [PlanRow]
    let isPast: Bool
    /// Цвет дня недели: колокольчик красится им и на соседних страницах,
    /// иначе он бледнеет на просвет и вспыхивает после поворота.
    var bellColor: Color = Look.inkFaint
    var events: [DayEvents.Shown] = []
    /// Где лежат снимки, поставленные между делами (P205).
    var resolve: ((String) -> URL?)?

    private var tasks: [PlanRow] { rows.filter(\.isTask) }

    var body: some View {
        // Прошедший день — как любой: не бледнее и с теми же кнопками,
        // как на открытой странице (P114, P381). Верх страницы дня, без
        // своей прокрутки — как на открытой (P408).
        VStack(alignment: .leading, spacing: 0) {
                // События Календаря — первыми, тем же кодом, что на
                // открытой странице (P114, P376).
                ForEach(Array(events.enumerated()), id: \.element.key) { i, e in
                    PlanRowLine(number: i + 1, row: e.row, faded: false, bellColor: bellColor,
                                stripe: e.color, past: isPast)
                }
                // Дела и снимки между ними — в том же порядке, что и на
                // открытой странице; прочие строки файла не рисуются.
                ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                    if row.isTask {
                        PlanRowLine(number: events.count + rows[..<i].filter(\.isTask).count + 1,
                                    row: row, faded: false, bellColor: bellColor, past: isPast)
                    } else if let line = row.verbatim {
                        PlanExtraLine(line: line, resolve: resolve)
                    }
                }
                // Пустая плашка следующего дела — как на открытой странице
                // (P114, P406); в прошедшем дне её нет (P421).
                if !isPast, !tasks.contains(where: PlanRow.blank) {
                    // Тот же текст, что у открытой страницы (P481): прежде здесь
                    // стояло пустое название, и бледное «Без названия»
                    // превращалось в «Напомню о важном деле», когда страница
                    // становилась открытой, — буквы скакали.
                    PlanRowLine(number: events.count + tasks.count + 1, row: .task(PlanRow.ghostTitle),
                                bellColor: bellColor, ghost: true)
                }
                // Счёта «запланировано · сделано» нет — как на открытой
                // странице (P425, P114).
            // Воздух под планом — как на открытой странице (P114).
            Color.clear.frame(height: 18)
        }
    }
}

/// Полоса под облачком без того места, где локоть лежит на вкладке
/// (P256). Вне облачка черта уже нарисована — второй раз не нужно.
private struct ElbowGap: Shape {
    let start: CGFloat
    let from: CGFloat
    let to: CGFloat
    let end: CGFloat

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addRect(CGRect(x: start, y: rect.minY, width: max(0, from - start), height: rect.height))
        p.addRect(CGRect(x: to, y: rect.minY, width: max(0, end - to), height: rect.height))
        return p
    }
}

/// Где стоит открытая вкладка — её рамка на странице передаётся наверх,
/// к рамке режима изменений (P341).
private struct OpenTabKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

/// Контур папки: страница с выступающей над ней вкладкой (P341).
///
/// Снизу вверх по левому краю страницы, по её верхнему краю до вкладки,
/// вокруг вкладки — вверх, поверху со скруглениями, вниз — и дальше по
/// верхнему краю страницы до правого края и вниз. Закрытая соседняя
/// вкладка остаётся за линией, над страницей. Низ не обводится: страница
/// продолжается в строку вложений.
struct FolderOutline: Shape {
    let tab: CGRect
    let radius: CGFloat
    /// Отступ от краёв, чтобы линию не срезал край экрана.
    var inset: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let left = rect.minX + inset, right = rect.maxX - inset
        let seam = tab.maxY
        let tabLeft = max(left, tab.minX), tabRight = min(right, tab.maxX)
        let top = tab.minY + inset
        var p = Path()
        p.move(to: CGPoint(x: left, y: rect.maxY))
        p.addLine(to: CGPoint(x: left, y: seam))
        p.addLine(to: CGPoint(x: tabLeft, y: seam))
        p.addLine(to: CGPoint(x: tabLeft, y: top + radius))
        p.addArc(center: CGPoint(x: tabLeft + radius, y: top + radius), radius: radius,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: tabRight - radius, y: top))
        p.addArc(center: CGPoint(x: tabRight - radius, y: top + radius), radius: radius,
                 startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: tabRight, y: seam))
        p.addLine(to: CGPoint(x: right, y: seam))
        p.addLine(to: CGPoint(x: right, y: rect.maxY))
        return p
    }
}


/// Облачко «А вот когда-то…» одной и той же отрисовки на открытой и на
/// соседних страницах (P114, P484). Касание — только у открытой.
struct DayCloud: View {

    let date: Date
    let live: Bool
    var open: () -> Void = {}

    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var archive: Archive

    /// Дни, чьи облачка уже прочитаны (решение P136).
    @AppStorage(Remembered.key) private var read = ""

    /// Сегодняшний день, каким его видит облачко (P518): облачко бывает только
    /// на сегодняшнем и будущих днях; когда день проходит, оно тает само.
    @State private var today = DayStore.today()

    var body: some View {
        ZStack {
            // Следит за сменой суток: без этого страница, открытая в полночь,
            // продолжала бы показывать облачко уже прошедшего дня.
            Color.clear.frame(width: 0, height: 0)
                .onReceive(NotificationCenter.default.publisher(
                    for: UIApplication.significantTimeChangeNotification)) { _ in refreshToday() }
                .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { _ in
                    refreshToday()
                }
            cloud
        }
    }

    private func refreshToday() {
        let now = DayStore.today()
        guard now != today else { return }
        // Тает так же мягко, как после прочтения (P334).
        withAnimation(.easeOut(duration: 1.5)) { today = now }
    }

    @ViewBuilder private var cloud: some View {
        if date >= today, !shell.hideCloud, archive.remembered(for: date) != nil,
           !Remembered.has(Vault.stamp(date), in: read) {
            // Те же размеры, что на прежнем корешке: половина его ширины,
            // а корешок был в половину страницы.
            let half = (UIScreen.main.bounds.width - 30) / 2
            let width = half * 0.50
            let height = width / RememberCloud.ratio
            RememberCloud(date: date, width: width) { if live { open() } }
                .frame(width: width, height: height)
                // Сидит над заголовком «Дневник», у правого края, и едет вместе
                // со страницей (P436); у края несколько миллиметров (P437);
                // ниже на две трети толщины линии рисунка (P456).
                .offset(x: -18, y: -0.2)
                .allowsHitTesting(live)
                .transition(.opacity)
        }
    }
}
