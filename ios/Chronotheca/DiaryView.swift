import SwiftUI
import Photos

/// Вкладка «Дневник»: как прошло, заголовок дня и свободный текст.
///
/// Набрана засечным шрифтом на тёплой бумаге — в отличие от плана. Это разные
/// занятия: план разглядывают, дневник читают.
struct DiaryView: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell
    @State private var health: String?
    /// Превью из полоски, которое несут, и где палец (P380).
    @State private var stripCarry: Int?
    @State private var stripSpot: CGPoint = .zero
    /// Крестик у вложения в тексте нажат — сперва вопрос (P456).
    /// Снимки сегодняшнего дня из галереи — предложением в ленте (P538).
    @StateObject private var suggest = DaySuggestions()

    /// На ступень крупнее прежних 15,5 и растёт с настройкой (P274).
    static var size: CGFloat { 16.5 * Prefs.textScale }
    static let leading: CGFloat = size * 0.24

    var body: some View {
        if store.isFuture {
            // Будущий день: дневника ещё нет — касание говорит почему, а не
            // молчит (P424).
            page.overlay {
                // Поверх — чтобы касание не съело поле записи под ним.
                Color.black.opacity(0.001)
                    .onTapGesture {
                        shell.say(T("Этот день ещё не наступил — дневник откроется в свой день",
                                    "This day hasn't come yet — the diary opens on the day itself"))
                    }
            }
        } else {
            page
        }
    }

    private var page: some View {
        DiaryPage(
            tasks: store.tasks,
            answer: { store.answers[$0] ?? "" },
            setAnswer: { store.answers[$0] = $1 },
            title: $store.diaryTitle,
            text: $store.diaryText,
            editable: store.canEditDiary,
            inCloud: store.away.contains(.diary),
            weather: store.weather,
            // Полоска одна на всю страницу (P408): снимки дневника, за ними
            // — прежние снимки полоски плана.
            photos: store.stripLinks.map(store.photoURL),
            photoLinks: store.stripLinks,
            takesBack: Plan.hasPhotoRows(store.planRows),
            suggested: AnyView(SuggestedRow(model: suggest) { asset in
                GalleryRow.take([asset], store: store, tab: .diary) { shell.say($0) }
            }),
            hasSuggested: store.canEditDiary && suggest.shows,
            resolve: store.photoURL,
            onOpenPhoto: { i in
                let n = store.photos.count
                shell.openedPhoto = i < n ? .init(tab: .diary, index: i) : .init(tab: .plan, index: i - n)
            },
            // Брошенный в текст снимок отметку времени не ставит — это
            // знает само поле записи (P362).
            onFocusText: { store.openNewLine(always: $0) },
            takeStamp: { store.takeStamp() },
            onWrite: { store.noteWriting() },
            onOpenInline: { link in
                shell.openedPhoto = .init(tab: .diary, index: -1,
                                          url: store.photoURL(link), link: link)
            },
            onOpenPoint: {
                store.noteLeaving(fromToday: true)
                shell.showPoint($0)
            },
            onCaret: { store.diaryCaret = $0 },
            onEditing: {
                store.diaryTyping = $0
                // Где пишут — там «где был» (P402, P408).
                if $0 { shell.tab = .diary }
            },
            placeCaret: $store.caretRequest,
            reveal: $store.revealRequest,
            // Снимок, отпущенный над полоской, возвращается в неё (P272).
            onReturnPhoto: { link in
                store.returnToStrip(link)
                shell.say(T("Снимок вернулся в полоску", "Photo moved back to the strip"))
            },
            // Точка из текста — в заголовок и обратно (P358).
            onPointToTitle: { line in
                store.diaryTitle = DiaryPage.title(Geo.stripped(store.diaryTitle),
                                                   keeping: store.diaryTitle + " " + line)
            },
            onPointFromTitle: { line in
                store.pointFromTitle(line)
            },
            undo: store.diaryBack.isEmpty || !store.canEditDiary ? nil : { store.undoDiary() },
            redo: store.diaryAhead.isEmpty || !store.canEditDiary ? nil : { store.redoDiary() },
            writeNow: shell.writeNow,
            health: health,
            // Касание по строке «Здоровья» — она ложится в запись (P378).
            onHealth: store.canEditDiary ? { line in store.addHealthLine(line) } : nil,
            onStripCarry: { carryStrip($0, $1, $2) },
            stripCarried: stripCarry,
            onRemovePhoto: { i, delete in
                let n = store.photos.count
                shell.say(i < n ? store.removeAttachment(at: i, from: .diary, delete: delete)
                                : store.removeAttachment(at: i - n, from: .plan, delete: delete))
            },
            onAnswering: {
                store.answerTyping = $0
                if $0 != nil { shell.tab = .diary }
            },
            planTarget: store.canEditPlan ? { PlanZones.task(at: $0, tasks: store.tasks) } : nil,
            onPlanHover: { hover($0, photo: $1) },
            onToPlan: { piece, task in store.textToPlan(piece, under: task) },
            // Вопрос уже задан у самого крестика (P556): второй такой же
            // после «Удалить файл» не нужен (P561 — автор видел два подряд).
            onDeleteAttachment: { deleteFromText($0, delete: true) })
        // Взятое из полоски — над пальцем, в синей рамке (P380): рисуется
        // поверх полосы у низа экрана, а не на странице под ней (P545,
        // `StripGhostLayer`).
        .task(id: store.date) { health = await HealthDay.summary(for: store.date) }
        // Предложенные снимки — заново при смене дня, после взятия, при
        // возвращении в приложение (новые снимки камерой) (P538).
        .onAppear {
            suggest.reload(today: store.isToday)
        }
        .onChange(of: store.date) { _, _ in suggest.reload(today: store.isToday) }
        .onReceive(NotificationCenter.default.publisher(for: DaySuggestions.changed)) { _ in
            suggest.reload(today: store.isToday)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.willEnterForegroundNotification)) { _ in
            suggest.reload(today: store.isToday)
        }
        .onReceive(NotificationCenter.default.publisher(for: HealthDay.note)) { _ in
            Task { health = await HealthDay.summary(for: store.date) }
        }
        .onChange(of: store.diaryTitle) { _, _ in store.scheduleSave() }
        .onChange(of: store.answers) { _, _ in
            // Снимок, перенесённый в ответ, уходит из полоски (P407).
            store.settlePhotos()
            store.scheduleSave()
        }
        .onChange(of: store.diaryText) { _, _ in
            store.settlePhotos()
            store.scheduleSave()
        }
    }
}

extension DiaryView {

    /// Превью из полоски несут (P380): над полем записи текст расступается
    /// там, куда оно ляжет; над полоской — встанет на место соседа.
    fileprivate func carryStrip(_ i: Int, _ phase: Lift, _ spot: CGPoint) {
        let links = store.stripLinks
        guard store.canEditDiary, links.indices.contains(i) else { return }
        let link = links[i]
        let line = Diary.line(link)
        let overStrip = StripZones.strip.map { spot.y >= $0.minY - 8 } ?? false
        // Над планом — встанет под дело, в ряд снимков (P408, P409).
        let overTask = overStrip || Diary.kind(of: link) != .photo || !store.canEditPlan
            ? nil : PlanZones.task(at: spot, tasks: store.tasks)
        // У краёв страница едет к пальцу (P409) — но только когда палец
        // ушёл с полоски (P531): полоска сама лежит у нижнего края, и на
        // длинной записи страница уезжала от одного долгого нажатия,
        // унося превью под нижнюю строку.
        func follow() {
            guard !overStrip else {
                DiaryEditor.active?.stopFollowingStrip()
                return
            }
            DiaryEditor.active?.followStrip(at: spot) { [self] in
                carryStrip(i, .moved(.zero), stripSpot)
            }
        }
        switch phase {
        case .began:
            Feel.lift()
            DiaryEditor.active?.holdPage(true)
            stripCarry = i
            stripSpot = spot
            StripGhost.shared.show(store.stripLinks[i], at: spot)
        case .moved:
            stripSpot = spot
            StripGhost.shared.spot = spot
            follow()
            hover(overTask, photo: true)
            if overTask != nil {
                AskLine.carryOutAll()
                DiaryEditor.active?.carryOut()
            // Над строкой «Как прошло?» — встаёт в конец ответа, в ту же
            // строку (P407).
            } else if !overStrip, AskLine.carry(line, at: spot) {
                DiaryEditor.active?.carryOut()
            } else if overStrip {
                AskLine.carryOutAll()
                DiaryEditor.active?.carryOut()
            } else {
                DiaryEditor.active?.carryIn(line, at: CGPoint(x: spot.x, y: spot.y))
            }
        case .ended:
            DiaryEditor.active?.holdPage(false)
            DiaryEditor.active?.stopFollowingStrip()
            hover(nil, photo: false)
            if let task = overTask, spot != .zero {
                AskLine.carryOutAll()
                DiaryEditor.active?.carryOut()
                if Diary.kind(of: link) == .photo {
                    store.stripPhotoToPlan(link, under: task)
                    Feel.thud()
                }
            } else if !overStrip, spot != .zero, AskLine.carryEnd(at: spot) {
                DiaryEditor.active?.carryOut()
                if i >= store.photos.count { store.dropFromPlanStrip(link) }
                Feel.thud()
            } else if overStrip || spot == .zero {
                AskLine.carryOutAll()
                DiaryEditor.active?.carryOut()
                let n = store.photos.count
                if let to = StripZones.nearest(to: spot, count: links.count), to != i, spot != .zero {
                    if i < n, to < n {
                        store.movePhoto(from: i, to: to, in: .diary)
                    } else if i >= n, to >= n {
                        store.movePhoto(from: i - n, to: to - n, in: .plan)
                    }
                    Feel.light()
                }
            } else if DiaryEditor.active?.carryEnd() == true {
                // Снимок из прежней полоски плана встал в запись — из
                // полоски он уходит (P408).
                if i >= store.photos.count { store.dropFromPlanStrip(link) }
                Feel.thud()
            }
            stripCarry = nil
            stripSpot = .zero
            StripGhost.shared.link = nil
        case .cancelled:
            DiaryEditor.active?.holdPage(false)
            DiaryEditor.active?.stopFollowingStrip()
            hover(nil, photo: false)
            AskLine.carryOutAll()
            DiaryEditor.active?.carryOut()
            stripCarry = nil
            stripSpot = .zero
            StripGhost.shared.link = nil
        }
    }

    /// Над каким делом несут (P409): план обводит его и раздвигает строки.
    fileprivate func hover(_ id: UUID?, photo: Bool) {
        let next = id.map { Shell.PlanHover(id: $0, photo: photo) }
        guard shell.planHover != next else { return }
        withAnimation(.easeOut(duration: 0.16)) { shell.planHover = next }
        if next != nil { Feel.tick() }
    }

    /// Крестик у снимка в записи → «удалить файл» (P409): снимок уходит из
    /// записи, а файл — в корзину на 30 дней, как из полоски (P371).
    fileprivate func deleteFromText(_ link: String, delete: Bool) {
        store.returnToStrip(link)
        guard let k = store.photos.lastIndex(of: link) else { return }
        shell.say(store.removeAttachment(at: k, from: .diary, delete: delete))
    }

}

/// Страница дневника.
///
/// Одна и та же и для открытого дня, и для соседних. Это не изящество, а
/// необходимость: стоит им разойтись хоть на строку — и при перелистывании
/// текст на открывающейся странице прыгает.
struct DiaryPage: View {

    let tasks: [PlanRow]
    let answer: (String) -> String
    var setAnswer: ((String, String) -> Void)?
    @Binding var title: String
    @Binding var text: String
    var editable = true
    /// Файл дневника лежит в iCloud и ещё не скачан: страница пуста не
    /// потому, что день пуст (решение P182).
    var inCloud = false
    /// Погода, когда отмечено место: бледной строкой над страницей (P208).
    var weather: String?
    /// Фотографии дня. Стоят над текстом, под заголовком (P200).
    var photos: [URL?] = []
    /// Строки-ссылки тех же снимков: их несёт палец из полоски в текст.
    var photoLinks: [String] = []
    /// Под делами плана есть снимки — полоска видна и пустой: в неё их
    /// возвращают (P358, P408).
    var takesBack = false
    /// Предложенные снимки дня в конце ленты (P538) — и есть ли они.
    var suggested: AnyView? = nil
    var hasSuggested = false
    /// Где лежат снимки, стоящие посреди текста (P204).
    var resolve: ((String) -> URL?)?
    var onOpenPhoto: ((Int) -> Void)?
    /// Возвращает `true`, если приложение поставило отметку времени: тогда
    /// курсор переезжает за неё.
    /// `true` в ответ — курсор переезжает в конец, в новую строку. Отдаётся,
    /// открыто ли поле само при открытии приложения (P403).
    var onFocusText: (Bool) -> Bool = { _ in false }
    var takeStamp: (() -> String?)? = nil
    var onWrite: (() -> Void)? = nil
    /// Касание по снимку посреди текста (P216) и по точке (P213).
    var onOpenInline: ((String) -> Void)?
    var onOpenPoint: ((GeoPoint) -> Void)?
    var onCaret: ((Int) -> Void)?
    var onEditing: ((Bool) -> Void)?
    var placeCaret: Binding<Int?> = .constant(nil)
    var reveal: Binding<Int?> = .constant(nil)
    var onReturnPhoto: ((String) -> Void)?
    /// Точку перенесли из текста в заголовок дня — и обратно (P358).
    var onPointToTitle: ((String) -> Void)?
    var onPointFromTitle: ((String) -> Void)?
    /// Шаг назад и вперёд (P261) — там же, где в плане (P312).
    var undo: (() -> Void)?
    var redo: (() -> Void)?
    /// Приложение открыли на дневнике (P403): поле само берёт ввод, курсор —
    /// в начале новой строки. У соседних страниц не меняется.
    var writeNow = 0
    /// День из «Здоровья» (P378) — слева в верхней строке, где пусто.
    var health: String? = nil
    var onHealth: ((String) -> Void)? = nil
    /// Превью из полоски несут своим жестом — в текст или на место соседа
    /// в полоске (P380).
    var onStripCarry: ((Int, Lift, CGPoint) -> Void)? = nil
    var stripCarried: Int? = nil
    /// Крестик у подержанного превью (P432): убрать со страницы или
    /// удалить в корзину — тот же вопрос, что у открытого снимка.
    var onRemovePhoto: ((Int, Bool) -> Void)? = nil
    @State private var removing: Int?
    /// В каком деле «Как прошло?» пишут — туда встаёт «место» (P407).
    var onAnswering: ((String?) -> Void)? = nil
    /// Снимок или точку из записи несут в план (P409).
    var planTarget: ((CGPoint) -> UUID?)? = nil
    var onPlanHover: ((UUID?, Bool) -> Void)? = nil
    var onToPlan: ((String, UUID) -> Bool)? = nil
    /// Крестик у снимка в записи → «удалить файл» (P409).
    var onDeleteAttachment: ((String) -> Void)? = nil

    /// Для какого открытия поле уже взяло ввод само (P403).
    private static var wrote = -1
    /// Поле берёт ввод по открытию приложения, а не по касанию.
    @State private var writing = false
    /// Конец записи: к нему страница едет, когда открывают на дневнике
    /// (P346, P408).
    static var end: String { "дневник-конец" }

    /// Курсор в заголовке (P425): поле теперь UIKit, со своей приставкой.
    @State private var titleFocused = false

    /// Дело, на которое сейчас отвечают в «Как прошло?».
    @State private var askingAt: String?

    /// Поднимается ровно на один оборот — когда отметка времени поставлена.
    @State private var caretToEnd = false

    /// Поднимается по «Вводу» в заголовке: ввод переходит к тексту записи.
    @State private var toText = false

    /// Точка заголовка, у которой сейчас крестик (P362).
    @State private var armedPoint: String?

    private let size = DiaryView.size

    var body: some View {
        // Верхней строки больше нет (P406): стрелки шага — на корешке
        // «Дневник», погоды в дневнике нет, «Здоровье» и вложения — внизу
        // страницы и едут вместе с ней.
        page
    }

    /// Низ страницы: «Здоровье» строкой и полоска вложений (P406).
    @ViewBuilder private var footer: some View {
        // Погода дня — строкой внизу страницы, над вложениями, как в
        // Diarium (P406, P408).
        if let weather, Prefs.weatherOn {
            Label(Prefs.weatherText(weather), systemImage: "cloud.sun")
                .font(Look.sans(12.5))
                .foregroundStyle(Look.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 6)
        }
        if let health {
            Label(health, systemImage: "heart")
                .font(Look.sans(12))
                .foregroundStyle(Look.inkFaint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .contentShape(Rectangle())
                .onTapGesture { onHealth?(health) }
                .accessibilityHint(T("Касание — записать в дневник", "Tap to add to the diary"))
        }
        // Лента превью — конец листа, едет с текстом, как в Diarium (P546).
        if (!photos.isEmpty || takesBack || hasSuggested) {
            PhotoStrip(photos: photos, onOpen: onOpenPhoto,
                       onCarry: editable ? onStripCarry : nil,
                       carried: stripCarried,
                       onRemove: editable && onRemovePhoto != nil ? { removing = $0 } : nil,
                       extra: hasSuggested ? suggested : nil)
                .modifier(RemoveQuestion(
                    asking: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                    act: { delete in
                        if let i = removing { onRemovePhoto?(i, delete) }
                        removing = nil
                    }))
                .background(GeometryReader { geo in
                    let frame = geo.frame(in: .global)
                    // Полоска одна на страницу (P408): по ней узнают
                    // «назад в полоску» и дневник, и план.
                    Color.clear
                        .onAppear { if editable { StripZones.strip = frame; PlanZones.strip = frame } }
                        .onChange(of: frame) { _, now in
                            if editable { StripZones.strip = now; PlanZones.strip = now }
                        }
                        // Ленты нет — нет и места, куда возвращать (P547).
                        .onDisappear { if editable { StripZones.strip = nil; PlanZones.strip = nil } }
                })
        }
    }

    /// Дневник — нижняя часть страницы дня, без своей прокрутки: страница
    /// едет целиком, план и дневник вместе (P408). Короткая запись —
    /// погода, «Здоровье» и полоска всё равно внизу экрана; длинная — под
    /// ней и уходят вниз вместе со страницей.
    private var page: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if inCloud {
                    Text(T("Запись этого дня ещё загружается из iCloud. Как только придёт, она появится здесь.",
                   "This day is still downloading from iCloud. It will appear here as soon as it arrives."))
                        .font(Look.serif(size - 1))
                        .foregroundStyle(Look.inkFaint)
                        .padding(.bottom, 12)
                }
                // «Как прошло?» можно выключить в настройках (P290).
                if Prefs.askOn, !asked.isEmpty { askBlock }
                titleField
                textField
                Color.clear.frame(height: 1).id(Self.end)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 20)
            Spacer(minLength: 0)
            footer
        }
        .onAppear { startWriting() }
        .onChange(of: writeNow) { _, _ in startWriting() }
    }

    /// Открыли приложение на дневнике — клавиатура поднята, курсор в начале
    /// новой строки под записью: открыл — и пишешь, без касания (P403).
    private func startWriting() {
        guard writeNow > 0, writeNow != Self.wrote, editable else { return }
        Self.wrote = writeNow
        writing = true
        // Страница успевает встать на место, потом поле берёт ввод.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { toText = true }
    }

    private var asked: [PlanRow] {
        Array(tasks.filter { !$0.text.isEmpty }.prefix(3))
    }

    // MARK: - Как прошло

    /// Три первых дела, по строке на каждое (решение P30). Ответ пишется
    /// прямо в той же строке, за двоеточием, и, дойдя до края, продолжается
    /// с начала следующей — во всю ширину, как в тетради (решение P185).
    private var askBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Не вопрос, а заголовок: вопросы раздражают (P452).
            Text(T("Итоги дня", "How the day went"))
                .font(Look.serif(size))
                .foregroundStyle(Look.hint)
                .frame(height: size * 1.6, alignment: .leading)

            ForEach(asked, id: \.id) { task in
                askRow(task)
            }
        }
        .padding(.bottom, 12)
    }

    /// Название дела в «Как прошло?» — в одну строку, не шире восьми
    /// десятых строки (P406; прежде шести десятых — обрывалось на середине);
    /// длиннее — обрезано многоточием (P23, P36). Заголовок
    /// и три дела — четыре строки, сколько бы ни было в названиях (P397:
    /// длинное название переносилось, и блок вырастал до семи строк).
    static func short(_ text: String, width: CGFloat) -> String {
        let font = AskLine.font
        func wide(_ s: String) -> CGFloat { (s as NSString).size(withAttributes: [.font: font]).width }
        guard wide(text + ":") > width else { return text + ":" }
        var cut = text
        while !cut.isEmpty, wide(cut + "…:") > width { cut.removeLast() }
        return cut.trimmingCharacters(in: .whitespaces) + "…:"
    }

    private func askRow(_ task: PlanRow) -> some View {
        AskLine(label: Self.short(Geo.stripped(task.text),
                                  width: (UIScreen.main.bounds.width - 40) * 0.8),
                answer: Binding(get: { answer(task.text) },
                                set: { setAnswer?(task.text, $0) }),
                editable: editable && setAnswer != nil,
                typing: askingAt == task.text,
                onBegin: {
                    askingAt = task.text
                    onAnswering?(task.text)
                },
                onDone: {
                    if askingAt == task.text { askingAt = nil }
                    onAnswering?(nil)
                },
                onNext: { next(after: task.text) },
                resolve: resolve,
                onOpen: onOpenInline,
                onOpenPoint: onOpenPoint,
                onReturn: editable ? onReturnPhoto : nil)
            // Пустая строка стоит ровно в строку, а исписанная растёт вниз —
            // и дела, стоящие ниже, отодвигаются, освобождая место (P175).
            .frame(minHeight: size * 1.7, alignment: .leading)
    }

    /// «Ввод» в ответе: к следующему делу, а после последнего — к
    /// заголовку дня. Страница идёт сверху вниз, и «Ввод» ведёт по ней в
    /// том же порядке: ответы, заголовок, запись. Прежде последний ответ
    /// уводил прямо в запись, мимо заголовка (решение P196, уточняет P185).
    private func next(after task: String) {
        let дела = asked.map(\.text)
        if let i = дела.firstIndex(of: task), i + 1 < дела.count {
            askingAt = дела[i + 1]
        } else {
            askingAt = nil
            // Ввод уходит из поля ответа, и только потом заголовок его
            // принимает: иначе два поля перетягивают клавиатуру.
            DispatchQueue.main.async { titleFocused = true }
        }
    }

    // MARK: - Заголовок

    /// Слова заголовка — без точек: точки стоят за ними значками (P358).
    private var titleWords: Binding<String> {
        // Без точек заголовок отдаётся как есть: прежде пробел в конце
        // срезался на лету, и набрать пробел после последнего слова было
        // нельзя (P529, запись автора).
        Binding(get: { Geo.points(inText: title).isEmpty ? title : Geo.stripped(title) },
                set: { title = DiaryPage.title($0, keeping: title) })
    }

    /// Заголовок без одной точки — той, что удаляют крестиком (P362).
    static func without(_ line: String, in title: String) -> String {
        guard let r = title.range(of: line) else { return title }
        var out = title
        out.removeSubrange(r)
        return out
    }

    /// Новые слова заголовка, а точки — прежние, за словами.
    static func title(_ words: String, keeping old: String) -> String {
        let ns = old as NSString
        let points = Geo.points(inText: old).map { ns.substring(with: $0.range) }
        // Пробел, только что набранный в конце, остаётся (P529): срезается
        // лишь там, где за словами идут точки.
        guard !points.isEmpty else {
            return String(words.drop(while: { $0 == " " || $0 == "\t" }))
        }
        let head = words.trimmingCharacters(in: .whitespaces)
        return ([head] + points).filter { !$0.isEmpty }.joined(separator: " ")
    }

    private var titleField: some View {
        let points = Geo.points(inText: title)
        let ns = title as NSString
        return VStack(spacing: 0) {
          HStack(spacing: 6) {
            ZStack(alignment: .leading) {
                if title.isEmpty {
                    Text(T("Заголовок дня", "Title of the day"))
                        .font(Look.serif(16.5))
                        .foregroundStyle(Look.hint)
                        .allowsHitTesting(false)
                }
                if editable {
                    // Строки вложений и разделов — и над заголовком (P425).
                    // «Ввод» уводит из заголовка в текст записи, а не просто
                    // убирает клавиатуру (решение P40).
                    TitleLine(text: titleWords, focused: $titleFocused, size: 16.5) {
                        titleFocused = false
                        toText = true
                    }
                    .frame(height: 22)
                    // Заголовок взяли в руки — просьба «перейти в запись»,
                    // если вдруг висит, снимается (P389).
                    .onChange(of: titleFocused) { _, now in
                        if now { toText = false }
                    }
                } else {
                    Text(Geo.stripped(title))
                        .font(Look.serif(16.5, weight: .semibold))
                        .foregroundStyle(Look.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            // Точки в заголовке — значками за словами (P358). Касание — на
            // карту; подержать и потянуть вниз — назад в текст; подержать и
            // отпустить — крупнее и с крестиком «удалить» (P362).
            ForEach(points.indices, id: \.self) { k in
                let line = ns.substring(with: points[k].range)
                TitlePoint(point: points[k].point,
                           armed: armedPoint == line,
                           open: { onOpenPoint?(points[k].point) },
                           arm: editable ? { on in
                               withAnimation(.easeOut(duration: 0.15)) { armedPoint = on ? line : nil }
                           } : nil,
                           down: editable ? { onPointFromTitle?(line) } : nil,
                           delete: editable ? {
                               armedPoint = nil
                               title = DiaryPage.title(Geo.stripped(title),
                                                       keeping: DiaryPage.without(line, in: title))
                           } : nil)
            }
          }
            // Заголовок — подпись к дню, а не вывеска: место на странице
            // принадлежит записи (решение P162).
            .frame(height: 23, alignment: .leading)
            // Где заголовок на экране — туда бросают точку из текста (P358).
            .background(GeometryReader { geo in
                let zone = geo.frame(in: .global)
                Color.clear
                    .onAppear { if editable { DiaryEditor.titleZone = zone } }
                    .onChange(of: zone) { _, now in if editable { DiaryEditor.titleZone = now } }
            })
            .padding(.bottom, 5)

            Rectangle().fill(Look.rule).frame(height: 1)
        }
        .padding(.top, 4)
    }

    // MARK: - Текст

    /// Поле записи — одно и то же и на открытой странице, и на соседних.
    /// Соседняя лишь не правится. Иначе рядом стоят два разных способа
    /// набрать текст, и строки на повороте расходятся (P114).
    private var textField: some View {
        DiaryEditor(text: $text, size: size, serif: true, stamped: true,
                    editable: editable, caretToEnd: $caretToEnd,
                    startEditing: $toText,
                    onFocus: {
                        if onFocusText(writing) { caretToEnd = true }
                        writing = false
                    },
                    // Под записью было пять пустых строк (P346), а с
                    // погодой, полоской и местом под ней до нижней строки
                    // набегало девять — автор просил четыре (P433): своих
                    // пустых строк у поля больше нет, остальное даёт низ
                    // страницы.
                    grows: true, minHeight: 320, room: 0, resolve: resolve,
                    onOpenPhoto: onOpenInline, onReturnPhoto: onReturnPhoto,
                    onOpenPoint: onOpenPoint, onPointToTitle: onPointToTitle, onCaret: onCaret,
                    moving: editable, onEditing: onEditing,
                    placeCaret: placeCaret, reveal: reveal, takeStamp: takeStamp, onWrite: onWrite,
                    planTarget: planTarget, onPlanHover: onPlanHover, onToPlan: onToPlan,
                    onDeleteAttachment: onDeleteAttachment)
            // Вдвое меньше, чем было: пробел между заголовком и записью не
            // должен отнимать место у страницы (P311).
            .padding(.top, 8)
    }
}

/// Точка в заголовке дня (P358, P362): касание — карта; подержать и
/// потянуть вниз — назад в текст записи; подержать и отпустить — крупнее и
/// с крестиком «удалить».
private struct TitlePoint: View {
    let point: GeoPoint
    var armed = false
    var open: () -> Void
    var arm: ((Bool) -> Void)?
    var down: (() -> Void)?
    var delete: (() -> Void)?

    @State private var lifted = false
    @State private var drop: CGFloat = 0

    var body: some View {
        PointChipView(point: point)
            .scaleEffect(armed ? 1.3 : 1)
            .offset(y: drop)
            .overlay(alignment: .topTrailing) {
                if armed, let delete {
                    DeleteBadge(action: delete)
                        .offset(x: PointChipView.width(point) * 0.15 + 13, y: -18)
                }
            }
            .zIndex(armed || drop != 0 ? 1 : 0)
            .contentShape(Capsule())
            .onTapGesture {
                if armed { arm?(false) } else { open() }
            }
            .gesture(arm == nil ? nil : hold)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(T("Точка на карте: ", "Place on the map: ") + point.label)
    }

    private var hold: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !lifted {
                    lifted = true
                    Feel.lift()
                }
                if let drag { drop = max(0, drag.translation.height) }
            }
            .onEnded { value in
                lifted = false
                let way = drop
                withAnimation(.easeOut(duration: 0.15)) { drop = 0 }
                guard case .second(true, _) = value else { return }
                // Потянули вниз, под черту заголовка, — назад в текст.
                if way > 24 {
                    arm?(false)
                    Feel.light()
                    down?()
                } else {
                    arm?(true)
                }
            }
    }
}

/// Что несут из ленты превью и где палец (P545): копия рисуется поверх всего
/// экрана — и поверх самой ленты, которая теперь лежит над страницей.
final class StripGhost: ObservableObject {
    static let shared = StripGhost()
    @Published var link: String?
    @Published var spot: CGPoint = .zero

    func show(_ link: String, at spot: CGPoint) {
        self.spot = spot
        self.link = link
    }
}

/// Копия взятого превью над пальцем, в синей рамке (P380, P545).
struct StripGhostLayer: View {
    @ObservedObject private var ghost = StripGhost.shared
    @EnvironmentObject private var store: DayStore

    var body: some View {
        GeometryReader { g in
            if let link = ghost.link, ghost.spot != .zero {
                let o = g.frame(in: .global).origin
                face(link)
                    // Каждый перенос — своя копия (P555): прежде над пальцем
                    // оставалась картинка прошлого переноса.
                    .id(link)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Look.glow, lineWidth: 2.6))
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                    .position(x: ghost.spot.x - o.x, y: ghost.spot.y - o.y - 48)
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private func face(_ link: String) -> some View {
        if Diary.kind(of: link) == .photo {
            PlanPhotoThumb(url: store.photoURL(link))
        } else {
            // Голос и документ несут той же плиткой, какой они встанут
            // в текст (P456).
            Image(uiImage: PhotoAttachment.tile(link))
        }
    }
}
