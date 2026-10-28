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
        // Взятое из ленты превью — поверх всего (P545).
        .overlay { StripGhostLayer() }
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

    @EnvironmentObject private var vault: Vault
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
        Ru.tint(date).overlay(PageTexture(tab: .diary, aged: Ru.isPast(date)))
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
                titleMenu
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
        .background(Ru.tint(date).overlay(PageTexture(tab: .diary, aged: Ru.isPast(date))))
        .contentShape(Rectangle())
        .onTapGesture { hideKeyboard() }
    }

    /// Имя дня и дата. Касание по ним на открытой странице — действия дня
    /// (P632; прежде они были в уголке с тремя точками). Стрелка ▾ стоит и
    /// на соседних страницах: иначе при листании строка меняла бы ширину.
    @ViewBuilder private var titleMenu: some View {
        if live {
            Menu { dayActions } label: { titleBlock }
                .buttonStyle(.plain)
                .accessibilityHint(T("Действия дня", "Day actions"))
        } else {
            titleBlock
        }
    }

    @ViewBuilder private var dayActions: some View {
        Button { shell.showingFile = true } label: {
            Label(T("Показать файл этого дня", "Show this day’s file"), systemImage: "doc.text")
        }
        Button { shell.showingWeek = true } label: {
            Label(T("Неделя одним взглядом", "The week at a glance"), systemImage: "calendar")
        }
        Button {
            // Текстом — план и запись; вложения остаются в папке (P249).
            Share.present([store.shareText()])
        } label: {
            Label(T("Поделиться днём", "Share the day"), systemImage: "square.and.arrow.up")
        }
        // PDF одного дня — та же книга, срок в один день (P296).
        Button {
            let date = store.date
            let vault = vault
            store.save()
            DispatchQueue.global(qos: .userInitiated).async {
                let url = PDFBook.make(.init(from: date, to: date), vault: vault)
                DispatchQueue.main.async {
                    if let url { Share.present([url]) } else { shell.say(T("В этом дне пока пусто — PDF не из чего собрать.", "This day is still empty — nothing to make a PDF from.")) }
                }
            }
        } label: {
            Label(T("PDF дня", "PDF of the day"), systemImage: "doc.richtext")
        }
        // Корзина (P295, P300): весь день уезжает в папку «Корзина», её
        // можно вернуть из настроек.
        Button(role: .destructive) { shell.trashAsk = true } label: {
            Label(T("Убрать день в корзину", "Move the day to the trash"), systemImage: "trash")
        }
    }

    private var titleBlock: some View {
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
                        .tracking(0.4)
                     + Text(" ▾").foregroundColor(Look.inkFaint))
                        .font(Look.sans(12.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .frame(maxWidth: .infinity)
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
        .accessibilityLabel(neighbour(step))
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
            DaySheet(date: date, home: shell.freshStart,
                     diaryOpen: !store.isFuture,
                     land: shell.landing, landDiary: shell.landOnDiary,
                     onDiary: { [shell] in shell.lookingAtDiary = $0 },
                     diaryMark: AnyView(cloud),
                     strip: AnyView(AttachBar(live: live))) {
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
    /// Прошедший день: поверх обычной фактуры — старая бумага (P676).
    var aged = false
    /// У прошедшего дня края темнеют янтарём (P676): верх — у верхнего
    /// куска страницы, низ — у нижнего; бока — у всех.
    var edgeTop = false
    var edgeBottom = false
    @Environment(\.colorScheme) private var scheme
    private var dark: Bool { scheme == .dark }

    /// Общая точка отсчёта фактуры — вся страница дня.
    static let space = "страница"

    var body: some View {
        ZStack {
            tiled(tab == .plan ? PageTexture.grid : PageTexture.grain)
            if aged {
                ZStack {
                    // В тёмной теме светлых облаков и янтарных краёв нет
                    // (P680): светлые пятна портили светлый текст.
                    tiled(dark ? PageTexture.cloudsDark : PageTexture.clouds)
                    tiled(PageTexture.paper)
                    if !dark { edges }
                }
                .opacity(dark ? 0.45 : 1)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tiled(_ picture: UIImage) -> some View {
        let tile = picture.size
        return GeometryReader { geo in
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
    }

    /// Сторона клетки — по ней же строки плана (P413).
    static let cell: CGFloat = 18

    /// Клетка в 18 точек — как в школьной тетради, но еле видная.
    static let grid: UIImage = {
        let side: CGFloat = cell
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            // Заметнее прежнего (P680: было 0,09 и 0,6): клетка видна между
            // плашками и по полям — под плашками её нет (P415).
            UIColor(Look.accent).withAlphaComponent(0.17).setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: side, height: 0.7))
            ctx.fill(CGRect(x: 0, y: 0, width: 0.7, height: side))
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

    /// Янтарные края (P676): темнеют к бокам и к низу, неровно — глубина
    /// гуляет вдоль края. Картинки нарисованы заранее; правый край и верх —
    /// те же картинки, отражённые.
    private var edges: some View {
        ZStack {
            HStack(spacing: 0) {
                Image(uiImage: PageTexture.sideEdge).resizable(resizingMode: .tile)
                    .frame(width: PageTexture.sideDepth)
                Spacer(minLength: 0)
                Image(uiImage: PageTexture.sideEdge).resizable(resizingMode: .tile)
                    .frame(width: PageTexture.sideDepth)
                    .scaleEffect(x: -1)
            }
            VStack(spacing: 0) {
                if edgeTop {
                    Image(uiImage: PageTexture.footEdge).resizable(resizingMode: .tile)
                        .frame(height: PageTexture.footDepth)
                        .scaleEffect(y: -1)
                        .opacity(0.3)
                }
                Spacer(minLength: 0)
                if edgeBottom {
                    Image(uiImage: PageTexture.footEdge).resizable(resizingMode: .tile)
                        .frame(height: PageTexture.footDepth)
                }
            }
            // Следы рук (P680): страницу берут за нижний внешний угол и
            // придерживают за правый край, когда листают, — там бумага
            // сереет и буреет мягкими пятнами. Нижний правый — сильнее всех.
            if edgeBottom {
                GeometryReader { geo in
                    thumbSmudge(radius: 95, opacity: 0.20)
                        .position(x: geo.size.width, y: geo.size.height)
                    thumbSmudge(radius: 70, opacity: 0.11)
                        .position(x: 0, y: geo.size.height - 6)
                    thumbSmudge(radius: 60, opacity: 0.09)
                        .position(x: geo.size.width + 4, y: geo.size.height * 0.62)
                }
            }
        }
    }

    private func thumbSmudge(radius: CGFloat, opacity: Double) -> some View {
        RadialGradient(colors: [Color(red: 0.42, green: 0.30, blue: 0.16).opacity(opacity * Double(PageTexture.wearStrength)),
                                .clear],
                       center: .center, startRadius: 0, endRadius: radius)
            .frame(width: radius * 2, height: radius * 2)
    }

    /// Густота износа (облака, края, крапинки): 1 — средняя (второй вариант
    /// эскиза `docs/paper/износ-по-образцу.png`); 1,7 — сильнее.
    static let wearStrength = CGFloat(1.3)

    private static let amber: (r: Float, g: Float, b: Float) = (140 / 255, 97 / 255, 41 / 255)

    /// Круговое размытие: края плитки сходятся. Бегущей суммой — работа не
    /// растёт с радиусом (P679: прежнее перебирание окна заново для каждой
    /// точки считалось секундами на главном потоке при первом показе
    /// прошедшего дня).
    private static func wrapBlur(_ a: [Float], side n: Int, radius r: Int, passes: Int) -> [Float] {
        var src = a, dst = a
        let w = Float(2 * r + 1)
        for _ in 0..<passes {
            for y in 0..<n {
                let row = y * n
                var sum: Float = 0
                for k in -r...r { sum += src[row + (k + n) % n] }
                for x in 0..<n {
                    dst[row + x] = sum / w
                    sum += src[row + (x + r + 1) % n] - src[row + (x - r + n) % n]
                }
            }
            for x in 0..<n {
                var sum: Float = 0
                for k in -r...r { sum += dst[((k + n) % n) * n + x] }
                for y in 0..<n {
                    src[y * n + x] = sum / w
                    sum += dst[((y + r + 1) % n) * n + x] - dst[((y - r + n) % n) * n + x]
                }
            }
        }
        return src
    }

    /// То же вдоль одной линии.
    private static func wrapBlur1D(_ a: [Float], radius r: Int, passes: Int) -> [Float] {
        let n = a.count
        var src = a, dst = a
        let w = Float(2 * r + 1)
        for _ in 0..<passes {
            var sum: Float = 0
            for k in -r...r { sum += src[(k + n) % n] }
            for x in 0..<n {
                dst[x] = sum / w
                sum += src[(x + r + 1) % n] - src[(x - r + n) % n]
            }
            swap(&src, &dst)
        }
        return src
    }

    /// Всю бумагу — заранее, в стороне, пока приложение запускается (P679):
    /// первый показ прошедшего дня не должен ждать, пока она нарисуется.
    static func prepareSoon() {
        DispatchQueue.global(qos: .utility).async {
            _ = clouds
            _ = cloudsDark
            _ = paper
            _ = sideEdge
            _ = footEdge
        }
    }

    private static func normalised(_ a: [Float]) -> [Float] {
        let mean = a.reduce(0, +) / Float(a.count)
        let sd = (a.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Float(a.count)).squareRoot()
        return a.map { ($0 - mean) / max(sd, 0.0001) }
    }

    private static func picture(_ bytes: [UInt8], width: Int, height: Int, scale: CGFloat) -> UIImage {
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: true,
                            intent: .defaultIntent)!
        return UIImage(cgImage: image, scale: scale, orientation: .up)
    }

    /// Облака тона (P676): крупные мягкие пятна, где светлее и теплее, где
    /// темнее. Плитка 576 точек, замкнута сама на себя.
    static let clouds: UIImage = cloudImage(darkOnly: false)

    /// Для тёмной темы: только тёмные пятна, без светлых (P680).
    static let cloudsDark: UIImage = cloudImage(darkOnly: true)

    private static func cloudImage(darkOnly: Bool) -> UIImage {
        let n = 192                                   // 3 точки на пиксель
        var seed: UInt64 = 0xC10D5
        func next() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(seed >> 40) / Float(1 << 24) - 0.5
        }
        let big = normalised(wrapBlur((0..<n * n).map { _ in next() }, side: n, radius: 12, passes: 4))
        let small = normalised(wrapBlur((0..<n * n).map { _ in next() }, side: n, radius: 4, passes: 3))
        let k = Float(wearStrength)
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<n * n {
            let v = (big[i] * 0.8 + small[i] * 0.35) * k
            let light = v > 0
            if darkOnly && light { continue }
            // Светлое — тёплый белый, тёмное — коричневый (в тёмной теме —
            // чёрный, и погуще: на тёмном листе коричневый почти не виден).
            let alpha = min(abs(v) * (light ? 0.09 : (darkOnly ? 0.08 : 0.04)), 0.4)
            let c: (Float, Float, Float) = light ? (1, 0.97, 0.88) : (darkOnly ? (0, 0, 0) : (0.45, 0.38, 0.25))
            bytes[i * 4] = UInt8(c.0 * alpha * 255)
            bytes[i * 4 + 1] = UInt8(c.1 * alpha * 255)
            bytes[i * 4 + 2] = UInt8(c.2 * alpha * 255)
            bytes[i * 4 + 3] = UInt8(alpha * 255)
        }
        return picture(bytes, width: n, height: n, scale: 1.0 / 3)
    }

    /// Бумага одним слоем (P679): рельеф и редкие бледные крапинки с
    /// волосками. Плитка 384 точки — рельеф (128) повторён три на три,
    /// поверх разбросаны крапинки, которых на ней около полусотни, так что
    /// повтор не бросается в глаза. Слоёв на странице стало меньше —
    /// страница, которую листают, легче.
    static let paper: UIImage = {
        var seed: UInt64 = 0x5BECC5
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
        }
        let side: CGFloat = 384
        let k = wearStrength
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        let tile = relief
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { ctx in
            let cg = ctx.cgContext
            for row in 0..<3 {
                for column in 0..<3 {
                    tile.draw(at: CGPoint(x: CGFloat(column) * 128, y: CGFloat(row) * 128))
                }
            }
            for _ in 0..<Int(48 * k) {
                let d = 0.9 + next() * 1.5
                UIColor(red: 0.42, green: 0.32, blue: 0.18, alpha: 0.10 + next() * 0.12).setFill()
                cg.fillEllipse(in: CGRect(x: next() * side, y: next() * side, width: d, height: d))
            }
            for _ in 0..<Int(12 * k) {
                let x = next() * side, y = next() * side
                let angle = next() * .pi, length = 4 + next() * 7
                let hair = UIBezierPath()
                hair.move(to: CGPoint(x: x, y: y))
                hair.addLine(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length))
                hair.lineWidth = 0.5
                UIColor(red: 0.45, green: 0.36, blue: 0.22, alpha: 0.22).setStroke()
                hair.stroke()
            }
        }
    }()

    static let sideDepth: CGFloat = 70
    static let footDepth: CGFloat = 110

    /// Бок: у края глубже всего, дальше затухает; глубина гуляет по длине.
    static let sideEdge: UIImage = edgeImage(depthPoints: sideDepth, falloff: 18, peak: 0.17, vertical: true)
    /// Низ: темнее и шире боков.
    static let footEdge: UIImage = edgeImage(depthPoints: footDepth, falloff: 28, peak: 0.18, vertical: false)

    /// Полоска вдоль края, 2 пикселя на точку, 480 точек вдоль. Вертикальная —
    /// край слева; горизонтальная — край внизу.
    private static func edgeImage(depthPoints: CGFloat, falloff: Float, peak: Float, vertical: Bool) -> UIImage {
        let along = 480 * 2, depth = Int(depthPoints) * 2
        var seed: UInt64 = vertical ? 0xED6E1 : 0xED6E2
        func next() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(seed >> 40) / Float(1 << 24) - 0.5
        }
        // Гуляющая глубина: круговая одномерная размытая случайность.
        let wob = wrapBlur1D((0..<along).map { _ in next() }, radius: 40, passes: 4)
        let wn = normalised(wob).map { max(-1.5, min(1.5, $0)) }
        let width = vertical ? depth : along, height = vertical ? along : depth
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let k = Float(wearStrength)
        for a in 0..<along {
            for d in 0..<depth {
                // d — расстояние от края в пикселях; в точках вдвое меньше.
                let distance = Float(d) / 2
                let alpha = min(peak * k * exp(-distance / (falloff * (1 + 0.35 * wn[a]))), 0.45)
                let x = vertical ? d : a
                let y = vertical ? a : depth - 1 - d     // низ: край — последняя строка
                let i = (y * width + x) * 4
                bytes[i] = UInt8(amber.r * alpha * 255)
                bytes[i + 1] = UInt8(amber.g * alpha * 255)
                bytes[i + 2] = UInt8(amber.b * alpha * 255)
                bytes[i + 3] = UInt8(alpha * 255)
            }
        }
        return picture(bytes, width: width, height: height, scale: 2)
    }

    /// Рельеф шершавой бумаги (P676, отменяет пятна и волоски): впадинки и
    /// бугорки, освещённые слева сверху, как все тени (P670). Складывается
    /// из двух слоёв случайных высот — мелкого и крупного; каждая точка
    /// светлеет или темнеет по тому, куда наклонена. Плитка 128 точек
    /// замкнута сама на себя — шва нет. Рисуется один раз.
    static let relief: UIImage = {
        let n = 256                                  // пикселей, плитка 128 точек при масштабе 2
        var seed: UInt64 = 0x0E11EF
        func next() -> Float {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Float(seed >> 40) / Float(1 << 24) - 0.5
        }
        let noise1 = (0..<n * n).map { _ in next() }
        let noise2 = (0..<n * n).map { _ in next() }
        let fine = normalised(wrapBlur(noise1, side: n, radius: 1, passes: 2))
        let coarse = normalised(wrapBlur(noise2, side: n, radius: 2, passes: 4))
        let height = zip(fine, coarse).map { $0 + $1 * 1.6 }
        // Наклон: свет слева сверху — склон, смотрящий на свет, светлый.
        var lit = [Float](repeating: 0, count: n * n)
        for y in 0..<n {
            for x in 0..<n {
                let h = height[y * n + x]
                let dx = height[y * n + (x + 1) % n] - h
                let dy = height[((y + 1) % n) * n + x] - h
                lit[y * n + x] = -(dx + dy)
            }
        }
        lit = normalised(lit)
        // Светлое — белым, тёмное — чёрным, густота по наклону.
        var bytes = [UInt8](repeating: 0, count: n * n * 4)
        for i in 0..<n * n {
            let v = lit[i] * Float(PageTexture.reliefStrength)
            let white = v > 0
            let alpha = min(abs(v) * (white ? 0.11 : 0.021), 0.5)
            let c: Float = white ? 1 : 0
            bytes[i * 4] = UInt8(c * alpha * 255)
            bytes[i * 4 + 1] = UInt8(c * alpha * 255)
            bytes[i * 4 + 2] = UInt8(c * alpha * 255)
            bytes[i * 4 + 3] = UInt8(alpha * 255)
        }
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        let image = CGImage(width: n, height: n, bitsPerComponent: 8, bitsPerPixel: 32,
                            bytesPerRow: n * 4, space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                            provider: provider, decode: nil, shouldInterpolate: false,
                            intent: .defaultIntent)!
        return UIImage(cgImage: image, scale: 2, orientation: .up)
    }()

    /// Густота рельефа: 1 — средняя (в эскизе `docs/paper/рельеф.png` — второй
    /// вариант); 0,55 — тихая, 1,55 — резкая.
    static let reliefStrength = CGFloat(1)
}

/// «＋» внизу страницы (P615) и всё, что она открывает: галерея, камера,
/// запись голоса, файлы, место. Её же просьбы исполняет и «＋» над
/// клавиатурой (`KeyboardBar.ask`).
struct AttachBar: View {

    /// Полоска открытой страницы: она исполняет просьбы кнопок над
    /// клавиатурой (P279).
    var live = false

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

    var body: some View {
        // Одна «＋» справа над нижней строкой (P610, P615): пять кнопок
        // строки вложений ушли в её меню.
        HStack {
            Spacer(minLength: 0)
            PlusMenu(id: "strip.plus")
        }
        .padding(.horizontal, 12)
        // Где полоска на экране — сюда возвращают снимок из текста (P547).
        // Уходящая страница не стирает место: новая открытая уже сообщила своё.
        .reportsY { [live] y in if live, let y { KeyboardBar.pillTarget = y } }
        .onChange(of: shell.keyboardAsk) { _, ask in
            guard live, let ask else { return }
            shell.keyboardAsk = nil
            hideKeyboard()
            switch ask {
            case .photo: open { choosing = true }
            case .camera: open { shooting = true }
            case .audio:
                open { recording = true }
            case .files: open { browsing = true }
            case .place: notePlaceHere()
            }
        }
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
            Recorder(done: keepVoice, cancel: { recording = false })
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

    /// Место, где человек сейчас, — под текстом записи (P615), а в день,
    /// который ещё не наступил, — в ленту плана (P588). Место узнаётся только по
    /// этому нажатию (A9).
    private func notePlaceHere() {
        let tab: Shell.Tab = store.canEditDiary ? .diary : .plan
        guard store.canEdit(tab) else { return shell.say(store.closedReason) }
        Feel.light()
        Locator.shared.current { location in
            DispatchQueue.main.async {
                guard let location else {
                    return shell.say(T("Место не определилось — разрешите приложению знать, где вы, в Настройках iPhone.",
                                       "Could not find where you are — allow location for the app in iPhone Settings."))
                }
                // Под последним текстом записи, как всё новое (P615).
                if store.writePoint(GeoPoint(title: "", at: location.coordinate), to: tab, here: true) {
                    shell.say(T("Место добавлено", "Place added"))
                }
            }
        }
    }

    /// Долгое нажатие на «место» — карта; точка с неё ляжет туда, где был
    /// курсор.
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
    /// Чей день сейчас лежит в полях выше: готовая страница (P679) кладётся
    /// сразу при создании, до первого кадра.
    @State private var loadedStamp: String?

    init(date: Date) {
        self.date = date
        if let page = ReadyPages.shared.page(for: date) {
            _rows = State(initialValue: page.rows)
            _planPhotos = State(initialValue: page.planPhotos)
            _title = State(initialValue: page.title)
            _text = State(initialValue: page.text)
            _answers = State(initialValue: page.answers)
            _photos = State(initialValue: page.photos)
            _weather = State(initialValue: page.weather)
            _events = State(initialValue: page.events)
            _loadedStamp = State(initialValue: Vault.stamp(date))
        }
    }

    var body: some View {
        // Та же страница, что у открытого дня: план сверху, дневник ниже
        // (P114, P408).
        // Вчерашняя страница, пока её тянут, стоит там же, где встанет
        // открытой: на дневнике, если смотрели в дневник (P424, P114).
        DaySheet(date: date, diaryOpen: date <= DayStore.today(),
                 landDiary: shell.lookingAtDiary,
                 diaryMark: AnyView(DayCloud(date: date, live: false)),
                 // Полоска вложений — конец страницы и у соседней (P502, P114).
                 strip: AnyView(AttachBar(live: false))) {
            plan
        } diary: {
            diary
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear(perform: load)
        // Страницу могли переиспользовать для другого дня, а запись открытого
        // дня — лечь на диск уже после первого чтения (P439).
        .onChange(of: date) { _, _ in load() }
        // Запись открытого дня легла на диск — её страница в готовых уже
        // выброшена (`DayStore.save`), соседние остаются как были (P679).
        .onChange(of: store.savedTick) { _, _ in
            loadedStamp = nil
            load()
        }
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
                  // Точки ленты — тем же квадратом, что на открытой странице (P588, P114).
                  points: (photos + planPhotos).map { Diary.isPoint($0) ? Geo.point(in: $0) : nil },
                  resolve: { [vault, date] in vault.mediaURL($0, for: date) },
                  health: health)
        .task(id: date) { health = await HealthDay.summary(for: date) }
        .onReceive(NotificationCenter.default.publisher(for: HealthDay.note)) { _ in
            Task { health = await HealthDay.summary(for: date) }
        }
    }

    /// Страница берёт готовое (`ReadyPages`, P679) и только раскладывает по
    /// полям; собранной нет — собирает сейчас, как прежде.
    private func load() {
        let stamp = Vault.stamp(date)
        guard loadedStamp != stamp else { return }
        let page = ReadyPages.shared.pageNow(for: date, vault: vault)
        rows = page.rows
        planPhotos = page.planPhotos
        title = page.title
        text = page.text
        answers = page.answers
        photos = page.photos
        weather = page.weather
        events = page.events
        loadedStamp = stamp
    }
}

/// Список дел без правки — для соседних страниц.
///
/// Порядок строк — общий с открытой страницей (`PlanLayout`, P668), строки —
/// те же `PlanRowLine` и `PlanExtraLine`; своего здесь только то, что
/// правки и жестов нет.
struct PlanPage: View {

    let rows: [PlanRow]
    let isPast: Bool
    /// Цвет дня недели: колокольчик красится им и на соседних страницах,
    /// иначе он бледнеет на просвет и вспыхивает после поворота.
    var bellColor: Color = Look.inkFaint
    var events: [DayEvents.Shown] = []
    /// Где лежат снимки, поставленные между делами (P205).
    var resolve: ((String) -> URL?)?

    var body: some View {
        // Прошедший день — как любой: не бледнее и с теми же кнопками,
        // как на открытой странице (P114, P381). Верх страницы дня, без
        // своей прокрутки — как на открытой (P408).
        VStack(alignment: .leading, spacing: 0) {
            // В прошедшем дне пустой плашки нет (P421).
            PlanLayout(rows: rows, events: events,
                       ghost: !isPast && !rows.contains { $0.isTask && PlanRow.blank($0) }) { number, e, under in
                VStack(spacing: 0) {
                    PlanRowLine(number: number, row: e.row, faded: false, bellColor: bellColor,
                                stripe: e.color, past: isPast)
                    if let under, let line = under.verbatim {
                        PlanExtraLine(line: line, resolve: resolve)
                    }
                }
            } task: { row, number in
                PlanRowLine(number: number, row: row, faded: false, bellColor: bellColor, past: isPast)
            } extra: { _, line in
                PlanExtraLine(line: line, resolve: resolve)
            } ghostRow: { number in
                PlanRowLine(number: number, row: .task(PlanRow.ghostTitle),
                            bellColor: bellColor, ghost: true)
            }
            // Воздух под планом — как на открытой странице (P114).
            Color.clear.frame(height: 18)
        }
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
            RememberCloud(width: width) { if live { open() } }
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
