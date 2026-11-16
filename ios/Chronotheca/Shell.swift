import SwiftUI

/// Что сейчас на экране и что поверх него.
///
/// Отдельно от данных: здесь нет ничего, что стоило бы записать в файл.
/// Закроется приложение — потеряется только то, на какой вкладке человек был,
/// и это не потеря.
final class Shell: ObservableObject {

    /// Разделы внизу: сегодня, календарь, карта, поиск (P239).
    enum Screen { case today, calendar, map, search }


    enum Tab: String, CaseIterable, Identifiable {
        case plan = "План"
        case diary = "Дневник"
        var id: String { rawValue }

        /// Чей это файл в папке записей — для корзины (P300).
        var vaultFolder: Vault.Folder { self == .diary ? .diary : .planner }
    }

    @Published var screen: Screen = .today

    /// Что-то несут пальцем (P799) — разделы вбок не листаются.
    @Published var holding = false
    @Published var tab: Tab = .plan

    /// Над каким делом плана несут снимок или точку из дневника или из
    /// полоски (P409): дело обведено синим, под ним расступается место.
    struct PlanHover: Equatable {
        let id: UUID
        let photo: Bool
    }
    @Published var planHover: PlanHover?
    /// Событие Календаря, над которым несут вложение из записи или снизу
    /// страницы, — оно подсвечивается, как дело (P651).
    @Published var eventHover: String?

    /// Снимки для сборки: облачко «…помнишь?» не показывается (P408).
    @Published var hideCloud = false

    /// Снимок «А вот когда-то…» для App Store: листок облачка открыт (P530).
    /// Счётчик, а не да/нет: экран для снимка ставится трижды, и записи к
    /// первому разу могут быть ещё не прочитаны.
    @Published var previewRemember = 0

    /// Снимки для App Store (P530): без стрелок шага над страницей — на
    /// дневнике они ложатся на строку плана.
    static let appStoreShots = Vault.isPreview
        && ProcessInfo.processInfo.environment["CHRONOTHECA_APPSTORE"] == "1"

    /// Листки и окна поверх «Дня» (P963): своё состояние — открытие
    /// настроек, недели, окна «Время» или снимка не пересчитывает ни
    /// «День», ни картотеку; смотрит его сама оболочка экрана.
    let overlays = Overlays()

    /// Что на карте (P932): своё состояние — его смотрит одна карта, и
    /// смена спутника или списка мест не пересчитывает «День».
    let map = MapState()

    /// Открыть карту на точке из текста.
    func showPoint(_ point: GeoPoint) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        map.focus = point
        screen = .map
    }

    /// Только для снимков: показать вместо открытой страницы ту же страницу,
    /// нарисованную соседским способом. Так две росписи можно сличить
    /// пиксель в пиксель, а не рассуждать о них по памяти.
    @Published var probingSide = false

    /// Просьба вернуться на сегодняшний день.
    /// Поднимается кнопкой «Сегодня» внизу; выполняет её сама книга.
    @Published var goHome = false

    /// Просьба убрать открытый день в корзину — спрашивает оболочка (P295).
    @Published var trashAsk = false

    /// Кнопка над клавиатурой попросила открыть фото, голос или файлы —
    /// исполняет полоска открытой страницы (P279).
    @Published var keyboardAsk: KeyboardBar.Ask?
    /// Просьба странице встать на план или на дневник (P424): после
    /// перелистывания и из календаря.
    @Published var landing = 0
    var landOnDiary = false

    /// Перелистнуть день — пальцем или стрелкой шапки (P424, P441, P443).
    /// Больше половины окна занимает дневник — новая страница на заголовке
    /// «Дневник», и назад, и вперёд; иначе — на плане. У будущего дня
    /// дневника нет — он на плане сам (`diaryOpen`).
    func turn(_ step: Int, _ store: DayStore) {
        landOnDiary = lookingAtDiary
        landing += 1
        store.move(by: step)
    }
    /// Открытая страница сейчас больше дневник, чем план (P424).
    var lookingAtDiary = false
    /// Где верх нижней строки разделов на экране — по нему листок настроек
    /// кончается над ней (P424).
    @Published var barTop: CGFloat = 0

    /// Сколько раз приложение открывали заново — при запуске и после долгой
    /// паузы. Меняется — страница встаёт на самый верх (P346; к концу
    /// записи она больше не едет, P607).
    @Published var freshStart = 0

    /// Вернулись после долгой паузы: всё открытое поверх убирается, на
    /// экране «Сегодня», вкладка — та, что выбрана в настройках (P346).
    /// Следующая смена экрана — сразу, без хода плашки (P583): виджет,
    /// напоминание, возвращение после паузы. Человек должен сразу увидеть
    /// «День», а не прежний экран, на который потом наезжает плашка.
    var instant = false

    func startOver(_ store: DayStore) {
        if screen != .today { instant = true }
        overlays.roller = nil
        overlays.openedPhoto = nil
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            overlays.showingSettings = false
            overlays.settingsPull = nil
            screen = .today
        }
        tab = .plan
        if !store.isToday { store.go(to: DayStore.today()) }
        freshStart += 1
    }

    /// Где закрыли приложение: экран, вкладка, день и какое было «сегодня»
    /// (P686). Открываясь вновь — после запуска или фона, — приложение
    /// встаёт там же; если «сегодня» сменилось, то на «День» сегодняшний.
    func rememberLeft(_ store: DayStore) {
        let d = UserDefaults.standard
        d.set(["today", "calendar", "map", "search"][[Screen.today, .calendar, .map, .search].firstIndex(of: screen) ?? 0],
              forKey: "left.screen")
        d.set(tab.rawValue, forKey: "left.tab")
        d.set(Vault.stamp(store.date), forKey: "left.day")
        d.set(Vault.stamp(DayStore.today()), forKey: "left.today")
    }

    /// Сутки сменились и «День» уже сегодняшний: больше не новые (P711).
    func noteToday() {
        UserDefaults.standard.set(Vault.stamp(DayStore.today()), forKey: "left.today")
    }

    /// Новые сутки с тех пор, как закрыли? Нет сведений — нет.
    func newDaySinceLeft() -> Bool {
        guard let t = UserDefaults.standard.string(forKey: "left.today") else { return false }
        return t != Vault.stamp(DayStore.today())
    }

    /// Холодный запуск: встать там, где закрыли (P686).
    func restoreLeft(_ store: DayStore) {
        guard !Vault.isPreview, !newDaySinceLeft() else { return }
        let d = UserDefaults.standard
        if let raw = d.string(forKey: "left.tab"), let t = Tab(rawValue: raw) { tab = t }
        if let st = d.string(forKey: "left.day"), let day = Vault.date(from: st), day != store.date {
            store.go(to: day)
        }
        let target: Screen
        switch d.string(forKey: "left.screen") {
        case "calendar": target = .calendar
        case "map": target = .map
        case "search": target = .search
        default: target = .today
        }
        if target != .today {
            instant = true
            screen = target
            // Лента — не плашка в стопке, а продолжение дня (P777).
            go(.place(open: target == .search))
        }
    }

    /// Просьба календарю вернуться к нынешнему месяцу или году. Поднимается из меню календаря; выполняет сам календарь.
    @Published var calendarHome = false

    /// Лента картотеки (P777): прошлое, место дня, будущее — одной
    /// прокруткой. Сама не публикуется: её сдвиги смотрит только день.
    let ribbon = Ribbon()
    /// Что на экране в разделе «День» — одним значением (P921, `Deck`).
    /// Лежит у ленты: ступени посадки смотрят её виды. Меняет только
    /// `go(_:)`; тянут ли лист, открыта ли картотека, с какой стороны,
    /// садится ли карточка — всё читается из него (P928).
    var deck: Deck { ribbon.deck }

    /// Где искать: везде, только в дневнике или только в плане.
    enum Scope { case all, diary, plan }

    /// Строка поиска и где искать живут здесь, а не в самом поиске: их
    /// меняет и меню поиска, а оно лежит поверх всего приложения.
    @Published var query = ""
    /// Насколько страница «Дня» поднята над клавиатурой поиска (P931):
    /// считает картотека (`SearchView.pageLift`), поднимает оболочка.
    @Published var searchLift: CGFloat = 0
    @Published var scope: Scope = .all

    /// Что искать: всё или только дни со снимками, видео, голосом,
    /// файлами, местами (P249).
    enum Find: String, CaseIterable { case all = "Всё", photo = "Снимки", video = "Видео",
                                          audio = "Голос", file = "Файлы", place = "Места"
        var title: String {
            switch self {
            case .all: return T("Всё", "Everything")
            case .photo: return T("Снимки", "Photos")
            case .video: return T("Видео", "Videos")
            case .audio: return T("Голос", "Voice")
            case .file: return T("Файлы", "Files")
            case .place: return T("Места", "Places")
            }
        }
    }
    @Published var find: Find = .all

    /// Короткие сообщения человеку (P933): своё состояние — показ и уход
    /// сообщения не пересчитывают экран.
    let notices = Notices()

    /// Сказать человеку, почему ничего не произошло.
    func say(_ text: String, for seconds: Double = 2.3) {
        notices.say(text, for: seconds)
    }

    /// Открыть экран, названный в переменной окружения, — для снимков.
    ///
    /// Нужно, чтобы у каждой сборки был снимок каждого экрана, а не одного.
    /// Иначе про интерфейс приходится рассуждать по памяти, а память врёт.
    ///
    /// Ставится ещё дважды, через полторы и через четыре секунды: с 101-й
    /// снимки календаря, поиска, меню, настроек и соседних дней выходили
    /// страницей «Сегодня» — что-то при запуске возвращало приложение на
    /// неё раньше, чем снималось (P448). Повтор делает снимки надёжными;
    /// всё, что он ставит, — те же значения, второй раз ничего не сдвигает.
    func openRequestedScreen(_ store: DayStore) {
        guard Vault.isPreview,
              let name = ProcessInfo.processInfo.environment["CHRONOTHECA_SCREEN"]
        else { return }
        applyScreen(name, store)
        for delay in [1.5, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.applyScreen(name, store)
            }
        }
    }

    private func applyScreen(_ name: String, _ store: DayStore) {
        let cal = Calendar.current
        let today = DayStore.today()
        func day(_ k: Int) -> Date { cal.date(byAdding: .day, value: k, to: today) ?? today }
        // Облачко «…помнишь?» — только на своих снимках: на снимке плана
        // его нет, иначе открытая страница не сойдётся с соседской
        // (P114, P408).
        hideCloud = !["remember", "diary"].contains(name)
        switch name {
        case "diary":     tab = .diary
        case "calendar":  CalendarView.previewStart = day(-7); screen = .calendar
        case "search", "searchdeep": screen = .search
        case "settings":  overlays.showingSettings = true
        case "map":       screen = .map
        case "mappoint":  screen = .map; map.previewPoint += 1
        // Окно «Время» (P874) — у первого дела с временем, иначе у первого.
        case "roller":
            let first = store.tasks.first { $0.time != nil } ?? store.tasks.first
            if let first, overlays.roller?.id != first.id { overlays.roller = .init(id: first.id) }
        case "remember":  tab = .diary; previewRemember += 1
        // Дни — от сегодняшнего, а не шагом: повтор не уводит дальше.
        case "past":      if store.date != day(-1) { store.go(to: day(-1)) }
        case "editing":
            if store.date != day(-1) { store.go(to: day(-1)) }
            store.setEditing(.plan, true)
        case "future":
            if store.date != day(1) { store.go(to: day(1)) }
            tab = .diary
        case "side":      probingSide = true
        case "hint":      Hints.shared.showFirstForPreview()
        case "filefuture":
            // Картотека будущего (P771, P773): вместо снимка «Списка»
            // календаря, которого больше нет.
            screen = .search
        default: break
        }
        // Для снимков — сразу, без хода (P799: разделы — лента вбок).
        instant = true
        go(.place(open: screen == .search, name == "filefuture" ? .future : .past))
    }

}

/// Замер замираний экрана для проверок (P573): только когда приложение
/// запустила проверка и назвала файл. Раз в 50 мс из стороннего потока
/// спрашиваем главный: ответил позже чем через 250 мс — экран стоял;
/// записываем, сколько и на каком разделе. Робот проверок сам медлителен
/// на больших экранах — по этому файлу видно, что медлит именно
/// приложение.
enum LagWatch {
    private static var screen = "?"
    static func note(_ now: Shell.Screen) { screen = "\(now)" }

    static func start() {
        guard Vault.isUITest,
              let path = ProcessInfo.processInfo.environment["CHRONOTHECA_TRACE"], !path.isEmpty
        else { return }
        let url = URL(fileURLWithPath: path)
        let thread = Thread {
            while true {
                let asked = Date()
                let answered = DispatchSemaphore(value: 0)
                var place = "?"
                DispatchQueue.main.async {
                    place = screen
                    answered.signal()
                }
                answered.wait()
                let stood = Date().timeIntervalSince(asked)
                if stood > 0.25 {
                    let line = String(format: "%@ экран стоял %.2f с (%@)\n",
                                      ISO8601DateFormatter().string(from: asked), stood, place)
                    if let handle = try? FileHandle(forWritingTo: url) {
                        handle.seekToEndOfFile()
                        handle.write(Data(line.utf8))
                        try? handle.close()
                    } else {
                        try? line.write(to: url, atomically: true, encoding: .utf8)
                    }
                }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
        thread.start()
    }
}

/// Что-то несут пальцем — дело, событие, снимок (P799): пока несут, разделы
/// не листаются вбок. Сообщают план и запись; слушает оболочка.
enum Hold {
    static var report: ((Bool) -> Void)?
}

/// След жестов для проверок движения (P787): только когда приложение
/// запустила проверка и назвала файл. По нему видно, на каком шаге свайп
/// или порог ленты отказали, а не гадать.
enum Trace {
    private static var last = ""

    static func note(_ line: String) {
        guard Vault.isUITest,
              let path = ProcessInfo.processInfo.environment["CHRONOTHECA_TRACE"], !path.isEmpty,
              line != last
        else { return }
        last = line
        let url = URL(fileURLWithPath: path)
        let text = String(format: "%.2f ", Date().timeIntervalSince(LaunchClock.start)) + line + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// Сколько шёл запуск и открывались разделы — по шагам (P581).
///
/// Видно в «Проверке скорости» (долгое нажатие на «Версия» в настройках)
/// и пишется в итог проверок движения: по шагам видно, на чём стоит
/// экран, а не только сколько всего.
enum LaunchClock {
    /// Начало отсчёта — создание приложения.
    static let start = Date()
    private(set) static var lines: [String] = []

    static func step(_ name: String) {
        let line = String(format: "%@: %.2f с", name, Date().timeIntervalSince(start))
        record(line)
    }

    /// Раздел открыт: от касания до первого такта после смены экрана.
    static func opened(_ name: String, since tap: Date) {
        DispatchQueue.main.async {
            record(String(format: "%@: %.2f с", name, Date().timeIntervalSince(tap)))
        }
    }

    private static func record(_ line: String) {
        lines.append(line)
        if lines.count > 40 { lines.removeFirst(lines.count - 40) }
        guard Vault.isUITest,
              let path = ProcessInfo.processInfo.environment["CHRONOTHECA_TRACE"], !path.isEmpty
        else { return }
        let url = URL(fileURLWithPath: path)
        let text = "шаг " + line + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// Где вид на экране — для переноса пальцем (P833). Свайп вбок между
/// разделами двигает весь «День» по горизонтали каждый кадр; прежде каждое
/// дело, полоска, точка и заголовок на каждом кадре заново записывали своё
/// место, а точки ещё и перерисовывались — свайп шёл двадцатью кадрами в
/// секунду вместо шестидесяти («дискретность», видео автора к 252). Теперь
/// место записывается, только когда меняется высота или размер: по
/// горизонтали после свайпа всё встаёт туда же, где было.
extension View {
    func trackFrame(appear: @escaping (CGRect) -> Void,
                    change: @escaping (CGRect) -> Void,
                    gone: @escaping () -> Void = {}) -> some View {
        modifier(FrameTrack(appear: appear, change: change, gone: gone))
    }
}

private struct FrameTrack: ViewModifier {
    let appear: (CGRect) -> Void
    let change: (CGRect) -> Void
    let gone: () -> Void
    final class Last { var rect: CGRect? }
    @State private var last = Last()

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { proxy in
                proxy.frame(in: .global)
            } action: { now in
                guard let before = last.rect else {
                    last.rect = now
                    appear(now)
                    return
                }
                guard abs(before.minY - now.minY) > 0.5 || before.size != now.size else { return }
                last.rect = now
                change(now)
            }
            .onDisappear {
                last.rect = nil
                gone()
            }
    }
}
