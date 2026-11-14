import EventKit
import SwiftUI

// MARK: - Настройки

/// Шестерёнка: голубая бумажка, приклеенная к верхнему левому углу.
///
/// Та же порода, что и меню страницы: рука узнаёт их одинаково, а цвет
/// говорит, к чему бумажка относится — к дню или ко всему приложению.
struct SettingsSticker: View {

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var shell: Shell
    @State private var askingTrial = false
    /// Замеры скорости — долгим нажатием на «Версия» (P910).
    @State private var showingSpeed = false
    /// Где стоит верх листка, когда он на месте (P669): мерится один раз по
    /// неподвижной подложке листка, а не по самому листку, — тот едет.
    @State private var origin: CGFloat?

    /// Высота листка: он кончается над рваным краем нижней строки (P667),
    /// за вычетом поля под последней плашкой. Известна до выезда (P669):
    /// прежде верх прокрутки мерился, когда листок уже встал, и низ листка
    /// дорастал на глазах.
    private var height: CGFloat? {
        guard let origin, shell.barTop > origin + 300 else { return nil }
        return shell.barTop - Leather.lip - origin - 8
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
        // Белый лист, разделы на нём — жёлтыми стикерами с тенью (P600).
        Sticker(side: .trailing, title: T("Настройки", "Settings"),
                width: Self.width, height: height, onDesk: true, close: close) {
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
            NoteCard { languagePart }
            NoteCard { entriesPart }
            NoteCard { privacyPart }
            NoteCard { dayPart }
            NoteCard { pagePart }
            NoteCard { lookPart }
            NoteCard {
                aboutPart
                version
            }
            // Воздух под последней строкой («Версия», P585).
            Color.clear.frame(height: 16)
           }
          }
          // Прокрутка — всё, что листку осталось под шапкой (P669).
          .frame(maxHeight: .infinity)
          // Строки, уехавшие за край прокрутки, пальца не ловят (P673).
          .clipShape(Rectangle())
          .contentShape(Rectangle())
        }
        .animation(nil, value: height)
        .background {
            GeometryReader { g in
                Color.clear.onAppear {
                    var still = Transaction()
                    still.disablesAnimations = true
                    withTransaction(still) { origin = g.frame(in: .global).minY }
                }
            }
        }
        .onAppear { shell.startPull() }
        .sheet(isPresented: $showingPDF) {
            PDFSheet(vault: vault, archive: archive)
        }
        .sheet(isPresented: $showingBackup, onDismiss: measureStorage) {
            BackupSheet().environmentObject(vault)
        }
        .sheet(isPresented: $showingImport, onDismiss: { archive.reload() }) {
            ImportSheet().environmentObject(vault).environmentObject(store)
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
            // Три места честно (P633, docs/50): что куда уходит и у кого копия.
            Text(T("«На iPhone»: записи никуда не уходят, синхронизации нет. ", "On My iPhone: entries never leave the phone, no sync. ")
                 + T("«В iCloud Drive»: записи и на iPad, и на Mac, копия лежит у Apple. ", "In iCloud Drive: entries on your iPad and Mac too, and Apple keeps a copy. ")
                 + T("«В iCloud Drive» с «Расширенной защитой данных» (включается в Настройках iPhone): то же, но копию прочитают только ваши устройства. ", "In iCloud Drive with Advanced Data Protection (turn it on in iPhone Settings): the same, but only your own devices can read the copy. ")
                 + T("Папка переживёт удаление приложения. ", "The folder outlives deleting the app. ")
                 + T("Записи, что уже есть, приложение предложит перенести.", "The app will offer to move the entries you already have."))
        }
        // Объём памяти считается, когда листок уже выехал (P475): ответ
        // менял строку и размер листка посреди движения — отсюда дёргание.
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { measureStorage() } }
    }

    @ViewBuilder private var languagePart: some View {
        // Заголовок — на языке приложения, как всё остальное (P380).
        NoteSection(title: T("Язык", "Language"))
        // Язык — в Настройках iPhone, как у всех приложений (P633): там
        // у приложения с переводами стоит своя строка «Язык».
        NoteRow(title: T("Язык приложения", "App language"),
                info: T("Язык приложения выбирается в Настройках iPhone: Приложения → Graphomanus → Язык.",
                          "The app’s language is chosen in iPhone Settings: Apps → Graphomanus → Language.")) {
            NoteButton(title: T("Открыть ›", "iPhone Settings ›")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
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
        NoteRow(title: T("Перенести архив", "Move the archive elsewhere")) {
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
                // Как прочие кнопки раздела (P914): надпись со стрелкой.
                NoteButton(title: T("Сделать ›", "Make ›")) { showingBackup = true }
            } else {
                DueButton(title: T("Пора сделать", "Time to make one")) { showingBackup = true }
            }
        }
        // Записи за срок одной книгой (P296).
        NoteRow(title: T("PDF за выбранный срок", "PDF for a period")) {
            NoteButton(title: T("Собрать ›", "Make ›")) { showingPDF = true }
        }
        // Корзина дней (P295): вернуть или удалить навсегда.
        NoteRow(title: T("Корзина", "Trash")) {
            NoteButton(title: T("Открыть ›", "Open ›")) { showingTrash = true }
        }
        // Перенос из других дневников — бесплатно всегда (M14, P378).
        NoteRow(title: T("Из другого приложения", "From another app")) {
            NoteButton(title: T("Открыть ›", "Open ›")) { showingImport = true }
        }
        // Уйти можно в любой день: записи и так обычные файлы (P428).
        NoteRow(title: T("В другое приложение", "To another app")) {
            NoteButton(title: T("Как ›", "How ›")) { showingLeave = true }
        }
        .alert(T("Как перейти в другое приложение", "How to move to another app"), isPresented: $showingLeave) {
            Button(T("Собрать PDF", "Make a PDF")) { showingPDF = true }
            Button(T("Понятно", "Got it"), role: .cancel) { }
        } message: {
            Text(T("Ничего выгружать не нужно: записи — обычные текстовые файлы Markdown в вашей папке, по дню на файл, снимки и голос — рядом в своих папках. Их открывают Obsidian, iA Writer и любой текстовый редактор: укажите им эту папку. Для чтения и печати — PDF за любой срок.",
                   "There is nothing to export: your entries are plain Markdown text files in your folder, one per day, with photos and voice next to them in their own folders. Obsidian, iA Writer and any text editor open them: point them at this folder. For reading and printing, make a PDF for any period."))
        }
    }

    @ViewBuilder private var privacyPart: some View {
        NoteSection(title: T("Защита", "Privacy"))
        // Совет — одной строчкой под замком, без новых строк (P600, по
        // docs/50): меню и так длинное. Страница в переключателе приложений
        // под замком и так прячется (P293).
        NoteRow(title: T("Замок: Face ID или код", "Lock: Face ID or passcode"),
                info: T("Для полной защиты можно включить двухфакторную защиту Apple ID и «Расширенную защиту данных» в iCloud.",
                          "For fuller protection you can turn on two-factor authentication for your Apple ID and Advanced Data Protection in iCloud.")) {
            Lever(isOn: lockChoice)
        }
        // Чужая клавиатура с «полным доступом» видит всё набранное (P633, по
        // docs/50): выключатель, как у банковских приложений.
        NoteRow(title: T("Без чужих клавиатур", "No third-party keyboards"),
                info: T("Клавиатуры из App Store (например, Gboard или SwiftKey) могут видеть всё, что вы набираете, если у них включён «полный доступ». Когда выключатель включён, в Graphomanus работает только обычная клавиатура iPhone. Может понадобиться перезапуск приложения.",
                          "Keyboards from the App Store (such as Gboard or SwiftKey) can see everything you type if they have “Full Access”. When this is on, only the standard iPhone keyboard works in Graphomanus. You may need to restart the app.")) {
            Lever(isOn: $ownKeyboardOnly)
        }
    }

    @ViewBuilder private var dayPart: some View {
        NoteSection(title: T("День", "Day"))
        // «Новый день начинается в» убрано (P915): день начинается в полночь.
        // Напоминание о дневнике (P444) — в любой час с шести утра до
        // одиннадцати вечера (P602), а не только 20, 21 или 22: списком.
        NoteRow(title: T("Напоминание", "Diary reminder"),
                info: T("Короткая мысль в этот час — если в дневнике сегодня пусто.",
                        "A short thought at this hour — if today’s diary is empty.")) {
            Menu {
                Button(T("выкл", "off")) { setEvening(-1) }
                ForEach(6..<24, id: \.self) { h in
                    Button(Clock.hour(h)) { setEvening(h) }
                }
            } label: {
                Text((evening >= 0 ? Clock.hour(evening) : T("выкл", "off")) + " ▾")
                    .font(Look.sans(13.5, weight: .semibold))
                    .modifier(Tag(look: .chosen))
            }
        }
        NoteRow(title: T("«Итоги дня»", "“How the day went”")) {
            Lever(isOn: Binding(get: { !noAsk }, set: { noAsk = !$0 }))
        }
    }

    private func setEvening(_ hour: Int) {
        evening = hour
        if hour >= 0 {
            Reminders.ask { _ in store.planEvening() }
        } else {
            store.planEvening()
        }
    }

    /// Что показывать на странице дня (P602): итоги, погода с градусами,
    /// «Здоровье», события Календаря. Прежде всё это стояло в «Дне», и
    /// градусы оказывались рядом с началом недели.
    @ViewBuilder private var pagePart: some View {
        // Всё, что приходит на страницу не от человека, — здесь и
        // выключено, пока он сам не включит (P452, P609).
        NoteSection(title: T("Дополнения", "Extras"))
        // Погоды нет — почему (P354). Текст можно выделить и прислать.
        NoteRow(title: T("Погода", "Weather"),
                info: T("Погода в шапке дня берётся из Погоды Apple, градусы — как в настройках iPhone. Если погоды нет, причина появится красным под выключателем. Условия Погоды Apple — по кнопке ниже.",
                        "The weather at the top of a day comes from Apple Weather; degrees follow your iPhone settings. If there is no weather, the reason appears in red under the switch. Apple Weather terms are on the button below."),
                infoLink: (T("Условия", "Terms"), WeatherNote.legal)) {
            Lever(isOn: Binding(get: { !noWeather }, set: { on in
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
        // «Здоровье» в шапке дневника (P378): включили — iPhone спросит.
        // Не вышло спросить — подсказка прямо под выключателем (P503).
        if HealthDay.available {
            NoteRow(title: T("Здоровье", "Health: steps, sleep, workouts"),
                    detail: healthDetail, pinned: true,
                    info: healthHint + (health ? healthToday.map { "\n\n" + $0 } ?? "" : "")) {
                Lever(isOn: Binding(get: { health }, set: { on in
                    health = on
                    if on { HealthDay.ask { healthIssue = !$0 } } else { healthIssue = false; HealthDay.changed() }
                }))
            }
            .onAppear { if health { HealthDay.ask { healthIssue = !$0 } } }
            .task(id: health) { healthToday = health ? await HealthDay.todayCheck() : nil }
        }
        // События Календаря iPhone в плане (P376).
        // Одной строкой (P852): нет доступа — строка «Доступ к Календарю»
        // ниже, второй строки здесь не надо.
        NoteRow(title: T("Календарь iPhone", "iPhone Calendar events"),
                info: T("События из приложения «Календарь» на iPhone показываются над делами дня, по времени. Какие календари и как показывать, настраивается в самом «Календаре»; о событиях напоминает тоже он. Нужен доступ к Календарю — iPhone спросит один раз.",
                        "Events from the Calendar app on your iPhone appear above the day’s tasks, by time. Which calendars exist and how they look is set in Calendar itself, and Calendar sends the reminders. It needs Calendar access; iPhone asks once.")) {
            Lever(isOn: Binding(get: { calendarEvents }, set: { on in
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
                // Один рычажок вместо двух кнопок (P914).
                Lever(isOn: $calendarHolidays)
            }
        }
    }

    private var eventsDenied: Bool {
        DayEvents.status == .denied || DayEvents.status == .restricted || DayEvents.status == .writeOnly
    }

    @ViewBuilder private var lookPart: some View {
        NoteSection(title: T("Вид", "Appearance"))
        NoteRow(title: T("Тема", "Theme")) {
            Choice(options: [("system", T("системная", "system")), ("light", T("светлая", "light")),
                             ("dark", T("тёмная", "dark"))], selection: $theme)
        }
        // Шрифт — в две строки: название и первый вариант, ниже справа
        // остальные (P691).
        NoteRow(title: T("Шрифт записи", "Entry font")) {
            Choice(options: Prefs.fonts.prefix(1).map { ($0.key, $0.name) }, selection: $fontKey,
                   labelFont: { key, on in Prefs.sampleFont(key, bold: on) })
        }
        Choice(options: Prefs.fonts.dropFirst().map { ($0.key, $0.name) }, selection: $fontKey,
               labelFont: { key, on in Prefs.sampleFont(key, bold: on) })
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 12)
            .padding(.top, -3)
            .padding(.bottom, 9)
        // Четыре гаммы двумя столбцами справа от названия (P691, замена P650).
        NoteRow(title: T("Цветовая гамма", "Colour scheme")) {
            SchemeChoice(selection: $calendarTint)
        }
        // «Старая бумага» (P730; с P737 — одним рычажком и уголок, и листок
        // настроек; имя «Ретро» не прижилось, P738). Выключено — прошедшие
        // дни просто цвета прошлого, листки белые, без износа и рваного края.
        // Без пояснения (P753, слово автора).
        NoteRow(title: T("Старая бумага", "Old paper")) {
            Lever(isOn: Binding(get: { !plainPast }, set: { plainPast = !$0 }))
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

    @AppStorage(Reminders.eveningKey) private var evening = -1
    @AppStorage(Prefs.lock) private var locked = false
    @AppStorage(Prefs.ownKeyboardOnly) private var ownKeyboardOnly = false
    @AppStorage(Prefs.theme) private var theme = "system"
    @AppStorage(Prefs.font) private var fontKey = "newyork"
    @AppStorage(Prefs.noWeather) private var noWeather = false
    @AppStorage(Prefs.noAsk) private var noAsk = false
    @AppStorage(Prefs.plainPast) private var plainPast = false
    @AppStorage(DayEvents.onKey) private var calendarEvents = true
    @AppStorage(HealthDay.key) private var health = false
    /// iPhone не смог спросить разрешение на «Здоровье» — у сборки нет права
    /// (P503).
    @State private var healthIssue = false

    /// Что «Здоровье» отдало за сегодня (P604) — видно, есть ли данные.
    @State private var healthToday: String?

    private var healthDetail: String? {
        guard health else { return nil }
        if healthIssue {
            return T("У этой сборки нет права на «Здоровье» — iPhone не может спросить разрешение.",
                     "This build has no Health permission, so iPhone cannot ask for access.")
        }
        // Итог проверки — в окошке «i» вместе с путём (P852, прежде на виду,
        // P687): строка — одна; на виду только беда с правом.
        return nil
    }

    /// Путь, который помог автору (24.10): шагов не было с весны — iPhone
    /// их не считал, а не прятал.
    private var healthHint: String {
        T("Шаги, сон и тренировки берутся из «Здоровья» iPhone и показываются в шапке дня; iPhone спросит разрешение один раз. Нет строки? Шаги считает iPhone: Настройки → Конфиденциальность и безопасность → Движение и фитнес → «Отслеживание фитнеса». Доступ: «Здоровье» → ваш значок → Приложения → Graphomanus.",
          "Steps, sleep and workouts come from iPhone Health and show at the top of a day; iPhone asks for permission once. No line? iPhone counts steps: Settings → Privacy & Security → Motion & Fitness → Fitness Tracking. Access: Health → your picture → Apps → Graphomanus.")
    }
    @AppStorage(DayEvents.holidaysKey) private var calendarHolidays = false
    @AppStorage(Prefs.calendarTint) private var calendarTint = "distance"
    @State private var showingTrash = false
    @State private var showingPDF = false
    @State private var showingBackup = false
    @State private var showingImport = false


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
            // Без связи — «Хранить загруженным» (P633, docs/50): в iCloud
            // iPhone выгружает давно не открытые файлы, и без сети записи
            // не открываются.
            if vault.friendlyPath.hasPrefix("iCloud Drive") {
                Text(T("Без связи: в «Файлах» нажмите на папку и подержите → «Хранить загруженным».",
                       "Without a connection: in Files, press and hold the folder → “Keep Downloaded”."))
                    .font(Look.sans(11.5))
                    .foregroundStyle(Look.inkFaint)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
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
            SafetySheet(onPhone: vault.onPhone, inCloud: vault.inCloud, stuck: vault.uploadStuck()) {
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

    private var version: some View {
        HStack {
            Text(T("Версия", "Version"))
                .font(Look.sans(12))
                .foregroundStyle(Look.inkFaint)
            Spacer()
            Text(Build.label)
                .font(Look.mono(12))
                .foregroundStyle(Look.inkSoft)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .contentShape(Rectangle())
        // Замеры скорости (P910): сколько заняли запуск и открытие разделов
        // на этом телефоне с этим архивом. Для автора и для тех, кто пишет
        // о медленной работе: снимок этого окна говорит, что именно медлит.
        .onLongPressGesture { showingSpeed = true }
        .sheet(isPresented: $showingSpeed) { SpeedSheet(bytes: storageBytes) }
    }

    private func close() {
        shell.tuckIn()
    }
}

/// «Данные в сохранности?» — коротко, что означает ответ, и что делать,
/// если «нет» (P326).
struct SafetySheet: View {
    let onPhone: Bool
    /// Папка в iCloud: строки про «Недавно удалённые» и про записи,
    /// которые не уходят в iCloud (P575).
    var inCloud = false
    var stuck = false
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
                       + T("Если приложение удалить, iPhone сотрёт их вместе с ним, без возврата.", "If the app is deleted, the iPhone erases them with it, for good.")
                     : T("Записи лежат вне приложения, в вашей папке. Если «Graphomanus» удалить, ", "Your entries are outside the app, in your own folder. If Graphomanus is deleted, ")
                       + T("они останутся на месте: в «Файлах», в облаке, на других устройствах.", "they stay where they are: in Files, in the cloud, on other devices."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if !onPhone, inCloud {
                    if stuck {
                        Text(T("Записи этих дней пока не ушли в iCloud, и на других устройствах их ещё нет. "
                               + "Обычно в iCloud кончилось место или выключен iCloud Drive: это видно в "
                               + "«Настройки» › ваше имя › iCloud. На этом iPhone записи целы.",
                               "Entries from these days have not reached iCloud yet, so other devices do not have "
                               + "them. Usually iCloud is out of space or iCloud Drive is off: see Settings › your "
                               + "name › iCloud. On this iPhone the entries are safe."))
                            .font(.callout)
                            .foregroundStyle(Look.ink)
                            .multilineTextAlignment(.center)
                    }
                    Text(T("Удалили что-то по ошибке — в «Файлах» есть «Недавно удалённые»: "
                           + "iCloud Drive держит там удалённое 30 дней.",
                           "Deleted something by mistake? Files has “Recently Deleted”: "
                           + "iCloud Drive keeps deleted items there for 30 days."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

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
        .presentationDetents([.medium, .large])
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

/// Время дела, напоминание и повтор — одним окном (P872, автор: «чтобы не
/// крутить две рулетки, а в два движения выбрать время, периодичность и
/// напоминание»; вместо двух окон — времени и колокольчика, P152, P194).
/// Ролик один — время дела; под ним «Напомнить» только кнопками, считая от
/// этого времени (P873: второго ролика нет). В файле напоминание
/// по-прежнему точным временем «(напомнить ЧЧ:ММ)».
struct RollerSheet: View {

    let roller: Shell.Roller

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var shell: Shell
    /// Время дела.
    @State private var picked = Date()
    /// Напоминание, записанное раньше на своё время, не по кнопке.
    @State private var keptBell: String?
    @State private var bell: Bell = .off
    /// Повтор дела (P359): нет, каждый день, неделю, месяц, год.
    @State private var every: Repeat.Every?

    /// Когда напомнить.
    enum Bell {
        case off, atTime, before15, before60, morning
        /// Записанное на своё время (в файле или прежним роликом): кнопки не
        /// горят, напоминание остаётся, пока не нажали другую (P873).
        case kept

        var title: String {
            switch self {
            case .off: return T("нет", "no")
            case .atTime: return T("в это время", "at the time")
            case .before15: return T("за 15 мин", "15 min before")
            case .before60: return T("за 1 час", "1 hour before")
            case .morning: return T("в 9 утра", "at 9 am")
            case .kept: return ""
            }
        }
    }

    var body: some View {
        NavigationStack {
            // Ролик посередине, слева столбиком повтор, справа — напоминание
            // (P874, автор).
            // Ролик — узкий, с просветом от кнопок (P882, автор: «окошко
            // ролика слишком широкое и чувствительное — выставляя повтор, всё
            // время задеваешь его пальцем»).
            HStack(alignment: .center, spacing: 8) {
                column(T("Повторять", "Repeat"),
                       [nil, .day, .week, .month, .year] as [Repeat.Every?],
                       chip: { kind in
                           chip(kind?.title ?? T("нет", "no"), on: every == kind) { every = kind }
                       })
                // С AM/PM ролику нужно шире — иначе часы 10–12 обрезаны
                // (снимок CI к P882).
                TimeWheel(time: $picked)
                    .frame(width: Clock.twelve ? 176 : 140)
                    .clipped()
                column(T("Напомнить", "Remind"),
                       [Bell.off, .atTime, .before15, .before60, .morning],
                       chip: { kind in chip(kind.title, on: bell == kind) { bell = kind } })
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle(T("Время", "Time"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Отказ от времени — словом, а не «Отменой» (P49, P150):
                // дело остаётся без часа; напоминание «в 9 утра» и своё
                // остаётся, от времени дела — снимается.
                ToolbarItem(placement: .topBarLeading) {
                    Button(T("Без времени", "No time")) { apply(time: nil) }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("Готово", "Done")) { apply(time: picked) }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                guard let i = store.index(of: roller.id) else { return }
                let row = store.planRows[i]
                let time = Clock.date(row.time)
                // Нет времени — ролик с 9 утра: самое частое начало дня (P330).
                picked = Clock.snap(time ?? Clock.at(9))
                bell = Self.bell(row.bell, time: row.time)
                keptBell = row.bell
                every = row.repeats?.every
            }
        }
        .presentationDetents([.height(330)])
    }

    /// Какой готовый ответ у записанного напоминания.
    static func bell(_ bell: String?, time: String?) -> Bell {
        guard let bell else { return .off }
        if let t = Clock.date(time) {
            if Clock.text(t) == bell { return .atTime }
            if Clock.text(t.addingTimeInterval(-900)) == bell { return .before15 }
            if Clock.text(t.addingTimeInterval(-3600)) == bell { return .before60 }
        }
        if Clock.text(Clock.at(9)) == bell { return .morning }
        return .kept
    }

    /// Столбик готовых ответов с подписью сверху (P874).
    private func column<Item: Hashable, Chip: View>(
        _ title: String, _ items: [Item],
        chip: @escaping (Item) -> Chip) -> some View {
        VStack(spacing: 6) {
            Text(title)
                .font(Look.sans(12, weight: .semibold))
                .foregroundStyle(Look.inkSoft)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            ForEach(items, id: \.self) { chip($0) }
        }
        .frame(width: 86)
    }

    private func chip(_ title: String, on: Bool, _ pick: @escaping () -> Void) -> some View {
        Button {
            // Щелчок, как у будильника (P267).
            Feel.tick()
            pick()
        } label: {
            // Все кнопки одного роста и одним шрифтом (P885, автор): длинная
            // надпись — в две строки, а не мельче.
            Text(title)
                .font(Look.sans(12))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.9)
                .foregroundStyle(on ? Look.planBg : Look.accent)
                .padding(.horizontal, 6)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(on ? Look.accent : Look.chrome, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Look.accent.opacity(0.35)))
        }
        .buttonStyle(.plain)
    }

    /// Напоминание по выбранному ответу — от времени дела `time`.
    private func bellText(_ time: Date?) -> String? {
        switch bell {
        case .off: return nil
        case .atTime: return time.map(Clock.text)
        case .before15: return time.map { Clock.text($0.addingTimeInterval(-900)) }
        case .before60: return time.map { Clock.text($0.addingTimeInterval(-3600)) }
        case .morning: return Clock.text(Clock.at(9))
        case .kept: return keptBell
        }
    }

    private func apply(time: Date?) {
        let bellValue = bellText(time)
        if let i = store.index(of: roller.id) {
            let before = store.planRows[i].repeats?.every
            store.planRows[i].time = time.map(Clock.text)
            store.planRows[i].bell = bellValue
            store.save()
            // Повтор поменяли — серия заводится или снимается; иначе, если
            // дело из серии, спросить, только ли здесь новое время (P359).
            if every != before {
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
        if bellValue != nil {
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
    /// 12 часов или 24 — как в самом iPhone (P633; прежде выбирались в
    /// настройках, P602). В файлах время всегда «21:30» — так его читает
    /// любая программа; на экране — как у телефона.
    static var twelve: Bool { forced ?? phoneTwelve }

    /// Только для проверок: заставить часы показывать 12 или 24 часа, не
    /// трогая телефон (P633).
    static var forced: Bool?

    /// Как в самом iPhone — считается один раз (P605): прежде выяснялось на
    /// каждой плашке плана при каждой отрисовке, и листание страниц, где
    /// рисуются три дня сразу, стало отзываться с задержкой.
    private static let phoneTwelve =
        (DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")

    /// «21:30» из файла — на экран: «21:30» или «9:30 PM».
    static func show(_ hhmm: String) -> String {
        guard twelve, hhmm.count == 5, let h = Int(hhmm.prefix(2)) else { return hhmm }
        return "\(h % 12 == 0 ? 12 : h % 12):\(hhmm.suffix(2)) \(h < 12 ? "AM" : "PM")"
    }

    /// Час ровно — «21:00» или «9 PM».
    static func hour(_ h: Int) -> String {
        twelve ? "\(h % 12 == 0 ? 12 : h % 12) \(h < 12 ? "AM" : "PM")" : "\(h):00"
    }

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
                     : T("Записи лягут в iCloud Drive › Graphomanus. Их видно в «Файлах», они есть на iPad и Mac и остаются, даже если удалить приложение.",
                         "Entries go to iCloud Drive › Graphomanus. You can see them in Files, they are on your iPad and Mac, and they stay even if you delete the app."))
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
            guide(T("Копия лежит у Apple; с «Расширенной защитой данных» (Настройки iPhone → ваше имя → iCloud) "
                    + "её прочитают только ваши устройства.",
                    "Apple keeps a copy; with Advanced Data Protection (iPhone Settings → your name → iCloud) "
                    + "only your own devices can read it."))

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

/// Замеры скорости (P910): шаги запуска и открытия разделов по часам
/// самого приложения, размер архива. Проверка на сервере мерит робота, а
/// не приложение (`docs/68`), — настоящие числа есть только здесь, на
/// телефоне человека.
private struct SpeedSheet: View {
    let bytes: Int64?
    @Environment(\.dismiss) private var dismiss

    private var text: String {
        var out = Build.label + "\n"
        if let bytes {
            out += T("архив: ", "archive: ") + ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) + "\n"
        }
        out += "\n" + LaunchClock.lines.joined(separator: "\n")
        // След переходов картотеки (P921): «✗» — события нет в таблице.
        if !DeckTrail.lines.isEmpty {
            out += "\n\n" + DeckTrail.lines.joined(separator: "\n")
        }
        return out
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(text)
                    .font(Look.mono(13))
                    .foregroundStyle(Look.ink)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }
            .navigationTitle(T("Замеры скорости", "Speed measurements"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(T("Готово", "Done")) { dismiss() }
                }
            }
        }
    }
}
