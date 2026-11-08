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
    @EnvironmentObject private var vault: Vault

    /// Строка поиска лежит в оболочке: её очищает и меню поиска.
    private var query: String { shell.query }
    @FocusState private var typing: Bool
    /// Строка поиска раскрыта (P798): иначе — только лупа в кружке.
    @State private var searching = false

    /// Насколько клавиатура закрывает список находок.
    @State private var keyboard: CGFloat = 0

    /// Высота экрана раздела — высота места дня в ленте (P777).
    let height: CGFloat

    var body: some View {
        ribbonList
            .keyboardHeight($keyboard)
            // Своя высота — экран раздела; запас ленты ниже экрана (P791)
            // выходит за неё вниз, а не сдвигает ленту.
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            // Строка поиска — внизу, над нижней строкой, полупрозрачная
            // (P797, прежде вверху — P334, P718): карточки идут от самого
            // верха до самого низа, у будущего завтрашняя — у самого верха.
            // Только у открытой ленты (P777). Пока набирают — над клавиатурой.
            // Поиск — лупа в полупрозрачном кружке там же, где у дня «＋»
            // (P798, вместо постоянной строки P797): касание — строка
            // раскрывается и поднимается клавиатура; убрали клавиатуру с
            // пустой строкой — снова лупа.
            .overlay(alignment: .bottom) {
                Group {
                    if searching || !query.isEmpty {
                        field.padding(.bottom, fieldLift)
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
                .animation(.easeOut(duration: 0.2), value: shell.screen == .search)
                .animation(.easeOut(duration: 0.2), value: searching)
            }
            .onChange(of: typing) { _, now in
                if !now && query.isEmpty { searching = false }
            }
            .onAppear { shell.ribbon.height = height }
            .onChange(of: height) { _, h in shell.ribbon.height = h }
    }

    /// Насколько поднять строку поиска над клавиатурой (P797): строка стоит
    /// над нижней строкой разделов, клавиатура поднимается от низа экрана.
    private var fieldLift: CGFloat {
        guard keyboard > 0, shell.barTop > 0 else { return 0 }
        let safe = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }.first ?? 0
        let keysTop = UIScreen.main.bounds.height - safe - keyboard
        return max(0, shell.barTop - keysTop + 4)
    }

    /// Лупа в стеклянном кружке, размером с «＋» дня (P798).
    private var loupe: some View {
        Button {
            searching = true
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
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Look.inkFaint)
            TextField(prompt, text: $shell.query)
                .focused($typing)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { shell.query = "" } label: { Image(systemName: "xmark.circle.fill") }
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
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    /// Где и что искать — меню в самой строке поиска (P632; прежде в меню
    /// уголка). Горит, когда ищем не по всему архиву.
    private var filterMenu: some View {
        Menu {
            scopeButton(T("Искать везде", "Search everywhere"), .all)
            scopeButton(T("Только в дневнике", "Only in the diary"), .diary)
            scopeButton(T("Только в плане", "Only in the plan"), .plan)
            Divider()
            ForEach(Shell.Find.allCases, id: \.self) { kind in
                Button {
                    shell.find = kind
                } label: {
                    let title = kind == .all ? T("Искать всё", "Find everything")
                                             : T("Только: ", "Only: ") + kind.title.lowercased()
                    if shell.find == kind { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 18))
                .foregroundStyle(shell.scope != .all || shell.find != .all ? Look.accent : Look.inkFaint)
        }
        .accessibilityLabel(T("Что и где искать", "What and where to search"))
    }

    private func scopeButton(_ title: String, _ scope: Shell.Scope) -> some View {
        Button {
            shell.scope = scope
        } label: {
            if shell.scope == scope { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    /// Где ищем — видно прямо в строке поиска, а не только в меню: иначе,
    /// выбрав «только в плане» и забыв об этом, человек решит, что запись
    /// пропала.
    private var prompt: String {
        switch shell.scope {
        case .all:   return T("Поиск по словам", "Search")
        case .diary: return T("Поиск в дневнике", "Search the diary")
        case .plan:  return T("Поиск в плане", "Search the plan")
        }
    }

    private var whereNot: String {
        switch shell.scope {
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
        let scope = shell.scope
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
            case past(Archive.Day)
            case slot
            case future(Archive.Day)
        }
        let id: String
        let kind: Kind
        /// Заходит на предыдущую карточку (P694, P695).
        var over = false
        /// Карточка под днём (P791): у дня из прошлого там прошлое после него.
        var below = false

        /// Куда уходит даль (P782): 1 — прошлое, вдаль вверх; -1 — будущее,
        /// вдаль вниз; 0 — не карточка (место дня, поля).
        var depth: Int {
            switch kind {
            case .past: return below ? -1 : 1
            case .future: return -1
            default: return 0
            }
        }
    }

    /// Будущее ленты (P771): месяц подряд, и пустые дни тоже, потом только
    /// дни с делами. Когда ищут — только находки.
    private func ahead(_ days: [Archive.Day], from today: Date) -> [Archive.Day] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard needle.isEmpty, shell.find == .all else { return days }
        let byStamp = Dictionary(days.map { ($0.stamp, $0) }, uniquingKeysWith: { first, _ in first })
        var out: [Archive.Day] = []
        var last = Vault.stamp(today)
        for offset in 1...Search.ahead {
            guard let date = Calendar.current.date(byAdding: .day, value: offset, to: today) else { continue }
            let stamp = Vault.stamp(date)
            out.append(byStamp[stamp] ?? Archive.Day(stamp: stamp, date: date))
            last = stamp
        }
        out += days.filter { $0.stamp > last }
        return out
    }

    /// Вся лента одной стопкой (P777, вместо двух картотек P771): старые
    /// сверху, внизу прошлого вчера, ниже место сегодняшнего дня, под ним
    /// завтра и дальше. Сегодняшней карточки нет: на её месте сам день.
    private func entries(_ past: [Archive.Day], _ future: [Archive.Day],
                         later: [Archive.Day]) -> [Entry] {
        var out: [Entry] = []
        // Над самой старой — место под строку поиска; в коротком архиве —
        // стол до верха экрана, чтобы лента могла встать вчерашним днём
        // над нижней строкой.
        let lead = max(8, height - CGFloat(past.count) * 60)
        out.append(Entry(id: "lead", kind: .pad(lead)))
        if !query.trimmingCharacters(in: .whitespaces).isEmpty && past.isEmpty && future.isEmpty && later.isEmpty {
            out.append(Entry(id: "note", kind: .note))
        }
        for (i, day) in past.enumerated() {
            out.append(Entry(id: Search.deep ? "p\(i)" : day.id, kind: .past(day), over: i > 0))
        }
        // Место дня заходит на нижний край вчерашней карточки, как
        // следующая карточка; завтрашняя лежит под днём своим корешком.
        out.append(Entry(id: Ribbon.slotID, kind: .slot, over: !past.isEmpty))
        for (i, day) in future.enumerated() {
            out.append(Entry(id: day.id, kind: .future(day), over: i > 0))
        }
        // У дня из прошлого под ним — прошлое после него (P791), такими же
        // карточками, как над ним: ближайший следующий день сверху.
        for (i, day) in later.enumerated() {
            out.append(Entry(id: day.id, kind: .past(day), over: i > 0, below: true))
        }
        // Под последней — место под строку поиска внизу (P797).
        let tail = max(Search.fieldHeight + 8, height - CGFloat(future.count + later.count) * 60)
        out.append(Entry(id: "tail", kind: .pad(tail)))
        return out
    }

    /// В дне есть запись дневника — заголовок, текст или снимки (P791).
    private static func written(_ day: Archive.Day) -> Bool {
        !day.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !day.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || day.photos > 0
    }

    /// Подходит ли день под «что искать» из меню поиска (P249).
    private func kept(_ day: Archive.Day) -> Bool {
        let kinds = day.attachments.map { Diary.kind(of: $0) }
        switch shell.find {
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
        // Лента — вокруг открытого дня, а не сегодняшнего (P791): над ним
        // дни до него; под ним — у сегодняшнего и будущего дела вперёд, у
        // прошлого — записанные дни после него.
        let todayStamp = Vault.stamp(DayStore.today())
        let anchor = Vault.stamp(store.date)
        // Опись читается один раз за перерисовку (P771): старые сверху.
        let all = Array(found.reversed())
        var past = all.filter { $0.stamp < anchor }
        // На снимке CI «лента поиска» находки повторены, чтобы было что
        // листать (P717).
        if Search.deep { past = Array(repeating: past, count: 12).flatMap { $0 } }
        let future = anchor >= todayStamp
            ? ahead(all.filter { $0.stamp > anchor }, from: store.date) : []
        let later = anchor < todayStamp
            ? all.filter { $0.stamp > anchor && $0.stamp <= todayStamp && Self.written($0) } : []
        // Столбец времени у будущих карточек один на всю стопку, как в
        // «Списке» календаря (P756): по самому длинному виду времени.
        let times = future.flatMap { plan($0).compactMap(\.time) }
        let sample: String? = times.isEmpty ? nil
            : times.contains { $0.contains(where: \.isLetter) } ? "00:00 PM" : "00:00"
        let items = entries(past, future, later: later)
        let ribbon = shell.ribbon
        return ScrollViewReader { proxy in ScrollView {
            // Карточки — вид сверху: нижняя лежит поверх верхней и своим
            // корешком с датой закрывает её низ (P694, P695).
            LazyVStack(spacing: 0) {
                ForEach(items) { entry in
                    piece(entry, sample: sample)
                        .padding(.top, entry.over ? -Search.overlap : 0)
                        .modifier(Distance(side: entry.depth, height: height))
                        .id(entry.id)
                }
            }
            .padding(.horizontal, 10)
            // Прокрутка без оттяжки (P445): лента и день едут вместе, а
            // оттяжка разлучила бы их.
            .background(NoBounce(box: ribbon.box))
            // Место под клавиатуру (P174).
            .padding(.bottom, keyboard > 0 ? keyboard + 4 : 0)
        }
        .coordinateSpace(.named(Ribbon.space))
        .scrollDismissesKeyboard(.interactively)
        // Ниже экрана — запас (P791): лента там уже собрана, и карточка,
        // подтянутая наползанием из-за нижнего края, выходит плавно.
        .frame(height: height + Afar.reserve(height), alignment: .top)
        .onAppear {
            ribbon.home = { proxy.scrollTo(Ribbon.slotID, anchor: .top) }
            DispatchQueue.main.async {
                if shell.ribbonOpen { settle() } else { ribbon.park() }
                // Ленивая стопка ставит дальнюю карточку со второго раза.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    if shell.ribbonOpen && ribbon.fresh { settle() }
                }
                // Снимок «лента поиска»: список пролистан, как у человека.
                if Search.deep {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        proxy.scrollTo("p20", anchor: .top)
                    }
                }
            }
        }
        // Опись перечитана, пока лента спрятана: место дня — снова под днём,
        // чтобы тяга из дня начиналась сразу.
        // Только что открытую ленту (снимок, запуск на картотеке) опись
        // догоняет позже — встаём в покой ещё раз.
        .onChange(of: items.count) { _, _ in
            DispatchQueue.main.async {
                if !shell.ribbonLive { ribbon.park() } else if ribbon.fresh { settle() }
            }
        }
        // Высота экрана известна не с первого кадра: до неё место дня
        // нулевое, и лента вставала не там (снимки CI к P777).
        .onChange(of: height) { _, _ in
            DispatchQueue.main.async {
                if !shell.ribbonLive { ribbon.park() } else if ribbon.fresh { settle() }
            }
        }
        // Ленту открыли не тягой (снимок, запуск на картотеке) — в покой.
        .onChange(of: shell.ribbonOpen) { _, open in
            guard open, !shell.pulling else { return }
            DispatchQueue.main.async { settle() }
        }
        // Набрали слово — к ближайшей находке: в прошлом она над днём, в
        // будущем под ним. Стёрли — лента снова в покое у дня.
        .onChange(of: query) { _, _ in
            DispatchQueue.main.async { settle() }
        }
        }
        .animation(.easeOut(duration: 0.25), value: keyboard)
    }

    /// Лента в покое: вчера над нижней строкой или завтра под строкой поиска.
    private func settle() {
        guard shell.ribbonOpen, !shell.pulling, !shell.ribbon.busy else { return }
        shell.ribbon.opened()
        shell.ribbon.settle(shell.fileFrom < 0 ? -1 : 1)
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
        case .past(let day):
            // Карточки уже дня (P780): по бокам виден стол, день — во всю
            // ширину, и его не спутать с карточкой.
            SearchCard(stamp: Search.stamp(day.date), past: Ru.isPast(day.date),
                       seed: PageTexture.seed(day.date) &+ (Search.deep ? (Int(entry.id.dropFirst()) ?? 0) * 7 : 0)) {
                row(day)
            }
            .padding(.horizontal, Search.cardInset)
        case .slot:
            daySlot
        case .future(let day):
            SearchCard(stamp: Search.stamp(day.date), past: false,
                       seed: PageTexture.seed(day.date), tight: true) {
                futureRow(day, sample: sample)
            }
            .padding(.horizontal, Search.cardInset)
        }
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
                typing = false
                shell.screen = .today
            }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.frame(in: .named(Ribbon.space)).minY
            } action: { y in
                ribbon.measured(y)
            }
            .onAppear { ribbon.seen = true }
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
                if tasks.isEmpty {
                    Text(T("Пусто — можно вписать дела", "Empty — room to plan"))
                        .font(Look.sans(12))
                        .foregroundStyle(Look.inkFaint)
                }
                ForEach(shown) { task in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let sample {
                            ZStack(alignment: .leading) {
                                Text(sample).hidden()
                                Text(task.time ?? "")
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
    private func openCard(_ date: Date, tab: Shell.Tab) {
        typing = false
        Feel.thud()
        let ribbon = shell.ribbon
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            shell.instant = true
            shell.ribbonOpen = false
            shell.fileFrom = 0
            store.go(to: date)
            shell.tab = tab
            shell.screen = .today
        }
        ribbon.release()
        ribbon.park()
        archive.reloadSoon()
    }

    private func row(_ day: Archive.Day) -> some View {
        Button {
            // Искали в плане — туда и открываем: там нашлось искомое.
            openCard(day.date, tab: shell.scope == .plan || day.date > DayStore.today()
                     || (day.text.isEmpty && !day.tasks.isEmpty) ? .plan : .diary)
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
    /// На сколько карточка заходит на предыдущую: корешок и ещё немного
    /// листа, чтобы нижний край предыдущей скрылся под ней (P696).
    static let overlap: CGFloat = tabHeight + 10
    /// Карточки ленты уже дня (P780): ещё столько с каждого бока.
    static let cardInset: CGFloat = 14

    static let lineGap: CGFloat = 3

    /// Сколько дней подряд идёт картотека будущего, пустые тоже (P771);
    /// дальше — только дни с делами.
    static let ahead = 30

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
    /// Прошедший день — края затёрты, как у его страницы (P722).
    var past = true
    /// Номер дня — у каждой карточки свой износ (P723).
    var seed = 0
    /// Будущая карточка — плотнее (P774): меньше воздуха над и под строками,
    /// чтобы на экран входила неделя.
    var tight = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text(stamp)
                    .font(Look.mono(11.5, weight: .medium))
                    .tracking(0.3)
                    .foregroundStyle(Look.dateBlue)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                Color.clear.frame(maxWidth: .infinity)
                Color.clear.frame(maxWidth: .infinity)
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
                CardPaper(seed: seed, past: past)
            }
        }
    }
}

/// Лист карточки поиска (P732): старая бумага, затёртые края и рваный край —
/// один лист из пачки заготовок; пока его нет — ровная бумага. Сегодняшний
/// день слегка тронут (P728), без «Старой бумаги» (P730) — ровная бумага.
struct CardPaper: View {
    let seed: Int
    let past: Bool
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Prefs.plainPast) private var plainPast = false
    @State private var art: PageTexture.AgedArt?

    var body: some View {
        GeometryReader { geo in
            let order = PageTexture.agedOrder(size: geo.size, band: 12, seed: seed, openBottom: true,
                                              light: !past)
            let ready = plainPast ? nil : (art ?? PageTexture.agedReady(order))
            ZStack {
                paper.clipShape(FolderShape(tabHeight: Search.tabHeight))
                if let ready {
                    Image(uiImage: ready.frame)
                        .resizable()
                        .opacity(scheme == .dark ? 0.35 : 1)
                        .clipShape(FolderShape(tabHeight: Search.tabHeight))
                }
                if let ready {
                    // Плечо карточки (P738) — справа от корешка, где лист
                    // ступенькой ниже корешка, — затёрто той же полосой, что
                    // верх корешка: та же картинка, опущенная на высоту
                    // корешка, видна только вдоль плеча и сходит на нет.
                    Image(uiImage: ready.frame)
                        .resizable()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .offset(y: Search.tabHeight)
                        .mask(alignment: .topLeading) { shoulder(geo.size) }
                        // В полную силу, как верх корешка (P823; прежде 0,6).
                        .opacity(scheme == .dark ? 0.35 : 1)
                    // Правый бок корешка (P823): тот же правый край листа,
                    // сдвинутый к корешку, — видна только полоса вдоль бока.
                    Image(uiImage: ready.frame)
                        .resizable()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .offset(x: geo.size.width / 3 - geo.size.width)
                        .mask(alignment: .topLeading) { tabSide(geo.size) }
                        .clipShape(FolderShape(tabHeight: Search.tabHeight))
                        .opacity(scheme == .dark ? 0.35 : 1)
                }
                FolderShape(tabHeight: Search.tabHeight)
                    .stroke(Scheme.current.kraftEdge.opacity(0.5), lineWidth: 0.8)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .mask {
                if let ready { Image(uiImage: ready.cut).resizable() } else { Rectangle() }
            }
            .task(id: order) {
                guard !plainPast else { return }
                art = await PageTexture.aged(order)
            }
        }
        .allowsHitTesting(false)
    }

    /// Полоса вдоль плеча: от корешка до правого края, книзу и к правому
    /// краю тает (правый край затёрт и так).
    private func shoulder(_ size: CGSize) -> some View {
        let from = size.width / 3 + 6
        return LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom)
            .frame(width: max(0, size.width - from - 10), height: 30)
            // С обоих концов тает (P742): на снимке автора начало и конец
            // полосы читались чёрточками.
            .mask(LinearGradient(colors: [.clear, .black, .black, .clear],
                                 startPoint: .leading, endPoint: .trailing))
            .offset(x: from, y: Search.tabHeight)
    }

    /// Полоса вдоль правого бока корешка: от верха до плеча, книзу тает.
    private func tabSide(_ size: CGSize) -> some View {
        LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom)
            .frame(width: 16, height: Search.tabHeight + 6)
            .offset(x: size.width / 3 - 16)
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

/// Контур карточки с корешком на левой трети: корешок и лист — одна фигура.
struct FolderShape: Shape {
    let tabHeight: CGFloat
    /// Доля ширины под корешок: у карточек треть, у листа «Дня» шире —
    /// там имя дня и дата (P797).
    var tabShare: CGFloat = 1.0 / 3
    /// Скруглённый низ — у листа «Дня» (P830): у карточек картотеки низ
    /// уходит под следующую и остаётся прямым (P725).
    var roundBottom = false

    func path(in r: CGRect) -> Path {
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
                let top = geo.frame(in: .scrollView).minY
                return view.offset(y: Afar.shift(top, side: side, height: height))
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
    static func reserve(_ height: CGFloat) -> CGFloat { height * (1 - tightest) / 2 + 40 }

    /// `top` — верх карточки на экране ленты, `height` — высота экрана.
    /// Возвращает сдвиг по вертикали: шаг между карточками — прежний у
    /// ближнего края и плавно убывает до `tightest` у дальнего, за дальним
    /// краем — как у края. Карточки только сближаются — щели нет.
    static func shift(_ top: CGFloat, side: Int, height h: CGFloat) -> CGFloat {
        // Расстояние до дальнего края: у прошлого — от верха экрана,
        // у будущего — от низа.
        let t = side > 0 ? top : h - top
        let loss = 1 - tightest
        // Сколько показанной длины у ленты от `t` до ближнего края: шаг k(u)
        // = tightest + loss·u/h, сложенный от t до h.
        func shown(_ u: CGFloat) -> CGFloat {
            tightest * (h - u) + loss * (h * h - u * u) / (2 * h)
        }
        let f: CGFloat
        if t >= h {
            f = t
        } else if t >= 0 {
            f = h - shown(t)
        } else {
            f = h - shown(0) + tightest * t
        }
        let place = side > 0 ? f : h - f
        return place - top
    }
}
