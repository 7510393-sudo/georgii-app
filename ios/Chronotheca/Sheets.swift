import EventKit
import SwiftUI

// MARK: - Меню страницы

/// Три точки: жёлтая бумажка, приклеенная к верхнему правому углу.
///
/// Точки есть на каждом экране, а бумажка у каждого своя: на странице дня —
/// действия с днём, на календаре и в поиске — то, чем управляют там.
/// Включать с календаря режим изменений дня нельзя: он управлял бы чужим
/// экраном (решения P169, P188).
struct MenuSticker: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var vault: Vault

    /// Вид календаря — чтобы звать домой к месяцу или к году.
    @AppStorage("calendar.kind") private var calendarKind = CalendarView.Kind.month.rawValue

    var body: some View {
        switch shell.screen {
        case .today:    dayMenu
        case .calendar: calendarMenu
        case .map:      mapMenu
        case .search:   searchMenu
        }
    }

    /// Меню карты: строки повторяют кнопки полоски — для тех, кто ищет
    /// действие в меню, а не внизу (P219).
    private var mapMenu: some View {
        // Меню и настройки — на одной жёлтой бумаге (P465; прежде меню
        // было голубым, P434): меньше разных материалов на экране.
        Sticker(side: .trailing, title: T("Меню карты", "Map menu"),
                paper: Look.sticker, edge: Look.stickerEdge, close: close) {
            StickerItem(title: T("Открыть в навигаторе", "Open in navigation"),
                        note: shell.mapPoint == nil ? T("выберите точку", "choose a place") : "→") {
                close()
                guard let point = shell.mapPoint else {
                    return shell.say(T("Сначала выберите точку долгим нажатием на карту.", "First choose a place with a long press on the map."))
                }
                MapActions.navigate(point)
            }
            StickerItem(title: T("Скопировать координаты", "Copy coordinates"),
                        note: shell.mapPoint == nil ? T("выберите точку", "choose a place") : "→") {
                close()
                guard let point = shell.mapPoint else {
                    return shell.say(T("Сначала выберите точку долгим нажатием на карту.", "First choose a place with a long press on the map."))
                }
                MapActions.copy(point)
                shell.say(T("Скопировано: ", "Copied: ") + Geo.text(point.at))
            }
            StickerItem(title: T("Поделиться точкой", "Share place"),
                        note: shell.mapPoint == nil ? T("выберите точку", "choose a place") : "→") {
                close()
                guard let point = shell.mapPoint else {
                    return shell.say(T("Сначала выберите точку долгим нажатием на карту.", "First choose a place with a long press on the map."))
                }
                MapActions.share(point)
            }
            StickerItem(title: T("Схема / спутник", "Map / satellite"),
                        note: shell.mapSatellite ? T("спутник", "satellite") : T("схема", "map"),
                        active: shell.mapSatellite) {
                shell.mapSatellite.toggle()
                close()
            }
            StickerItem(title: T("Показать все мои места", "Show all my places")) {
                close()
                shell.mapShowAll += 1
            }
            StickerItem(title: T("Все места списком", "All places as a list")) {
                close()
                shell.mapList = true
            }
            StickerItem(title: T("Вернуться к странице дня", "Back to the day page")) {
                close()
                shell.screen = .today
            }
        }
    }

    private var dayMenu: some View {
        Sticker(side: .trailing, title: T("Меню страницы", "Page menu"),
                paper: Look.sticker, edge: Look.stickerEdge, close: close) {
            // Режима изменений нет совсем: всё — долгим нажатием, и
            // прошедший день правится так же, как сегодняшний (P362, P381).
            StickerItem(title: T("Показать файл этого дня", "Show this day’s file")) {
                close()
                shell.showingFile = true
            }
            StickerItem(title: T("Неделя одним взглядом", "The week at a glance")) {
                close()
                shell.showingWeek = true
            }
            StickerItem(title: T("Поделиться днём", "Share the day")) {
                close()
                // Текстом — план и запись; вложения остаются в папке (P249).
                Share.present([store.shareText()])
            }
            // PDF одного дня — та же книга, срок в один день (P296).
            StickerItem(title: T("PDF дня", "PDF of the day")) {
                close()
                let date = store.date
                let vault = vault
                store.save()
                DispatchQueue.global(qos: .userInitiated).async {
                    let url = PDFBook.make(.init(from: date, to: date), vault: vault)
                    DispatchQueue.main.async {
                        if let url { Share.present([url]) } else { shell.say(T("В этом дне пока пусто — PDF не из чего собрать.", "This day is still empty — nothing to make a PDF from.")) }
                    }
                }
            }
            // Корзина (P295, P300): уезжает в папку «Корзина», её можно
            // вернуть из настроек. План и дневник — одна страница (P408):
            // убирается весь день.
            StickerItem(title: T("Убрать день в корзину", "Move the day to the trash")) {
                close()
                shell.trashAsk = true
            }
        }
    }

    private var calendarMenu: some View {
        let year = calendarKind == CalendarView.Kind.year.rawValue
        return Sticker(side: .trailing, title: T("Меню календаря", "Calendar menu"),
                       paper: Look.sticker, edge: Look.stickerEdge, close: close) {
            StickerItem(title: year ? T("Вернуться к этому году", "Back to this year")
                                    : T("Вернуться к этому месяцу", "Back to this month")) {
                close()
                shell.calendarHome = true
            }
        }
    }

    /// Где искать. Выбранное отмечено, а не спрятано: все три строки стоят
    /// всегда, чтобы рука находила их на одном месте.
    private var searchMenu: some View {
        Sticker(side: .trailing, title: T("Меню поиска", "Search menu"),
                paper: Look.sticker, edge: Look.stickerEdge, close: close) {
            scopeItem(T("Искать везде", "Search everywhere"), .all)
            scopeItem(T("Только в дневнике", "Only in the diary"), .diary)
            scopeItem(T("Только в плане", "Only in the plan"), .plan)
            // Что искать — только дни, где есть это (P249).
            ForEach(Shell.Find.allCases, id: \.self) { kind in
                StickerItem(title: kind == .all ? T("Искать всё", "Find everything") : T("Только: ", "Only: ") + kind.title.lowercased(),
                            note: shell.find == kind ? "✓" : "", active: shell.find == kind) {
                    shell.find = kind
                    close()
                }
            }
            StickerItem(title: T("Очистить поиск", "Clear search")) {
                close()
                if shell.query.isEmpty {
                    shell.say(T("Строка поиска и так пуста.", "The search field is already empty."))
                } else {
                    shell.query = ""
                }
            }
        }
    }

    private func scopeItem(_ title: String, _ scope: Shell.Scope) -> some View {
        let on = shell.scope == scope
        return StickerItem(title: title, note: on ? "✓" : "", active: on) {
            shell.scope = scope
            close()
        }
    }

    private func close() {
        shell.tuckIn(settings: false)
    }
}

// MARK: - Настройки

/// Шестерёнка: голубая бумажка, приклеенная к верхнему левому углу.
///
/// Та же порода, что и меню страницы: рука узнаёт их одинаково, а цвет
/// говорит, к чему бумажка относится — к дню или ко всему приложению.
struct SettingsSticker: View {

    /// Высота листка: от верха до нижних разделов, за вычетом шапки листка.
    static var fullHeight: CGFloat {
        let window = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
        let insets = window?.safeAreaInsets ?? .zero
        return max(300, UIScreen.main.bounds.height - insets.top - insets.bottom - 66 - 52 - RootView.topBarHeight)
    }

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var shell: Shell
    @State private var askingRename = false
    @State private var askingTrial = false
    @ObservedObject private var hints = Hints.shared
    /// Где начинается прокрутка листка на экране (P424). Листок выезжает
    /// сдвигом картинки, а не места, — эта точка стоит, пока он едет.
    @State private var top: CGFloat = 0
    /// Листок встал на место: можно мерить (P513).
    @State private var settled = false

    /// Высота прокрутки: до верха нижней строки и на полторы точки ниже —
    /// рваный край строки закрыт, рамка открытого раздела видна (P424).
    private var height: CGFloat {
        guard top > 0, shell.barTop > top else { return Self.fullHeight }
        return max(300, shell.barTop + 1.5 - top)
    }

    /// Объём папки, посчитанный заранее (P486): пока листок открывался, объём
    /// дописывался в подпись «Резервной копии», и строки ниже съезжали.
    /// Теперь он известен до открытия — приложение считает его вскоре после
    /// запуска, а листок берёт готовое.
    static var cachedBytes: Int64?

    static func warm(_ root: URL?) {
        guard let root, cachedBytes == nil else { return }
        DispatchQueue.global(qos: .utility).async {
            let total = folderBytes(root)
            DispatchQueue.main.async { cachedBytes = total }
        }
    }

    static func folderBytes(_ root: URL) -> Int64 {
        var total: Int64 = 0
        let keys: Set<URLResourceKey> = [.fileAllocatedSizeKey, .isDirectoryKey]
        if let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys)) {
            for case let url as URL in walker {
                guard let values = try? url.resourceValues(forKeys: keys),
                      values.isDirectory != true else { continue }
                total += Int64(values.fileAllocatedSize ?? 0)
            }
        }
        return total
    }

    /// Ширина записки: шире прежних 330, но так, чтобы справа оставалась
    /// полоска страницы, — по ней видно, где человек остался (P383).
    static var width: CGFloat { min(360, UIScreen.main.bounds.width - 40) }

    var body: some View {
        Sticker(side: .leading, title: T("Настройки", "Settings"),
                paper: Look.sticker, edge: Look.stickerEdge, width: Self.width, close: close) {
          // Длинная бумажка прокручивается: разделов стало много (P249).
          ScrollView {
           // Ленивая стопка (P475): листок строился целиком — все девять
           // частей, с десятками переключателей, — ещё до того, как он
           // начинал выезжать; экран замирал на это время, а потом
           // дёргался. Теперь строится то, что видно.
           LazyVStack(spacing: 0) {
            // Вид — тетрадь на голубой записке (P367): кружки-выбор,
            // «Открыть ›», одна главная кнопка. Нажимается только кнопка.
            //
            // Язык — первым: на незнакомом языке остальное не прочитать
            // (P355). Подпись на обоих языках, чтобы её нашли с любого.
            languagePart
            entriesPart
            privacyPart
            dayPart
            lookPart
            attachPart
            mapPart
            aboutPart
            version
           }
          }
          // Листок — до нижней неподвижной строки (P291): прикрывает её
          // рваный край, но не значки и не рамку открытого раздела (P424).
          .frame(height: height)
          // Высота листка не должна меняться плавно, пока он едет (P477):
          // измеренный верх прокрутки приходил в самом начале выезда, высота
          // менялась пружиной, и вместе с ней дрожал и сам листок.
          .animation(nil, value: height)
          .background {
              // Верх прокрутки меряется, когда листок уже встал (P513): раньше
              // он читался на каждом кадре выезда, и высота прокрутки
              // менялась вместе с ним — отсюда рывок в середине движения.
              GeometryReader { g in
                  Color.clear
                      .onChange(of: settled) { _, now in
                          guard now else { return }
                          var still = Transaction()
                          still.disablesAnimations = true
                          withTransaction(still) { top = g.frame(in: .global).minY }
                      }
              }
          }
          .onAppear {
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { settled = true }
          }
        }
        .sheet(isPresented: $showingPDF) {
            PDFSheet(vault: vault, archive: archive)
        }
        .sheet(isPresented: $showingBackup, onDismiss: measureStorage) {
            BackupSheet().environmentObject(vault)
        }
        .sheet(isPresented: $showingImport, onDismiss: { archive.reload() }) {
            ImportSheet().environmentObject(vault).environmentObject(store)
        }
        .sheet(isPresented: $showingGoogleMaps) {
            GoogleMapsImportSheet().environmentObject(vault)
        }
        .sheet(isPresented: $showingTrash) {
            TrashSheet(vault: vault, save: { store.save() }) {
                store.load()
                archive.reload()
            }
        }
        .confirmationDialog(T("Пройти первый запуск?", "Try the first launch?"), isPresented: $askingTrial,
                            titleVisibility: .visible) {
            Button(T("Начать пробу", "Start the trial")) {
                close()
                shell.trialWelcome = true
            }
            Button(T("Отмена", "Cancel"), role: .cancel) { }
        } message: {
            Text(T("Приложение откроется как в первый раз: приветствие, образцы дней, подсказки. Всё это — в отдельной пробной папке; ваши записи останутся на месте и не изменятся. Вернуться к ним — здесь же, в настройках: «К своим».",
                   "The app opens as if for the first time: welcome, sample days, tips. All of it lives in a separate trial folder; your entries stay where they are, untouched. To return to them — here in the settings: “Back”."))
        }
        .confirmationDialog(T("Где хранить записи", "Where to keep entries"), isPresented: $choosingPlace,
                            titleVisibility: .visible) {
            // Папки самого приложения больше не предлагаем: iPhone стирает
            // её вместе с приложением (P366).
            Button(T("Выбрать папку…", "Choose a folder…")) {
                close()
                shell.picking = true
            }
            Button(T("Отмена", "Cancel"), role: .cancel) { }
        } message: {
            Text(T("В iCloud Drive записи будут и на iPad, и на Mac. На iPhone — «На iPhone», ", "In iCloud Drive your entries are on your iPad and Mac too. On the iPhone — “On My iPhone”, ")
                 + T("новая папка, «Открыть»: она переживёт удаление приложения, но живёт только на этом телефоне. ", "a new folder, “Open”: it outlives deleting the app but lives only on this phone. ")
                 + T("Записи, что уже есть, приложение предложит перенести.", "The app will offer to move the entries you already have."))
        }
        // Объём памяти считается, когда листок уже выехал (P475): ответ
        // менял строку и размер листка посреди движения — отсюда дёргание.
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { measureStorage() } }
    }

    @ViewBuilder private var languagePart: some View {
        // Заголовок — на языке приложения, как всё остальное (P380).
        NoteSection(title: T("Язык", "Language"))
        // Десять языков (P369) — списком: кружков столько не поместить.
        // Пока не выбран — язык телефона, если он у нас есть.
        NoteRow(title: T("Язык приложения", "App language")) {
            Menu {
                ForEach(Lang.all, id: \.code) { lang in
                    Button {
                        Lang.set(lang.code)
                        language = lang.code
                        KeyboardBar.relabel()
                    } label: {
                        if lang.code == Lang.code {
                            Label(lang.name, systemImage: "checkmark")
                        } else {
                            Text(lang.name)
                        }
                    }
                }
            } label: {
                Text(Lang.name + " ▾")
                    .font(Look.sans(13.5, weight: .semibold))
                    .modifier(Tag(main: true))
            }
        }
    }

    @ViewBuilder private var entriesPart: some View {
        NoteSection(title: T("Записи", "Entries"))
        // Порядок — от того, где лежат записи, к тому, как их взять с
        // собой (P428).
        place
        safety
        // Жмут — и весь архив переезжает, а не только то, что будет
        // написано дальше (P325).
        NoteRow(title: T("Перенести архив в другое место", "Move the archive elsewhere")) {
            NoteButton(title: T("Выбрать ›", "Choose ›")) { choosingPlace = true }
        }
        // «Вернуться к прежней папке» больше нет (P468): перенос забирает
        // записи с собой, и прежняя папка после него пуста — возврат туда
        // открывал пустой архив. Передумал — тот же «Перенести архив».
        // Резервная копия (P368): когда была, сколько, куда. Пора — кнопка
        // мигает красным «Пора сделать» (P428).
        NoteRow(title: T("Резервная копия", "Backup"), detail: Backup.detail(size: storageBytes),
                detailColor: Backup.healthy ? Look.inkSoft : .orange, pinned: true) {
            if Backup.healthy {
                NoteButton(title: T("Сделать", "Make"), main: true) { showingBackup = true }
            } else {
                DueButton(title: T("Пора сделать", "Time to make one")) { showingBackup = true }
            }
        }
        // Записи за срок одной книгой (P296).
        NoteRow(title: T("PDF за выбранный срок", "PDF for a period")) {
            NoteButton(title: T("Собрать ›", "Make ›")) { showingPDF = true }
        }
        // Перенос из других дневников — бесплатно всегда (M14, P378).
        NoteRow(title: T("Переход из другого приложения", "Switch from another app")) {
            NoteButton(title: T("Открыть ›", "Open ›")) { showingImport = true }
        }
        // Уйти можно в любой день: записи и так обычные файлы (P428).
        NoteRow(title: T("Переход в другое приложение", "Switch to another app")) {
            NoteButton(title: T("Как ›", "How ›")) { showingLeave = true }
        }
        .alert(T("Как перейти в другое приложение", "How to move to another app"), isPresented: $showingLeave) {
            Button(T("Собрать PDF", "Make a PDF")) { showingPDF = true }
            Button(T("Понятно", "Got it"), role: .cancel) { }
        } message: {
            Text(T("Ничего выгружать не нужно: записи — обычные текстовые файлы Markdown в вашей папке, по дню на файл, снимки и голос — рядом в своих папках. Их открывают Obsidian, iA Writer и любой текстовый редактор: укажите им эту папку. Для чтения и печати — PDF за любой срок.",
                   "There is nothing to export: your entries are plain Markdown text files in your folder, one per day, with photos and voice next to them in their own folders. Obsidian, iA Writer and any text editor open them: point them at this folder. For reading and printing, make a PDF for any period."))
        }
        // Папки с прежними, русскими, именами — перевести (P353).
        if vault.hasRussianNames {
            NoteRow(title: T("Имена папок — по-английски", "Rename folders to English")) {
                NoteButton(title: T("Перевести ›", "Rename ›")) { askingRename = true }
            }
            .confirmationDialog(T("Перевести имена папок?", "Rename the folders to English?"), isPresented: $askingRename,
                                titleVisibility: .visible) {
                Button(T("Перевести", "Rename")) {
                    store.save()
                    close()
                    vault.translateNames()
                }
                Button(T("Не сейчас", "Not now"), role: .cancel) { }
            } message: {
                Text(T("«Дневник» станет «Diary», «Фотографии» — «Photos» и так далее; ", "“Дневник” becomes “Diary”, “Фотографии” — “Photos” and so on; ")
                     + T("ссылки на снимки в записях поправятся следом. Файлы не копируются ", "photo links in your entries are updated after that. Files are not copied ")
                     + T("и не пересоздаются — меняются только имена. Если перевод оборвётся, ", "or recreated — only the names change. If it is interrupted, ")
                     + T("ничего не пропадёт: приложение понимает оба имени.", "nothing is lost: the app understands both names."))
            }
        }
    }

    @ViewBuilder private var privacyPart: some View {
        NoteSection(title: T("Защита", "Privacy"))
        NoteRow(title: T("Замок: Face ID или код", "Lock: Face ID or passcode")) {
            Choice(options: onOff, selection: lockChoice)
        }
    }

    @ViewBuilder private var dayPart: some View {
        NoteSection(title: T("День", "Day"))
        NoteRow(title: T("Новый день начинается в", "A new day starts at")) {
            Menu {
                ForEach(0..<7, id: \.self) { h in
                    Button("\(h):00") {
                        boundary = h
                        Prefs.applyBoundary()
                        store.go(to: DayStore.today())
                    }
                }
            } label: {
                Text("\(boundary):00 ▾")
                    .font(Look.sans(13.5, weight: .semibold))
                    .modifier(Tag())
            }
        }
        NoteRow(title: T("Открывать на", "Open on")) {
            // Три варианта (P402): где был в прошлый раз, план, дневник.
            Choice(options: [("last", T("где был", "where I left")), ("plan", T("плане", "plan")),
                             ("diary", T("дневнике", "diary"))],
                   selection: $startTab)
        }
        // P290.
        NoteRow(title: T("Неделя с", "Week starts on")) {
            Choice(options: [(false, T("понедельника", "Monday")), (true, T("воскресенья", "Sunday"))],
                   selection: $sundayFirst)
        }
        NoteRow(title: T("«Итоги дня»", "“How the day went”")) {
            Choice(options: onOff, selection: Binding(get: { !noAsk }, set: { noAsk = !$0 }))
        }
        // Погоды нет — почему (P354). Текст можно выделить и прислать.
        NoteRow(title: T("Погода", "Weather")) {
            Choice(options: onOff, selection: Binding(get: { !noWeather }, set: { on in
                noWeather = !on
                if on { store.fetchWeatherIfNeeded() }
            }))
        }
        if !noWeather, let trouble = store.weatherTrouble {
            Text(trouble)
                .font(Look.sans(11.5))
                .foregroundStyle(Color.red.opacity(0.8))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
        }
        if !noWeather {
            NoteRow(title: T("Градусы", "Degrees")) {
                Choice(options: [(false, "°C"), (true, "°F")], selection: $fahrenheit)
            }
        }
        // «Здоровье» в шапке дневника (P378): включили — iPhone спросит.
        // Не вышло спросить — подсказка прямо под выключателем (P503).
        if HealthDay.available {
            NoteRow(title: T("Здоровье: шаги, сон, тренировки", "Health: steps, sleep, workouts"),
                    detail: healthDetail) {
                Choice(options: onOff, selection: Binding(get: { health }, set: { on in
                    health = on
                    if on { HealthDay.ask { healthIssue = !$0 } } else { healthIssue = false; HealthDay.changed() }
                }))
            }
            .onAppear { if health { HealthDay.ask { healthIssue = !$0 } } }
        }
        // Вечером — «запишите день» (P444): в выбранный час, если день ещё
        // не записан.
        NoteRow(title: T("Напоминание вечером", "Evening reminder"),
                detail: evening >= 0 ? T("Короткая мысль в этот час — если в дневнике сегодня пусто.",
                                         "A short thought at this hour — if today’s diary is empty.") : nil) {
            Choice(options: [(-1, T("выкл", "off")), (20, "20:00"), (21, "21:00"), (22, "22:00")],
                   selection: Binding(get: { evening }, set: { hour in
                evening = hour
                if hour >= 0 {
                    Reminders.ask { _ in store.planEvening() }
                } else {
                    store.planEvening()
                }
            }))
        }
        // События Календаря iPhone в плане (P376).
        NoteRow(title: T("События Календаря iPhone", "iPhone Calendar events"),
                detail: eventsDetail, detailColor: eventsDenied ? .orange : Look.inkSoft) {
            Choice(options: onOff, selection: Binding(get: { calendarEvents }, set: { on in
                calendarEvents = on
                if on, DayEvents.status == .notDetermined { DayEvents.ask { _ in } }
            }))
        }
        if calendarEvents && eventsDenied {
            NoteRow(title: T("Доступ к Календарю", "Calendar access")) {
                NoteButton(title: T("Открыть ›", "Open ›")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
        if calendarEvents {
            NoteRow(title: T("Праздники и дни рождения", "Holidays and birthdays")) {
                Choice(options: [(true, T("показывать", "show")), (false, T("нет", "hide"))],
                       selection: $calendarHolidays)
            }
        }
    }

    private var eventsDenied: Bool {
        DayEvents.status == .denied || DayEvents.status == .restricted || DayEvents.status == .writeOnly
    }

    private var eventsDetail: String? {
        guard calendarEvents else { return nil }
        if eventsDenied {
            return T("Нет доступа к Календарю — разрешите в Настройках iPhone.",
                     "No access to Calendar — allow it in iPhone Settings.")
        }
        return T("Над делами, по времени; звонит сам Календарь.",
                 "Above your tasks, by time; Calendar itself rings.")
    }

    @ViewBuilder private var lookPart: some View {
        NoteSection(title: T("Вид", "Appearance"))
        NoteRow(title: T("Тема", "Theme")) {
            Choice(options: [("system", T("как iPhone", "as iPhone")), ("light", T("светлая", "light")),
                             ("dark", T("тёмная", "dark"))], selection: $theme)
        }
        // Размер и шрифт записей (P274).
        NoteRow(title: T("Размер текста", "Text size")) {
            HStack(spacing: 6) {
                NoteButton(title: "A−") { if textSize > -1 { Feel.tick(); textSize -= 1 } }
                    .opacity(textSize > -1 ? 1 : 0.4)
                Text(Prefs.textSteps[Prefs.textStep].name)
                    .font(Look.sans(12.5))
                    .foregroundStyle(Look.ink)
                    .frame(minWidth: 62)
                NoteButton(title: "A+") {
                    if textSize < Prefs.textSteps.count - 2 { Feel.tick(); textSize += 1 }
                }
                .opacity(textSize < Prefs.textSteps.count - 2 ? 1 : 0.4)
            }
        }
        NoteRow(title: T("Шрифт записи", "Entry font")) {
            Choice(options: Prefs.fonts.map { ($0.key, $0.name) }, selection: $fontKey)
        }
        // Три гаммы с образцами цветов и «без цвета» (P498). Гамма красит
        // страницы, календарь и строки разделов; «без цвета» — только календарь.
        NoteRow(title: T("Цветовая гамма", "Colour scheme")) {
            SchemeChoice(selection: $calendarTint)
        }
        NoteRow(title: T("Шелест страниц", "Page rustle")) {
            Choice(options: onOff, selection: Binding(get: { !quiet }, set: { quiet = !$0 }))
        }
    }

    @ViewBuilder private var attachPart: some View {
        NoteSection(title: T("Вложения", "Attachments"))
        // Три уровня, снимок — в формате iPhone (P365). Под строкой —
        // сколько весит снимок: по этому и выбирают.
        NoteRow(title: T("Сжатие снимков", "Photo compression"), detail: squeezeDetail) {
            Choice(options: [("medium", T("высокое", "high")), ("high", T("среднее", "medium")),
                             ("original", T("без сжатия", "none"))], selection: $squeeze)
        }
        NoteRow(title: T("Сжатие видео", "Video compression"), detail: videoDetail) {
            Choice(options: [("1080", T("до 1080p", "to 1080p")), ("original", T("без сжатия", "none"))],
                   selection: $videoSqueeze)
        }
        // Корзина дней (P295): вернуть или удалить навсегда.
        NoteRow(title: T("Корзина", "Trash")) {
            NoteButton(title: T("Открыть ›", "Open ›")) { showingTrash = true }
        }
    }

    @ViewBuilder private var mapPart: some View {
        NoteSection(title: T("Карта", "Map"))
        NoteRow(title: T("Кнопка «в навигатор» открывает:", "Directions button opens:")) {
            Choice(options: [("apple", T("Карты Apple", "Apple Maps")), ("google", "Google")],
                   selection: $navigator)
        }
        // Разовый перенос меток из файлов Google (P512).
        NoteRow(title: T("Перенести метки из Google Карт", "Move places from Google Maps")) {
            NoteButton(title: T("Открыть ›", "Open ›")) { showingGoogleMaps = true }
        }
    }

    @ViewBuilder private var aboutPart: some View {
        NoteSection(title: T("О приложении", "About"))
        // Покупка: месяц пробы, потом разовая (M14, P432).
        NoteRow(title: T("Graphomanus навсегда", "Graphomanus for good"), detail: Purchase.shared.summary) {
            // Листок покупки — поверх настроек; закрыли — снова настройки
            // (P458): прежде настройки закрывались, и человек терялся.
            NoteButton(title: T("Открыть ›", "Open ›")) {
                Purchase.shared.asking = true
            }
        }
        // Подсказки для знакомства — заново, с первой (P427).
        // Две кнопки (P458): включить снова — подсказки придут к месту, по
        // одной, когда понадобятся; отключить — ни одной больше. Настройки
        // при этом не закрываются.
        NoteRow(title: T("Подсказки для знакомства", "Getting-started tips"),
                detail: hints.off ? T("Сейчас отключены.", "Turned off now.")
                                  : T("Появляются по одной, к месту.", "They appear one at a time, where needed.")) {
            HStack(spacing: 6) {
                NoteButton(title: T("Показать снова", "Show again")) {
                    Hints.shared.startOver()
                    shell.say(T("Подсказки снова включены — появятся по одной, к месту.",
                                "Tips are on again — they will appear one at a time, where needed."))
                }
                NoteButton(title: T("Отключить", "Turn off")) {
                    Hints.shared.turnOff()
                }
            }
        }
        // Пройти первый запуск самому — в пробной папке (P452): свои записи
        // остаются на месте, в них ничего не пишется.
        if vault.inTrial {
            NoteRow(title: T("Идёт проба первого запуска", "Trying the first launch"),
                    detail: T("Образцы — в пробной папке. Ваши записи на месте.",
                              "The samples are in a trial folder. Your entries are untouched.")) {
                NoteButton(title: T("К своим ›", "Back ›")) {
                    close()
                    vault.endTrial()
                }
            }
        } else {
            NoteRow(title: T("Пройти первый запуск", "Try the first launch"),
                    detail: T("Как увидит приложение новый человек — в пробной папке.",
                              "See the app as a newcomer does — in a trial folder.")) {
                NoteButton(title: T("Начать ›", "Start ›")) { askingTrial = true }
            }
        }
        NoteRow(title: T("Чего ещё нет", "Not there yet")) {
            NoteButton(title: undone ? T("Скрыть ▾", "Hide ▾") : T("Показать ›", "Show ›")) { undone.toggle() }
        }
        if undone { missing }
        // Погода в записях — от Погоды Apple; её условия положено
        // показывать там, где приложение показывает погоду (P208).
        NoteRow(title: T("Погода — Погода Apple", "Weather — Apple Weather")) {
            NoteButton(title: T("Условия ›", "Terms ›")) { openURL(WeatherNote.legal) }
        }
    }

    @State private var storageBytes: Int64? = SettingsSticker.cachedBytes
    @State private var showingLeave = false

    /// Сколько места занимает вся папка — не только записи, но и снимки,
    /// голос, видео и документы. Считаем не на каждый штрих, а один раз,
    /// пока листок открыт, и в стороне от главного потока — папка может
    /// быть большой (P315).
    private func measureStorage() {
        guard let root = vault.root else { return }
        DispatchQueue.global(qos: .utility).async {
            let total = SettingsSticker.folderBytes(root)
            DispatchQueue.main.async {
                // Без движения (P485): строки ниже не должны ехать.
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { storageBytes = total }
                SettingsSticker.cachedBytes = total
            }
        }
    }

    @State private var undone = false
    @AppStorage(Reminders.eveningKey) private var evening = -1
    @AppStorage(Prefs.lock) private var locked = false
    @AppStorage(Prefs.boundary) private var boundary = 0
    @AppStorage(Prefs.startTab) private var startTab = "plan"
    @AppStorage(Prefs.theme) private var theme = "system"
    @AppStorage(Prefs.navigator) private var navigator = "apple"
    @AppStorage(Prefs.quiet) private var quiet = false
    @AppStorage(Prefs.textSize) private var textSize = 0
    @AppStorage(Prefs.font) private var fontKey = "newyork"
    @AppStorage(Prefs.noWeather) private var noWeather = false
    @AppStorage(Prefs.fahrenheit) private var fahrenheit = false
    @AppStorage(Prefs.noAsk) private var noAsk = false
    @AppStorage(DayEvents.onKey) private var calendarEvents = true
    @AppStorage(HealthDay.key) private var health = false
    /// iPhone не смог спросить разрешение на «Здоровье» — у сборки нет права
    /// (P503).
    @State private var healthIssue = false

    private var healthDetail: String? {
        guard health else { return nil }
        return healthIssue
            ? T("У этой сборки нет права на «Здоровье» — iPhone не может спросить разрешение.",
                "This build has no Health permission, so iPhone cannot ask for access.")
            : T("Нет строки? Проверьте: Настройки iPhone → Здоровье → Доступ к данным и устройства → Graphomanus.",
                "No line? Check iPhone Settings → Health → Data Access & Devices → Graphomanus.")
    }
    @AppStorage(DayEvents.holidaysKey) private var calendarHolidays = false
    @AppStorage(Prefs.calendarTint) private var calendarTint = "distance"
    @AppStorage(Prefs.sundayFirst) private var sundayFirst = false
    @AppStorage(Prefs.squeeze) private var squeeze = "high"
    @AppStorage(Prefs.videoSqueeze) private var videoSqueeze = "1080"
    @State private var showingTrash = false
    @State private var showingPDF = false
    @State private var showingBackup = false
    @State private var showingImport = false
    @State private var showingGoogleMaps = false
    @AppStorage(Lang.key) private var language = "en"

    private var onOff: [(Bool, String)] { [(true, T("вкл", "on")), (false, T("выкл", "off"))] }

    /// Замок меняется, только если телефон подтвердил владельца: иначе
    /// можно запереться и не открыть (P249).
    private var lockChoice: Binding<Bool> {
        Binding(get: { locked }, set: { want in
            LockView.check(reason: want ? T("Закрыть записи замком", "Lock your entries")
                                        : T("Снять замок с записей", "Unlock your entries")) { ok in
                if ok { locked = want } else {
                    shell.say(T("Телефон не подтвердил владельца — замок не изменён.", "The phone did not confirm the owner — the lock was not changed."))
                }
            }
        })
    }

    private var squeezeDetail: String {
        switch squeeze {
        case "high":
            return T("2560 точек, снимок ~0,5–1 МБ. На экране не отличить от оригинала",
                     "2560 px, about 0.5–1 MB a photo. Looks the same as the original on screen")
        case "medium":
            return T("1600 точек, снимок ~0,2–0,4 МБ. При увеличении мягче",
                     "1600 px, about 0.2–0.4 MB a photo. Softer when zoomed in")
        default:
            return T("Как снял iPhone, снимок ~2–5 МБ",
                     "As the iPhone took it, about 2–5 MB a photo")
        }
    }

    private var videoDetail: String {
        videoSqueeze == "1080"
            ? T("Минута ~60 МБ. Ролики меньше 1080p — как есть",
                "About 60 MB a minute. Smaller clips stay as they are")
            : T("Как снял iPhone: минута 4K ~170–400 МБ",
                "As the iPhone took it: a minute of 4K is about 170–400 MB")
    }

    @State private var choosingPlace = false
    @State private var showingSafety = false
    @EnvironmentObject private var store: DayStore

    @EnvironmentObject private var archive: Archive
    @Environment(\.openURL) private var openURL

    /// Сколько файлов и места занято, а путь — блёкло, справочно (P316:
    /// переименовано из «Записи лежат здесь», раньше показывал только
    /// путь и число файлов, без объёма).
    ///
    /// Строка целиком — кнопка: нажатие открывает ту же папку в «Файлах».
    /// Раньше это было две строки — теперь одна (P305).
    private var place: some View {
        VStack(alignment: .leading, spacing: 0) {
            NoteRow(title: T("Хранилище", "Storage"), detail: vault.friendlyPath + "\n" + count, pinned: true) {
                NoteButton(title: T("Где ›", "Show ›")) {
                    close()
                    if let link = vault.filesLink { openURL(link) }
                }
            }
            if let parent = vault.nestedIn {
                Text(T("Похоже, это папка внутри архива, а не сам архив. Прежние ", "This looks like a folder inside the archive, not the archive itself. Earlier ")
                     + T("записи, скорее всего, лежат уровнем выше — в «\(parent)». ", "entries are most likely one level up — in “\(parent)”. ")
                     + T("Нажмите «Перенести архив» и выберите саму «\(parent)»: ", "Tap “Move the archive” and choose “\(parent)” itself: ")
                     + T("приложение узнает архив и предложит перенести туда то, ", "the app will recognise the archive and offer to move there ")
                     + T("что записано здесь.", "what was written here."))
                    .font(Look.sans(11.5))
                    .foregroundStyle(Color.red.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
        }
    }

    /// «Данные в сохранности?» — сразу под строкой хранилища: да, если папка
    /// не в самом приложении, и заметное «нет», если записи живут только
    /// внутри «Graphomanus» и пропадут вместе с ней (P326).
    private var safety: some View {
        NoteRow(title: T("Данные в сохранности?", "Is my data safe?")) {
            Button {
                showingSafety = true
            } label: {
                if vault.onPhone {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        Text(T("НЕТ ›", "NO ›")).font(Look.sans(13.5, weight: .bold)).foregroundStyle(.red)
                    }
                } else {
                    Text(T("✓ да ›", "✓ yes ›"))
                        .font(Look.sans(13.5, weight: .semibold))
                        .foregroundStyle(Color(red: 0.23, green: 0.6, blue: 0.35))
                }
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $showingSafety) {
            SafetySheet(onPhone: vault.onPhone) {
                showingSafety = false
                choosingPlace = true
            }
        }
    }

    private var count: String {
        var out = T("Файлов с записями: \(archive.files)", "Entry files: \(archive.files)")
        if let storageBytes {
            out += T(" · занято: ", " · size: ") + ByteCountFormatter.string(fromByteCount: storageBytes,
                                                              countStyle: .file)
        }
        if archive.awayFiles > 0 {
            out += T(" · ещё в iCloud: \(archive.awayFiles)", " · still in iCloud: \(archive.awayFiles)")
            out += archive.fetching ? T(", скачиваются", ", downloading") : ""
        }
        return out
    }

    private var missing: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Вечернее напоминание есть (P444), Day One, Diarium, Journey —
            // тоже; «Дневник» Apple своих записей наружу не отдаёт.
            Text(T("Перенос из «Дневника» Apple", "Import from Apple Journal"))
        }
        .font(Look.sans(12))
        .foregroundStyle(Look.inkFaint)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var version: some View {
        HStack {
            Text(T("Версия", "Version"))
                .font(Look.sans(12))
                .foregroundStyle(Look.inkFaint)
            Spacer()
            Text(Build.label)
                .font(Look.mono(12))
                .foregroundStyle(Look.inkSoft)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func close() {
        shell.tuckIn(settings: true)
    }
}

/// «Данные в сохранности?» — коротко, что означает ответ, и что делать,
/// если «нет» (P326).
struct SafetySheet: View {
    let onPhone: Bool
    /// Закрыть и сразу открыть выбор папки — из «нет» ведёт прямо к делу.
    let moveNow: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Image(systemName: onPhone ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(onPhone ? .red : Look.inkSoft)

                Text(onPhone ? T("Данные не защищены", "Your data is not protected") : T("Данные в сохранности", "Your data is safe"))
                    .font(.title2)

                Text(onPhone
                     ? T("Записи лежат внутри самой «Graphomanus», на этом iPhone. ", "Your entries are inside Graphomanus itself, on this iPhone. ")
                       + T("Удалите приложение — iPhone сотрёт их вместе с ним, без возврата.", "Delete the app, and the iPhone erases them with it, for good.")
                     : T("Записи лежат вне приложения, в вашей папке. Удалите «Graphomanus» — ", "Your entries are outside the app, in your own folder. Delete Graphomanus, and ")
                       + T("они останутся на месте: в «Файлах», в облаке, на других устройствах.", "they stay where they are: in Files, in the cloud, on other devices."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if onPhone {
                    Button {
                        moveNow()
                    } label: {
                        Text(T("Перенести архив и писать в другое место", "Move the archive and write elsewhere"))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(28)
            .navigationTitle(T("Данные в сохранности?", "Is my data safe?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(T("Готово", "Done")) { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Номер сборки на виду.
///
/// Без него нельзя ответить на вопрос «а это новая версия или старая?» —
/// ни мне по журналам сборки, ни человеку с телефоном в руках.
enum Build {
    static var label: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }
}

// MARK: - Ролик времени

/// Время дела и время напоминания крутятся одним и тем же роликом.
/// Выход «Без времени» — это отказ, а не пустое значение: дело останется
/// без часа, и это нормальное состояние дела.
struct RollerSheet: View {

    private static var aboutBell: String {
        T("Напоминания ещё не приходят — время записывается в файл, "
          + "но телефон о нём пока не сообщает.",
          "Reminders do not arrive yet — the time is written to the file, "
          + "but the phone does not announce it yet.")
    }

    let roller: Shell.Roller

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell
    @State private var picked = Date()
    /// Готовый ответ, нажатый последним.
    @State private var chosen: String?
    /// Повтор дела (P359): нет, каждую неделю, месяц, год.
    @State private var every: Repeat.Every?

    private var isBell: Bool { roller.kind == .bell }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                TimeWheel(time: $picked)
                if !isBell { repeatRow }
                if isBell {
                    presets
                    Text(Self.aboutBell)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 6)
            .navigationTitle(isBell ? T("Напоминание", "Reminder") : T("Время дела", "Task time"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // «Отмена» не просто закрывает, а снимает назначенное: дело
                // остаётся без часа, напоминание — снятым. Иначе отказаться
                // от времени было бы нечем (решения P49, P150).
                ToolbarItem(placement: .topBarLeading) {
                    Button(T("Отмена", "Cancel")) { apply(nil) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("Готово", "Done")) { apply(Clock.text(picked)) }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard let i = store.index(of: roller.id) else { return }
                let row = store.planRows[i]
                let current = isBell ? row.bell : row.time
                set(Clock.date(current) ?? start(row))
                every = row.repeats?.every
            }
        }
        .presentationDetents([.height(isBell ? 392 : 370)])
    }

    /// Повторять ли дело (P359). Выбор — до «Готово»: ничего не пишется,
    /// пока ролик не закрыт.
    private var repeatRow: some View {
        VStack(spacing: 8) {
            Text(T("Повторять", "Repeat"))
                .font(Look.sans(12, weight: .semibold))
                .foregroundStyle(Look.inkSoft)
            // Пять кнопок в ряд на узком телефоне не помещаются — тогда
            // в два ряда (P378: добавилось «каждый день»).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    repeatChip(nil, T("нет", "no"))
                    ForEach(Repeat.Every.allCases, id: \.self) { kind in
                        repeatChip(kind, kind.title)
                    }
                }
                VStack(spacing: 6) {
                    HStack(spacing: 6) {
                        repeatChip(nil, T("нет", "no"))
                        repeatChip(.day, Repeat.Every.day.title)
                    }
                    HStack(spacing: 6) {
                        ForEach([Repeat.Every.week, .month, .year], id: \.self) { kind in
                            repeatChip(kind, kind.title)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func repeatChip(_ kind: Repeat.Every?, _ title: String) -> some View {
        let on = every == kind
        return Button {
            Feel.tick()
            every = kind
        } label: {
            Text(title)
                .font(Look.sans(12.5))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundStyle(on ? Look.planBg : Look.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(on ? Look.accent : Look.chrome, in: Capsule())
                .overlay(Capsule().strokeBorder(Look.accent.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }

    /// Поставить ролик. Всегда через подгонку к шагу: ролик с шагом в пять
    /// минут всё равно округлит, и лучше, чтобы приложение и ролик считали
    /// одинаково, чем расходились молча.
    private func set(_ date: Date) { picked = Clock.snap(date) }

    /// Время дела, если оно назначено: от него считаются напоминания.
    private var eventTime: Date? {
        guard let i = store.index(of: roller.id) else { return nil }
        return Clock.date(store.planRows[i].time)
    }

    /// Готовые ответы для напоминания.
    ///
    /// Почти все напоминания ставят на одно из трёх: незадолго до дела,
    /// за час до дела или с утра. Крутить ради этого барабан — лишняя
    /// работа на каждом деле (решение P152).
    ///
    /// Готовый ответ не закрывает ролик, а ставит на нужное место барабан:
    /// человек видит, что выбралось, и может поправить. Одно касание мимо
    /// не должно молча назначать напоминание.
    private var presets: some View {
        HStack(spacing: 8) {
            preset(T("за 10 минут", "10 minutes before"), eventTime?.addingTimeInterval(-600))
            preset(T("за 1 час", "1 hour before"), eventTime?.addingTimeInterval(-3600))
            preset(T("в 9 утра", "at 9 am"), Clock.at(9))
        }
    }

    /// Готовый ответ. Бледный и неотзывчивый, когда считать не от чего:
    /// у дела ещё нет времени, и «за час до» не от чего отсчитать.
    ///
    /// Первое нажатие ставит ролик на это время — можно подкрутить.
    /// Второе нажатие на тот же ответ, пока ролик стоит на нём, значит
    /// «вот это и надо»: время записывается, и ролик закрывается сам
    /// (решение P194).
    private func preset(_ title: String, _ value: Date?) -> some View {
        let ready = value != nil
        return Button {
            guard let value else { return }
            // Щелчок, как у будильника (P267). Само колёсико щёлкает
            // своим, системным.
            Feel.tick()
            if chosen == title, picked == Clock.snap(value) {
                apply(Clock.text(picked))
                return
            }
            chosen = title
            set(value)
        } label: {
            Text(title)
                .font(Look.sans(13))
                .foregroundStyle(ready ? Look.accent : Look.inkFaint)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Look.chrome, in: Capsule())
                .overlay(Capsule().strokeBorder(
                    ready ? Look.accent.opacity(0.35) : Look.rule))
        }
        .buttonStyle(.plain)
        // Не .disabled: система рисует выключенную кнопку бледнее поверх
        // заданного цвета, и бледность сложилась бы дважды (P141).
        .allowsHitTesting(ready)
    }

    /// Откуда начинает ролик, когда время ещё не назначено.
    ///
    /// Для дела — 9 утра: самое частое время начала дня, крутить от него
    /// в обе стороны короче, чем от текущего часа (P330, решение сменяет
    /// прежнее — ближайший круглый час, P149).
    ///
    /// Для напоминания — за час до дела: напоминают заранее, иначе незачем
    /// напоминать. А если у дела времени ещё нет, отсчитывать не от чего —
    /// ролик тоже встаёт на 9 утра (P330, было — полночь, P149).
    private func start(_ row: PlanRow) -> Date {
        guard isBell else { return Clock.at(9) }
        guard let time = Clock.date(row.time) else { return Clock.at(9) }
        return time.addingTimeInterval(-3600)
    }

    private func apply(_ value: String?) {
        if let i = store.index(of: roller.id) {
            let before = store.planRows[i].repeats?.every
            if isBell { store.planRows[i].bell = value } else { store.planRows[i].time = value }
            store.save()
            // Повтор поменяли — серия заводится или снимается; иначе, если
            // дело из серии, спросить, только ли здесь новое время (P359).
            if !isBell, every != before {
                if let every {
                    let n = store.startSeries(roller.id, every: every)
                    shell.say(T("Повтор вписан в дни на год вперёд: \(n)",
                                "Repeat written into the days a year ahead: \(n)"))
                } else {
                    store.stopSeries(roller.id)
                    shell.say(T("Больше не повторяется", "No longer repeats"))
                }
            } else {
                store.checkSeries(roller.id)
            }
        }
        // Колокольчик поставлен — спросить у iPhone разрешение звонить
        // (P260). Запрещено — сказать, где разрешить.
        if isBell, value != nil {
            let shell = shell
            Reminders.ask { ok in
                if !ok {
                    shell.say(T("Напоминания выключены: Настройки iPhone → Graphomanus → Уведомления", "Reminders are off: iPhone Settings → Graphomanus → Notifications"))
                }
            }
        }
        shell.roller = nil
    }
}

enum Clock {
    private static var formatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }

    static func text(_ date: Date) -> String { formatter.string(from: date) }

    static func date(_ text: String?) -> Date? {
        guard let text, let t = formatter.date(from: text) else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: t)
        return Calendar.current.date(bySettingHour: c.hour ?? 0, minute: c.minute ?? 0,
                                     second: 0, of: Date())
    }

    /// Ближайший следующий круглый час. Ровно в час — он сам: в 23:00
    /// предлагать полночь было бы странно.
    ///
    /// После 23:00 круглый час приходится на следующие сутки, но ролик
    /// показывает только часы и минуты — для него это просто 00:00.
    static func nextHour(_ now: Date = Date()) -> Date {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: now)
        let minute = c.minute ?? 0
        let hour = (minute == 0 ? (c.hour ?? 0) : (c.hour ?? 0) + 1) % 24
        return cal.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
    }

    /// Полночь — для ролика, которому не от чего отсчитывать.
    static func midnight(_ now: Date = Date()) -> Date {
        Calendar.current.startOfDay(for: now)
    }

    /// Такой-то час ровно.
    static func at(_ hour: Int, _ now: Date = Date()) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: now) ?? now
    }

    /// Подогнать к шагу ролика: минуты вниз до кратных шагу.
    ///
    /// Вниз, а не к ближайшему: назначенное на 14:37 дело безопаснее
    /// сдвинуть на 14:35, чем на 14:40 — раньше можно, позже нельзя.
    static func snap(_ date: Date, step: Int = 5) -> Date {
        let cal = Calendar.current
        let c = cal.dateComponents([.hour, .minute], from: date)
        let minute = ((c.minute ?? 0) / step) * step
        return cal.date(bySettingHour: c.hour ?? 0, minute: minute,
                        second: 0, of: date) ?? date
    }
}

// MARK: - Подробности

/// Шторка справа: адрес, дорога, стоимость, с кем.
///
/// Размеры прототипа: ширина 324 или 88 % экрана — что меньше; отступ 15
/// сверху и снизу, чтобы шторка не упиралась в края вкладки; скруглена
/// слева, справа уходит за край. Она не закрывает ни вкладки, ни нижние
/// кнопки — человек видит, где находится, и выходит касанием мимо.
struct DetailsDrawer: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var archive: Archive
    @EnvironmentObject private var shell: Shell
    @State private var keyboard: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.14)
                .contentShape(Rectangle())
                .onTapGesture { close() }
            panel
        }
        .transition(.move(edge: .trailing))
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillChangeFrameNotification)) { note in
            let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                as? CGRect ?? .zero
            let screen = UIScreen.main.bounds.height
            // Нижняя безопасная полоса телефона уже учтена в отступах шторки:
            // не вычесть её — и между клавиатурой и шторкой остаётся пустое
            // поле шириной в палец.
            let safe = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow?.safeAreaInsets.bottom }
                .first ?? 0
            keyboard = max(0, screen - frame.origin.y - safe)
        }
        .onReceive(NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboard = 0
        }
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 0) {
            head
            if let i = index { body(at: i) }
        }
        .frame(maxWidth: 324)
        .background(Look.chrome)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 12))
        .overlay(SideTabBorder(radius: 12).stroke(Look.rule, lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 17, x: -8)
        .padding(.leading, 40)
        .padding(.top, 15)
        // Шторка поднимается над клавиатурой, а не прячет под ней строку,
        // которую человек как раз набирает.
        .padding(.bottom, max(15, keyboard - 16))
        .animation(.easeOut(duration: 0.22), value: keyboard)
    }

    private var head: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(T("ПОДРОБНОСТИ", "DETAILS"))
                .font(Look.sans(12, weight: .medium))
                .tracking(1.2)
                .foregroundStyle(Look.inkFaint)
                .padding(.top, 4)
            Spacer(minLength: 0)
            closeButton
        }
        .padding(.horizontal, 12)
        .padding(.top, 13)
        .padding(.bottom, 4)
    }

    private var closeButton: some View {
        Button { close() } label: {
            CloseMark()
        }
        .accessibilityLabel(T("Закрыть", "Close"))
    }

    /// Привычка (P378): сколько раз подряд и сколько в этом месяце.
    @ViewBuilder private func habit(_ series: String) -> some View {
        let stats = habitStats(series)
        if stats.monthAll > 0 || stats.streak > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text(T("Подряд: \(stats.streak) · в этом месяце: \(stats.monthDone) из \(stats.monthAll)",
                       "In a row: \(stats.streak) · this month: \(stats.monthDone) of \(stats.monthAll)"))
                    .font(Look.sans(12.5, weight: .medium))
                    .foregroundStyle(Look.accent)
                HStack(spacing: 4) {
                    ForEach(Array(stats.recent.enumerated()), id: \.offset) { _, done in
                        Circle()
                            .fill(done ? Look.accent : Color.clear)
                            .overlay(Circle().strokeBorder(Look.accent.opacity(0.6), lineWidth: 1))
                            .frame(width: 10, height: 10)
                    }
                }
                .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    private func habitStats(_ series: String) -> HabitStats {
        var days: [Date: Bool] = [:]
        for day in archive.days.values {
            if let row = day.tasks.first(where: { $0.repeats?.series == series }) {
                days[Calendar.current.startOfDay(for: day.date)] = row.done
            }
        }
        // Открытый день — как он сейчас на экране, а не как в описи.
        if let row = store.planRows.first(where: { $0.repeats?.series == series }) {
            days[Calendar.current.startOfDay(for: store.date)] = row.done
        }
        return HabitStats.count(days, today: DayStore.today())
    }

    @ViewBuilder private func body(at i: Int) -> some View {
        Text(store.planRows[i].text.isEmpty ? T("Без названия", "Untitled") : store.planRows[i].text)
            .font(Look.sans(14.5))
            .foregroundStyle(Look.ink)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

        if let series = store.planRows[i].repeats?.series { habit(series) }

        editor(at: i)
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 12)
            .padding(.bottom, 14)

        if !store.canEditPlan {
            Text(store.closedReason)
                .font(Look.sans(11.5))
                .foregroundStyle(Look.inkFaint)
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
        }
    }

    private func editor(at i: Int) -> some View {
        ZStack(alignment: .topLeading) {
            if store.planRows[i].details.isEmpty {
                Text(T("Адрес, дорога, стоимость, с кем…", "Address, route, cost, with whom…"))
                    .font(Look.sans(14.5))
                    .foregroundStyle(Look.inkFaint)
                    .padding(.horizontal, 11)
                    .padding(.top, 19)
                    .allowsHitTesting(false)
            }
            // Снимки в подробностях рисуются картинками, как в дневнике (P205).
            DiaryEditor(text: details(at: i), size: 14.5,
                        serif: false, stamped: false, resolve: store.photoURL)
                .padding(.horizontal, 6)
                .disabled(!store.canEditPlan)
        }
        .background(Look.planBg, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Look.rule))
    }

    private func details(at i: Int) -> Binding<String> {
        Binding(
            get: { store.planRows[i].details.joined(separator: "\n") },
            set: { text in
                store.planRows[i].details =
                    text.isEmpty ? [] : text.components(separatedBy: "\n")
            })
    }

    private var index: Int? { shell.drawer.flatMap(store.index(of:)) }

    private func close() {
        hideKeyboard()
        store.save()
        withAnimation(.easeOut(duration: 0.26)) { shell.drawer = nil }
    }
}

// MARK: - Файл на диске

struct FileSheet: View {

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(T("Папка", "Folder")).font(.caption).foregroundStyle(.secondary)
                        Text(vault.displayPath)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    Divider()
                    Text(store.onDisk())
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(T("Файл на диске", "File on disk"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("Закрыть", "Close")) { shell.showingFile = false }
                }
            }
        }
    }
}

// MARK: - Первый запуск

struct WelcomeView: View {

    /// Проба первого запуска из настроек (P452): «Начать» ведёт в пробную
    /// папку, своих папок не предлагает.
    var trial = false

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var archive: Archive

    /// Своя папка в iCloud Drive доступна: iCloud включён и приложению его
    /// дали. Нет — остаётся выбрать папку самому.
    @State private var cloud = true
    /// Человек сам захотел выбрать папку.
    @State private var manual = false
    @State private var starting = false

    private static var invitation: String {
        T("Записи ложатся обычными файлами в папку «\(Vault.folderName)». Папка ваша: "
          + "приложение только пишет и читает, и её всегда видно в «Файлах».",
          "Your entries are saved as plain files in the “\(Vault.folderName)” folder. The folder "
          + "is yours: the app only writes and reads, and you can always see it in Files.")
    }

    var body: some View {
        ScrollView {
        VStack(spacing: 18) {
            Image(systemName: "book.closed")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
                .padding(.top, 24)

            Text(T("Graphomanus", "Graphomanus")).font(.largeTitle.weight(.semibold))

            Text(T("Тетрадь дня: утром — план, вечером — итоги. Записи — ваши файлы.",
                   "A notebook for your day: a plan in the morning, the outcome in the evening. Your entries are your files."))
                .font(.title3)
                .multilineTextAlignment(.center)

            // Одна кнопка (P452): своя папка в iCloud Drive заводится сама,
            // без системного окна выбора.
            if trial || (cloud && !manual) {
                Button(action: start) {
                    Group {
                        if starting { ProgressView() } else { Text(T("Начать", "Start")) }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .disabled(starting)
                .padding(.top, 8)

                Text(trial
                     ? T("Проба: записи лягут в отдельную пробную папку. Ваши настоящие записи останутся на месте.",
                         "A trial: entries go into a separate trial folder. Your real entries stay where they are.")
                     : T("Записи лягут в iCloud Drive › Chronotheca. Их видно в «Файлах», они есть на iPad и Mac и остаются, даже если удалить приложение.",
                         "Entries go to iCloud Drive › Chronotheca. You can see them in Files, they are on your iPad and Mac, and they stay even if you delete the app."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if trial {
                    Button(T("Отмена", "Cancel")) { shell.trialWelcome = false }
                        .font(.footnote)
                } else {
                    Button(T("Выбрать папку самому", "Choose a folder myself")) {
                        withAnimation { manual = true }
                    }
                    .font(.footnote)
                }
            } else {
                if !cloud {
                    Text(T("iCloud Drive на этом iPhone недоступен — выберите, где хранить записи.",
                           "iCloud Drive is not available on this iPhone — choose where to keep your entries."))
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .multilineTextAlignment(.center)
                }
                choices
            }

            if let problem = vault.problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(28)
        }
        .onAppear {
            guard !trial else { return }
            Vault.cloudAvailable { ok in cloud = ok }
        }
    }

    private func start() {
        starting = true
        if trial {
            vault.startTrial()
            Hints.shared.startOver()
            shell.trialWelcome = false
            shell.startOver(store)
            archive.reload()
            starting = false
            return
        }
        vault.useCloud { ok in
            starting = false
            if !ok { withAnimation { cloud = false } }
        }
    }

    /// Выбрать папку самому — прежние два пути (P366).
    @ViewBuilder private var choices: some View {
            Text(T("Где хранить записи", "Where to keep entries")).font(.title2)

            Text(Self.invitation)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Два пути, и оба — папка человека, а не приложения (P366):
            // папку приложения iPhone стирает вместе с ним, и записи
            // пропали бы от одного неосторожного касания. Своя папка
            // остаётся, что бы ни случилось с приложением.
            Button {
                shell.picking = true
            } label: {
                Text(T("Папка в iCloud Drive", "A folder in iCloud Drive")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            guide(T("В окне выберите «iCloud Drive» и нажмите «Открыть» вверху справа. Записи будут "
                    + "и на iPad, и на Mac; место берётся из вашего iCloud (бесплатно — 5 ГБ).",
                    "In the window choose “iCloud Drive” and tap “Open” at the top right. Your entries "
                    + "will be on your iPad and Mac too; they use your iCloud space (5 GB free)."))

            Button {
                shell.picking = true
            } label: {
                Text(T("Папка на этом iPhone", "A folder on this iPhone")).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            guide(T("В окне выберите «На iPhone», нажмите значок новой папки, назовите её, например, "
                    + "«Мои записи», зайдите в неё и нажмите «Открыть». Места в iCloud не нужно, но "
                    + "записи будут только на этом iPhone — делайте резервные копии.",
                    "In the window choose “On My iPhone”, tap the new folder icon, name it, say, "
                    + "“My Journal”, open it and tap “Open”. No iCloud space needed, but your entries "
                    + "will only be on this iPhone — make backups."))

            Text(T("В обоих случаях папка ваша и переживёт удаление приложения. Уже есть папка "
                   + "с записями — зайдите в неё и нажмите «Открыть»: приложение узнает свой архив.",
                   "Either way the folder is yours and outlives deleting the app. Already have a "
                   + "folder with entries? Go into it and tap “Open”: the app will recognise its archive."))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if cloud {
                Button(T("Назад", "Back")) { withAnimation { manual = false } }
                    .font(.footnote)
            }
    }

    private func guide(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 6)
    }
}
