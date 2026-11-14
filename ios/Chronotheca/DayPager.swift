import SwiftUI
import UIKit
import PhotosUI
import Photos
import UniformTypeIdentifiers
import CoreTransferable

/// Открытый день.
///
/// Вместе со страницей меняется всё, что к этому дню относится: имя дня,
/// день недели, дата, вкладки и полоска вложений. Неподвижны только
/// шестерёнка и три раздела внизу — то, что принадлежит приложению, а не дню.
/// Соседний день встаёт на место без загиба листа (P779).
struct DayPages: View {

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var archive: Archive

    var body: some View {
        PageHost(clear: true) {
            DayPage(date: store.date, live: true)
                .environmentObject(vault)
                .environmentObject(store)
                .environmentObject(shell)
                .environmentObject(archive)
        }
        // Лента превью и строка вложений — одна, у низа экрана, над всеми
        // страницами (P544): не листается с днём, а с клавиатурой едет вверх.
        // Взятое из ленты превью — поверх всего (P545).
        .overlay { StripGhostLayer() }
        .onChange(of: shell.goHome) { _, want in
            guard want else { return }
            shell.goHome = false
            let days = Calendar.current.dateComponents([.day], from: store.date,
                                                       to: DayStore.today()).day ?? 0
            guard days != 0 else { return }
            hideKeyboard()
            shell.turn(days, store)
        }
        // Ушли со вкладки в режиме изменений — режим выключается сам, а не
        // остаётся включённым за спиной (P330).
        .onChange(of: shell.tab) { _, now in
            for t in Shell.Tab.allCases where t != now { store.setEditing(t, false) }
        }
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
    /// Куда прокручен лист — для боков страницы (P737).
    @StateObject private var scroll = PageScroll()

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
                    // Дымка — та же бумага, что у шапки (P735): прежде она
                    // была ровного цвета, и под шапкой проступала полоса.
                    background
                        .mask(LinearGradient(colors: [.black, .black.opacity(0)],
                                             startPoint: .top, endPoint: .bottom))
                        // Короче прежних 22 точек: слово «План» вверху
                        // страницы больше не тонет в дымке (P441).
                        .frame(height: 14)
                        .allowsHitTesting(false)
                }
                .overlay(alignment: .top) { if !Shell.appStoreShots { steps } }
                // Черты между шапкой и страницей больше нет (P434, прежде
                // P250): шапка — продолжение листа.
        }
        // Бумага, бока и обводка листа — на `DayPage.under` ниже страницы
        // (P850): нижние скругления листа уходят под нижнюю строку, и в покое
        // их не видно — прежде по ним проходил затёртый край страницы и
        // выдавал подделку. Всё, что на странице, — на прежних местах.
        // Затёртые бока — на всю страницу разом, без шва под шапкой (P735).
        .overlay(alignment: .top) {
            GeometryReader { g in
                PageSides(aged: Ru.isPast(date), seed: PageTexture.seed(date), scroll: scroll)
                    .frame(height: g.size.height + DayPage.under)
                    .clipShape(DayPage.folder)
            }
            .allowsHitTesting(false)
        }
        // Лист «Дня» — карточка с корешком (P797): бумага по контуру карточки
        // картотеки, с чёткой обводкой.
        .background(alignment: .top) {
            GeometryReader { g in
                background
                    .frame(height: g.size.height + DayPage.under)
                    .clipShape(DayPage.folder)
            }
        }
        // Край листа — чёткой линией (P802): у сегодняшнего фактуры нет, и
        // без линии глаз не видел, где кончается лист.
        .overlay(alignment: .top) {
            GeometryReader { g in
                DayPage.folder.stroke(DayPage.edge, lineWidth: 1)
                    .frame(height: g.size.height + DayPage.under)
            }
            .allowsHitTesting(false)
        }
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

    /// Шапка дня: корешок листа с именем дня и датой (P793, P797, P802).
    private var heading: some View {
        VStack(spacing: 2) {
            // Строка задана ростом жёстко, чтобы шапка была одной высоты на
            // любой странице (P113).
            // Корешок — тот же контур листа, что у карточек картотеки (P797):
            // имя дня и дата в нём, слева. Стрелок ‹ › больше нет (P802):
            // день меняют тягой за край; справа от корешка ничего своего —
            // видно то, что под листом (P849).
            HStack(spacing: 0) {
                titleMenu
                    .padding(.leading, 14)
                    .padding(.top, 4)
                    .frame(height: DayPage.headLine + 8)
                Spacer(minLength: 6)
            }
            .frame(height: DayPage.headLine + 8)
        }
        .padding(.leading, 8)
        .padding(.trailing, Corner.size + 14)
        // Верх поднят (P434): над шапкой воздуха меньше.
        .padding(.top, 2)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
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
                VStack(alignment: .leading, spacing: 0) {
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

    /// Контур листа «Дня» (P797): корешок во всю высоту шапки, шире, чем у
    /// карточек, — в нём имя дня и дата.
    // Плечо справа от корешка — на 8 точек выше (P853: щель была широка).
    static let folder = FolderShape(tabHeight: headLine + 6, tabShare: 0.56, roundBottom: true, soft: true)
    /// Насколько лист продолжается ниже страницы — под нижнюю строку (P850).
    /// Ещё на высоту полоски «Сегодня» (P907): когда лист уходит вверх,
    /// надпись «Сегодня» с датой едет на этом чистом поле под шагами и «＋»,
    /// а не поверх них.
    static let under: CGFloat = 20 + FollowRibbon.peekTop

    /// Линия края листа и корешков позади (P802).
    static let edge = Color(light: 0xB8A67C, dark: 0x5A4E33)

    /// Высота строки заголовка. Одна на всех страницах: шапка не должна
    /// менять рост от того, горит стрелка или нет (P113).
    /// Выше прежних 31: стрелки на 50% крупнее (P425).
    static let headLine: CGFloat = 38

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
                     strip: AnyView(AttachBar(live: live)),
                     onPull: { [shell, store] dir in
                         // Дотянули до порога и отпустили — лента картотеки
                         // открыта (P769, P777): доезжает, пока вчера не встанет
                         // над нижней строкой, а завтра — под строкой поиска.
                         // У прошедшего дня и вверх, и вниз — картотека на его
                         // месте (P826, вместо «вверх — сегодня» P801): снизу
                         // записанные дни после него. В сегодня — повторное
                         // касание «Дневника».
                         let ribbon = shell.ribbon
                         guard shell.screen == .today, shell.movingTask == nil, shell.pulling else {
                             ribbon.glide(to: 0) { shell.go(.pullBack); ribbon.release() }
                             return
                         }
                         hideKeyboard()
                         // Толчка нет: он был на пороге (P800; прежде
                         // второй — по отпусканию, два на одно движение).
                         // Сначала ход, раздел — когда лента встала (P828):
                         // смена раздела в миг отпускания перестраивала весь
                         // экран, ход на это время вставал и потом догонял
                         // прыжком (видео автора к 251). Запись дня — тоже
                         // после хода: она шла посреди него.
                         ribbon.opened()
                         // Не сегодняшний день (P834, P875) — сразу в свою
                         // карточку: лист, где его отпустили, уменьшается к
                         // краю, куда его тянули, и тает, а лента в ту же
                         // меру доезжает до его карточки (P877, автор: «чтобы
                         // карточка не уходила за край и растворялась, а
                         // уменьшалась и вставала в своё гнездо»).
                         if !store.isToday {
                             shell.go(.fold(card: Vault.stamp(store.date),
                                            store.isFuture ? .future : .past, swipe: nil))
                             ribbon.release()
                             store.prune()
                             DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                                 store.save()
                             }
                             return
                         }
                         ribbon.glide(to: ribbon.restY(dir)) {
                             shell.go(.released)
                             ribbon.release()
                             // Остаток движения пальца ленту дальше не
                             // катит (P892): встала на вчера или завтра.
                             ribbon.quench()
                             store.prune()
                             // Опись перечитывается, когда лента закроется
                             // (P797): перечитанная сразу после открытия, она
                             // меняла высоту карточек над днём.
                             DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                 store.save()
                             }
                         }
                     },
                     onPullMove: { [shell, store] amount, dir in
                         guard shell.screen == .today, shell.movingTask == nil else { return }
                         let ribbon = shell.ribbon
                         if dir == 0 {
                             // Не дотянули или вернули палец — мягко назад.
                             guard shell.pulling else { return }
                             ribbon.glide(to: 0) {
                                 shell.go(.pullBack)
                                 ribbon.release()
                             }
                             return
                         }
                         if !shell.pulling {
                             // Лента ещё не стоит у дня — ставим и ждём
                             // следующего движения пальца.
                             guard ribbon.begin() else { return }
                             shell.go(.pull(Deck.Side(dir), today: store.isToday))
                         } else if shell.fileFrom != dir {
                             shell.go(.pull(Deck.Side(dir), today: store.isToday))
                         }
                         // Лента и день — одной прокруткой: место дня ровно
                         // под днём, карточки вплотную к его краю.
                         ribbon.pull(amount * CGFloat(dir))
                     }) {
                PlanView()
            } diary: {
                DiaryView()
            }
            .environment(\.pageScroll, scroll)
        } else {
            SideDay(date: date)
        }
    }
}

/// Куда прокручен лист дня (P737): бока страницы едут вместе с ним.
/// Отдельная коробочка — при прокрутке перерисовываются только бока, а не
/// вся страница.
final class PageScroll: ObservableObject {
    @Published var y: CGFloat = 0
}

private struct PageScrollKey: EnvironmentKey {
    static let defaultValue: PageScroll? = nil
}

extension EnvironmentValues {
    var pageScroll: PageScroll? {
        get { self[PageScrollKey.self] }
        set { self[PageScrollKey.self] = newValue }
    }
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
                let tab = into
                // Снимок с камеры приложения — ещё и в «Фото» iPhone, в полном
                // размере (P903, автор: «класть и в галерею»): прежде
                // единственным экземпляром был сжатый снимок в архиве. «Фото»
                // не разрешили — в просмотре снимка остаётся кнопка «В Фото».
                PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                    let allowed = status == .authorized || status == .limited
                    if allowed {
                        PHPhotoLibrary.shared().performChanges {
                            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data, options: nil)
                        }
                    }
                    DispatchQueue.main.async {
                        if store.addPhoto(data, to: tab, camera: !allowed) {
                            shell.say(T("Снимок положен в папку «", "Photo saved to the “") + vault.name(.photos) + T("»", "” folder"))
                        } else if store.keepForLater(data, kind: .photos, name: "", tab: tab) {
                            // Не лёг в папку — остаётся у приложения и дойдёт сам (P904).
                            shell.say(T("Снимок пока не лёг в папку — приложение хранит его и доложит само",
                                        "The photo has not reached your folder yet — the app is keeping it and will add it"))
                        } else if allowed {
                            shell.say(T("В папку снимок не лёг — он есть в «Фото» iPhone",
                                        "The photo did not reach your folder — it is in iPhone Photos"))
                        } else {
                            shell.say(T("Снимок не сохранился", "The photo was not saved"))
                        }
                    }
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
        guard let data = try? Data(contentsOf: url), !data.isEmpty
        else { return shell.say(T("Запись не сохранилась.", "The recording was not saved.")) }
        let name = Vault.moment(store.date) + ".m4a"
        guard store.addAttachment(data, to: .audio, name: name, tab: into) else {
            // Не лёг в папку — голос остаётся у приложения и дойдёт сам (P904).
            return shell.say(store.keepForLater(data, kind: .audio, name: name, tab: into)
                ? T("Голос пока не лёг в папку — приложение хранит его и доложит само",
                    "The voice note has not reached your folder yet — the app is keeping it and will add it")
                : T("Запись не сохранилась.", "The recording was not saved."))
        }
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
                if store.writePoint(GeoPoint(title: "", at: location.coordinate), to: tab) {
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

