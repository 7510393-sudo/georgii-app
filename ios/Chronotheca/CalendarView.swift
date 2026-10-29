import SwiftUI

/// Календарь: год, месяц и список месяца.
///
/// Первое касание даты разворачивает дела этого дня, второе открывает день.
/// Так можно заглянуть в дату, не теряя места, где стоишь.
struct CalendarView: View {

    enum Kind: String, CaseIterable, Identifiable {
        case year = "Год", month = "Месяц", list = "Список"
        var id: String { rawValue }
        /// Название на языке приложения; `rawValue` хранится в настройках
        /// и не меняется (P355).
        var title: String {
            switch self {
            case .year: return T("Год", "Year")
            case .month: return T("Месяц", "Month")
            case .list: return T("Список", "List")
            }
        }
    }

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var archive: Archive
    @EnvironmentObject private var shell: Shell

    /// Вид запоминается между заходами: человек, оставивший «Список»,
    /// возвращается в «Список», а не в чужой ему «Месяц».
    @AppStorage("calendar.kind") private var stored = Kind.month.rawValue
    private var kind: Kind { Kind(rawValue: stored) ?? .month }
    @State private var shown: Date = DayStore.today()
    @State private var plan: [Int] = []
    @State private var selected: String? = Vault.stamp(DayStore.today())

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
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 10)

            PageCurl(content: { offset in
                page(at: step(offset), current: offset == 0)
                    .environmentObject(store)
                    .environmentObject(archive)
                    .environmentObject(shell)
            }, onTurn: { step in
                shown = shift(shown, by: step)
                // Бегунок снимается: дело выбранного дня к новому месяцу
                // отношения не имеет и висеть под ним не должно.
                selected = nil
            }, plan: $plan)
        }
        .onAppear {
            DayEvents.forgetCache()
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

    /// Страница календаря целиком: название, сетка и список дел под ней.
    ///
    /// Название и стрелки теперь в неподвижной верхней строке (P334), не
    /// на самой странице. Список дел показывается только на той странице,
    /// на которой человек стоит: на соседнем месяце дела сегодняшнего
    /// дня — чужие.
    private func page(at date: Date, current: Bool) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                ScrollViewReader { proxy in
                    VStack(spacing: 0) {
                        switch kind {
                        case .year:  yearGrid(of: date)
                        case .month: monthGrid(of: date, current: current)
                        case .list:  monthList(of: date)
                        }
                    }
                    // Список открывается так, чтобы нужный день — открытый
                    // или сегодняшний — стоял вверху экрана (P286).
                    .onAppear { toTop(proxy, in: date, current: current) }
                    .onChange(of: stored) { _, _ in toTop(proxy, in: date, current: current) }
                    // Календарь ждёт на своей плашке там, где его оставили
                    // (P576); прежде вставал на день при каждом открытии
                    // (P442) — отменено.
                }
            }
        }
        .background(Look.planBg)
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

    /// Вернуться к нынешнему месяцу или году, перелистнув страницы.
    ///
    /// Не прыжком: дорога домой должна быть видна — то же правило, что у
    /// кнопки «Сегодня» (решение P164).
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
        plan = wayHome(steps)
        shell.say(kind == .year ? T("Вернулись на этот год", "Back to this year")
                                : T("Вернулись на этот месяц", "Back to this month"))
    }

    private func homeHint(_ k: Kind) -> String {
        k == .year ? T("Нажмите ещё раз, чтобы вернуться на этот год", "Tap again to go back to this year")
                   : T("Нажмите ещё раз, чтобы вернуться на этот месяц", "Tap again to go back to this month")
    }

    private func step(_ offset: Int) -> Date { shift(shown, by: offset) }

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
                shown = shift(shown, by: step)
                selected = nil
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
                            ZStack {
                                Ru.pastTint
                                OldPaper()
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Look.stickerEdge, lineWidth: 1))
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
                        .fill(LinearGradient(colors: [Look.plateLight, Look.plateDark],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Look.stickerEdge, lineWidth: 1))
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
        let first = cal.date(from: DateComponents(year: year, month: month, day: 1)) ?? Date()
        let cells = MonthGrid.cells(of: first, calendar: cal, firstWeekday: cal.firstWeekday)
        let today = Vault.stamp(DayStore.today())

        // Крупнее прежнего — цифры было плохо видно (P319).
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(14), spacing: 2), count: 7),
                         spacing: 2) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                if let day {
                    let stamp = Vault.stamp(day)
                    let filled = archive.day(stamp)?.hasSomething == true
                    // День с записью — чёткий кружок с тонкой рамкой и плотной
                    // цифрой, а не бледное серое пятно (P499): издали год
                    // читается ровно.
                    Text("\(cal.component(.day, from: day))")
                        .font(.system(size: 9, weight: filled ? .semibold : .regular))
                        .frame(width: 14, height: 14)
                        .foregroundStyle(stamp == today ? Color.white
                                         : (filled ? Look.accent : Look.inkFaint))
                        .background(stamp == today ? Look.accent
                                    : (filled ? Look.accent.opacity(0.12) : .clear),
                                    in: Circle())
                        .overlay(Circle().strokeBorder(
                            stamp != today && filled ? Look.accent.opacity(0.8) : .clear,
                            lineWidth: 1))
                } else {
                    Color.clear.frame(height: 14)
                }
            }
        }
    }

    // MARK: - Месяц

    /// Сетка на пятую часть плотнее прежней: место внизу нужнее списку дел,
    /// ради которого в календарь и заходят.
    private func monthGrid(of date: Date, current: Bool) -> some View {
        let cells = MonthGrid.cells(of: date, calendar: cal, firstWeekday: cal.firstWeekday)
        let today = Vault.stamp(DayStore.today())

        return VStack(spacing: 0) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7),
                      spacing: 4) {
                ForEach(Array(header.enumerated()), id: \.offset) { i, name in
                    Text(name.uppercased())
                        .font(Look.sans(10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(Ru.dayColor(dateOfWeekday(i)))
                        .padding(.bottom, 3)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day { cell(day, today: today) } else { Color.clear.frame(height: 32) }
                }
            }
            .padding(.horizontal, 10)

            monthStats(cells)
            Rectangle().fill(Look.rule).frame(height: 1).padding(.vertical, 10)
            if current { dayList }
        }
        .padding(.bottom, 20)
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

        // Сегодняшний день залит — он есть всегда и ни от чего не зависит.
        // Выбранный обведён лёгким ободком: внимание можно переставить, и
        // оно не должно выглядеть весомее самого дня.
        return Button { pick(stamp, date) } label: {
            VStack(spacing: 1) {
                Text("\(cal.component(.day, from: date))")
                    // Цифры плотнее, сегодняшняя — крупнее и жирнее всех
                    // (P247), белая; синим залита вся клетка, а не кружок
                    // под цифрой (P442, прежде P431).
                    .font(Look.sans(isToday ? 16 : 14.5, weight: isToday ? .bold : .medium))
                    .foregroundStyle(isToday ? Color.white : Look.ink)
                dots(count: entries(stamp, date).count, light: isToday)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            // Клетка — того же цвета, что страница этого дня: сегодня
            // абрикосовое, прошлое голубеет, будущее зеленеет (P245).
            .background(isToday ? Look.accent : tint(date), in: RoundedRectangle(cornerRadius: 8))
            // Прошедший день — на бумаге с рельефом, как его страница (P684).
            .overlay {
                if !isToday && Ru.isPast(date) {
                    OldPaper().clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Look.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
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
                    // Сначала число, справа день недели (P467).
                    (Text(Ru.shortDate(date)).foregroundColor(Look.ink)
                     + Text("  " + Ru.weekdayShort(date)).foregroundColor(Ru.dayColor(date)))
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

    // MARK: - Список

    private func toTop(_ proxy: ScrollViewProxy, in month: Date, current: Bool) {
        guard current, kind == .list else { return }
        // Сегодняшний — первым (P456): автор открыл «Список» в пятницу, а
        // вверху стояло воскресенье, открытое раньше.
        let target = [DayStore.today(), store.date].first {
            cal.isDate($0, equalTo: month, toGranularity: .month)
        }
        guard let target else { return }
        // Строки списка рисуются по мере надобности: дать им встать, потом
        // ехать к дню (P442).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            proxy.scrollTo(Vault.stamp(target), anchor: .top)
        }
    }

    private func monthList(of date: Date) -> some View {
        let cells = MonthGrid.cells(of: date, calendar: cal, firstWeekday: cal.firstWeekday).compactMap { $0 }
        let today = Vault.stamp(DayStore.today())

        // Не «ленивый» столбец (P456): в нём строки, ещё не нарисованные,
        // стоят наугад, и прокрутка к дню промахивалась на день-два. Дней в
        // месяце не больше 31 — рисовать их сразу ничего не стоит.
        return VStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                row(day, today: today)
                    .id(Vault.stamp(day))
                weekRule(after: day)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 20)
    }

    private func row(_ date: Date, today: String) -> some View {
        let stamp = Vault.stamp(date)
        let tasks = entries(stamp, date)
        let open = stamp == selected
        // Пустой день — тонкой строкой (P466): прежде каждый пустой день
        // был такой же высоты, как занятый, и дела тонули среди тире.
        let quiet = tasks.isEmpty && !open && stamp != today

        return Button { pick(stamp, date) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                // Число и справа от него день недели — у всех дней одинаково
                // (P467): прежде у пустых дней день недели стоял справа, у
                // занятых — под числом, и столбец дат прыгал.
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    // Сегодня — белым в синем кружке (P431).
                    Text("\(cal.component(.day, from: date))")
                        .font(Look.mono(15, weight: stamp == today ? .bold : .regular))
                        .foregroundStyle(stamp == today ? Color.white : Look.ink)
                        .padding(.horizontal, stamp == today ? 5 : 0)
                        .background { if stamp == today { Capsule().fill(Look.accent).padding(.vertical, -3) } }
                    Text(Ru.weekdayShort(date))
                        .font(Look.sans(10))
                        .foregroundStyle(Ru.dayColor(date))
                }
                .frame(width: 56, alignment: .leading)

                VStack(alignment: .leading, spacing: 3) {
                    if tasks.isEmpty {
                        Text(open ? T("Дел нет. Нажмите ещё раз, чтобы открыть день →", "No tasks. Tap again to open the day →") : "—")
                            .font(Look.sans(13))
                            .foregroundStyle(Look.inkFaint)
                    } else {
                        // Дело — ровно одна строка. Длинное обрывается
                        // троеточием: иначе одно дело занимает место двух,
                        // и по строкам уже не видно, насколько день занят
                        // (решение P159).
                        ForEach(open ? tasks : Array(tasks.prefix(3))) { task in
                            Text((task.time.map { $0 + "  " } ?? "") + task.text)
                                .font(Look.sans(13))
                                .foregroundStyle(Look.ink)
                                .opacity(task.done ? 0.45 : 1)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !open && tasks.count > 3 {
                            Text(T("ещё \(tasks.count - 3)", "\(tasks.count - 3) more"))
                                .font(Look.sans(11))
                                .foregroundStyle(Look.inkFaint)
                        }
                        if open {
                            Text(T("Нажмите ещё раз, чтобы открыть день →", "Tap again to open the day →"))
                                .font(Look.sans(11))
                                .foregroundStyle(Look.inkFaint)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, quiet ? 4 : 9)
            .opacity(quiet ? 0.75 : 1)
            // Строка дня — цвета его страницы (P245); выбранная обведена.
            .background(tint(date))
            // Прошедший день — на бумаге с рельефом (P684).
            .overlay { if Ru.isPast(date) { OldPaper() } }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(open ? Look.accent.opacity(0.6) : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    /// Разделение недель: воскресенье отбивается жирной чертой — это конец
    /// недели; пятница тонкой — за ней начинаются выходные. Так месяц
    /// читается ритмом, а не сплошным столбцом.
    ///
    /// Черта воскресенья загибается на концах вверх: она не сама по себе, а
    /// нижний край рамки вокруг недели, и этот загиб её и замыкает (P143).
    @ViewBuilder private func weekRule(after date: Date) -> some View {
        let weekday = cal.component(.weekday, from: date)
        // Черты обнимают выходные — субботу и воскресенье, — с какого бы дня
        // ни начиналась неделя (P456; прежде при неделе с воскресенья жирная
        // черта вставала после субботы, и выделенными выглядели пятница и
        // суббота). Нижняя — заметнее, с явными загибами.
        if weekday == 1 {
            WeekEnd(rise: 9).stroke(Look.inkSoft, style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                .frame(height: 3)
        } else if weekday == 6 {
            Rectangle().fill(Look.inkFaint).opacity(0.55).frame(height: 1)
        } else {
            Rectangle().fill(Look.ruleSoft).frame(height: 1)
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
        shell.landOnDiary = false
        shell.landing += 1
        shell.screen = .today
    }
}
