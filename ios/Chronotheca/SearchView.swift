import SwiftUI

/// Поиск по архиву.
///
/// Ищет по тому, что лежит в файлах: по заголовку дня, по тексту записи, по
/// названиям дел и по ответам «Как прошло?». Показывает при этом только
/// заголовок и текст: ответы — служебная часть записи, в выдаче от них
/// рябит. Но если искомое слово нашлось именно в них, день всё равно
/// попадает в список — иначе поиск лгал бы.
struct SearchView: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var archive: Archive
    @EnvironmentObject private var shell: Shell
    /// Слово, где и что искать (P964).
    @EnvironmentObject private var search: SearchState
    @EnvironmentObject private var vault: Vault

    /// Строка поиска лежит в оболочке: её очищает и меню поиска.
    private var query: String { search.query }
    /// Насколько клавиатура закрывает список находок.
    @State private var keyboard: CGFloat = 0
    /// Какая стопка пустых дней раскрыта (P988): число её первого дня.
    /// Раскрыта всегда одна — раскрыли другую, прежняя сложилась.
    @State private var unfolded: String?
    /// Когда последний раз сама пришла подсказка, что стопку раскрывают
    /// долгим нажатием (P989, автор по 314: «подсказка хорошая, пусть будет
    /// периодически вылезать»; вместо «первые три раза» P988): не чаще раза
    /// в сутки.
    @AppStorage(Prefs.stackHintAt) private var stackHintAt: Double = 0
    /// Сама подсказка — не чаще раза за запуск.
    private static var hintedThisRun = false

    /// Высота экрана раздела — высота места дня в ленте (P777).
    let height: CGFloat

    var body: some View {
        ribbonList
            // Листы старой бумаги для карточек прошлого — все сразу, заранее
            // (P847): лист рисуется, когда карточка показалась впервые, и пока
            // его нет, карточка ровная — в картотеке одни карточки были с
            // затёртыми краями, другие без (снимок автора, «Без цвета»). Через
            // несколько секунд после запуска, в стороне; готовые лежат на
            // диске (P809), второй раз не рисуются. Своя гамма — свой набор.
            .task(id: PageTexture.grey) {
                try? await Task.sleep(for: .seconds(8))
                guard !UserDefaults.standard.bool(forKey: Prefs.plainPast) else { return }
                let w = UIScreen.main.bounds.width - 2 * (10 + Search.cardInset)
                let h = Search.tabHeight + 8 + Search.body + Search.overlap + 6
                for v in 0..<24 {
                    let order = PageTexture.agedOrder(size: CGSize(width: w, height: h), band: 12,
                                                      seed: v, openBottom: true, light: false,
                                                      tab: Search.tabHeight, share: Search.tabShare)
                    _ = await PageTexture.aged(order)
                }
            }
            .keyboardHeight($keyboard)
            // Своя высота — экран раздела; запас ленты ниже экрана (P791)
            // выходит за неё вниз, а не сдвигает ленту.
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            // Строка поиска и лупа — не здесь, а на верхнем слое страницы
            // «Дня» (`SearchBar`, P969): картотека лежит под листом «Сегодня»,
            // и строка под корешком пряталась бы под ним (P968).
            .onAppear { shell.ribbon.height = height }
            .onChange(of: height) { _, h in shell.ribbon.height = h }
    }

    private var whereNot: String {
        switch search.scope {
        case .all:   return ""
        case .diary: return T("в дневнике ", "in the diary ")
        case .plan:  return T("в плане ", "in the plan ")
        }
    }

    /// Ответы «Как прошло?» — часть дневника: их пишут там, а не в плане.
    private var found: [Archive.Day] {
        let days = archive.newestFirst.filter(kept)
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        // Пока ничего не набрано — все дни, и прошлые, и будущие с делами:
        // в картотеке они стоят ниже сегодняшнего (P768, отменяет P426).
        guard !needle.isEmpty else { return days }
        let scope = search.scope
        return days.filter { day in
            if scope != .plan {
                if day.title.lowercased().contains(needle) { return true }
                if day.text.lowercased().contains(needle) { return true }
                if day.answers.values.contains(where: { $0.lowercased().contains(needle) }) {
                    return true
                }
            }
            if scope != .diary {
                return day.tasks.contains { $0.text.lowercased().contains(needle) }
            }
            return false
        }
    }

    /// Строка ленты (P777): поле сверху, прошлое, место дня, будущее, поле
    /// снизу.
    private struct Entry: Identifiable {
        enum Kind {
            case pad(CGFloat)
            case note
            /// С этой стороны от «Сегодня» не нашлось, а с другой — есть (P934).
            case hint(Deck.Side)
            case past(Archive.Day)
            case slot
            /// Будущий день с делами и пустые дни перед ним — стопкой над его
            /// корешком (P990).
            case future(Archive.Day, [Date])
            /// Пустые дни после последней карточки — одна стопка (P983).
            case empty([Date])
            /// Пустой день: в ближайший месяц (P990) или раскрытой стопки
            /// (P988) — пустая карточка.
            case blank(Date)
        }
        let id: String
        let kind: Kind
        /// Заходит на предыдущую карточку (P694, P695).
        var over = false

        /// Куда уходит даль (P782): 1 — прошлое, вдаль вверх; -1 — будущее,
        /// вдаль вниз; 0 — не карточка (место дня, поля).
        var depth: Int {
            switch kind {
            case .past: return 1
            case .future, .empty, .blank: return -1
            default: return 0
            }
        }
    }

    /// Будущее ленты (P771, P983): все дни подряд — месяц и дальше, до
    /// последнего дня с делами (не дальше `Search.horizon`); пустые потом
    /// лягут корешками. Когда ищут — только находки.
    private func ahead(_ days: [Archive.Day], from today: Date) -> [Archive.Day] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard needle.isEmpty, search.find == .all else { return days }
        let byStamp = Dictionary(days.map { ($0.stamp, $0) }, uniquingKeysWith: { first, _ in first })
        let lastPlanned = days.map(\.stamp).max() ?? ""
        var out: [Archive.Day] = []
        var last = Vault.stamp(today)
        for offset in 1...Search.horizon {
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: today) else { continue }
            let stamp = Vault.stamp(date)
            if offset > Search.ahead && stamp > lastPlanned { break }
            out.append(byStamp[stamp] ?? Archive.Day(stamp: stamp, date: date))
            last = stamp
        }
        out += days.filter { $0.stamp > last }
        return out
    }

    /// Вся лента одной стопкой (P777, вместо двух картотек P771): старые
    /// сверху, внизу прошлого вчера, ниже место сегодняшнего дня, под ним
    /// завтра и дальше. Сегодняшней карточки нет: на её месте сам день.
    /// Лента всегда собрана вокруг сегодня (P923): открытый с карточки день
    /// её не пересобирает.
    private func entries(_ past: [Archive.Day], _ future: [Archive.Day]) -> [Entry] {
        var out: [Entry] = []
        // Над самой старой — место под строку поиска; в коротком архиве —
        // стол до верха экрана, чтобы лента могла встать вчерашним днём
        // над нижней строкой.
        out.append(Entry(id: "lead", kind: .pad(max(8, height - CGFloat(past.count) * 60))))
        // Слово есть только с другой стороны от «Сегодня» — подсказка на
        // пустой стороне (P934, ответ автора: «писать подсказку, но не
        // переходить без пользователя»): прежде экран был пуст, будто не
        // нашлось ничего.
        let asked = !query.trimmingCharacters(in: .whitespaces).isEmpty
        if asked && past.isEmpty {
            out.append(future.isEmpty ? Entry(id: "note", kind: .note)
                                      : Entry(id: "hint-past", kind: .hint(.past)))
        }
        for (i, day) in past.enumerated() {
            out.append(Entry(id: Search.deep ? "p\(i)" : day.id, kind: .past(day), over: i > 0))
        }
        // Место дня заходит на нижний край вчерашней карточки, как
        // следующая карточка; завтрашняя лежит под днём своим корешком.
        out.append(Entry(id: Ribbon.slotID, kind: .slot, over: !past.isEmpty))
        if asked && future.isEmpty && !past.isEmpty {
            out.append(Entry(id: "hint-future", kind: .hint(.future)))
        }
        // Пустой будущий день (P990, автор по 314: «карточки ближайшего
        // месяца всегда должны быть открыты, чтобы у человека было
        // визуальное представление о ближайшем месяце»): в ближайший месяц —
        // пустая карточка, дальше — стопкой закрытых карточек (P983). Когда
        // ищут, пустых нет — только находки. Стопка лежит в одной строке
        // ленты с карточкой под ней, а не с карточкой над ней (P990): при
        // движении к середине экрана строки ленты сближаются по-разному
        // (P909), и карточка под стопкой то закрывала, то открывала её
        // линии — стопка раздвигалась, как открытые карточки (автор по 314:
        // «лишнее»). Теперь линии и карточка под ними едут вместе.
        let month = Calendar.current.date(byAdding: .day, value: Search.ahead, to: DayStore.today()) ?? .distantPast
        var stack: [Date] = []
        var cards = 0
        func add(_ id: String, _ kind: Entry.Kind) {
            out.append(Entry(id: id, kind: kind, over: cards > 0))
            cards += 1
        }
        // Накопленные пустые дни: раскрытая стопка (P988) — пустыми
        // карточками; сложенная — отдаётся карточке под ней, а если её нет,
        // встаёт отдельной строкой.
        func folded(under card: Bool) -> [Date] {
            defer { stack = [] }
            guard let first = stack.first else { return [] }
            let key = Vault.stamp(first)
            if unfolded == key {
                for date in stack { add(Vault.stamp(date), .blank(date)) }
                return []
            }
            if card { return stack }
            add("e" + key, .empty(stack))
            return []
        }
        for day in future {
            if !asked && plan(day).isEmpty {
                if day.date <= month {
                    _ = folded(under: false)
                    add(Vault.stamp(day.date), .blank(day.date))
                } else {
                    stack.append(day.date)
                }
            } else {
                add(day.id, .future(day, folded(under: true)))
            }
        }
        _ = folded(under: false)
        // Под последней — место под строку поиска внизу (P797).
        out.append(Entry(id: "tail", kind: .pad(max(Search.fieldHeight + 8,
                                                    height - CGFloat(future.count) * 60))))
        return out
    }

    /// Подходит ли день под «что искать» из меню поиска (P249).
    private func kept(_ day: Archive.Day) -> Bool {
        let kinds = day.attachments.map { Diary.kind(of: $0) }
        switch search.find {
        case .all:   return true
        case .photo: return kinds.contains(.photo)
        case .video: return kinds.contains(.video)
        case .audio: return kinds.contains(.audio)
        case .file:  return kinds.contains(.file)
        case .place:
            return day.place != nil || day.text.contains("geo:")
        }
    }

    private var ribbonList: some View {
        // Лента — всегда вокруг сегодня (P923; отменяет «вокруг открытого дня»
        // P791 и ряды под закрытую карточку P834, P840, P871, P875). С тех
        // пор как под не сегодняшним листом картотека не видна (P907), ленту
        // вокруг его дня никто не видел — она только пересобиралась туда и
        // обратно, и эта пересборка была пустым экраном при закрытии
        // карточки (`docs/71` §8). Теперь, пока открыт день с карточки, лента
        // стоит, где её оставили, и карточка садится в то же гнездо.
        let began = CACurrentMediaTime()
        let today = DayStore.today()
        let todayStamp = Vault.stamp(today)
        // Опись читается один раз за перерисовку (P771): старые сверху.
        let all = Array(found.reversed())
        var past = all.filter { $0.stamp < todayStamp }
        // На снимке CI «лента поиска» находки повторены, чтобы было что
        // листать (P717).
        if Search.deep { past = Array(repeating: past, count: 12).flatMap { $0 } }
        let future = ahead(all.filter { $0.stamp > todayStamp }, from: today)
        // Столбец времени у будущих карточек один на всю стопку, как в
        // «Списке» календаря (P756): по самому длинному виду времени.
        let times = future.flatMap { plan($0).compactMap(\.time) }
        // Время — как у телефона, тем же `Clock.show`, что в плане (P1006).
        let sample: String? = times.isEmpty ? nil : Clock.twelve ? "00:00 PM" : "00:00"
        let items = entries(past, future)
        // Запас над экраном (P861) — поле сверху, за верхним краем.
        let above = Afar.above(height)
        let ribbon = shell.ribbon
        // Какие карточки есть в ленте — чтобы не искать ту, которой нет (P923).
        ribbon.ids = Set(items.map(\.id))
        // Сколько стоила эта сборка — в заметки посадки (P929).
        ribbon.built = (CACurrentMediaTime() - began, items.count)
        // Замер большого архива (P975): во что обходится каждая пересборка
        // ленты — по следу видно, она ли держит экран.
        if Vault.isSelfDrive {
            Trace.note(String(format: "лента собрана: %.0f мс, %ld строк",
                              ribbon.built.time * 1000, items.count))
        }
        return ScrollViewReader { proxy in ScrollView {
            // Карточки — вид сверху: нижняя лежит поверх верхней и своим
            // корешком с датой закрывает её низ (P694, P695).
            LazyVStack(spacing: 0) {
                // Запас над экраном (P861): верхнее поле ленты — за верхним краем.
                Color.clear.frame(height: above)
                ForEach(items) { entry in
                    piece(entry, sample: sample)
                        // Где карточка закрытого дня на экране — в неё
                        // складывается лист (P883).
                        .onGeometryChange(for: CGRect.self) { proxy in
                            proxy.frame(in: .named(Ribbon.space))
                        } action: { frame in
                            // Где карточки на экране — чтобы, закрыв открытый с
                            // неё день, вернуть ленту туда же (P893).
                            ribbon.saw(entry.id, frame.offsetBy(dx: 0, dy: -above))
                        }
                        // Карточку разобрала ленивая стопка — её рамки больше
                        // нет: по ней видно, удался ли переход к карточке (P906).
                        .onDisappear { ribbon.saw(entry.id, nil) }
                        .padding(.top, entry.over ? -Search.overlap : 0)
                        .modifier(Distance(side: entry.depth, height: height))
                        .id(entry.id)
                }
            }
            .padding(.horizontal, 10)
            // Прокрутка без оттяжки (P445): лента и день едут вместе, а
            // оттяжка разлучила бы их.
            .background(NoBounce(box: ribbon.box))
            // Добавка к запасу ниже экрана (P859).
            .padding(.bottom, Afar.lift)
            // Место под клавиатуру (P174).
            .padding(.bottom, keyboard > 0 ? keyboard + 4 : 0)
        }
        .coordinateSpace(.named(Ribbon.space))
        .scrollDismissesKeyboard(.interactively)
        // Ниже экрана — запас (P791): лента там уже собрана, и карточка,
        // подтянутая наползанием из-за нижнего края, выходит плавно.
        // Выше экрана — тоже (P861, вместо таяния верхних карточек P850/P859,
        // автор по 260: «растворяются, не доходя до края; должны уходить за
        // край»): карточка прошлого нарисована с наползанием ниже своего
        // места, и ленивая стопка убирала её, пока она ещё была видна. Теперь
        // стопка держит её, пока она не ушла за верх; за верхним краем
        // экрана раздела лента обрезана.
        .frame(height: above + height + Afar.reserve(height), alignment: .top)
        .clipShape(TopCut(cut: above))
        .offset(y: -above)
        .onAppear {
            // Место дня — на верх экрана, а не на верх окна ленты: окно выше
            // экрана на запас (P861).
            ribbon.home = { proxy.scrollTo(Ribbon.slotID, anchor: Afar.screenTop(height)) }
            // Переход к карточке: верхом на `top` от верха экрана (P923).
            // Окно ленты больше экрана на запасы сверху и снизу (P791, P861).
            ribbon.jump = { id, top in
                let window: CGFloat = above + height + Afar.reserve(height)
                let row: CGFloat = Ribbon.cardHeight - Search.overlap
                let spot = UnitPoint(x: 0.5, y: window > row ? (above + top) / (window - row) : 0)
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { proxy.scrollTo(id, anchor: spot) }
            }
            DispatchQueue.main.async {
                // Ленивая стопка ставит дальнее со второго раза — это ждёт
                // сам покой ленты, по замеру места дня (P928; прежде —
                // второй раз через 0,3 с).
                if shell.deck.isOpen { settle() } else { ribbon.park() }
                // Снимок «лента поиска»: список пролистан, как у человека.
                if Search.deep {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        proxy.scrollTo("p20", anchor: Afar.screenTop(height))
                    }
                }
            }
        }
        // Опись перечитана, пока лента спрятана: место дня — снова под днём,
        // чтобы тяга из дня начиналась сразу.
        // Только что открытую ленту (снимок, запуск на картотеке) опись
        // догоняет позже — встаём в покой ещё раз.
        // Открыт день с карточки — лента стоит, где её оставили (P923): в
        // то же гнездо карточка и вернётся.
        .onChange(of: items.count) { _, _ in
            DispatchQueue.main.async {
                if !shell.deck.isLive { if store.isToday { ribbon.park() } } else if ribbon.fresh { settle() }
            }
        }
        // На листе снова сегодня, а картотека закрыта — место дня под день.
        .onChange(of: store.isToday) { _, today in
            guard today else { return }
            DispatchQueue.main.async {
                if !shell.deck.isLive { ribbon.park() }
            }
        }
        // Высота экрана известна не с первого кадра: до неё место дня
        // нулевое, и лента вставала не там (снимки CI к P777).
        .onChange(of: height) { _, _ in
            DispatchQueue.main.async {
                if !shell.deck.isLive { if store.isToday { ribbon.park() } } else if ribbon.fresh { settle() }
            }
        }
        // Ленту открыли не тягой (снимок, запуск на картотеке) — в покой.
        .onChange(of: shell.deck.isOpen) { _, open in
            guard open else { return }
            DispatchQueue.main.async { settle() }
        }
        // Набрали слово — к ближайшей находке: в прошлом она над днём, в
        // будущем под ним. Стёрли — лента снова в покое у дня.
        .onChange(of: query) { _, _ in
            DispatchQueue.main.async { settle() }
        }
        // День закрывают в карточку (P834, P875) — посадка по событиям (P923).
        .onChange(of: shell.deck.isLanding) { _, now in
            guard now, case .landing(let closed, let at, _) = shell.deck else {
                // Посадка кончена или прервана: её шаги больше не к месту.
                ribbon.landing.clear()
                ribbon.unseat()
                ribbon.flight.stop()
                ribbon.foldTo = nil
                ribbon.fold.clear()
                return
            }
            land(closed, at)
        }
        }
        .animation(.easeOut(duration: 0.25), value: keyboard)
    }

    /// Сколько летит схема из листа к гнезду (P895).
    static let flight: Double = 0.45

    /// Посадка закрытой карточки — по событиям (P923, `docs/71` §3; вместо
    /// восьми отложенных шагов P890–P913: 0,2 с; 0,09; 0,03 до 24 раз; 0,3;
    /// 0,25…). Лента под листом уже стоит — она собрана вокруг сегодня и с
    /// открытия карточки не двигалась, — поэтому проступает сразу, вместе с
    /// тем как лист превращается в схему: пустого экрана между ними нет
    /// (`docs/71` §8). Шаги идут друг за другом по делу, а не по часам:
    /// схема долетела — последний кадр её хода (`Glide`, P926); лента
    /// встала — замер карточки; карточка опустилась и надпись проступила —
    /// последний кадр этих движений. По времени остаётся один
    /// предохранитель: если что-то из этого не пришло, карточка считается
    /// севшей.
    private func land(_ closed: String, _ at: Deck.Side) {
        let ribbon = shell.ribbon
        let landing = ribbon.landing
        let run = landing.begin()
        // Сторона «Сегодня» от закрытого дня: прошлое — снизу, будущее — сверху.
        let side = at.rawValue
        var still = Transaction()
        still.disablesAnimations = true
        let quiet = still
        let spot = ribbon.nest(for: closed, side: side)
        let known = ribbon.ids.contains(closed)
        // Рамка карточки там, куда она встанет; пока её не мерили — на глаз.
        let about = ribbon.frames[closed].map {
            CGRect(x: $0.minX, y: spot.top, width: $0.width, height: $0.height)
        } ?? CGRect(x: 10, y: spot.top, width: UIScreen.main.bounds.width - 20, height: Ribbon.cardHeight)
        DeckTrail.mark(String(format: "закрыт %@, гнездо на %.0f — %@", closed, spot.top,
                              spot.inPlace ? "стоит на месте" : known ? "навести" : "карточки нет"))
        // Гнездо карточки пустует, пока она летит (P895).
        withTransaction(quiet) {
            landing.id = closed
            landing.stage = .away
        }

        var arrived = false
        var stood = false
        /// Карточки в ленте не нашлось — схеме садиться некуда.
        var lost = false
        /// Откуда схема летит — лист, каким его отпустили, — и куда.
        let lead = FollowRibbon.shown(ribbon.y, height: height, stick: ribbon.stick)
        let under: CGFloat = side < 0 ? FollowRibbon.futureTop : 0
        var from = CGRect(x: 0, y: lead + under, width: UIScreen.main.bounds.width, height: height - under)
        // Лист стоит, где его отпустили, и сворачивается вверх (P1015).
        let fold = ribbon.fold
        withTransaction(quiet) {
            fold.under = under
            fold.at = lead
            fold.visible = height - under
        }
        var target = CGRect.zero
        // Замер замирания в миг закрытия (P929): когда показан первый кадр
        // хода схемы, какой кадр был самым долгим и сколько стоила последняя
        // сборка списка ленты — в след, одной заметкой.
        let began = CACurrentMediaTime()
        var firstFrame: Double?
        var lastFrame = 0.0
        var worstFrame = 0.0
        var told = false

        func alive() -> Bool { landing.run == run && shell.deck.isLanding }

        /// Над гнездом: схема шире карточки на поля по бокам. Замер рамки
        /// карточки — уже там, где она видна, со сближением (P927): замер
        /// идёт сквозь сдвиг `Distance`. Прежде сближение прибавлялось к
        /// нему ещё раз (P909), и схема вставала мимо — у будущего выше
        /// гнезда, у прошлого ниже; карточка появлялась в стороне от неё
        /// (след автора к 292: карточка на 430, схема летела к 340 вместо 394).
        func hover(over frame: CGRect) -> CGRect {
            frame.insetBy(dx: Search.cardInset, dy: 0).offsetBy(dx: 0, dy: -Landing.lift)
        }

        /// Картотека под карточкой проступает — если ещё не проступила:
        /// посадка доходит до ступени «встаёт» (P928; прежде — отдельный
        /// флажок ленты). Не в безходовой перемене: проступает плавно.
        func unveil() {
            if case .landing(_, _, .flying) = shell.deck { shell.go(.aimed) }
            if case .landing(_, _, .waiting) = shell.deck { shell.go(.stood) }
        }

        /// `cut` — досадили разом: предохранитель или человек не стал ждать.
        func finish(cut: Bool = false) {
            guard alive() else { return }
            ribbon.unseat()
            ribbon.flight.stop()
            store.save()
            // На листе снова сегодня — он у своего края, корешком или полоской.
            ribbon.stick = true
            let settled: Bool
            if case .landing(_, _, .settling) = shell.deck { settled = !cut } else { settled = false }
            withTransaction(quiet) {
                fold.clear()
                store.go(to: DayStore.today())
                shell.go(settled ? .landed : .cutShort)
            }
            // Села — опись больше не двигает ленту (P898).
            ribbon.settledHere()
            ribbon.refresh()
            if let frame = ribbon.frames[closed] {
                Trace.note(String(format: "лента: %@ встал на %.0f", closed, frame.minY))
            }
        }

        /// Схема долетела, и лента стоит: над гнездом схема становится самой
        /// карточкой в своём ряду, та опускается под следующую, и на ней
        /// проступает надпись (P895). Ступени идут по кадрам экрана (P926).
        func sit() {
            guard alive(), arrived, stood, landing.stage == .away else { return }
            if lost {
                // Карточки нет — схема тает у края, а не пропадает разом.
                withAnimation(.easeOut(duration: 0.25)) {
                    landing.stage = .lost
                    fold.fading = true
                }
                ribbon.flight.run(0.25, then: { finish() })
                return
            }
            withTransaction(quiet) { landing.stage = .hover }
            DispatchQueue.main.async {
                guard alive() else { return }
                // Полоса тает над карточкой (P1018): прежде ступень шла без
                // хода, и полоса пропадала за один кадр.
                withAnimation(.easeOut(duration: 0.22)) { fold.fading = true }
                withAnimation(.easeInOut(duration: 0.3)) { landing.stage = .down }
                ribbon.flight.run(0.3, then: {
                    guard alive() else { return }
                    withAnimation(.easeOut(duration: 0.25)) { landing.stage = .done }
                    ribbon.flight.run(0.25, then: { finish() })
                })
            }
        }

        /// Схема летит от того места, где она сейчас, к гнезду. Куда — может
        /// уточниться в пути (`target`): ход тот же, без рывка.
        func fly(in time: Double) {
            from = ribbon.foldTo ?? from
            arrived = false
            ribbon.flight.run(time, step: { p in
                guard alive() else { return }
                // Полпути пройдено, и гнездо точно известно (лента встала) —
                // карточка проступает над гнездом, полоса тает до посадки
                // (P1023, видео автора к 335: долетев, полоса с серединой
                // прокрученного листа разом сменялась другой карточкой).
                if p >= 0.5, stood, !lost, landing.bare, !landing.nearing,
                   landing.stage == .away {
                    let rest = time * 0.5
                    withAnimation(.easeIn(duration: rest)) {
                        landing.nearing = true
                        fold.fading = true
                    }
                }
                let now = CACurrentMediaTime()
                if firstFrame == nil { firstFrame = now - began } else { worstFrame = max(worstFrame, now - lastFrame) }
                lastFrame = now
                ribbon.foldTo = CGRect(x: from.minX + (target.minX - from.minX) * p,
                                       y: from.minY + (target.minY - from.minY) * p,
                                       width: from.width + (target.width - from.width) * p,
                                       height: from.height + (target.height - from.height) * p)
            }, then: {
                guard alive() else { return }
                if !told {
                    told = true
                    DeckTrail.mark(String(format: "схема долетела: первый кадр через %.2f с, самый долгий кадр %.2f с; "
                                          + "лента перед этим собиралась %.0f мс на %ld карточек",
                                          firstFrame ?? -1, worstFrame,
                                          ribbon.built.time * 1000, ribbon.built.cards))
                }
                arrived = true
                sit()
            })
        }

        /// Лист шторкой сворачивается вверх до полосы высотой с карточку
        /// (P1015); свернулся — снимок полосы летит в гнездо, лист уходит.
        func shutUp() {
            let width = UIScreen.main.bounds.width
            let card = about.height - Search.overlap
            let band = max(Search.tabHeight + 40, card * width / max(1, about.width))
            let full = height - under
            // Будущий лист, утянутый пальцем вверх, заходит верхом под
            // полоску «Сегодня» (P1018, видео автора к 333: в гнездо летела
            // вторая полоска «Сегодня» — снимок брал её). Полоса — от низа
            // полоски, а лист сворачивается до низа полосы.
            let shown = side < 0 ? max(lead + under, FollowRibbon.peekTop) : lead + under
            let keep = shown - (lead + under) + band
            fold.glide.run(FoldUp.shut, step: { p in
                guard alive() else { return }
                fold.visible = full + (keep - full) * p
            }, then: {
                guard alive() else { return }
                let rect = CGRect(x: 0, y: shown, width: width, height: band)
                let area = ribbon.unfold.area
                let picture = FoldUp.picture(rect.offsetBy(dx: area.minX, dy: area.minY))
                    .map { FoldUp.shaped($0, top: lead + under - shown) }
                withTransaction(quiet) {
                    // Полоса летит — карточка под ней садится без схемы
                    // (P1018): её сменяет полоса, а не бледный контур.
                    landing.bare = picture != nil
                    fold.band = picture
                    // Снимка нет — летит схема с места полосы.
                    if picture == nil { fold.visible = nil }
                    fold.gone = true
                    ribbon.foldTo = rect
                }
                from = rect
                fly(in: FoldUp.flight)
            })
        }

        /// Лента встала: картотека проступает на своём месте, схема — к
        /// точному гнезду, если оно не там, куда она уже летит.
        func stand(_ frame: CGRect?) {
            guard alive(), !stood else { return }
            stood = true
            lost = frame == nil
            unveil()
            let place = hover(over: frame ?? about)
            DeckTrail.mark(String(format: "лента встала, карточка на %.0f, схема к %.0f (было %.0f)",
                                  frame?.minY ?? -1, place.minY, target.minY))
            let moved = abs(place.minY - target.minY) > 0.5 || abs(place.height - target.height) > 0.5
            target = place
            // Уже долетела до прежнего места — короткий доход до точного.
            if moved && arrived { fly(in: 0.15) } else { sit() }
        }

        // Единственный шаг по времени — предохранитель.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            guard alive() else { return }
            DeckTrail.mark("посадка не дождалась своих событий — предохранитель")
            unveil()
            finish(cut: true)
        }
        landing.hurry = {
            guard alive() else { return }
            unveil()
            finish(cut: true)
        }
        // Следующим тактом: схема уже нарисована во весь лист — оттуда и летит,
        // сразу, с толчком в руку (P913).
        DispatchQueue.main.async {
            guard alive() else { return }
            target = hover(over: about)
            shutUp()
            if spot.inPlace {
                stand(ribbon.frames[closed])
            } else if known {
                ribbon.seat(closed, top: spot.top) { frame in
                    guard alive() else { return }
                    if frame != nil { ribbon.keepToday(side) }
                    stand(ribbon.frames[closed] ?? frame)
                }
            } else {
                // Карточки у этого дня нет (пустой день из календаря, или
                // ищут слово, которого в нём нет): картотека — в покой у
                // «Сегодня» с его стороны; покой — как у сегодняшнего листа.
                ribbon.stick = true
                ribbon.settle(side) { stand(nil) }
            }
        }
    }

    /// Лента в покое: вчера над нижней строкой или завтра под строкой поиска.
    private func settle() {
        guard case .file(let side) = shell.deck, !shell.ribbon.busy else { return }
        shell.ribbon.opened()
        shell.ribbon.settle(side.rawValue)
    }

    @ViewBuilder private func piece(_ entry: Entry, sample: String?) -> some View {
        switch entry.kind {
        case .pad(let h):
            Color.clear.frame(height: h)
        case .note:
            message(T("Ничего не нашлось.", "Nothing found."),
                    T("По запросу «\(query)» \(whereNot)записей нет.",
                      "No entries \(whereNot)match “\(query)”."))
                .frame(height: 160)
        case .hint(let side):
            message(side == .past ? T("В прошлом не нашлось.", "Nothing in the past.")
                                  : T("В будущих днях не нашлось.", "Nothing in the days ahead."),
                    side == .past ? T("Есть находки в будущих днях.", "There are matches in the days ahead.")
                                  : T("Есть находки в прошлом.", "There are matches in the past."))
                .frame(height: 120)
        case .past(let day):
            // Карточки уже дня (P780): по бокам виден стол, день — во всю
            // ширину, и его не спутать с карточкой.
            SearchCard(stamp: Search.stamp(day.date), weekday: Search.weekday(day.date),
                       past: Ru.isPast(day.date), fresh: day.date > DayStore.today(),
                       seed: PageTexture.seed(day.date) &+ (Search.deep ? (Int(entry.id.dropFirst()) ?? 0) * 7 : 0)) {
                row(day)
            }
            .modifier(Landed(landing: shell.ribbon.landing, id: entry.id, aged: Ru.isPast(day.date)))
            .modifier(UnfoldHole(unfold: shell.ribbon.unfold, id: entry.id))
            // Касание по всей карточке, а не только по буквам (P866).
            .contentShape(FolderShape(tabHeight: Search.tabHeight, tabShare: Search.tabShare))
            .onTapGesture { openPast(day) }
            .padding(.horizontal, Search.cardInset)
        case .slot:
            daySlot
        case .future(let day, let above):
            VStack(spacing: -Search.overlap) {
                // Пустые дни перед ним — стопкой над его корешком (P990,
                // вместо стопки под карточкой дня перед ними P983).
                if !above.isEmpty { emptyTabs(above) }
                SearchCard(stamp: Search.stamp(day.date), weekday: Search.weekday(day.date),
                           weekend: Calendar.current.isDateInWeekend(day.date), past: false, fresh: true,
                           seed: PageTexture.seed(day.date), tight: true) {
                    futureRow(day, sample: sample)
                }
                .modifier(Landed(landing: shell.ribbon.landing, id: entry.id))
                .modifier(UnfoldHole(unfold: shell.ribbon.unfold, id: entry.id))
                // Касание по всей карточке, а не только по буквам (P866, автор:
                // «будущие открываются, только когда нажимаешь на текст»).
                .contentShape(FolderShape(tabHeight: Search.tabHeight, tabShare: Search.tabShare))
                .onTapGesture { openCard(day.date, tab: .plan) }
            }
            .padding(.horizontal, Search.cardInset)
        case .empty(let dates):
            emptyTabs(dates, over: false)
                .padding(.horizontal, Search.cardInset)
        case .blank(let date):
            // Пустой день ближайшего месяца (P990) или раскрытой стопки
            // (P988): та же будущая карточка, без дел. Короткое нажатие
            // открывает день, долгое складывает раскрытую стопку обратно.
            SearchCard(stamp: Search.stamp(date), weekday: Search.weekday(date),
                       weekend: Calendar.current.isDateInWeekend(date), past: false, fresh: true,
                       seed: PageTexture.seed(date), tight: true) {
                Color.clear
                    .frame(height: Search.futureBody)
                    .frame(maxWidth: .infinity)
            }
            .modifier(Landed(landing: shell.ribbon.landing, id: entry.id))
            .modifier(UnfoldHole(unfold: shell.ribbon.unfold, id: entry.id))
            .contentShape(FolderShape(tabHeight: Search.tabHeight, tabShare: Search.tabShare))
            .onTapGesture { openCard(date, tab: .plan) }
            .onLongPressGesture(minimumDuration: Search.holdTime) { unfold(nil) }
            .accessibilityElement()
            .accessibilityLabel(Search.stamp(date) + " " + Search.weekday(date))
            .accessibilityAddTraits(.isButton)
            .padding(.horizontal, Search.cardInset)
            .transition(.opacity)
        }
    }

    /// Раскрыть стопку пустых дней или сложить раскрытую (P988) — плавно:
    /// карточки ниже отъезжают, а не прыгают (P893).
    private func unfold(_ key: String?) {
        guard unfolded != key else { return }
        Feel.light()
        withAnimation(.easeInOut(duration: 0.3)) { unfolded = key }
    }

    /// Мягкая подсказка, как раскрыть стопку (P988, тон P482).
    private func hintStack() {
        shell.say(T("Подержите палец на стопке — пустые дни раскроются",
                    "Touch and hold the stack to unfold the empty days"), for: 2.5)
    }

    /// Стопка закрытых карточек пустых дней (P983, P988). Долгое нажатие
    /// раскрывает её в пустые карточки (прежняя раскрытая складывается);
    /// короткое — подсказывает, как раскрыть (прежде открывало день под
    /// пальцем — в линиях через 3 точки не попасть, отменено P988).
    private func emptyTabs(_ dates: [Date], over: Bool = true) -> some View {
        let key = Vault.stamp(dates[0])
        return EmptyTabs(count: dates.count, over: over)
            .contentShape(Rectangle())
            .onTapGesture { hintStack() }
            .onLongPressGesture(minimumDuration: Search.holdTime) { unfold(key) }
            .onAppear {
                // Подсказка приходит сама время от времени — не чаще раза в
                // сутки и раза за запуск (P989); в снимках и проверках — нет.
                let now = Date().timeIntervalSince1970
                guard now - stackHintAt > 20 * 3600, !Self.hintedThisRun,
                      shell.screen == .search, !Vault.isPreview, !Vault.isSelfDrive else { return }
                Self.hintedThisRun = true
                stackHintAt = now
                hintStack()
            }
            .accessibilityElement()
            .accessibilityLabel(Search.stamp(dates[0]) + " – " + Search.stamp(dates[dates.count - 1]))
            .accessibilityHint(T("Подержите палец на стопке — пустые дни раскроются",
                                 "Touch and hold the stack to unfold the empty days"))
            .accessibilityAction(named: T("Раскрыть", "Unfold")) { unfold(key) }
            .transition(.opacity)
    }

    /// Место сегодняшнего дня в ленте (P777): пустое, высотой с экран; живой
    /// день лежит над ним и едет вместе с ним. Касание — вернуться в день.
    private var daySlot: some View {
        let ribbon = shell.ribbon
        return Color.clear
            .frame(height: height)
            .contentShape(Rectangle())
            .onTapGesture {
                guard shell.screen == .search else { return }
                search.typing = false
                shell.screen = .today
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(Ribbon.space)).minY
            } action: { [height] y in
                // От верха экрана, а не окна ленты (P861).
                ribbon.measured(y - Afar.above(height))
            }
            .onAppear { ribbon.appeared() }
            .onDisappear { ribbon.lost() }
            .accessibilityLabel(T("Вернуться в день", "Back to the day"))
            .accessibilityAddTraits(.isButton)
    }

    /// Дела будущего дня вместе с событиями Календаря iPhone — как в
    /// «Списке» календаря (P376).
    private func plan(_ day: Archive.Day) -> [PlanRow] {
        let marks = archive.day(day.stamp)?.marks ?? []
        let events = DayEvents.shown(DayEvents.cachedItems(for: day.date), marks: marks).map(\.row)
        return events + archive.tasks(day.stamp)
    }

    /// Карточка будущего дня (P771): та же карточка картотеки, но ниже —
    /// четыре строки, чтобы на экран входила неделя. Строки — как в «Списке»
    /// календаря: время своим столбцом, дело одной строкой. Больше четырёх
    /// дел — четыре и «ещё N» пятой строкой у правого края (P773): слева
    /// пятую строку закрывает корешок следующей карточки, справа место есть.
    private func futureRow(_ day: Archive.Day, sample: String?) -> some View {
        let tasks = plan(day)
        let shown = Array(tasks.prefix(4))
        return Button {
            openCard(day.date, tab: .plan)
        } label: {
            VStack(alignment: .leading, spacing: Search.futureGap) {
                ForEach(shown) { task in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let sample {
                            ZStack(alignment: .leading) {
                                Text(sample).hidden()
                                Text(task.time.map(Clock.show) ?? "")
                            }
                            .font(Look.sans(12).monospacedDigit())
                            .lineLimit(1)
                            .fixedSize()
                        }
                        Text(task.text)
                            .font(Look.sans(12))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .foregroundStyle(Look.ink)
                    .opacity(task.done ? 0.45 : 1)
                }
            }
            .frame(height: Search.futureBody, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Пятая строка — под четырьмя, в полосе, которую справа от своего
            // корешка оставляет открытой следующая карточка.
            .overlay(alignment: .bottomTrailing) {
                if tasks.count > 4 {
                    Text(T("ещё \(tasks.count - 4)", "\(tasks.count - 4) more"))
                        .font(Look.sans(11))
                        .foregroundStyle(Look.inkFaint)
                        .offset(y: Search.tabHeight - 2)
                }
            }
            .padding(.horizontal, 18)
        }
        .buttonStyle(.plain)
    }

    /// Карточка открывает свой день сразу, без хода ленты (P796). Лента
    /// стоит вокруг открытого дня (P791) и с новым днём перестраивается —
    /// прежде она, доезжая до места дня, перестраивалась на ходу, и день
    /// мелькал вверху, пропадал и всплывал снизу (запись автора к 244).
    /// Теперь лента закрывается в том же такте, что и меняется день.
    private func openCard(_ date: Date, tab: DayTab) {
        let ribbon = shell.ribbon
        // Соседняя карточка ещё садится — досадить её разом.
        ribbon.landing.hurry?()
        // Откуда открыли — туда карточка и вернётся, когда день закроют
        // (P893). Лента при этом стоит, где была (P923): прежде она
        // пересобиралась вокруг открытого дня и уходила к его месту.
        let id = Vault.stamp(date)
        let card = shell.screen == .search ? ribbon.frames[id] : nil
        let from = ribbon.frames[id].map { (id: id, top: $0.minY) }
        search.typing = false
        Feel.thud()
        // Карточка выезжает к верху и разворачивается вниз (P1011): день
        // открывается, когда она доехала, — его страница строится в миг
        // удара о край, а не посреди хода (P998).
        guard let card else {
            open(date, tab: tab, from: from, id: id)
            return
        }
        let future = date > DayStore.today()
        // У будущей карточки в рамке может быть и стопка пустых дней над
        // ней (P990): едет только сама карточка — нижняя часть рамки.
        let tall = Search.tabHeight + 4 + Search.futureBody + Search.overlap + 2
        let own = future && card.height > tall + 6
            ? CGRect(x: card.minX, y: card.maxY - tall, width: card.width, height: tall) : card
        ribbon.unfold.start(from: own, id: id, top: future ? FollowRibbon.futureTop : 0) {
            open(date, tab: tab, from: from, id: id)
        }
    }

    /// Открыть день карточки в одном такте: день сменился, лента закрылась
    /// (P796). `false` — открыть нельзя: картотеку уже сменили.
    @discardableResult
    private func open(_ date: Date, tab: DayTab, from: (id: String, top: CGFloat)?, id: String) -> Bool {
        let ribbon = shell.ribbon
        var still = Transaction()
        still.disablesAnimations = true
        let opened: Bool = withTransaction(still) {
            guard shell.go(.openCard) else { return false }
            shell.instant = true
            store.go(to: date)
            shell.tab = tab
            shell.screen = .today
            return true
        }
        guard opened else { return false }
        ribbon.reset()
        ribbon.openedFrom = from
        Trace.note(String(format: "лента: открыт %@ с места %.0f", id, from?.top ?? -1))
        archive.reloadSoon()
        return true
    }

    /// Искали в плане — туда и открываем: там нашлось искомое.
    private func openPast(_ day: Archive.Day) {
        openCard(day.date, tab: search.scope == .plan || day.date > DayStore.today()
                 || (day.text.isEmpty && !day.tasks.isEmpty) ? .plan : .diary)
    }

    private func row(_ day: Archive.Day) -> some View {
        Button {
            openPast(day)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: Search.lineGap) {
                    // Дата — на корешке карточки (P695): год, месяц, число —
                    // в этом порядке, при поиске по архиву сначала выбирают
                    // время, а не день недели (P282).
                    if !day.title.isEmpty {
                        Text(Geo.stripped(day.title))
                            .font(Look.serif(15, weight: .semibold))
                            .foregroundStyle(Look.ink)
                            .lineLimit(1)
                    }
                    if day.title.isEmpty && day.preview.isEmpty {
                        // День без записи — его дела.
                        Text(day.tasks.prefix(4).map { $0.text }.joined(separator: "\n"))
                            .font(Look.serif(13.5))
                            .foregroundStyle(Look.inkFaint)
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                    }
                    if !day.text.isEmpty {
                        Text(day.preview)
                            .font(Look.serif(13.5))
                            .foregroundStyle(Look.inkSoft)
                            .lineLimit(day.title.isEmpty ? 5 : 4)
                            .multilineTextAlignment(.leading)
                    }
                }
                // Ровно пять строк: низ пятой строки — на одной линии с низом
                // снимка (P696).
                .frame(height: Search.body, alignment: .top)
                Spacer(minLength: 0)
                if let cover = day.cover { preview(cover, of: day) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
        }
        .buttonStyle(.plain)
    }

    /// Превью справа от находки: снимок, кадр видео, голос или документ
    /// (P215).
    @ViewBuilder private func preview(_ link: String, of day: Archive.Day) -> some View {
        let url = vault.mediaURL(link, for: day.date)
        Group {
            switch Diary.kind(of: link) {
            case .photo: PhotoThumb(url: url)
            case .video: PhotoThumb(url: url, video: true)
            case .audio: FileTile(icon: "waveform", label: T("голос", "voice"))
            case .file:  FileTile(icon: "doc.text",
                                  label: (link as NSString).pathExtension.lowercased())
            }
        }
        // Превью — той же высоты, что блок из пяти строк (P282, P696): низы
        // совпадают.
        .frame(width: Search.body, height: Search.body)
    }

    private func message(_ head: String, _ tail: String) -> some View {
        VStack(spacing: 6) {
            Spacer()
            Text(head).font(Look.sans(15)).foregroundStyle(Look.inkSoft)
            Text(tail).font(Look.sans(13)).foregroundStyle(Look.inkFaint)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity)
    }
}

enum Search {
    /// Высота корешка карточки (P695).
    static let tabHeight: CGFloat = 22
    /// Доля ширины карточки под корешок (P859; прежде треть): дата крупнее —
    /// «2026 сентябрь 22 ПН» шрифтом 13 входит целиком, а в трети ужималась
    /// почти до 9.
    static let tabShare: CGFloat = 0.45
    /// На сколько карточка заходит на предыдущую: корешок и ещё немного
    /// листа, чтобы нижний край предыдущей скрылся под ней (P696).
    static let overlap: CGFloat = tabHeight + 10
    /// Карточки ленты уже дня (P780): ещё столько с каждого бока.
    static let cardInset: CGFloat = 14

    static let lineGap: CGFloat = 3

    /// Сколько дней подряд идёт картотека будущего в любом случае (P771);
    /// пустые дни в нём — открытыми карточками (P990); дальше — до
    /// последнего дня с делами, пустые стопками (P983).
    static let ahead = 30
    /// Дальше всего вперёд лента идёт подряд — год (P983).
    static let horizon = 366
    /// Сколько видно от пустой карточки (P990, автор по 314: «торчит не на
    /// две ширины линии, а на три»; вместо 3 точек P983): линия края и три
    /// раза по столько бумаги.
    static let emptyPitch: CGFloat = 4
    /// Сколько держать палец на стопке пустых дней, чтобы она раскрылась (P988).
    static let holdTime: Double = 0.35

    /// Высота четырёх строк будущей карточки (P771).
    static var futureBody: CGFloat {
        ceil(UIFont.systemFont(ofSize: 12).lineHeight) * 4 + futureGap * 3
    }
    /// Промежуток между строками будущей карточки (P774).
    static let futureGap: CGFloat = 1

    /// Высота строки поиска над списком (с отступами): под неё уходит
    /// список (P716, P719).
    static let fieldHeight: CGFloat = 56
    /// Снимок CI «лента поиска» (P717): находок много, список пролистан —
    /// как у человека на телефоне.
    static let deep = Vault.isPreview
        && ProcessInfo.processInfo.environment["CHRONOTHECA_SCREEN"] == "searchdeep"

    /// Высота блока из пяти строк находки: строка заголовка и четыре строки
    /// текста; по ней же — сторона снимка (P696).
    static var body: CGFloat {
        let title = ceil(Prefs.serifUIFont(15).lineHeight)
        let line = ceil(Prefs.serifUIFont(13.5).lineHeight)
        // Между заголовком и текстом один промежуток; четыре строки текста идут подряд.
        return title + lineGap + line * 4
    }

    /// «2026 сентябрь 22» — от крупного к мелкому, как ищут в архиве.
    /// День недели двумя буквами (P844): ПН, ВТ, СР… — на языке приложения
    /// (у английского Mo, Tu…). Названия берутся у календаря один раз.
    static func weekday(_ date: Date) -> String {
        if weekdayCode != Lang.code {
            var cal = Calendar(identifier: .gregorian)
            cal.locale = Lang.locale
            weekdayNames = cal.shortStandaloneWeekdaySymbols.map {
                String($0.replacingOccurrences(of: ".", with: "").prefix(2)).uppercased()
            }
            weekdayCode = Lang.code
        }
        let i = Calendar.current.component(.weekday, from: date) - 1
        return weekdayNames.indices.contains(i) ? weekdayNames[i] : ""
    }
    private static var weekdayCode = ""
    private static var weekdayNames: [String] = []

    static func stamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month, .year], from: date)
        // Промежутки — в один пробел, вдвое уже прежних (P282).
        return "\(c.year ?? 2026) \(Ru.monthNames[(c.month ?? 1) - 1]) \(c.day ?? 1)"
    }

}


/// Карточка находки — лист картотеки с корешком (P695): на левой трети
/// сверху выступает корешок с датой; корешок и лист — один контур без черты
/// между ними (P697). Карточка из фактурной старой бумаги (цвет прошлого и
/// рельеф, P696) с заранее нарисованной тенью вправо-вниз (лампа слева сверху,
/// P670, P675). Снизу пустое место: следующая карточка заходит на него и
/// скрывает нижний край этой.
private struct SearchCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let stamp: String
    /// День недели двумя буквами после даты (P844).
    var weekday = ""
    /// Выходной будущего — день недели красным (P844).
    var weekend = false
    /// Прошедший день — края затёрты, как у его страницы (P722).
    var past = true
    /// Будущий день — новая карточка, без износа (P859).
    var fresh = false
    /// Номер дня — у каждой карточки свой износ (P723).
    var seed = 0
    /// Будущая карточка — плотнее (P774): меньше воздуха над и под строками,
    /// чтобы на экран входила неделя.
    var tight = false
    @ViewBuilder let content: () -> Content

    /// Дата и день недели на корешке (P844); выходной будущего — красным.
    private var tabText: Text {
        let date = Text(stamp).foregroundColor(Look.dateBlue)
        guard !weekday.isEmpty else { return date }
        let ink: Color = weekend ? Ru.weekendColour : Look.dateBlue
        return date + Text(" " + weekday).foregroundColor(ink)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Дата крупнее (P859, автор по 259; прежде 11,5 в трети ширины —
            // ужималась почти до 9): корешок шире, шрифт 13.
            GeometryReader { tab in
                tabText
                    .font(Look.mono(13, weight: .medium))
                    .tracking(0.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .padding(.horizontal, 7)
                    .frame(width: tab.size.width * Search.tabShare, height: tab.size.height,
                           alignment: .leading)
            }
            .frame(height: Search.tabHeight)
            content()
                .padding(.top, tight ? 4 : 8)
                // Пустое место под карточкой — под следующую (P696).
                .padding(.bottom, Search.overlap + (tight ? 2 : 6))
                .frame(maxWidth: .infinity)
        }
        .background {
            ZStack {
                // Тень — только у листа, не у корешка.
                PaintedShadow(radius: 5, corner: 12, x: 2, y: 3,
                              opacity: scheme == .dark ? 0.5 : 0.3)
                    .padding(.top, Search.tabHeight)
                // Бумага карточки, затёртые края и рваный край — одним листом
                // из пачки заготовок (P732, как у клеток месяца: прежде края
                // и маска были двумя отдельными листами, и края не доходили).
                CardPaper(seed: seed, past: past, fresh: fresh)
            }
        }
    }
}

/// Пустые будущие дни подряд (P983, P988): стопка закрытых карточек. Каждая
/// — контур настоящей карточки с корешком (автор по 313: «должны полностью
/// повторять очертания карточки, за которой лежат, с корешками»; вместо
/// полос), следующая лежит на предыдущей на `Search.emptyPitch` ниже: видны
/// верхние края корешков и плечи лесенкой. Низ последней уходит под
/// следующую карточку, как у полной (`Search.overlap`). Десять пустых дней —
/// десять карточек: на глаз видно, сколько дней между делами. Одним
/// рисунком, без строк ленты на каждую (замирание P983).
private struct EmptyTabs: View {
    let count: Int
    /// Под стопкой лежит карточка (P992): ближняя закрытая выглядывает из-за
    /// неё на тот же шаг, что и остальные. Прежде карточка вставала на
    /// корешок ниже, и ближняя закрытая торчала на целый корешок (автор по
    /// 316: «все карточки должны выглядывать одинаково»). Без карточки под
    /// ней — последняя рисуется целиком.
    var over = true
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            let shape = FolderShape(tabHeight: Search.tabHeight, tabShare: Search.tabShare)
            let tall = Search.tabHeight + Search.overlap
            let paper = Image(uiImage: PageTexture.paper)
            let edge = Scheme.current.kraftEdge.opacity(0.5)
            for i in 0..<count {
                let rect = CGRect(x: 0, y: CGFloat(i) * Search.emptyPitch, width: size.width, height: tall)
                let path = shape.path(in: rect)
                context.fill(path, with: .color(Scheme.current.past))
                var grain = context
                grain.opacity = scheme == .dark ? 0.2 : 0.3
                grain.fill(path, with: .tiledImage(paper))
                context.stroke(path, with: .color(edge), lineWidth: 0.8)
            }
        }
        .frame(height: over ? CGFloat(count) * Search.emptyPitch + Search.overlap
                            : CGFloat(max(0, count - 1)) * Search.emptyPitch + Search.tabHeight + Search.overlap)
        .frame(maxWidth: .infinity)
    }
}

/// Лист карточки поиска (P732): старая бумага, затёртые края и рваный край —
/// один лист из пачки заготовок; пока его нет — ровная бумага. Сегодняшний
/// день слегка тронут (P728), без «Старой бумаги» (P730) — ровная бумага.
/// Будущий день — новая карточка, без износа (P859, автор по 259: «состарены
/// должны быть в прошлом»). Износ идёт по всему контуру одним способом —
/// корешок, вырез, плечо и бока (P859, вместо отдельного затёртого выреза
/// `EdgeWear` P854 на картинке, затёртой только по прямоугольнику).
private struct CardPaper: View {
    let seed: Int
    let past: Bool
    var fresh = false
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Prefs.plainPast) private var plainPast = false
    @State private var art: PageTexture.AgedArt?

    private var folder: FolderShape { FolderShape(tabHeight: Search.tabHeight, tabShare: Search.tabShare) }

    var body: some View {
        GeometryReader { geo in
            let order = PageTexture.agedOrder(size: geo.size, band: 12, seed: seed, openBottom: true,
                                              light: !past, tab: Search.tabHeight, share: Search.tabShare)
            let ready = plainPast || fresh ? nil : (art ?? PageTexture.agedReady(order))
            ZStack {
                paper.clipShape(folder)
                if let ready {
                    Image(uiImage: ready.frame)
                        .resizable()
                        .opacity(scheme == .dark ? 0.35 : 1)
                        .clipShape(folder)
                } else {
                    // Тонкая линия края — только у ровной бумаги (P854): у
                    // затёртой край виден и так, а линия шла вторым краем
                    // над затёртым.
                    folder.stroke(Scheme.current.kraftEdge.opacity(0.5), lineWidth: 0.8)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .mask {
                if let ready { Image(uiImage: ready.cut).resizable() } else { Rectangle() }
            }
            .task(id: order) {
                guard !plainPast, !fresh else { return }
                art = await PageTexture.aged(order)
            }
        }
        .allowsHitTesting(false)
    }

    /// Старая бумага: цвет прошлого и рельеф плиткой — непрозрачная, иначе
    /// корешок соседа просвечивал бы.
    private var paper: some View {
        ZStack {
            Scheme.current.past
            Image(uiImage: PageTexture.paper)
                .resizable(resizingMode: .tile)
                .opacity(scheme == .dark ? 0.2 : 0.3)
        }
    }
}

/// Затёртый край по самому контуру (P854): охра, к краю гуще, и неровная
/// тёмная кромка. Повторяет форму как есть — дугу выреза корешка, плечо,
/// скруглённые углы, — где картинки края, нарисованные прямоугольником, не
/// повторяли. Видна только внутренняя половина — снаружи листа ничего.
struct EdgeWear<S: Shape>: View {
    let shape: S
    var depth: CGFloat = 10

    var body: some View {
        ZStack {
            shape.stroke(PageTexture.wearAmber.opacity(0.5), lineWidth: depth * 2)
                .blur(radius: depth * 0.45)
            shape.stroke(PageTexture.wearAmber.opacity(0.45), lineWidth: depth * 0.8)
                .blur(radius: depth * 0.2)
            shape.stroke(PageTexture.wearBurnt.opacity(0.7),
                         style: StrokeStyle(lineWidth: 3.5, lineCap: .round, dash: [9, 2, 4, 3, 13, 2, 6, 4]))
                .blur(radius: 0.7)
        }
        .clipShape(shape)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Где виден затёртый край выреза корешка (P854).
enum WearNotch {
    /// Где виден затёртый вырез корешка: бок корешка, дуга, плечо; к правому
    /// краю тает — там свой затёртый край.
    static func region(width: CGFloat, tab: CGFloat, tabHeight: CGFloat, depth: CGFloat) -> some View {
        let from = max(0, tab - depth * 2.5)
        return LinearGradient(stops: [.init(color: .black, location: 0),
                                      .init(color: .black, location: 0.85),
                                      .init(color: .clear, location: 1)],
                              startPoint: .leading, endPoint: .trailing)
            .frame(width: max(0, width - from), height: tabHeight + depth * 2.5)
            .offset(x: from)
    }
}

/// Контур карточки с корешком на левой трети: корешок и лист — одна фигура.
/// Схема карточки — пустой контур цвета бумаги (P886): летит из листа к
/// гнезду и, сев, уступает место надписи карточки (P895).
/// У прошедшего дня схема — сразу цвета своей карточки (P923, `docs/71`
/// §8: «схема светлая, а карточки тёмные, состаренные — видна смена
/// цвета»): тот же рельеф бумаги и затёртый по контуру край.
struct FoldSchema: View {
    var aged = false
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Prefs.plainPast) private var plainPast = false

    var body: some View {
        let shape = FolderShape(tabHeight: Search.tabHeight, tabShare: Search.tabShare)
        ZStack {
            shape.fill(Scheme.current.past)
            if aged && !plainPast {
                Image(uiImage: PageTexture.paper)
                    .resizable(resizingMode: .tile)
                    .opacity(scheme == .dark ? 0.2 : 0.3)
                    .clipShape(shape)
                // Затёртый край — без размытия (P1000): схема меняет размер
                // на каждом кадре, и три размытые обводки `EdgeWear`
                // пересчитывались каждый кадр — у прошлого рост и сжатие шли
                // рывками (замер: кадры до 0,5 с), у будущего, без края, —
                // ровно. Две полосы, обрезанные по контуру, на ходу не
                // отличить, а считаются они сразу.
                ZStack {
                    shape.stroke(PageTexture.wearAmber.opacity(0.32), lineWidth: 12)
                    shape.stroke(PageTexture.wearAmber.opacity(0.4), lineWidth: 5)
                    shape.stroke(PageTexture.wearBurnt.opacity(0.55),
                                 style: StrokeStyle(lineWidth: 2.5, lineCap: .round, dash: [9, 2, 4, 3, 13, 2, 6, 4]))
                }
                .clipShape(shape)
                .opacity(scheme == .dark ? 0.35 : 1)
            }
            shape.stroke(Scheme.current.kraftEdge.opacity(0.7), lineWidth: 1)
        }
    }
}

/// Карточка садится в своё гнездо (P895): пока схема летит, карточки нет —
/// гнездо пустует; над гнездом она уже в своём ряду, под схемой, и
/// опускается под следующую карточку; затем схема тает — проступает надпись.
/// Гнездо карточки, которая едет к верху (P1011), пустует: едет её снимок.
private struct UnfoldHole: ViewModifier {
    @ObservedObject var unfold: Unfold
    let id: String

    func body(content: Content) -> some View {
        content.opacity(unfold.hole == id ? 0 : 1)
    }
}

private struct Landed: ViewModifier {
    @ObservedObject var landing: Landing
    let id: String
    /// Карточка прошлого — схема той же старой бумаги (P923).
    var aged = false

    func body(content: Content) -> some View {
        let stage = landing.id == id ? landing.stage : .none
        // Схема полупрозрачна уже на подлёте (P906, автор: «впечатление
        // угловатости; пораньше делать вставляющуюся карточку
        // полупрозрачной»): сквозь неё проступает сама карточка, и к концу
        // опускания схемы почти нет — без смены одного на другое разом.
        // Над карточкой тает снимок полосы листа (P1018) — схемы нет,
        // карточка сразу целиком.
        let veil: Double = landing.bare ? 0 : stage == .hover ? 0.6 : stage == .down ? 0.2 : 0
        // Проступает над гнездом ещё в полёте полосы (P1023).
        let near = stage == .away && landing.id == id && landing.nearing
        content
            .animation(.easeOut(duration: 0.2)) { $0.opacity(stage == .away && !near ? 0 : 1) }
            .overlay {
                if stage == .hover || stage == .down || stage == .done {
                    // Меняется вместе со ступенью — её ходом (P923), своего нет:
                    // по концу этого хода посадка идёт дальше.
                    FoldSchema(aged: aged)
                        .opacity(veil)
                        .allowsHitTesting(false)
                }
            }
            .offset(y: stage == .hover || near ? -Landing.lift : 0)
    }
}

struct FolderShape: Shape {
    /// Радиус углов корешка листа «Дня» (P850).
    static let wave: CGFloat = 14

    let tabHeight: CGFloat
    /// Доля ширины под корешок: у карточек треть, у листа «Дня» шире —
    /// там имя дня и дата (P797).
    var tabShare: CGFloat = 1.0 / 3
    /// Скруглённый низ — у листа «Дня» (P830): у карточек картотеки низ
    /// уходит под следующую и остаётся прямым (P725).
    var roundBottom = false
    /// Мягкие обводы — у листа «Дня» (P845, автор: «слишком геометрично
    /// вырезан, нужно более ламповый»): углы круглее, а корешок переходит в
    /// плечо плавной волной, без дуги и прямого уступа.
    var soft = false

    func path(in r: CGRect) -> Path {
        if soft { return softPath(in: r) }
        let tabWidth = r.width * tabShare
        let tabR: CGFloat = 10, bodyR: CGFloat = 12
        // Вырез у корешка — по большему радиусу (P830; прежде 6 — «очень
        // условно»): насколько позволяет высота корешка.
        let inner = max(6, min(16, tabHeight - tabR - 2))
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + tabR))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY),
                 tangent2End: CGPoint(x: r.minX + tabR, y: r.minY), radius: tabR)
        p.addLine(to: CGPoint(x: r.minX + tabWidth - tabR, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.minX + tabWidth, y: r.minY),
                 tangent2End: CGPoint(x: r.minX + tabWidth, y: r.minY + tabR), radius: tabR)
        p.addLine(to: CGPoint(x: r.minX + tabWidth, y: r.minY + tabHeight - inner))
        p.addArc(tangent1End: CGPoint(x: r.minX + tabWidth, y: r.minY + tabHeight),
                 tangent2End: CGPoint(x: r.minX + tabWidth + inner, y: r.minY + tabHeight), radius: inner)
        p.addLine(to: CGPoint(x: r.maxX - bodyR, y: r.minY + tabHeight))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY + tabHeight),
                 tangent2End: CGPoint(x: r.maxX, y: r.minY + tabHeight + bodyR), radius: bodyR)
        if roundBottom {
            // Низ листа — те же скругления, что вверху (P830).
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bodyR))
            p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY),
                     tangent2End: CGPoint(x: r.maxX - bodyR, y: r.maxY), radius: bodyR)
            p.addLine(to: CGPoint(x: r.minX + bodyR, y: r.maxY))
            p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY),
                     tangent2End: CGPoint(x: r.minX, y: r.maxY - bodyR), radius: bodyR)
        } else {
            // Низ прямой, без скругления (P725): карточка уходит под
            // следующую, и видно, что она выше видимой части.
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        }
        p.closeSubpath()
        return p
    }

    /// Мягкий контур листа «Дня» (P850, вместо волны P845 — «чрезмерно
    /// наклонен, почти нет вертикальной части»): правый край корешка
    /// вертикален, оба его угла — и верхний, и внутренний у плеча — круглые,
    /// радиусом 14; углы листа — 18 сверху слева и 16 у плеча и внизу.
    private func softPath(in r: CGRect) -> Path {
        let tabWidth = r.width * tabShare
        let tabR: CGFloat = 18, bodyR: CGFloat = 16
        let corner = min(Self.wave, (tabHeight - 4) / 2)
        let shoulder = r.minY + tabHeight
        let edge = r.minX + tabWidth
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.minY + tabR))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY),
                 tangent2End: CGPoint(x: r.minX + tabR, y: r.minY), radius: tabR)
        p.addLine(to: CGPoint(x: edge - corner, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: edge, y: r.minY),
                 tangent2End: CGPoint(x: edge, y: r.minY + corner), radius: corner)
        p.addLine(to: CGPoint(x: edge, y: shoulder - corner))
        p.addArc(tangent1End: CGPoint(x: edge, y: shoulder),
                 tangent2End: CGPoint(x: edge + corner, y: shoulder), radius: corner)
        p.addLine(to: CGPoint(x: r.maxX - bodyR, y: shoulder))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: shoulder),
                 tangent2End: CGPoint(x: r.maxX, y: shoulder + bodyR), radius: bodyR)
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bodyR))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY),
                 tangent2End: CGPoint(x: r.maxX - bodyR, y: r.maxY), radius: bodyR)
        p.addLine(to: CGPoint(x: r.minX + bodyR, y: r.maxY))
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY),
                 tangent2End: CGPoint(x: r.minX, y: r.maxY - bodyR), radius: bodyR)
        p.closeSubpath()
        return p
    }
}

/// Карточки наползают друг на друга по всему экрану (P791, вместо «только в
/// дальней трети» P789; размер карточек не меняется). У ближнего края шаг
/// между ними прежний, к дальнему плавно убывает — до края передняя карточка
/// закрывает у задней на одну строку больше (от пяти видимых строк до
/// четырёх). У прошлого дальний край вверху, у будущего — внизу. Только при
/// показе: раскладка ленты, замеры места дня и прокрутка те же.
private struct Distance: ViewModifier {
    let side: Int
    let height: CGFloat

    func body(content: Content) -> some View {
        if side == 0 || height <= 0 {
            content
        } else {
            content.visualEffect { [side, height] view, geo in
                // От верха экрана: окно ленты выше на запас (P861). Карточки
                // не тают — уходят за край (P861, вместо таяния P850, P859).
                let top = geo.frame(in: .scrollView).minY - Afar.above(height)
                let shift = Afar.shift(top, side: side, height: height)
                return view.offset(y: shift)
            }
        }
    }
}

/// Мера наползания (P791).
enum Afar {
    /// Сколько от прежнего шага остаётся у дальнего края: 4 строки из 5.
    static let tightest: CGFloat = 0.8

    /// Сколько ленты собрано ниже экрана (P791): карточки, что подтягиваются
    /// к дальнему нижнему краю из-за экрана, уже нарисованы и выходят плавно,
    /// а не появляются на глазах. С запасом к наибольшему сдвигу у края.
    /// Сколько ленты собрано выше экрана (P861): карточка прошлого у верха
    /// нарисована с наползанием ниже своего места (до десятой доли экрана и
    /// пятой доли того, на сколько место ушло за край), и стопка должна
    /// держать её, пока она не ушла за верх целиком.
    static func above(_ height: CGFloat) -> CGFloat { height * (1 - tightest) * 0.625 + 90 }

    /// Верх экрана в окне ленты — как доля для `scrollTo` (P861): строка с
    /// таким местом встаёт верхом на верх экрана, а не окна.
    static func screenTop(_ height: CGFloat) -> UnitPoint {
        let a = above(height), b = reserve(height)
        return UnitPoint(x: 0.5, y: a + b > 0 ? a / (a + b) : 0)
    }

    /// Плюс `lift` (P859).
    static func reserve(_ height: CGFloat) -> CGFloat { height * (1 - tightest) / 2 + 40 + lift }

    /// Добавка к запасу (P859): рамка карточки на 32 точки ниже её корешка,
    /// и без добавки будущая карточка у нижнего края пропадала на последних
    /// 3 мм, а не уходила под нижнюю строку. Столько же пустого места внизу
    /// ленты — чтобы последняя карточка вставала там же, где прежде.
    static let lift: CGFloat = Search.overlap + 40

    /// `top` — верх карточки на экране ленты, `height` — высота экрана.
    /// Возвращает сдвиг по вертикали. Карточки стоят плотнее у края, где
    /// «Сегодня», и свободнее у дальнего (P909, автор: «в прошлом плотнее у
    /// низа экрана и свободнее у верха, в будущем наоборот»; прежде было
    /// наоборот — плотнее у дальнего края). Шаг у ближнего края — `tightest`
    /// от настоящего, к дальнему плавно растёт до настоящего и за дальним
    /// краем остаётся настоящим. Опора — ближний край: стык с листом
    /// «Сегодня» не двигается. Карточки только сближаются — щели нет.
    static func shift(_ top: CGFloat, side: Int, height h: CGFloat) -> CGFloat {
        // Расстояние от ближнего края: у прошлого — от низа экрана, у
        // будущего — от верха.
        // Край — не край экрана, а край листа «Сегодня» (P913): верх его
        // корешка внизу или низ его полоски вверху. Прежде опорой был край
        // экрана, и завтрашняя карточка уезжала корешком с датой под
        // полоску «Сегодня» (снимок автора к 286).
        let near: CGFloat = side > 0 ? h - FollowRibbon.peekBottom : FollowRibbon.peekTop
        let d = side > 0 ? near - top : top - near
        let loss = 1 - tightest
        let shown: CGFloat
        if d < 0 {
            shown = tightest * d
        } else if d <= h {
            // Шаг k(v) = tightest + loss·v/h, сложенный от края до d.
            shown = tightest * d + loss * d * d / (2 * h)
        } else {
            shown = tightest * h + loss * h / 2 + (d - h)
        }
        let place = side > 0 ? near - shown : near + shown
        return place - top
    }
}


/// Окно ленты без запаса сверху (P861): выше экрана раздела карточек не видно.
private struct TopCut: Shape {
    let cut: CGFloat
    func path(in r: CGRect) -> Path {
        Path(CGRect(x: r.minX, y: r.minY + cut, width: r.width, height: max(0, r.height - cut)))
    }
}

/// Строка поиска и лупа картотеки — на верхнем слое страницы «Дня» (P969).
///
/// Прежде они лежали в самой картотеке (`SearchView`), а картотека — под
/// листом «Сегодня». В картотеке прошлого находки стоят вплотную над
/// корешком «Сегодня»; строка над корешком закрывала нижнюю находку (автор
/// по 302), а строка под корешком уходила под лист (P966, отменено P968).
/// Теперь строка рисуется поверх всей страницы и стоит у самого низа: снизу
/// вверх — клавиатура (или нижняя строка разделов), строка поиска, корешок
/// «Сегодня», находки. Для этого страница поднимается ещё на высоту строки,
/// а строка лежит на столе и закрывает открывшийся низ листа «Сегодня».
/// Не поднимается вместе со страницей: стоит над клавиатурой сама.
struct SearchBar: View {

    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var search: SearchState
    @FocusState private var typing: Bool

    /// Насколько клавиатура закрывает экран снизу.
    @State private var keyboard: CGFloat = 0
    /// Высота строки поиска с отступами — на столько поднимается страница.
    @State private var fieldHeight: CGFloat = 52

    var body: some View {
        // Строка поиска — внизу, над нижней строкой, полупрозрачная
        // (P797, прежде вверху — P334, P718): карточки идут от самого
        // верха до самого низа, у будущего завтрашняя — у самого верха.
        // Только у открытой ленты (P777). Пока набирают — над клавиатурой.
        // Поиск — лупа в полупрозрачном кружке там же, где у дня «＋»
        // (P798, вместо постоянной строки P797): касание — строка
        // раскрывается и поднимается клавиатура; убрали клавиатуру с
        // пустой строкой — снова лупа.
        Group {
            if shown {
                field
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
                        if abs(h - fieldHeight) > 0.5 { fieldHeight = h }
                    }
                    // Под корешком строка лежит на столе (P969): иначе сквозь
                    // неё был бы виден поднятый низ листа «Сегодня».
                    .background { if underSpine { Desk() } }
                    .padding(.bottom, fieldLift)
            } else {
                HStack {
                    Spacer(minLength: 0)
                    loupe
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .opacity(shell.screen == .search ? 1 : 0)
        .allowsHitTesting(shell.screen == .search)
        .accessibilityHidden(shell.screen != .search)
        .animation(.easeOut(duration: 0.2), value: shell.screen == .search)
        // Тем же ходом, каким поднимается страница (P931).
        .animation(.easeOut(duration: 0.25), value: shown)
        .keyboardHeight($keyboard)
        .onChange(of: typing) { _, now in
            if search.typing != now { search.typing = now }
            if !now && search.query.isEmpty { search.open = false }
        }
        // Клавиатуру убирает и картотека: открыли карточку, коснулись дня.
        .onChange(of: search.typing) { _, now in
            if typing != now { typing = now }
        }
        // Слово стёрли, когда клавиатуры уже нет, — тоже снова лупа
        // (P930): прежде строка сворачивалась, только если клавиатуру
        // убирали при пустой строке, и после крестика оставалась пустой
        // полосой (снимок автора к 295).
        .onChange(of: search.query) { _, now in
            if now.isEmpty && !typing { search.open = false }
        }
        // Насколько поднять страницу над клавиатурой поиска — оболочке (P931).
        .onChange(of: pageLift, initial: true) { _, lift in
            if shell.searchLift != lift { shell.searchLift = lift }
        }
        // Ушли из картотеки — клавиатура поиска уходит тоже (P931).
        .onChange(of: shell.screen) { _, screen in
            if screen != .search { typing = false }
        }
    }

    /// Строка поиска раскрыта: набирают или слово осталось.
    private var shown: Bool { search.open || !search.query.isEmpty }

    /// Строка стоит под корешком «Сегодня», у самого низа (P969): в
    /// картотеке прошлого, пока строка раскрыта.
    private var underSpine: Bool {
        shown && shell.screen == .search && shell.deck == .file(.past)
    }

    /// Верх клавиатуры на экране.
    private var keysTop: CGFloat {
        let safe = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }.first ?? 0
        return UIScreen.main.bounds.height - safe - keyboard
    }

    /// Сколько клавиатура закрывает над нижней строкой разделов.
    private var keys: CGFloat {
        keyboard > 0 && shell.barTop > 0 ? max(0, shell.barTop - keysTop) : 0
    }

    /// Насколько вся страница «Дня» поднята (P931, автор по 298: «если
    /// найденных карточек одна или две, они полностью закрыты клавиатурой»;
    /// P969, автор по 302: «её полностью закрывает строка поиска»). В
    /// картотеке прошлого находки стоят у низа экрана, над корешком
    /// «Сегодня». Пока строка раскрыта, страница поднимается целиком —
    /// карточки, корешок «Сегодня» — на высоту клавиатуры и строки поиска.
    /// Поднимает оболочка (`RootView.dayPage`): лист «Сегодня» лежит у неё.
    /// В картотеке будущего находки у верха экрана — поднимается одна строка
    /// поиска, как прежде.
    private var pageLift: CGFloat {
        underSpine ? keys + fieldHeight : 0
    }

    /// Насколько поднять строку поиска над нижней строкой разделов (P797).
    private var fieldLift: CGFloat {
        // В картотеке прошлого — вплотную над клавиатурой, под корешком (P969).
        if underSpine { return keys }
        // Без клавиатуры у прошлого строка — над корешком «Сегодня» (P930):
        // так она стоит, пока картотеку тянут или карточка садится.
        guard keyboard > 0, shell.barTop > 0 else {
            return shell.deck.side == .past ? FollowRibbon.peekBottom : 0
        }
        return keys + 4
    }

    /// Лупа в стеклянном кружке, размером с «＋» дня (P798).
    private var loupe: some View {
        Button {
            search.open = true
            DispatchQueue.main.async { typing = true }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Look.inkSoft)
                .frame(width: 44, height: 44)
                .background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(Look.inkFaint.opacity(0.5), lineWidth: 1))
                .shadow(color: .black.opacity(0.15), radius: 3, x: 1.5, y: 1.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(T("Поиск", "Search"))
    }

    /// Строка поиска — внизу ленты (P797).
    private var field: some View {
        HStack(spacing: 8) {
            fieldBox
            // Закончить поиск одним касанием (P930), как «Отменить» в Почте
            // и Заметках: слово стёрто, клавиатура убрана, снова лупа.
            // Крестик в строке только стирает слово — строка остаётся для
            // уточнения.
            Button {
                search.query = ""
                typing = false
                search.open = false
            } label: {
                Text(T("Отменить", "Cancel"))
                    .font(.system(size: 15))
                    .foregroundStyle(Look.accent)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .background(Look.fieldBg.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var fieldBox: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Look.inkFaint)
            TextField(prompt, text: $search.query)
                .focused($typing)
                .submitLabel(.search)
            if !search.query.isEmpty {
                Button { search.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(Look.inkFaint)
                    .accessibilityLabel(T("Очистить", "Clear"))
            }
            filterMenu
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        // Полупрозрачная, как стекло (P797): карточки под ней видны, но
        // размыто — иначе их текст спорил со словом «Поиск».
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .background(Look.fieldBg.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    /// Где и что искать — меню в самой строке поиска (P632; прежде в меню
    /// уголка). Горит, когда ищем не по всему архиву.
    private var filterMenu: some View {
        Menu {
            scopeButton(T("Искать везде", "Search everywhere"), .all)
            scopeButton(T("Только в дневнике", "Only in the diary"), .diary)
            scopeButton(T("Только в плане", "Only in the plan"), .plan)
            Divider()
            ForEach(SearchState.Find.allCases, id: \.self) { kind in
                Button {
                    search.find = kind
                } label: {
                    let title = kind == .all ? T("Искать всё", "Find everything")
                                             : T("Только: ", "Only: ") + kind.title.lowercased()
                    if search.find == kind { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 18))
                .foregroundStyle(search.scope != .all || search.find != .all ? Look.accent : Look.inkFaint)
        }
        .accessibilityLabel(T("Что и где искать", "What and where to search"))
    }

    private func scopeButton(_ title: String, _ scope: SearchState.Scope) -> some View {
        Button {
            search.scope = scope
        } label: {
            if search.scope == scope { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    /// Где ищем — видно прямо в строке поиска, а не только в меню: иначе,
    /// выбрав «только в плане» и забыв об этом, человек решит, что запись
    /// пропала.
    private var prompt: String {
        switch search.scope {
        case .all:   return T("Поиск по словам", "Search")
        case .diary: return T("Поиск в дневнике", "Search the diary")
        case .plan:  return T("Поиск в плане", "Search the plan")
        }
    }
}
