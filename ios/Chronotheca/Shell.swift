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

    /// Дело, чья шторка «Подробности» открыта.
    @Published var drawer: UUID?
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
    /// Снимок плашки точки на карте (P813): растёт — карта открывает плашку.
    @Published var previewMapPoint = 0

    /// Снимки для App Store (P530): без стрелок шага над страницей — на
    /// дневнике они ложатся на строку плана.
    static let appStoreShots = Vault.isPreview
        && ProcessInfo.processInfo.environment["CHRONOTHECA_APPSTORE"] == "1"

    /// Дело, которому выбирают время, напоминание и повтор (P872).
    @Published var roller: Roller?

    struct Roller: Identifiable {
        let id: UUID
    }

    /// Снимок, открытый во весь экран: с какой вкладки и который по счёту.
    struct OpenedPhoto: Identifiable {
        let tab: Tab
        let index: Int
        /// Снимок, стоящий посреди страницы, а не в полоске: открывается
        /// прямо по месту, без «убрать» (P205).
        var url: URL? = nil
        /// Строка-ссылка снимка из текста: по ней он возвращается в
        /// полоску (P216).
        var link: String? = nil
        var id: String { tab.rawValue + String(index) + (url?.path ?? "") }
    }
    @Published var openedPhoto: OpenedPhoto?

    /// Точка, на которой открыть карту: её нажали в тексте дня (P213).
    @Published var mapFocus: GeoPoint?
    /// Точка, выбранная сейчас на карте. По ней работают «в навигатор» и
    /// «скопировать» — и в полоске карты, и в её меню (P219).
    @Published var mapPoint: GeoPoint?
    /// Карта снимком со спутника, а не схемой (P222). Выбор запоминается
    /// (P419): открыли карту снова — она такая, какой её оставили.
    @Published var mapSatellite = UserDefaults.standard.bool(forKey: "map.satellite") {
        didSet { UserDefaults.standard.set(mapSatellite, forKey: "map.satellite") }
    }
    /// Показать приветствие первого запуска для пробы (P452).
    @Published var trialWelcome = false
    /// Карта показывает записи — дни с точками, превью и числом, — а не
    /// свои места (P451). Выбор запоминается, как спутник.
    @Published var mapEntries = UserDefaults.standard.bool(forKey: "map.entries") {
        didSet { UserDefaults.standard.set(mapEntries, forKey: "map.entries") }
    }

    /// Открыть карту на точке из текста.
    func showPoint(_ point: GeoPoint) {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        mapFocus = point
        screen = .map
    }
    @Published var showingSettings = false
    /// Дело отвели вправо — листок «На другой день» (P383, P387).
    @Published var movingTask: MovingTask?
    /// Бумажку тянут за уголок: сколько её ещё за краем, 1 — вся, 0 — на
    /// месте. Пусто — никто не тянет (P233).
    @Published var settingsPull: CGFloat?

    /// Вытянуть листок за уголок до конца: он стоит за краем экрана так,
    /// что наружу торчит только его угол, и съезжает вниз целиком (P237).
    func pullOut() {
        // Толчок — сразу по нажатию, не когда бумажка уже легла на место:
        // рука должна почувствовать отклик в момент касания (P320).
        Feel.paper()
        let built = showingSettings
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            showingSettings = true
            settingsPull = settingsPull ?? 1
        }
        if built {
            // Листок уже тянули пальцем — он построен, ехать сразу.
            DispatchQueue.main.async { withAnimation(.pull) { self.settingsPull = nil } }
        } else {
            // Ход — когда листок построен (P669): прежде он начинался сразу,
            // первые кадры уходили на постройку листка, и он выпрыгивал
            // рывком. Подстраховка — если листок не скажет, что появился.
            pullPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.startPull() }
        }
    }

    /// Листок ждёт своего первого кадра, чтобы поехать (P669).
    private var pullPending = false

    /// Листок появился — ехать.
    func startPull() {
        guard pullPending else { return }
        pullPending = false
        DispatchQueue.main.async { withAnimation(.pull) { self.settingsPull = nil } }
    }

    /// Задвинуть листок обратно: он уезжает вверх, пока снова не останется
    /// один уголок.
    func tuckIn() {
        // Толчок — в момент нажатия, как при выезде, а не когда листок уже
        // ушёл (P515).
        Feel.paper()
        withAnimation(.tuck) { settingsPull = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                self.showingSettings = false
                self.settingsPull = nil
            }
        }
    }
    @Published var showingFile = false
    /// Неделя одним взглядом (P466).
    @Published var showingWeek = false
    @Published var picking = false

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
        drawer = nil
        roller = nil
        openedPhoto = nil
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            showingSettings = false
            settingsPull = nil
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
            ribbonOpen = target == .search
        }
    }

    /// Просьба календарю вернуться к нынешнему месяцу или году. Поднимается из меню календаря; выполняет сам календарь.
    @Published var calendarHome = false

    /// Картотеку вытянули из «Дня» (P769): 1 — тянули вниз за верх
    /// страницы (прошлое), -1 — вверх за низ (будущее), 0 — открыли иначе.
    /// По нему лента встаёт в покой: вчера над нижней строкой или завтра под
    /// строкой поиска.
    @Published var fileFrom = 0
    /// Лента картотеки (P777): прошлое, место дня, будущее — одной
    /// прокруткой. Сама не публикуется: её сдвиги смотрит только день.
    let ribbon = Ribbon()
    /// День тянут за край — лента видна под ним и едет вместе с ним.
    @Published var pulling = false
    /// Лента открыта — день стоит в ней на своём месте, пока не вернутся.
    @Published var ribbonOpen = false {
        didSet { if !ribbonOpen && pastCard { pastCard = false } }
    }
    /// Прошедший день отодвинули в картотеку, и она встала (P834): в ленте
    /// на его месте — его маленькая карточка, а не открытый лист. Открыть
    /// снова — касанием по карточке.
    @Published var pastCard = false {
        didSet { if !pastCard { ribbon.frozen = false } }
    }
    /// Лента на экране: тянут или открыта.
    var ribbonLive: Bool { pulling || ribbonOpen }

    /// Где искать: везде, только в дневнике или только в плане.
    enum Scope { case all, diary, plan }

    /// Строка поиска и где искать живут здесь, а не в самом поиске: их
    /// меняет и меню поиска, а оно лежит поверх всего приложения.
    @Published var query = ""
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

    /// Просьбы к карте из её меню: показать все места, открыть список мест.
    @Published var mapShowAll = 0
    /// Второе нажатие на «Карту» — карта к тому месту, где человек сейчас
    /// (P577).
    @Published var mapHome = 0
    @Published var mapList = false

    @Published var notice: String?
    private var hiding: DispatchWorkItem?

    /// Сказать человеку, почему ничего не произошло.
    ///
    /// Молчаливый отказ — худшее, что может сделать приложение: человек решает,
    /// что сломалось оно, хотя оно просто не даёт нарушить правило.
    func say(_ text: String, for seconds: Double = 2.3) {
        hiding?.cancel()
        withAnimation { notice = text }
        let item = DispatchWorkItem { [weak self] in
            withAnimation { self?.notice = nil }
        }
        hiding = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
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
        case "settings":  showingSettings = true
        case "map":       screen = .map
        case "mappoint":  screen = .map; previewMapPoint += 1
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
            fileFrom = -1
            screen = .search
        default: break
        }
        // Для снимков — сразу, без хода (P799: разделы — лента вбок).
        instant = true
        ribbonOpen = screen == .search
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
