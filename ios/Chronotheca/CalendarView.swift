import SwiftUI
import UIKit

/// Календарь: год и месяц. «Список» перешёл в картотеку будущего (P773).
///
/// Первое касание даты разворачивает дела этого дня, второе открывает день.
/// Так можно заглянуть в дату, не теряя места, где стоишь.
struct CalendarView: View {

    enum Kind: String, CaseIterable, Identifiable {
        case year = "Год", month = "Месяц"
        var id: String { rawValue }
        /// Название на языке приложения; `rawValue` хранится в настройках
        /// и не меняется (P355).
        var title: String {
            switch self {
            case .year: return T("Год", "Year")
            case .month: return T("Месяц", "Month")
            }
        }
    }

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var archive: Archive
    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var shell: Shell

    /// Вид запоминается между заходами. Оставленный прежде «Список» (его
    /// больше нет, P773) открывается «Месяцем».
    @AppStorage("calendar.kind") private var stored = Kind.month.rawValue
    private var kind: Kind { Kind(rawValue: stored) ?? .month }
    @State private var shown: Date = CalendarView.previewStart ?? DayStore.today()
    /// Для снимков CI (P723): месяц недельной давности — в первые дни
    /// месяца на снимке иначе не было бы прошедших дней. Календарь собран
    /// заранее, поэтому месяц ставится, когда его открывают.
    static var previewStart: Date?
    @State private var selected: String? = Vault.stamp(DayStore.today())
    /// Месяц или год, что стоит вверху ленты календаря (P784): по нему
    /// название в шапке, его ставят стрелки и «домой».
    @State private var top: Date?
    /// Вид сменили, лента собирается заново (P840): пока она не встала на
    /// нужный месяц (год), её промежуточные остановки — не выбор человека.
    @State private var switching = false
    /// «Месяц»: просьба полосе перевернуть месяц — от стрелок и «домой»
    /// (P1071). Сама полоса со своим ходом — `MonthPager`.
    @State private var turnAsk = TurnAsk(id: 0, step: 0)

    private var cal: Calendar { Prefs.calendar }

    var body: some View {
        VStack(spacing: 0) {
            // Заголовок «Календарь» заменён на название месяца/года и
            // стрелки — тем же местом, что строка поиска на карте и на
            // экране «Поиск» (P334).
            nav(for: shown)

            HStack(spacing: 6) {
                ForEach(Kind.allCases) { k in
                    Button { choose(k) } label: {
                        Text(k.title)
                            .font(Look.sans(13))
                            .foregroundStyle(kind == k ? Look.planBg : Look.inkSoft)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(kind == k ? Look.accent : .clear,
                                        in: RoundedRectangle(cornerRadius: 8))
                            .overlay(RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(kind == k ? Look.accent : Look.rule))
                    }
                    .accessibilityHint(kind == k ? homeHint(k) : "")
                    .accessibilityIdentifier("kind.\(k.rawValue)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)

            // Месяцы или годы — одной лентой сверху вниз (P784, вместо
            // листания вбок): вбок — свайп между разделами.
            PageHost {
                stream
                    .environmentObject(store)
                    .environmentObject(archive)
                    .environmentObject(shell)
            }
        }
        .onAppear {
            DayEvents.forgetCache()
            if top == nil { top = period(shown) }
        }
        .onChange(of: shell.screen) { _, now in
            guard now == .calendar, let start = CalendarView.previewStart else { return }
            CalendarView.previewStart = nil
            shown = start
            top = period(start)
        }
        // Сменили вид — лента встаёт на тот же месяц или его год.
        .onChange(of: stored) { _, _ in
            // Месяц и год — те, что были до смены вида (P840): лента, собранная
            // заново, вставала по прежнему сдвигу на чужой месяц и успевала его
            // запомнить — «Месяц» открывался не тем месяцем и годом.
            let keep = shown
            switching = true
            top = period(keep)
            // Ещё раз, когда лента уже собрана заново из месяцев (лет) (P822).
            DispatchQueue.main.async {
                shown = keep
                top = period(keep)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    shown = keep
                    switching = false
                }
            }
        }
        // Просьба из меню календаря: та же дорога домой, что у кнопки вида.
        .onChange(of: shell.calendarHome) { _, want in
            guard want else { return }
            shell.calendarHome = false
            // Домой — и на сегодняшний день (P576: второе нажатие на
            // «Календарь»).
            selected = Vault.stamp(DayStore.today())
            goHome(asked: true)
        }
    }

    /// Календарь (P784): «Месяц» — полоса с сеткой и ниже дела выбранного
    /// дня (P1067, P1068); «Год» — лента годов друг под другом, двадцать
    /// назад и пять вперёд. Что стоит — то в шапке.
    private var stream: some View {
        GeometryReader { geo in
            // «Месяц» (P1067, автор по записи экрана: «следующие месяцы
            // появляются щелчком, скачком, будто подскакивают снизу»):
            // листается только полоса высотой с сетку месяца — месяцы лежат
            // вплотную, и следующий въезжает сразу за текущим. Прежде страница
            // была во весь экран: под сеткой — пустой низ, и при ходе вниз
            // сначала въезжала пустота, а сетка нового месяца появлялась
            // наверху в самом конце хода. Список дел выбранного дня — ниже
            // полосы, на месте. «Год» — по-прежнему страницей на экран.
            let strip = kind == .month ? min(geo.size.height, monthHeight(width: geo.size.width)) : geo.size.height
            VStack(spacing: 0) {
                if kind == .month {
                    monthPager(height: strip)
                } else {
                    years.frame(height: strip)
                }
                if kind == .month {
                    Rectangle().fill(Look.rule).frame(height: 1).padding(.vertical, 8)
                    // Дела дня — своей прокруткой в остатке экрана (P792).
                    ZStack(alignment: .top) {
                        if listHere(period(shown)) {
                            ScrollView { dayList.padding(.bottom, 12) }
                                .transition(.opacity)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .animation(.easeOut(duration: 0.2), value: period(shown))
                }
            }
        }
        // Тот же тёплый стол, что под поиском (P755).
        .background(Desk())
    }

    /// Высота полосы «Месяца»: шесть недель квадратных клеток, строка дней
    /// недели и сводка — у всех месяцев одна, лента не дёргается (P792).
    private func monthHeight(width: CGFloat) -> CGFloat {
        let cell = (width - 6 - 6) / 7
        let words: CGFloat = 70 * max(1, Prefs.textScale)
        return 10 + words + cell * 6 + 6
    }

    /// «Месяц» листается своим ходом (P1068) — в отдельной полосе
    /// (`MonthPager`, P1071): календарь лежит в рамке, которая при каждой
    /// правке подменяет своё содержимое целиком, и ход, заведённый снаружи,
    /// в ней не играл — месяц менялся скачком, снимки клеток слетали.
    private func monthPager(height h: CGFloat) -> some View {
        MonthPager(shown: $shown, ask: turnAsk, height: h,
                   token: "\(selected ?? "")|\(archive.revision)|\(Vault.stamp(DayStore.today()))|\(Prefs.textScale)|\(UserDefaults.standard.string(forKey: Prefs.calendarTint) ?? "")|\(UserDefaults.standard.bool(forKey: Prefs.plainPast))",
                   period: { period($0) }, shift: { shift($0, by: $1) },
                   grid: { AnyView(monthGrid(of: $0)) })
            // Три месяца клеток со снимками — не перерисовывать от каждой
            // правки экрана (смена раздела, картотека): только когда
            // поменялось то, что в них видно (P1071; на 358 смена раздела
            // показывала первый кадр через 0,3–0,4 с, на 334 — через 0,07).
            .equatable()
    }

    /// Перевернуть «Месяц» стрелкой или «домой».
    private func turn(by step: Int) {
        turnAsk = TurnAsk(id: turnAsk.id + 1, step: step)
    }

    private var years: some View {
        let list = periods()
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(list, id: \.self) { p in
                    section(p)
                }
            }
            .scrollTargetLayout()
        }
        // Один месяц (год) на экран (P792): лента встаёт страницами, не
        // останавливается посередине между двумя месяцами.
        .scrollTargetBehavior(.paging)
        .scrollPosition(id: $top, anchor: .top)
        // Сменился месяц — толчок в руку (P792); шапка меняется, когда
        // лента встала (P800: менялась на ходу, и месяц прыгал на строки).
        .modifier(PageWatch(at: $top) { now in
            guard !switching else { return }
            let keep = keepMonth(now)
            if shown != keep { shown = keep }
        })
    }

    /// Встал год — месяц остаётся прежним (P822): прежде `shown` становился
    /// 1 января этого года, и «Месяц» открывался январём — так год, долистанный
    /// до 2020-го, ставил и месяц на январь 2020-го (проверка движения P821).
    private func keepMonth(_ landed: Date) -> Date {
        guard kind == .year else { return landed }
        let month = cal.component(.month, from: shown)
        return cal.date(from: DateComponents(year: cal.component(.year, from: landed),
                                             month: month, day: 1)) ?? landed
    }

    /// Начала лет ленты «Года» — от нынешнего, двадцать назад и пять вперёд.
    private func periods() -> [Date] {
        let home = period(DayStore.today())
        return (-20...5).compactMap { cal.date(byAdding: .year, value: $0, to: home) }
    }

    /// Один год ленты — ровно на экран (P792). «Месяц» листается своей
    /// полосой (`MonthPager`, P1068), лента — только у «Года» (расчистка
    /// P1075). Высота у всех страниц одна, и ленте не приходится угадывать
    /// её на ходу — не дёргается. Своего названия у страницы нет (P1007):
    /// год уже написан в шапке со стрелками.
    private func section(_ p: Date) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Color.clear.frame(height: 4)
            yearGrid(of: p)
            Spacer(minLength: 0)
        }
        .containerRelativeFrame(.vertical, alignment: .top)
        .clipped()
    }

    /// Список дел — под месяцем выбранного дня; ничего не выбрано — под
    /// нынешним месяцем подсказка.
    private func listHere(_ p: Date) -> Bool {
        if let stamp = selected, let date = Vault.date(from: stamp) { return period(date) == p }
        return p == period(DayStore.today())
    }

    /// Кнопка вида работает дважды. Первое нажатие переключает вид. Нажатие
    /// на уже выбранный вид возвращает в сегодняшний месяц или год: та же
    /// кнопка, которой человек сюда пришёл, уводит его обратно домой. Долгое
    /// нажатие на стрелке делает то же самое, но о нём нужно знать заранее,
    /// а по названию вида понятно и без подсказки (решение P135).
    private func choose(_ k: Kind) {
        guard kind == k else { stored = k.rawValue; return }
        goHome()
    }

    /// Вернуться к нынешнему месяцу или году — лента едет к нему (P784).
    private func goHome(asked: Bool = false) {
        let unit: Calendar.Component = kind == .year ? .year : .month
        let c = cal.dateComponents([unit], from: period(shown),
                                   to: period(DayStore.today()))
        let steps = (kind == .year ? c.year : c.month) ?? 0
        // Мы и так дома — двигать нечего: ничто не должно шевелиться зря.
        // Но если просили из меню, молчать нельзя: человек решит, что
        // кнопка не сработала.
        guard steps != 0 else {
            if asked {
                shell.say(kind == .year ? T("Это и есть нынешний год", "This is the current year")
                                        : T("Это и есть нынешний месяц", "This is the current month"))
            }
            return
        }
        if kind == .month {
            // Дальний месяц — полоса сперва без хода ставит соседа, потом
            // один ход: траектория та же, что у пальца (P1068).
            turn(by: steps)
        } else {
            withAnimation(.easeInOut(duration: 0.35)) { top = period(DayStore.today()) }
        }
        shell.say(kind == .year ? T("Вернулись на этот год", "Back to this year")
                                : T("Вернулись на этот месяц", "Back to this month"))
    }

    private func homeHint(_ k: Kind) -> String {
        k == .year ? T("Нажмите ещё раз, чтобы вернуться на этот год", "Tap again to go back to this year")
                   : T("Нажмите ещё раз, чтобы вернуться на этот месяц", "Tap again to go back to this month")
    }

    private func shift(_ date: Date, by n: Int) -> Date {
        let unit: Calendar.Component = kind == .year ? .year : .month
        return cal.date(byAdding: unit, value: n, to: date) ?? date
    }

    private func nav(for date: Date) -> some View {
        let toward = towardToday(from: date)
        return HStack {
            arrow("‹", lit: toward < 0, label: kind == .year ? T("Предыдущий год", "Previous year")
                                                            : T("Предыдущий месяц", "Previous month"))
            Spacer()
            Text(kind == .year ? String(cal.component(.year, from: date))
                               : Ru.monthTitle(date))
                .font(Look.sans(16, weight: .semibold))
                .foregroundStyle(Look.ink)
                // Для проверки движения (P821): что в шапке после листания.
                .accessibilityIdentifier("calendarTitle")
            Spacer()
            arrow("›", lit: toward > 0, label: kind == .year ? T("Следующий год", "Next year")
                                                            : T("Следующий месяц", "Next month"))
        }
        // Отступ от уголков шестерёнки и точек — тот же, что у строки
        // поиска на карте и на экране «Поиск» (P334).
        .padding(.leading, Corner.size + 8)
        .padding(.trailing, Corner.size + 8)
        .padding(.top, DayPage.airAbove)
        .padding(.bottom, 8)
    }

    /// Стрелка. Та, что смотрит в сторону сегодняшнего месяца, горит: уйдя
    /// на июнь, человек видит, что «сейчас» — справа, и не гадает, в какую
    /// сторону возвращаться.
    ///
    /// Нажатие — шаг. Долгого нажатия нет (P626): в сегодняшний месяц ведёт
    /// «День» внизу.
    private func arrow(_ sign: String, lit: Bool, label: String) -> some View {
        let step = sign == "‹" ? -1 : 1
        return Text(sign)
            .font(.system(size: 22, weight: lit ? .semibold : .regular))
            .foregroundStyle(lit ? Look.accent : Look.inkFaint)
            .frame(width: 40, height: 34)
            .background(lit ? Look.accent.opacity(0.1) : .clear,
                        in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
            .onTapGesture {
                if kind == .month {
                    turn(by: step)
                } else {
                    withAnimation(.easeInOut(duration: 0.3)) { top = shift(period(shown), by: step) }
                }
            }
            .accessibilityLabel(label)
    }

    /// В какой стороне сегодняшний месяц: −1 слева, +1 справа, 0 — мы на нём.
    private func towardToday(from date: Date) -> Int {
        let here = period(date), now = period(DayStore.today())
        if here < now { return 1 }
        if here > now { return -1 }
        return 0
    }

    private func period(_ date: Date) -> Date {
        let parts: Set<Calendar.Component> = kind == .year ? [.year] : [.year, .month]
        return cal.date(from: cal.dateComponents(parts, from: date)) ?? date
    }

    // MARK: - Год

    private func yearGrid(of date: Date) -> some View {
        let year = cal.component(.year, from: date)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
                         spacing: 16) {
            ForEach(1...12, id: \.self) { m in
                Button {
                    shown = cal.date(from: DateComponents(year: year, month: m, day: 1)) ?? shown
                    stored = Kind.month.rawValue
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Ru.monthNames[m - 1].capitalized)
                            .font(Look.sans(11, weight: .medium))
                            .foregroundStyle(Look.ink)
                        // Всегда шесть недель по высоте: панельки одинаковые,
                        // а не короче у месяцев в четыре-пять недель (P525).
                        miniMonth(year: year, month: m)
                            .frame(height: 6 * 14 + 5 * 2, alignment: .top)
                    }
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    // Прошедший месяц — на бумаге прошлого с рельефом (P684).
                    .background {
                        if monthIsPast(year: year, month: m) {
                            // Кромка — у целого листа под рваным (P728).
                            ZStack {
                                OldPaper(seed: m, base: Ru.pastTint)
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Scheme.current.rim, lineWidth: 1)
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
                .buttonStyle(MonthPanelStyle())
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 20)
    }

    /// Месяц в годе — панелька: при касании чуть проседает и светлеет тень (P521).
    private struct MonthPanelStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            let down = configuration.isPressed
            return configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        // Цвет «сегодня» гаммы, светлее к верху (P757): прежде
                        // жёлтые плашки во всех гаммах.
                        .fill(Scheme.current.today)
                        .overlay(LinearGradient(colors: [.white.opacity(0.35), .black.opacity(0.04)],
                                                startPoint: .top, endPoint: .bottom)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous)))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Scheme.current.rim, lineWidth: 1))
                        .shadow(color: .black.opacity(down ? 0.06 : 0.16),
                                radius: down ? 1 : 3, x: down ? 0.5 : 2, y: down ? 0.5 : 2)
                )
                .scaleEffect(down ? 0.96 : 1)
                .brightness(down ? -0.03 : 0)
                .animation(.easeOut(duration: 0.12), value: down)
        }
    }

    /// Месяц целиком позади — до нынешнего месяца (P684).
    private func monthIsPast(year: Int, month: Int) -> Bool {
        let first = cal.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let nowFirst = cal.date(from: cal.dateComponents([.year, .month], from: DayStore.today())) ?? Date()
        return first < nowFirst
    }

    private func miniMonth(year: Int, month: Int) -> some View {
        let c = cal
        let first = c.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let cells = MonthGrid.cells(of: first, calendar: c, firstWeekday: c.firstWeekday)
        let today = Vault.stamp(DayStore.today())
        // Числа — по номеру клетки, без календаря на каждую (P827).
        let lead = cells.firstIndex { $0 != nil } ?? 0
        let rows = stride(from: 0, to: cells.count, by: 7).map { start in
            Array(start..<min(start + 7, cells.count))
        }

        // Крупнее прежнего — цифры было плохо видно (P319). Простые ряды
        // вместо ленивой сетки (P827): у сотен клеток страницы «Года» ленивая
        // сетка заново решала, что показывать, при каждом появлении.
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(rows, id: \.first) { row in
                HStack(spacing: 2) {
                    ForEach(row, id: \.self) { i in
                        if let day = cells[i] {
                            dayDot(number: i - lead + 1, stamp: Vault.stamp(day), today: today)
                        } else {
                            Color.clear.frame(width: 14, height: 14)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Число в маленьком месяце «Года».
    private func dayDot(number: Int, stamp: String, today: String) -> some View {
        let filled = archive.day(stamp)?.hasSomething == true
        // День с записью — чёткий кружок с тонкой рамкой и плотной цифрой, а
        // не бледное серое пятно (P499): издали год читается ровно.
        let fill: Color = stamp == today ? Look.accent : (filled ? Look.accent.opacity(0.12) : .clear)
        let ink: Color = stamp == today ? .white : (filled ? Look.accent : Look.inkFaint)
        let ring: Color = stamp != today && filled ? Look.accent.opacity(0.8) : .clear
        return Text("\(number)")
            .font(.system(size: 9, weight: filled ? .semibold : .regular))
            .frame(width: 14, height: 14)
            .foregroundStyle(ink)
            .background(fill, in: Circle())
            .overlay(Circle().strokeBorder(ring, lineWidth: 1))
    }

    // MARK: - Месяц

    /// Клетки квадратные, почти вплотную (P1058, автор: «квадратные
    /// окошечки, без лишнего промежутка между кадрами; закругление
    /// оставить»): снимок дня в клетке — кадриком, а не полоской. Сетка от
    /// этого выше прежней, место списку дел внизу — меньше.
    private func monthGrid(of date: Date) -> some View {
        let cells = MonthGrid.cells(of: date, calendar: cal, firstWeekday: cal.firstWeekday)
        let today = Vault.stamp(DayStore.today())

        return VStack(spacing: 0) {
            // Промежуток в точку и поля по 3 точки у краёв экрана (P1061):
            // место — снимкам дней.
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7),
                      spacing: 1) {
                ForEach(Array(header.enumerated()), id: \.offset) { i, name in
                    Text(name.uppercased())
                        .font(Look.sans(10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Ru.dayColor(dateOfWeekday(i)))
                        .padding(.bottom, 3)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day { cell(day, today: today) } else { Color.clear.aspectRatio(1, contentMode: .fit) }
                }
            }
            .padding(.horizontal, 3)

            monthStats(cells)
            Spacer(minLength: 0)
        }
    }

    /// Тихая сводка месяца (P466): сколько дней записано и сколько дел
    /// сделано. Без серий, наград и «вы пропустили день» — только итог.
    @ViewBuilder private func monthStats(_ cells: [Date?]) -> some View {
        let days = cells.compactMap { $0 }.compactMap { archive.day(Vault.stamp($0)) }
        let written = days.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || $0.photos > 0
        }.count
        let done = days.reduce(0) { $0 + $1.tasks.filter(\.done).count }
        if written + done > 0 {
            Text(T("Записано дней: \(written) · сделано дел: \(done)",
                   "Days written: \(written) · tasks done: \(done)"))
                .font(Look.sans(13))
                .foregroundStyle(Look.inkSoft)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 10)
        }
    }

    /// Клетка дня. Сегодняшний обведён, выбранный залит: «сегодня» и «то, на
    /// что я смотрю» должны различаться с одного взгляда.
    private func cell(_ date: Date, today: String) -> some View {
        let stamp = Vault.stamp(date)
        let isToday = stamp == today
        let isSelected = stamp == selected
        let shot = isToday ? nil : snapshot(stamp, date)
        let past = !isToday && Ru.isPast(date)

        // Сегодняшний день залит — он есть всегда и ни от чего не зависит.
        // Выбранный обведён лёгким ободком: внимание можно переставить, и
        // оно не должно выглядеть весомее самого дня.
        return Button { pick(stamp, date) } label: {
            // Число — в правом нижнем углу (P1058); точки дел — слева на
            // той же высоте, только у сегодня и будущего: у прошлого их нет.
            ZStack(alignment: .bottomTrailing) {
                if !past {
                    dots(count: entries(stamp, date).count, light: isToday)
                        .padding(.leading, 6)
                        .padding(.bottom, 8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
                Text("\(cal.component(.day, from: date))")
                    // Цифры плотнее, сегодняшняя — крупнее и жирнее всех
                    // (P247), белая; синим залита вся клетка, а не кружок
                    // под цифрой (P442, прежде P431).
                    .font(Look.sans(isToday ? 16 : 14.5, weight: isToday ? .bold : .medium))
                    .foregroundStyle(isToday || shot != nil ? Color.white : Look.ink)
                    // На снимке — белая с тенью, и у выходных тоже (P1056).
                    .shadow(color: .black.opacity(shot != nil ? 0.7 : 0), radius: 2, y: 0.5)
                    .padding(.trailing, 6)
                    .padding(.bottom, 3)
            }
            // Угол — у всей клетки: без него у прошлого, где точек нет,
            // число вставало посередине.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .aspectRatio(1, contentMode: .fit)
            // Клетка — того же цвета, что страница этого дня: сегодня
            // абрикосовое, прошлое голубеет, будущее зеленеет (P245).
            // Прошедший день — на бумаге с рельефом, как его страница (P684),
            // со своим износом и травмами края (P723).
            .background {
                if past {
                    // Износ — по числу месяца, один набор на все месяцы и годы (P798):
                    // готовая бумага берётся из запаса, а не рисуется на ходу.
                    OldPaper(seed: cal.component(.day, from: date), base: tint(date))
                        .overlay { if let shot { CalendarShot(url: shot.url, video: shot.video) } }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    RoundedRectangle(cornerRadius: 8).fill(isToday ? Look.accent : tint(date))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Look.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    /// Кадрик прошедшего дня (P1056, автор: «как в Diarium»): первый снимок
    /// дня, иначе кадр первого видео; голос, файлы, места — нет, клетка
    /// бумажная. Снимок ещё в iCloud — тоже бумага: календарь не тянет
    /// файлы из облака.
    private func snapshot(_ stamp: String, _ date: Date) -> (url: URL, video: Bool)? {
        guard Ru.isPast(date), let day = archive.day(stamp) else { return nil }
        let link = day.attachments.first { Diary.kind(of: $0) == .photo }
            ?? day.attachments.first { Diary.kind(of: $0) == .video }
        guard let link, let url = vault.mediaURL(link, for: date),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return (url, Diary.kind(of: link) == .video)
    }

    /// Дела дня вместе с событиями Календаря iPhone — как на странице дня
    /// (P376): сперва события, потом свои дела. Прежде календарь показывал
    /// только свои дела, и события были видны лишь на самой странице (P428).
    private func entries(_ stamp: String, _ date: Date) -> [PlanRow] {
        let marks = archive.day(stamp)?.marks ?? []
        let events = DayEvents.shown(DayEvents.cachedItems(for: date), marks: marks).map(\.row)
        return events + archive.tasks(stamp)
    }

    /// Точек столько, сколько дел, но не больше трёх: по ним видно,
    /// насколько день занят, не открывая его.
    private func dots(count: Int, light: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<min(count, 3), id: \.self) { _ in
                Circle()
                    .fill(light ? Look.planBg : Look.inkFaint)
                    .frame(width: 3.5, height: 3.5)
            }
        }
        .frame(height: 3.5)
    }

    private func dateOfWeekday(_ i: Int) -> Date {
        // 5 января 2026 — понедельник, 4-е — воскресенье.
        let first = cal.date(from: DateComponents(year: 2026, month: 1,
                                                  day: cal.firstWeekday == 1 ? 4 : 5)) ?? Date()
        return cal.date(byAdding: .day, value: i, to: first) ?? first
    }

    /// Заголовок недели — с выбранного первого дня (P290).
    private var header: [String] {
        cal.firstWeekday == 1 ? [Ru.weekHeader.last ?? ""] + Array(Ru.weekHeader.dropLast()) : Ru.weekHeader
    }

    /// Цвет клетки дня — как выбрано в настройках (P290): цветом гаммы или без цвета (P498).
    private func tint(_ date: Date) -> Color { Ru.tint(date) }

    @ViewBuilder private var dayList: some View {
        if let stamp = selected, let date = Vault.date(from: stamp) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Как под именем листа (P1053): «23 ноября ’26,
                    // понедельник»; сначала число, справа день недели (P467).
                    (Text(Ru.headDate(date) + ", ").foregroundColor(Look.ink)
                     + Text(Ru.weekday(date)).foregroundColor(Ru.dayColor(date)))
                        .font(Look.sans(13, weight: .medium))
                    Spacer()
                    Button(T("Открыть день →", "Open day →")) { open(date) }
                        .font(Look.sans(13))
                        .foregroundStyle(Look.accent)
                }
                let tasks = entries(stamp, date)
                if tasks.isEmpty {
                    Text(T("Дел на этот день нет.", "No tasks on this day."))
                        .font(Look.sans(13))
                        .foregroundStyle(Look.inkFaint)
                } else {
                    ForEach(tasks) { task in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(task.time.map(Clock.show) ?? "--:--")
                                .font(Look.mono(12))
                                .foregroundStyle(Look.inkFaint)
                            Text(task.text)
                                .font(Look.sans(13))
                                .foregroundStyle(Look.ink)
                                .opacity(task.done ? 0.45 : 1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
        } else {
            Text(T("Нажмите дату, чтобы увидеть дела этого дня.", "Tap a date to see its tasks."))
                .font(Look.sans(13))
                .foregroundStyle(Look.inkFaint)
                .padding(.horizontal, 20)
        }
    }

    // MARK: - Касания

    private func pick(_ stamp: String, _ date: Date) {
        if selected == stamp { open(date) } else { selected = stamp }
    }

    private func open(_ date: Date) {
        store.go(to: date)
        shell.tab = .plan
        // Из календаря — всегда на план (P424).
        shell.asks.landOnDiary = false
        shell.asks.landing += 1
        shell.screen = .today
    }
}

/// Снимок дня во всю клетку месяца (P1056). Читается из папки уменьшенным и
/// держится только в памяти, как превью в тексте: приложение ничего своего
/// не хранит. Проявляется плавно (P893): пока читается — бумага клетки.
/// Видео — его первый кадр и треугольник «играть».
private struct CalendarShot: View {
    let url: URL
    let video: Bool
    @State private var image: UIImage?
    @State private var visible: Bool

    init(url: URL, video: Bool) {
        self.url = url
        self.video = video
        let cached = Photo.cache.object(forKey: url.path as NSString)
        _image = State(initialValue: cached)
        _visible = State(initialValue: cached != nil)
    }

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    // Низ темнее — белое число читается на любом снимке.
                    .overlay(LinearGradient(colors: [.clear, .black.opacity(0.35)],
                                            startPoint: .center, endPoint: .bottom))
                    .overlay(alignment: .topTrailing) {
                        if video {
                            Image(systemName: "play.fill")
                                .font(.system(size: 6))
                                .foregroundStyle(.white)
                                .padding(2.5)
                                .background(.black.opacity(0.45), in: Circle())
                                .padding(2)
                        }
                    }
                    // Проступает только сам снимок (P1071): прежде общий ход
                    // подхватывал и место клетки, и снимок слетал в неё.
                    .opacity(visible ? 1 : 0)
                    .animation(.easeOut(duration: 0.25), value: visible)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .allowsHitTesting(false)
        .task(id: url) {
            guard image == nil else { return }
            let got: UIImage?
            if video {
                got = await Photo.poster(url, side: 160)
            } else {
                let at = url
                got = await Task.detached(priority: .userInitiated) {
                    Photo.load(at, side: Photo.thumbSide)
                }.value
            }
            guard let got else { return }
            Photo.cache.setObject(got, forKey: url.path as NSString)
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { image = got }
            DispatchQueue.main.async { visible = true }
        }
    }
}



/// Просьба полосе «Месяца» перевернуться (P1071).
struct TurnAsk: Equatable {
    let id: Int
    let step: Int
}

/// Полоса «Месяца» (P1068, P1071): три месяца вплотную — прежний, нынешний,
/// следующий. Идёт за пальцем по вертикали; отпущенная доезжает мягкой
/// пружиной без отскока, и сосед становится нынешним уже без движения.
/// Сверху и снизу тает в стол. Смахивание вбок сетка не забирает — по нему
/// листаются разделы (P1071, автор по 358: «невозможно сделать свайп на
/// сегодняшний день поверх окошечек месяца»).
private struct MonthPager: View, Equatable {
    @Binding var shown: Date
    let ask: TurnAsk
    let height: CGFloat
    /// Что видно в клетках: выбранный день, правка описи, сегодня, размер
    /// шрифта. Пока это то же, полоса не перерисовывается.
    let token: String
    let period: (Date) -> Date
    let shift: (Date, Int) -> Date
    let grid: (Date) -> AnyView

    static func == (a: MonthPager, b: MonthPager) -> Bool {
        a.shown == b.shown && a.ask == b.ask && a.height == b.height && a.token == b.token
    }

    @State private var pull: CGFloat = 0
    @State private var settling = false
    /// Какой месяц полоса показывает (P1077). Свой, а не `shown` снаружи:
    /// календарь лежит в рамке, и `shown` доходит до полосы на такт позже —
    /// на 359 ход кончался на октябре, а полоса ещё секунды стояла на
    /// ноябре и потом перелетала. Меняется вместе с ходом, наружу —
    /// следом, для шапки и списка дел.
    @State private var own: Date?

    private var current: Date { own ?? period(shown) }

    var body: some View {
        let h = height
        let here = current
        let pages = [-1, 0, 1].map { shift(here, $0) }
        ZStack(alignment: .top) {
            ForEach(Array(pages.enumerated()), id: \.element) { i, p in
                grid(p)
                    .padding(.top, 10)
                    .frame(height: h, alignment: .top)
                    .offset(y: CGFloat(i - 1) * h + pull)
            }
        }
        .frame(height: h, alignment: .top)
        .clipped()
        .mask(
            LinearGradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: min(0.5, 18 / max(h, 1))),
                .init(color: .black, location: max(0.5, 1 - 26 / max(h, 1))),
                .init(color: .clear, location: 1),
            ], startPoint: .top, endPoint: .bottom))
        // Ведёт полосу распознаватель iPhone, а не жест SwiftUI (P1076,
        // автор по 359: «по-прежнему нет свайпа с календаря»): тот, даже
        // «одновременный», забирал касание у ленты разделов. Этот начинается,
        // только если палец пошёл по вертикали, — вбок касание целиком
        // достаётся разделам, касания клеток проходят как прежде.
        .background(VerticalPan(
            changed: { dy in
                guard !settling else { return }
                pull = dy
            },
            ended: { dy, speed in
                guard !settling else { return }
                let flung = dy + speed * 0.25
                let step = (dy < -h * 0.5 || flung < -h * 0.3) ? 1
                         : (dy > h * 0.5 || flung > h * 0.3) ? -1 : 0
                turn(by: step)
            }))
        .onChange(of: ask) { _, now in
            guard !settling, now.step != 0 else { return }
            // Дальний месяц — сперва без хода соседом, потом один ход.
            if abs(now.step) > 1 {
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { own = shift(current, now.step - (now.step > 0 ? 1 : -1)) }
            }
            turn(by: now.step > 0 ? 1 : -1)
        }
        // Месяц поменяли снаружи (смена вида, «домой» без хода) — полоса
        // встаёт на него.
        .onChange(of: period(shown)) { _, now in
            guard !settling, own != now else { return }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { own = now }
        }
    }

    private func turn(by step: Int) {
        settling = true
        // Доводка — ровно за 0,45 с (P1077): мягкая пружина без отскока
        // считалась законченной только через секунды, и смена месяца ждала.
        withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.45), completionCriteria: .removed) {
            pull = -CGFloat(step) * height
        } completion: {
            let next = shift(current, step)
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                // Свой месяц и сдвиг — одним тактом: сосед встаёт на место
                // нынешнего, ничего не прыгает.
                if step != 0 { own = next }
                pull = 0
            }
            settling = false
            if step != 0 {
                shown = next
                Feel.light()
            }
        }
    }
}


/// Вертикальное ведение полосы «Месяца» (P1076): распознаватель iPhone на
/// окне, слушающий только касания внутри своей полосы. Начинается лишь при
/// движении по вертикали, с другими распознавателями уживается и касаний
/// не отменяет — свайп вбок листает разделы, касание клетки выбирает день.
private struct VerticalPan: UIViewRepresentable {
    var changed: (CGFloat) -> Void
    /// Сдвиг и скорость (точек в секунду) в миг отпускания; отменили — 0, 0.
    var ended: (CGFloat, CGFloat) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Probe {
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        probe.backgroundColor = .clear
        probe.coordinator = context.coordinator
        return probe
    }

    func updateUIView(_ probe: Probe, context: Context) {
        context.coordinator.changed = changed
        context.coordinator.ended = ended
    }

    static func dismantleUIView(_ probe: Probe, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Probe: UIView {
        weak var coordinator: Coordinator?
        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil { coordinator?.attach(self) } else { coordinator?.detach() }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var changed: ((CGFloat) -> Void)?
        var ended: ((CGFloat, CGFloat) -> Void)?
        private weak var probe: UIView?
        private var pan: UIPanGestureRecognizer?

        func attach(_ view: UIView) {
            detach()
            guard let window = view.window else { return }
            probe = view
            let pan = UIPanGestureRecognizer(target: self, action: #selector(moved(_:)))
            pan.delegate = self
            // Повели по вертикали — касание у клетки отменяется, как в
            // прокрутке iPhone (P1078: проверка движения на 360 — свайп,
            // начатый на клетке, месяц не листал: клетка-кнопка держала
            // касание). Простое касание клетки по-прежнему выбирает день.
            pan.cancelsTouchesInView = true
            pan.delaysTouchesBegan = false
            pan.delaysTouchesEnded = false
            window.addGestureRecognizer(pan)
            self.pan = pan
        }

        func detach() {
            if let pan { pan.view?.removeGestureRecognizer(pan) }
            pan = nil
        }

        @objc private func moved(_ pan: UIPanGestureRecognizer) {
            let t = pan.translation(in: pan.view).y
            switch pan.state {
            case .changed: changed?(t)
            case .ended: ended?(t, pan.velocity(in: pan.view).y)
            case .cancelled, .failed: ended?(0, 0)
            default: break
            }
        }

        /// Только в своей полосе, когда она на экране, и по вертикали.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            guard let pan = g as? UIPanGestureRecognizer, let probe,
                  let window = probe.window else { return false }
            guard probe.bounds.contains(pan.location(in: probe)) else { return false }
            // Полоса видна целиком — не уехала вбок вместе с разделами.
            let onScreen = probe.convert(probe.bounds, to: nil).intersection(window.bounds)
            guard onScreen.width > probe.bounds.width * 0.9 else { return false }
            let v = pan.velocity(in: probe)
            return abs(v.y) > abs(v.x)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        /// Ничьего провала не ждать и своим провалом никого не держать:
        /// кнопки клеток и лента разделов идут сами по себе.
        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRequireFailureOf other: UIGestureRecognizer) -> Bool { false }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool { false }
    }
}
