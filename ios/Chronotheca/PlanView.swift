import EventKit
import SwiftUI
import UIKit
import CoreLocation
import UniformTypeIdentifiers

// MARK: - Открытая страница

/// Вкладка «План»: дела на день.
/// Порядок плана — один для открытой и соседних страниц (P668, P114):
/// события Календаря с вложениями под ними, дела и строки под делами,
/// пустая плашка следующего дела. Открытая страница даёт строкам правку и
/// жесты, соседняя — нет; что за чем стоит, решается только здесь.
struct PlanLayout<Event: View, Task: View, Extra: View, Ghost: View>: View {

    let rows: [PlanRow]
    let events: [DayEvents.Shown]
    let ghost: Bool
    @ViewBuilder let event: (_ number: Int, _ shown: DayEvents.Shown, _ under: PlanRow?) -> Event
    @ViewBuilder let task: (_ row: PlanRow, _ number: Int) -> Task
    @ViewBuilder let extra: (_ row: PlanRow, _ line: String) -> Extra
    @ViewBuilder let ghostRow: (_ number: Int) -> Ghost

    var body: some View {
        ForEach(Array(events.enumerated()), id: \.element.key) { i, e in
            event(i + 1, e, Plan.under(e.key, in: rows))
        }
        let owned = Set(events.compactMap { Plan.under($0.key, in: rows)?.id })
        let tasks = rows.filter(\.isTask).map(\.id)
        ForEach(rows) { row in
            if row.isTask {
                task(row, events.count + (tasks.firstIndex(of: row.id) ?? 0) + 1)
            } else if let line = row.verbatim, !owned.contains(row.id) {
                extra(row, line)
            }
        }
        if ghost { ghostRow(events.count + tasks.count + 1) }
    }
}

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
    /// Дело подержали, не сдвигая, — меню дела (P626).
    @State private var holdMenu: UUID?
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
    /// Прокрутка страницы в начале переноса (P648): страница едет за пальцем
    /// у края, а места строк запомнены по началу.
    @State private var photoScroll: CGFloat = 0
    @State private var photoTo: UUID?
    /// Снимок ложится под событие Календаря — его ключ (P625).
    @State private var photoToEvent: String?
    @State private var photoEventSpots: [String: CGRect] = [:]
    @State private var photoBack = false
    @State private var photoSpots: [UUID: CGRect] = [:]
    @State private var photoStripTop: CGFloat = .infinity
    /// Снимок под делом, о котором спрашивают «что сделать с файлом» (P623).
    @State private var removingPlanPhoto: String?
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

    /// Как расступаются строки под взятым делом: пружина без рывка (P631) —
    /// прежнее быстрое замедление (0,16 с) дёргало места, когда палец
    /// стоял у границы.
    static let makeRoom = Animation.spring(response: 0.3, dampingFraction: 0.9)

    /// Дело отпущено, но ещё доезжает до своего места: настоящая перестановка
    /// в файле — когда доехало (P631).
    @State private var pendingDrop: (() -> Void)?

    /// Дело, которое сейчас ведут вверх-вниз, и на сколько оно сдвинуто.
    @State private var dragged: UUID?
    @State private var dragBy = 0
    /// Где стоят дела вместе со снимками и точками под ними — снято, когда
    /// дело взяли (P628): по этим меркам решается, куда встанет взятое, и на
    /// сколько расступаются соседи.
    @State private var dragBlocks: [UUID: CGRect] = [:]
    /// Высота взятого дела вместе с тем, что под ним: на столько
    /// расступаются соседи.
    @State private var dragHeight: CGFloat = PlanRowLine.height

    /// Сколько пальец прошёл от начала. Взятое дело идёт за пальцем
    /// вплотную, а расступаются соседи уже по целым строкам.
    @State private var dragOffset: CGFloat = 0

    /// Насколько клавиатура закрывает страницу: строку, в которой пишут,
    /// страница держит над ней.
    @State private var keyboard: CGFloat = 0

    var body: some View {
        planBody
            // Пока дело, событие или снимок несут пальцем — разделы не
            // листаются вбок (P799): иначе ход вправо-влево уводил бы страницу.
            .onChange(of: lifted != nil || liftedEvent != nil || photoCarry != nil) { _, now in
                Hold.report?(now)
            }
    }

    private var planBody: some View {
        // План — верхняя часть страницы дня, без своей прокрутки: страница
        // едет целиком, план и дневник вместе (P408).
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                // Запись не дошла до папки (P900) — сказать прямо на странице.
                if let why = store.unsaved { UnsavedNote(why: why) }
                // Архив новее приложения (P953) — спокойно сказать, почему
                // не пишется.
                if Vault.newer { NewerArchiveNote() }
                if store.away.contains(.planner) {
                    PlanEmpty(inCloud: true)
                } else {
                    PlanLayout(rows: store.planRows, events: shownEvents, ghost: ghostShown) { number, e, under in
                        eventItem(e, number: number, under: under)
                    } task: { row, _ in
                        taskItem(row.id)
                    } extra: { row, line in
                        extraItem(row.id, line: line)
                    } ghostRow: { number in
                        ghost(number)
                    }
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
            // Касание по свободному месту вне плашек убирает курсор (P652):
            // плашки ловят касание сами, сюда доходит только мимо них.
            .background(
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard typingIn != nil else { return }
                        hideKeyboard()
                        typingIn = nil
                    })
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
        .confirmationDialog(T("Дело", "Task"),
                            isPresented: Binding(get: { holdMenu != nil },
                                                 set: { if !$0 { holdMenu = nil } }),
                            titleVisibility: .hidden, presenting: holdMenu) { id in
            if let i = store.index(of: id) {
                Button(store.planRows[i].done ? T("Не сделано", "Not done") : T("Сделано", "Done")) {
                    holdMenu = nil
                    toggle($store.planRows[i])
                }
                Button(T("Перенести на другой день", "Move to another day")) {
                    holdMenu = nil
                    Feel.paper()
                    withAnimation(.pull) {
                        shell.movingTask = MovingTask(id: id, title: store.planRows[i].text)
                    }
                }
                Button(T("Удалить", "Delete"), role: .destructive) {
                    holdMenu = nil
                    let r = store.planRows[i]
                    if r.repeats != nil || (r.text.isEmpty && r.details.isEmpty) {
                        withAnimation(.easeOut(duration: 0.2)) { store.delete(id) }
                        Feel.light()
                    } else {
                        askingDelete = id
                    }
                }
            }
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
                    Group {
                        if Diary.isPoint(c.link), let point = Geo.point(in: c.link) {
                            PointSquare(point: point)
                                .frame(width: DiaryEditor.photoSize.width, height: DiaryEditor.photoSize.height)
                        } else {
                            PlanPhotoThumb(url: store.photoURL(c.link))
                        }
                    }
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Look.glow, lineWidth: 2.6))
                        .shadow(color: .black.opacity(0.25), radius: 8, x: 4, y: 4)
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
        .modifier(RemoveQuestion(
            asking: Binding(get: { removingPlanPhoto != nil }, set: { if !$0 { removingPlanPhoto = nil } }),
            act: { delete in
                if let link = removingPlanPhoto { shell.say(store.removePlanRowPhoto(link, delete: delete)) }
                removingPlanPhoto = nil
            }))
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
    private func add(roller: Bool = false) {
        guard let id = store.addTask() else { return shell.say(store.closedReason) }
        if roller { openRoller(id) } else { typingIn = id }
    }

    /// Пустая плашка видна, пока все дела чем-то заполнены: начали писать в
    /// новом — под ним появляется следующая (P406).
    private var ghostShown: Bool {
        // В прошедших днях пустой плашки нет (P421).
        store.canEditPlan && !store.isPast && !store.tasks.contains(where: PlanRow.blank)
    }

    private func ghost(_ number: Int) -> some View {
        VStack(spacing: 0) {
            // Не «Без названия», а предложение помощи (P452).
            PlanRowLine(number: number,
                        row: .task(PlanRow.ghostTitle),
                        bellColor: Look.accent,
                        onTime: { add(roller: true) },
                        onBell: { add(roller: true) },
                        ghost: true)
        }
        .contentShape(Rectangle())
        .onTapGesture { add() }
        .accessibilityLabel(T("Новое дело", "New task"))
    }

    /// Дело и черта под ним — одним куском: пока несут точку, они
    /// расступаются вместе (P374).
    @ViewBuilder private func taskItem(_ id: UUID) -> some View {
        if let i = store.index(of: id) {
            VStack(spacing: 0) {
                taskRow($store.planRows[i])
            }
            .modifier(Zone(id: id))
            .offset(y: lineShift(id) + eventShift(id) + photoShift(id))
            .animation(.easeOut(duration: 0.16), value: lineShift(id) + eventShift(id) + photoShift(id))
            .zIndex(dragged == id || lifted == id ? 1 : 0)
        }
    }

    private func extraItem(_ id: UUID, line: String) -> some View {
        extraLine(id: id, line: line)
            .offset(y: lineShift(id) + eventShift(id) + photoShift(id) + blockDisplaced(id))
            .animation(Self.makeRoom,
                       value: lineShift(id) + eventShift(id) + photoShift(id) + blockDisplaced(id))
            // Снимки под взятым делом идут за пальцем вместе с ним (P628).
            .offset(y: blockDragged(id))
            .zIndex(lineDrag == id || blockOwner(id) == dragged && dragged != nil ? 1 : 0)
    }

    /// Строка под делом или под событием: снимки в ряд, точка, текст (P358).
    /// Одна на всех — под делом и под событием Календаря (P625).
    private func extraLine(id: UUID, line: String) -> some View {
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
                      carriedPhoto: photoCarry?.from == id ? photoCarry?.link : nil,
                      onRemovePhoto: store.canEditPlan
                          ? { link in
                              // У точки нет файла — вопроса «что с файлом» нет (P630).
                              if Diary.isPoint(link) { shell.say(store.removePlanRowPhoto(link, delete: false)) }
                              else { removingPlanPhoto = link }
                          } : nil,
                      photoSlot: photoCarry?.from == id ? photoSlot : nil)
            .modifier(Zone(id: id))
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
            // Название с продолжением после «Ввода» (P652).
            text: Binding(get: { row.wrappedValue.fullTitle },
                          set: { row.wrappedValue.setFullTitle($0) }),
            typing: typingIn == id,
            onTime: { openRoller(id) },
            onBell: { openRoller(id) },
            onCheck: { toggle(row) },
            // Правку кончила эта самая строка, а не соседняя, которой
            // только что отдали ввод: иначе курсор гас бы сразу после
            // перехода в следующее дело.
            onDone: {
                if typingIn == id { typingIn = nil }
                store.save()
                store.checkSeries(id)
            },
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
                    : CGFloat(displaced(id)) * dragHeight)
            .animation(dragged == id ? nil : Self.makeRoom, value: displaced(id))
            .background { underneath(id) }
            .shadow(color: .black.opacity(dragged == id ? 0.18 : 0),
                    radius: 8, x: 3, y: 3)
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
            // Прежнее дело ещё доезжало — довести, прежде чем брать новое.
            if let settle = pendingDrop {
                pendingDrop = nil
                settle()
            }
            Feel.lift()
            liftAxis = nil
            slide = 0
            armedLine = nil
            var blocks: [UUID: CGRect] = [:]
            for task in store.tasks {
                var frame = CGRect.null
                for rowID in store.blockIDs(of: task.id) {
                    if let f = PlanZones.rows[rowID] { frame = frame.union(f) }
                }
                if !frame.isNull { blocks[task.id] = frame }
            }
            dragBlocks = blocks
            dragHeight = blocks[id]?.height ?? PlanRowLine.height
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
                // Место сменилось — тихий щелчок: видно, что соседи уступили.
                let steps = dragSteps(id, way.height)
                if steps != dragBy { Feel.tick() }
                dragBy = steps
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
            // Подержал на месте — меню, как в iPhone; повёл — перенос (P626).
            if real, axis == nil {
                Feel.light()
                holdMenu = id
                return
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

    /// Событие и снимки под ним — одним куском, как дело, над делами (P376, P625).
    private func eventItem(_ e: DayEvents.Shown, number: Int, under: PlanRow?) -> some View {
        let i = number - 1
        let list = shownEvents
        return VStack(spacing: 0) {
            eventRow(e, number: number)
            if let under, let line = under.verbatim {
                extraLine(id: under.id, line: line)
            }
        }
        .offset(y: eventPhotoShift(after: i, in: list))
        .animation(.easeOut(duration: 0.16), value: eventPhotoShift(after: i, in: list))
        .zIndex(liftedEvent == e.key ? 1 : 0)
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
                        lifted: up || photoToEvent == e.key || shell.eventHover == e.key,
                        past: store.isPast)
        }
        // Без пересчёта на каждом кадре свайпа вбок (P833).
        .trackFrame(appear: { frame in
                        PlanZones.events[e.key] = frame
                        PlanZones.marks[e.key] = DayEvents.Mark(key: e.key, time: e.row.time, title: e.row.text)
                    },
                    change: { PlanZones.events[e.key] = $0 },
                    gone: {
                    PlanZones.events[e.key] = nil
                    PlanZones.marks[e.key] = nil
                })
        .offset(x: up ? eventSlide : 0, y: up ? eventDrag : 0)
        .background {
            if up, eventSlide < 0 { Self.swipeBack(eventSlide, left: T("Убрать", "Remove")) }
        }
        .shadow(color: .black.opacity(up && eventDrag != 0 ? 0.18 : 0), radius: 8, x: 3, y: 3)
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
            if axis == nil {
                // Подержал на месте — меню события (P626).
                Feel.light()
                askingEvent = e
            } else if axis == .horizontal {
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
            armedLine = nil
            photoSpots = PlanZones.rows
            photoEventSpots = PlanZones.events
            photoToEvent = nil
            photoStripTop = min(PlanZones.strip?.minY ?? .infinity, PlanZones.diaryTop ?? .infinity)
            photoTo = nil
            photoBack = false
            photoSlot = nil
            photoSpot = spot
            photoScroll = DiaryEditor.active?.pageOffset() ?? 0
            DiaryEditor.active?.holdPage(true)
        case .moved:
            // Подержали — пока только крестик (P720); копия над пальцем —
            // когда повели, как в тексте записи.
            if photoCarry == nil { photoCarry = PhotoCarry(link: link, from: row) }
            guard photoCarry?.link == link else { return }
            photoSpot = spot
            // У края экрана страница едет навстречу, как при переносе из
            // текста и снизу страницы (замечание автора к 180, P648).
            DiaryEditor.active?.followStrip(at: spot) { [self] in
                carryPhoto(link, from: row, .moved(.zero), at: photoSpot)
            }
            // Места строк запомнены в начале переноса, а страница с тех пор
            // могла уехать — палец переводится в те же места (P648).
            let shift = (DiaryEditor.active?.pageOffset() ?? 0) - photoScroll
            let here = CGPoint(x: spot.x, y: spot.y + shift)
            // Цель — там, где картинка (она нарисована на 48 выше пальца), а
            // не там, где палец: иначе «вниз» и «под другое дело» не
            // совпадали с тем, что видно (P623).
            let aim = CGPoint(x: here.x, y: here.y - 48)
            let back = aim.y >= photoStripTop - 8
            // Вдоль своего ряда — переставить в ряду (P409).
            let slot = back ? nil : slotInRow(row, at: here)
            if slot != photoSlot {
                photoSlot = slot
                if slot != nil { Feel.tick() }
            }
            var to: UUID?
            var toEvent: String?
            if !back, slot == nil {
                // Цели — и дела, и события Календаря: та, чей верх выше
                // картинки и ближе всех к ней (P625).
                let list = store.tasks
                let events = shownEvents
                let task = list.last { (photoSpots[$0.id]?.minY ?? .infinity) < aim.y }
                let event = events.last { (photoEventSpots[$0.key]?.minY ?? .infinity) < aim.y }
                let taskTop = task.flatMap { photoSpots[$0.id]?.minY } ?? -.infinity
                let eventTop = event.flatMap { photoEventSpots[$0.key]?.minY } ?? -.infinity
                if let event, eventTop > taskTop {
                    toEvent = event.key
                } else if let task {
                    to = task.id
                } else if let first = events.first {
                    toEvent = first.key
                } else {
                    to = list.first?.id
                }
                if to == owner(of: row) { to = nil }
                if toEvent != nil, toEvent == store.eventOwner(of: row) { toEvent = nil }
            }
            if to != photoTo || toEvent != photoToEvent || back != photoBack {
                withAnimation(.easeOut(duration: 0.16)) {
                    photoTo = to
                    photoToEvent = toEvent
                    photoBack = back
                }
                if to != nil || toEvent != nil || back { Feel.tick() }
            }
        case .ended, .cancelled:
            DiaryEditor.active?.holdPage(false)
            DiaryEditor.active?.stopFollowingStrip()
            guard photoCarry?.link == link else { return }
            let to = photoTo
            let toEvent = photoToEvent
            let back = photoBack
            let slot = photoSlot
            let real: Bool
            if case .ended = phase { real = true } else { real = false }
            withAnimation(.easeOut(duration: 0.2)) {
                photoCarry = nil
                photoTo = nil
                photoToEvent = nil
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
                } else if let toEvent, let e = shownEvents.first(where: { $0.key == toEvent }) {
                    store.putPlanPhoto(link, underEvent: DayEvents.Mark(key: e.key, time: e.row.time,
                                                                       title: e.row.text))
                }
            }
            if real, back || to != nil || toEvent != nil || slot != nil { Feel.thud() }
        }
    }

    /// Место в своей сетке вложений под пальцем: перед каким встать.
    /// `nil` — палец не над этим рядом.
    private func slotInRow(_ row: UUID, at spot: CGPoint) -> Int? {
        guard let frame = photoSpots[row], frame.insetBy(dx: 0, dy: -6).contains(spot),
              let line = store.planRows.first(where: { $0.id == row })?.verbatim
        else { return nil }
        let count = Plan.items(in: line).count
        guard count > 1 else { return nil }
        // Сетка по четыре (P654): ряд и место в ряду.
        return PlanPhotoGrid.slot(at: CGPoint(x: spot.x - frame.minX, y: spot.y - frame.minY),
                                  width: frame.width, count: count)
    }

    /// Дело, под которым стоит строка.
    private func owner(of row: UUID) -> UUID? {
        guard let i = store.index(of: row), store.eventOwner(of: row) == nil else { return nil }
        return store.planRows[..<i].last { $0.isTask }?.id
    }

    /// На сколько сдвинута строка, пока несут снимок: под выбранным делом
    /// открывается место под новый ряд — если ряда снимков там ещё нет.
    private func photoShift(_ id: UUID) -> CGFloat {
        // Свой снимок из-под дела — или снимок из дневника и полоски (P409).
        // Под событием Календаря: события стоят над делами, так что место
        // под новый ряд открывается у всех дел сразу (P625).
        if photoCarry != nil, let key = photoToEvent, store.eventPhotoRow(key) == nil {
            return PlanPhotoLine.height + 1
        }
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

    /// На сколько сдвинуты события ниже того, под которое несут снимок (P625).
    private func eventPhotoShift(after i: Int, in list: [DayEvents.Shown]) -> CGFloat {
        guard photoCarry != nil, let key = photoToEvent,
              let t = list.firstIndex(where: { $0.key == key }), i > t,
              store.eventPhotoRow(key) == nil else { return 0 }
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
        // Другое время или день — в окне события от Apple (P669): переносом
        // на день, как у дела, событие не ходит — приложение в Календарь само
        // не пишет (P376).
        Button(T("Другое время или день", "Another time or day")) {
            askingEvent = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { open(e) }
        }
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
    ///
    /// Оно плавно доезжает до освобождённого места (P631) и только потом
    /// переставляется в файле: прежде оно прыгало с того места, где его
    /// отпустили, на новое.
    private func drop(_ id: UUID) {
        let by = dragBy
        let list = store.tasks
        // Куда оно сядет: низом на низ блока, на место которого встаёт, или
        // верхом на его верх.
        var land: CGFloat = 0
        if by != 0, let from = list.firstIndex(where: { $0.id == id }), let mine = dragBlocks[id] {
            let to = min(max(from + by, 0), list.count - 1)
            if let target = dragBlocks[list[to].id] {
                land = by > 0 ? target.maxY - mine.maxY : target.minY - mine.minY
            }
        }
        pendingDrop = {
            var plain = Transaction()
            plain.disablesAnimations = true
            withTransaction(plain) {
                dragged = nil
                dragBy = 0
                dragOffset = 0
                dragBlocks = [:]
                dragHeight = PlanRowLine.height
                if by != 0 { for _ in 0..<abs(by) { store.move(id, by: by > 0 ? 1 : -1) } }
            }
        }
        withAnimation(Self.makeRoom) { dragOffset = land }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            if let settle = pendingDrop {
                pendingDrop = nil
                settle()
            }
        }
    }

    /// «Ввод» в названии: ввод переходит к делу ниже.

    private func openRoller(_ id: UUID) {
        guard store.canEditPlan else { return shell.say(store.closedReason) }
        // Ролик встаёт на место клавиатуры, а не поверх неё: два разных
        // способа ввода разом на экране не помещаются, и человеку пришлось
        // бы сперва убирать клавиатуру самому (решение P176).
        hideKeyboard()
        shell.roller = .init(id: id)
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

    /// Какое дело взять за хозяина строки под ним — только пока дело тащат.
    private func blockOwner(_ row: UUID) -> UUID? {
        dragged == nil ? nil : owner(of: row)
    }

    /// Снимки и точки под взятым делом идут за пальцем (P628).
    private func blockDragged(_ row: UUID) -> CGFloat {
        guard let dragged, blockOwner(row) == dragged else { return 0 }
        return dragOffset
    }

    /// Снимки и точки под делом, которое расступается, едут вместе с ним.
    private func blockDisplaced(_ row: UUID) -> CGFloat {
        guard let dragged, let owner = blockOwner(row), owner != dragged else { return 0 }
        return CGFloat(displaced(owner)) * dragHeight
    }

    /// На сколько дел сдвинулось бы взятое, если отпустить: когда его
    /// середина перешла середину соседа — вместе со снимками соседа. Меряется
    /// по снятым меркам, а не по высоте одной строки (P628): у дел со
    /// снимками и в две строки она другая, и место под взятым не сходилось с
    /// тем, где его отпускали.
    private func dragSteps(_ id: UUID, _ dy: CGFloat) -> Int {
        let list = store.tasks
        guard let from = list.firstIndex(where: { $0.id == id }), let mine = dragBlocks[id]
        else { return Int((dy / PlanRowLine.height).rounded()) }
        let centre = mine.midY + dy
        var to = from
        if dy > 0 {
            for j in (from + 1)..<list.count {
                guard let b = dragBlocks[list[j].id], centre > b.midY else { break }
                to = j
            }
        } else {
            for j in stride(from: from - 1, through: 0, by: -1) {
                guard let b = dragBlocks[list[j].id], centre < b.midY else { break }
                to = j
            }
        }
        return to - from
    }

    private func number(of id: UUID) -> Int {
        (store.tasks.firstIndex { $0.id == id } ?? 0) + 1
    }
}
