import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Оболочка приложения: шапка, вкладки, экран, нижние кнопки.
///
/// Порядок сверху вниз тот же, что в прототипе: имя экрана, день недели и
/// дата, «План / Дневник», сам экран, полоска вложений и три раздела внизу.
struct RootView: View {

    @EnvironmentObject private var vault: Vault
    /// Покупка: месяц пробы и разовая покупка (P432).
    @ObservedObject private var purchase = Purchase.shared
    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var archive: Archive
    @EnvironmentObject private var shell: Shell

    /// Карта ещё на плашке, пока та уезжает (P242).
    /// Карта собрана заранее, в стороне, вскоре после запуска (P581): на
    /// большом архиве её сборка по нажатию держала экран секундами.
    @State private var mapReady = false

    /// Клавиатура: над ней встаёт полоска вложений (P253).
    @StateObject private var keyboard = KeyboardWatch()
    /// Высота полосы «домой» — меряется раскладкой и запоминается, пока
    /// клавиатуры нет (P450). Прежде её спрашивали у окна прямо во время
    /// рисования экрана: с 103-й весь верхний слой — настройки, меню,
    /// разделы — переставал обновляться.
    @State private var homeBar: CGFloat = 0
    /// Полоса «домой» по окну: читается один раз, не в теле вида (P495).
    @State private var windowBottom: CGFloat = 0

    // Настройки (P249): замок, скрытие страницы, тема.
    @Environment(\.scenePhase) private var phase
    /// Размер текста iPhone (P465): сменили — страницы собираются заново.
    @Environment(\.dynamicTypeSize) private var systemText
    @AppStorage(Prefs.lock) private var lockOn = false
    @AppStorage(Prefs.theme) private var theme = "system"
    @AppStorage(Prefs.textSize) private var textSize = 0
    @AppStorage(Prefs.font) private var fontKey = "newyork"
    /// Цветовая гамма (P498): меняется — страницы и строки собираются заново.
    @AppStorage(Prefs.calendarTint) private var palette = "distance"
    @State private var locked = UserDefaults.standard.bool(forKey: Prefs.lock)
    /// Приложение открыли на дневнике, пока стоял замок: поле возьмёт ввод,
    /// когда замок откроют, — не поверх него (P403).
    @State private var waitingToWrite = false

    /// Открыли на дневнике — страница у конца записи, но клавиатура сама
    /// не поднимается (P416; прежде поле брало ввод само, P403): поднятая
    /// клавиатура закрывала нижнюю строку разделов, и человек терялся.
    /// Время по-прежнему ставится с первой буквой — когда он сам коснётся.
    private func startWriting() {}

    private var scheme: ColorScheme? {
        theme == "light" ? .light : theme == "dark" ? .dark : nil
    }

    private func unlock() {
        LockView.check(reason: T("Открыть записи", "Open your entries")) { ok in
            if ok {
                locked = false
                // Замок открыт — теперь и клавиатура (P403).
                if waitingToWrite { waitingToWrite = false; startWriting() }
            }
        }
    }


    /// Человек должен увидеть полный путь до того, как что-то создано.
    private static func proposalText(_ p: Vault.Proposal) -> String {
        var out = T("Записей здесь не нашлось. Приложение может завести новую папку:\n\n",
                    "No entries here. The app can make a new folder:\n\n")
        out += p.path
        out += T("\n\nЭто будет отдельный архив — прежние записи останутся там, где лежат.",
                 "\n\nIt will be a separate archive — earlier entries stay where they are.")
        if p.insideArchive {
            out += T("\n\nПохоже, вы зашли внутрь уже существующего архива. "
                     + "Тогда выберите не эту папку, а саму «\(Vault.folderName)» — "
                     + "или место, где она лежит.",
                     "\n\nIt looks like you went inside an existing archive. "
                     + "Choose “\(Vault.folderName)” itself instead — or the place where it lies.")
        }
        return out
    }

    private static func transferText(_ t: Transfer.Offer) -> String {
        var out = T("В прежней папке осталось записей: \(t.records).\n\n",
                    "Entries left in the previous folder: \(t.records).\n\n")
        out += t.fromPath
        out += T("\n\nПеренести их сюда:\n\n", "\n\nMove them here:\n\n")
        out += t.toPath
        out += T("\n\nСначала делается копия, и только потом убирается "
                 + "прежний файл. Прервётся — ничего не пропадёт, перенос можно "
                 + "будет продолжить.",
                 "\n\nEach file is copied first, and only then the old one is removed. "
                 + "If it is interrupted, nothing is lost — you can continue.")
        return out
    }

    /// Снимок, видео, документ — во весь экран; голос — нет, он шторкой
    /// (P360).
    private var coverShown: Binding<Shell.OpenedPhoto?> {
        Binding(get: { shell.openedPhoto.flatMap { VoiceShown.isVoice($0, store) ? nil : $0 } },
                set: { shell.openedPhoto = $0 })
    }

    /// Имя корзины, как его видно в «Файлах»: «Trash» или прежнее
    /// «Корзина» (P353).
    private var trashFolder: String {
        guard let root = vault.root else { return Vault.trashName }
        return Vault.trash(in: root).lastPathComponent
    }

    /// План и дневник — одна страница (P408): в корзину уходит весь день.
    private var trashTitle: String {
        T("Убрать этот день в корзину?", "Move this day to the trash?")
    }

    private var trashMessage: String {
        T("План и запись этого дня переедут в папку «", "The plan and the entry of this day will move to the “") + trashFolder
            + T("» на 30 дней. Снимки и голос останутся на месте. Вернуть можно в Настройки → Корзина.",
                "” folder for 30 days. Photos and voice notes stay where they are. You can restore it in Settings → Trash.")
    }

    fileprivate static func renameText(_ r: Rename.Report) -> String {
        var out = T("Папок переименовано: \(r.folders). Записей поправлено: \(r.files).",
                    "Folders renamed: \(r.folders). Entries updated: \(r.files).")
        if !r.stuck.isEmpty {
            out += T("\n\nОстались под прежним именем: ", "\n\nKept their old name: ")
                + r.stuck.joined(separator: ", ")
            out += T(". Они работают как раньше; перевод можно запустить ещё раз.",
                     ". They work as before; you can run the renaming again.")
        }
        if r.skipped > 0 {
            out += T("\n\nНе поправлено записей: \(r.skipped) — они ещё в iCloud или "
                     + "изменились в другом месте. Снимки в них видны и так; "
                     + "перевод можно запустить ещё раз позже.",
                     "\n\nEntries not updated: \(r.skipped) — they are still in iCloud or "
                     + "were changed elsewhere. Their photos show anyway; you can run it again later.")
        }
        if r.kept > 0 {
            out += T("\n\nФайлов с одинаковыми именами, но разных: \(r.kept). "
                     + "Они остались в папках с прежними именами — ничего не затёрто.",
                     "\n\nFiles with the same name but different contents: \(r.kept). "
                     + "They stayed in the folders with the old names — nothing was overwritten.")
        }
        return out
    }

    private static func reportText(_ r: Transfer.Report) -> String {
        var out = T("Перенесено файлов: \(r.moved).", "Files moved: \(r.moved).")
        if r.kept > 0 {
            out += T("\n\nОсталось в прежней папке: \(r.kept). "
                     + "За те же числа здесь уже есть записи, и приложение "
                     + "не стало решать за вас, какая из них важнее. Обе целы.",
                     "\n\nLeft in the previous folder: \(r.kept). "
                     + "There are already entries for those dates here, and the app did not "
                     + "decide for you which one matters more. Both are safe.")
        }
        if r.failed > 0 {
            out += T("\n\nНе удалось перенести: \(r.failed). Эти файлы остались на прежнем месте.",
                     "\n\nCould not move: \(r.failed). These files stayed where they were.")
        }
        if r.kept == 0 && r.failed == 0 {
            out += T(" Прежняя папка осталась на месте, но записей в ней больше нет.",
                     " The previous folder is still there, but it has no entries any more.")
        } else {
            out += T("\n\nПрежняя папка:\n\n", "\n\nPrevious folder:\n\n") + r.fromPath
        }
        return out
    }

    private static var moved: String {
        T("Вы её переименовали или передвинули. Приложение пошло за ней следом "
          + "и пишет теперь сюда:",
          "You renamed or moved it. The app followed it and now writes here:")
    }

    var body: some View {
        Group {
            if vault.root == nil { WelcomeView() } else { app }
        }
        // Клавиатура с приставкой (P546) не сдвигает экран: со 140-й,
        // пока её смахивали, весь экран вместе с верхней строкой уезжал
        // вверх на высоту приставки (снимок автора, P548).
        .ignoresSafeArea(.keyboard)
        // Замок и скрытие страницы в переключателе приложений (P249).
        .overlay {
            if lockOn && locked {
                LockView(unlock: unlock)
            // Пункта «прятать страницу» больше нет (P293): прячется только
            // под замком — закрытые записи не видны и в списке приложений.
            } else if lockOn && phase != .active {
                Look.chrome.ignoresSafeArea()
            }
        }
        .onChange(of: phase) { _, now in
            if now == .background && lockOn { locked = true }
        }
        // Каждое открытие приложения (и возвращение после паузы, P346) на
        // дневнике — сразу писать (P403).
        .onChange(of: shell.freshStart) { _, _ in
            if lockOn && locked { waitingToWrite = true } else { startWriting() }
        }
        // Записи переехали — «Вернуться к прежней папке», новая папка после
        // «Завести», «На этом iPhone», уровень поправлен при запуске. Страница
        // и опись перечитываются с нового места: прежде после возврата к
        // прежней папке на экране оставался день, прочитанный со старого
        // (P426).
        .onChange(of: vault.root) { _, now in
            guard now != nil else { return }
            store.load()
            archive.reload()
        }
        .preferredColorScheme(scheme)
        // Проба первого запуска из настроек (P452).
        .fullScreenCover(isPresented: $shell.trialWelcome) {
            WelcomeView(trial: true)
                .environmentObject(vault)
                .environmentObject(shell)
                .environmentObject(store)
                .environmentObject(archive)
        }
        .onAppear {
            purchase.start()
            // Объём папки — заранее, чтобы листок настроек не менялся (P486).
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) { SettingsSticker.warm(vault.root) }
        }
        .sheet(isPresented: $purchase.asking) { PurchaseSheet(purchase: purchase) }
        .fileImporter(isPresented: $shell.picking, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                vault.adopt(url)
                store.load()
                archive.reload()
                // Выбрав папку, человек хочет увидеть свои записи, а не тот
                // экран, с которого он ушёл за папкой (решение P170).
                shell.screen = .today
            }
        }
        .alert(T("Завести здесь новую папку?", "Make a new folder here?"),
               isPresented: Binding(get: { vault.proposal != nil },
                                    set: { if !$0 { vault.declineProposal() } }),
               presenting: vault.proposal) { p in
            Button(T("Отмена", "Cancel"), role: .cancel) { vault.declineProposal() }
            Button(T("Завести", "Make")) { vault.acceptProposal() }
        } message: { p in
            Text(Self.proposalText(p))
        }
        .alert(T("Перенести записи?", "Move your entries?"),
               isPresented: Binding(get: { vault.transfer != nil },
                                    set: { if !$0 { vault.declineTransfer() } }),
               presenting: vault.transfer) { _ in
            Button(T("Оставить", "Leave them"), role: .cancel) { vault.declineTransfer() }
            Button(T("Перенести", "Move")) {
                vault.moveRecords()
            }
        } message: { t in
            Text(Self.transferText(t))
        }
        .alert(T("Перенос закончен", "Moving finished"),
               isPresented: Binding(get: { vault.transferDone != nil },
                                    set: { if !$0 { vault.transferDone = nil } }),
               presenting: vault.transferDone) { _ in
            Button(T("Понятно", "OK")) {
                vault.transferDone = nil
                store.load()
                archive.reload()
            }
        } message: { r in
            Text(Self.reportText(r))
        }
        .modifier(RenameShown())
        // Пора ли сделать резервную копию (P368) — спросить, но не делать.
        .modifier(BackupReminder())
        // Голосовая запись — небольшой шторкой снизу, а не на весь экран
        // (P360).
        .modifier(VoiceShown())
        .alert(T("Папка переехала", "The folder moved"),
               isPresented: Binding(get: { vault.moved != nil },
                                    set: { if !$0 { vault.moved = nil } })) {
            Button(T("Понятно", "OK")) { vault.moved = nil }
        } message: {
            Text(Self.moved + "\n\n" + (vault.moved ?? ""))
        }
        // Запись поправили в другом месте, пока она была открыта здесь.
        // Ничего не затёрто: чужая правка на экране, своя — рядом в папке.
        // Человек должен знать, где её искать (решение P183).
        .alert(T("Запись изменилась в другом месте", "The entry changed elsewhere"),
               isPresented: Binding(get: { store.conflict != nil },
                                    set: { if !$0 { store.conflict = nil } })) {
            Button(T("Понятно", "OK")) { store.conflict = nil }
        } message: {
            Text(Self.conflictText(store.conflict ?? ""))
        }
    }

    static func conflictText(_ name: String) -> String {
        T("Пока день был открыт здесь, его файл поправили в другом месте — на Mac или на другом устройстве. На экране теперь та версия.\n\nВаша правка не пропала: она лежит рядом, в той же папке, в файле «\(name)». Откройте его в «Файлах» и перенесите нужное.",
          "While the day was open here, its file was changed elsewhere — on a Mac or another device. The screen now shows that version.\n\nYour change is not lost: it is next to it, in the same folder, in the file “\(name)”. Open it in Files and move over what you need.")
    }

    private var app: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                // Верхняя строка-ориентир (P494): те же четыре раздела, всегда
                // на месте, клавиатура её не трогает. Всё остальное — уголки,
                // имя дня — стоит ниже неё.
                Color.clear.frame(height: Self.topBarHeight)
                canvas
                    // Сменили размер или шрифт записи — страницы собираются
                    // заново: поля UIKit помнят свой шрифт (P274).
                    .id("\(textSize)|\(fontKey)|\(systemText)|\(palette)")
                tabbar
            }
            // Нижний отступ (полоса «домой») — свой, постоянный, а не
            // системный (P447): пока открыта клавиатура, система считала
            // низ экрана занятым ею, и нижняя строка опускалась на высоту
            // полосы «домой»; клавиатура уходила — строка прыгала вверх
            // (запись экрана автора). Это и был «скачок нижней строки».
            // Все системные отступы снизу, а не только обычный (P449): со
            // 103-й, пока клавиатура была видна, система всё равно добавляла
            // свой отступ поверх нашего — строка стояла выше и в конце
            // падала вниз (вторая запись автора).
            .ignoresSafeArea(.all, edges: .bottom)
            // На странице дня полоса над шапкой (часы, батарея) — того же
            // цвета, что лист: шапка — продолжение страницы (P434).
            .background((shell.screen == .today ? Ru.tint(store.date) : Look.chrome).ignoresSafeArea())

            // Верхней строки больше нет: шестерёнка и три точки нарисованы
            // на уголках бумаги, торчащих сверху слева и справа, а имя дня
            // поднялось между ними (P229).
            // Уголки торчат из-под верхней строки (P496): их верх спрятан
            // под ней на `Corner.lift`.
            corners.padding(.top, Self.topBarHeight - Corner.lift)

            // Верхняя строка лежит поверх уголков, но под листками: листок
            // открыт — касание по ней его закрывает, как и по нижней.
            topBar
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            // Листки висят от нижнего края верхней строки; выезжают они из-под
            // неё, поэтому всё, что выше, обрезано.
            ZStack(alignment: .topTrailing) {
                if shell.showingMenu { MenuSticker() }
                if let m = shell.movingTask {
                    MoveDaySticker(task: m)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                if shell.showingSettings {
                    SettingsSticker().frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .padding(.top, Self.topBarHeight)
            // Нижняя строка — самый верхний слой, как и верхняя (P515): листок
            // заходит под неё. Пока листок открыт, поверх него лежит точная
            // копия строки на том же месте; закрыт — копии нет.
            if shell.showingSettings || shell.showingMenu || shell.movingTask != nil {
                tabbar
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .ignoresSafeArea(.all, edges: .bottom)
            }
            // Строки разделов над клавиатурой на карте и в поиске больше нет
            // (P499): верхняя строка всегда на месте.
            // Подсказки для первого знакомства (P427) — поверх всего, когда
            // экран спокоен.
            HintLayer(screen: shell.screen,
                      quiet: !shell.showingMenu && !shell.showingSettings
                          && shell.movingTask == nil && keyboard.height == 0
                          && vault.moving == nil)
            // Для проверок движения (P552): какой день открыт — невидимой
            // строкой, только когда приложение запустила проверка.
            if Vault.isUITest {
                Text(Calendar.current.isDate(store.date, inSameDayAs: DayStore.today())
                     ? "today" : String(Int(store.date.timeIntervalSince1970)))
                    .font(.system(size: 2))
                    .opacity(0.02)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("openDay")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // Какой раздел открыт — для замеров большого архива (P567).
                Text("\(shell.screen)")
                    .font(.system(size: 2))
                    .opacity(0.02)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("openScreen")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            }
            if let notice = shell.notice {
                toast(notice)
                    // Над клавиатурой и полоской на ней, иначе не видно.
                    .padding(.bottom, keyboard.height > 0 ? keyboard.height + 24 : 0)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
            // Перенос между памятью телефона и iCloud идёт минутами. Пока он
            // идёт, трогать записи нельзя: экран закрыт, и на нём видно, что
            // происходит и сколько осталось.
            if let m = vault.moving {
                MovingView(progress: m)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

        }
        // Нижние разделы стоят на месте, что бы ни случилось: клавиатура их
        // не поднимает. Иначе значки пляшут по экрану и в них не попасть.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        // Мерка — во весь экран: внутри безопасной области полоса «домой»
        // читалась бы нулём. Пока видна клавиатура, низ занят ею — тогда
        // прежняя мерка остаётся; полоса «домой» не бывает выше 60 точек.
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { if g.safeAreaInsets.bottom < 60 { homeBar = g.safeAreaInsets.bottom } }
                    // Меряется один раз (P456): полоса «домой» у телефона
                    // всегда одна. Перемеряя её, строка в конце ухода
                    // клавиатуры ловила промежуточный низ и улетала вверх
                    // (запись экрана автора). Поправка — только если первая
                    // мерка пришла пустой.
                    .onChange(of: g.safeAreaInsets.bottom) { _, now in
                        if homeBar == 0, keyboard.height == 0, now > 0, now < 60 { homeBar = now }
                    }
            }
            .ignoresSafeArea()
        }
        .tint(Look.accent)
        .onAppear {
            windowBottom = UIApplication.shared.connectedScenes
                .compactMap { ($0 as? UIWindowScene)?.keyWindow }.first?.safeAreaInsets.bottom ?? 0
        }
        .onChange(of: shell.screen) { old, new in
            LagWatch.note(new)
            follow(from: old, to: new)
            if new == .map { mapReady = true }
        }
        // Снимок во весь экран — один на всё приложение: открывают его и
        // из плана, и из дневника (P203).
        .fullScreenCover(item: coverShown) { opened in
            let links = store.links(opened.tab)
            let link = opened.link ?? (links.indices.contains(opened.index) ? links[opened.index] : nil)
            let all = store.dayPhotos
            // Снимок — листаются все снимки дня, и из записи, и из ленты, не
            // закрывая открытого (P564; прежде только снимки своей ленты, P278).
            if let link, let start = all.firstIndex(of: link) {
                StripViewer(count: all.count, start: start,
                            url: { store.photoURL(all[$0]) },
                            remove: { i in
                                let one = all[i]
                                for tab in [Shell.Tab.diary, .plan] {
                                    if let k = store.links(tab).firstIndex(of: one), store.canEdit(tab) {
                                        return { delete in
                                            shell.openedPhoto = nil
                                            shell.say(store.removeAttachment(at: k, from: tab, delete: delete))
                                        }
                                    }
                                }
                                return nil
                            },
                            // Снимок из записи — вернуть в ленту (P216).
                            giveBack: { i in
                                let one = all[i]
                                guard store.canEditDiary, !store.stripLinks.contains(one) else { return nil }
                                return {
                                    store.returnToStrip(one)
                                    shell.openedPhoto = nil
                                }
                            },
                            close: { shell.openedPhoto = nil })
            // Видео и файл из ленты — листаются по ленте, как прежде (P278).
            } else if opened.url == nil, links.indices.contains(opened.index) {
                StripViewer(count: links.count, start: opened.index,
                            url: { store.photoURL(links[$0]) },
                            remove: { i in
                                guard store.canEdit(opened.tab) else { return nil }
                                return { delete in
                                    shell.openedPhoto = nil
                                    shell.say(store.removeAttachment(at: i, from: opened.tab, delete: delete))
                                }
                            },
                            close: { shell.openedPhoto = nil })
            } else {
            AttachmentViewer(
                url: opened.url ?? (links.indices.contains(opened.index)
                    ? store.photoURL(links[opened.index]) : nil),
                onRemove: opened.url == nil && store.canEdit(opened.tab) ? { delete in
                    shell.openedPhoto = nil
                    shell.say(store.removeAttachment(at: opened.index, from: opened.tab, delete: delete))
                } : nil,
                // Снимок из текста можно вернуть в полоску (P216).
                onReturn: opened.link != nil && store.canEdit(opened.tab) ? {
                    if let link = opened.link { store.returnToStrip(link) }
                    shell.openedPhoto = nil
                } : nil,
                close: { shell.openedPhoto = nil })
            }
        }
        .sheet(isPresented: $shell.showingFile) { FileSheet() }
        .sheet(isPresented: $shell.showingWeek) { WeekSheet() }
        .confirmationDialog(trashTitle,
                            isPresented: $shell.trashAsk, titleVisibility: .visible) {
            Button(T("Убрать в корзину", "Move to trash"), role: .destructive) {
                store.save()
                if Trash.put(store.date, parts: [Shell.Tab.plan.vaultFolder, Shell.Tab.diary.vaultFolder],
                             in: vault) {
                    store.load()
                    archive.reload()
                    store.syncUpcomingReminders()
                    shell.say(T("День в корзине. Вернуть — Настройки → Корзина.", "The day is in the trash. Restore it in Settings → Trash."))
                } else {
                    shell.say(T("Тут нечего убирать.", "Nothing to remove here."))
                }
            }
        } message: {
            Text(trashMessage)
        }
        .sheet(item: $shell.roller) { RollerSheet(roller: $0) }
        // Две версии дня сложены в одну (P570) — сказать.
        .onChange(of: store.syncNotice) { _, _ in
            shell.say(T("Запись дополнена тем, что было записано на другом устройстве",
                        "The entry now includes what was written on another device"))
        }
        .onAppear {
            // Просьбы кнопок над клавиатурой — открытой странице (P279).
            KeyboardBar.ask = { [shell] ask in shell.keyboardAsk = ask }
            // Опись архива нужна не только календарю и поиску: без неё
            // облачко «…помнишь?» не знает, есть ли что вспомнить, и не
            // появляется никогда. Читаем папку сразу при запуске.
            LagWatch.start()
            // В стороне (P565): прежде папка читалась целиком до первого
            // кадра — чем больше дневник, тем дольше открывалось приложение.
            archive.reloadSoon()
            // Свои места — для подписи точек в дневнике (P559), тоже в стороне.
            Places.loadSoon(vault)
            // Карту — заранее, когда запуск уже позади (P581).
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { mapReady = true }
            LaunchClock.step(T("первый экран", "first screen"))
            if Vault.speedTestOn {
                shell.say(T("Открыт пробный архив. Вернуться — в настройках, долгим нажатием на «Версия».",
                            "The test archive is open. To go back, long-press “Version” in Settings."), for: 5)
            }
            // С какой вкладки открывать — из настроек (P249).
            shell.tab = Prefs.openingTab
            shell.openRequestedScreen(store)
            // Первое открытие: план — сверху, дневник — к концу записи с
            // пустыми строками под ней (P346).
            shell.freshStart += 1
        }
    }

    /// Высота верхней строки-ориентира (P494, P496): значки и названия,
    /// на 15% мельче нижних.
    static let topBarHeight: CGFloat = 60

    private var topBar: some View {
        HStack(spacing: 0) {
            section("календарь", T("Календарь", "Calendar"), .calendar, small: true)
            section("сегодня", T("День", "Day"), .today, small: true)
            section("карта", T("Карта", "Map"), .map, small: true)
            section("поиск", T("Поиск", "Search"), .search, small: true)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .frame(height: Self.topBarHeight)
        // По этим меткам проверки движения находят строку и её кнопки (P552).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("topBar")
        // Нижний край неровный — вторая половина той же рваной бумаги, что
        // и верх нижней строки (P517): зубцы те же, выступ у одной —
        // выемка у другой.
        .background(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                KraftPaper()
                    .clipShape(TornEdgeBottom())
                TornEdgeBottomLine()
                    .stroke(Look.kraftEdge.opacity(0.55), lineWidth: 0.8)
                    .frame(height: TornEdge.depth + 1)
                    .clipped()
            }
            .padding(.bottom, -TornEdge.depth)
        }
    }

    /// Область содержимого: шторка «Подробности» живёт только внутри неё.
    private var canvas: some View {
        ZStack(alignment: .trailing) {
            screen
            // Шторки «Подробности» больше нет (P408).
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    // MARK: - Шапка

    /// Шестерёнка и три точки — на уголках бумаги, торчащих сверху: левый
    /// желтоватый, как бумажка настроек, правый голубой, как бумажка меню
    /// (P434; прежде наоборот).
    /// У уголков тень — они лежат поверх страницы (P229). Меню у каждого
    /// экрана своё; кнопка не пропадает, что бы ни было открыто (P188).
    private var corners: some View {
        HStack(alignment: .top) {
            Button {
                if closeDrawer() { return }
                // Открытая клавиатура и строка над ней не должны мешать
                // листку настроек — убираются вниз, как при касании по
                // точке на карте (P309).
                hideKeyboard()
                shell.pullOut(settings: true)
            } label: {
                Corner(leading: true, paper: Look.sticker, edge: Look.stickerEdge, icon: "gearshape",
                       tint: shell.showingSettings ? Look.accent : Look.inkSoft)
                    // Пока листок вытянут, его угол — это и есть уголок.
                    .opacity(shell.showingSettings ? 0 : 1)
            }
            .buttonStyle(.plain)
            // Уголок тянут вниз, и бумажка идёт за пальцем (P233).
            .simultaneousGesture(pull(\.showingSettings, \.settingsPull))
            .accessibilityLabel(T("Настройки", "Settings"))

            Spacer(minLength: 0)

            Button {
                if closeDrawer() { return }
                hideKeyboard()
                shell.pullOut(settings: false)
            } label: {
                Corner(leading: false, paper: Look.sticker, edge: Look.stickerEdge, icon: "ellipsis",
                       tint: dotsLit ? Look.accent : Look.inkSoft)
                    .opacity(shell.showingMenu ? 0 : 1)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(pull(\.showingMenu, \.menuPull))
            .accessibilityLabel(dotsLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Бумажку вытягивают за уголок: она идёт за пальцем; отпустили,
    /// протянув заметно, — доезжает сама, иначе уезжает обратно (P233).
    private func pull(_ showing: ReferenceWritableKeyPath<Shell, Bool>,
                      _ amount: ReferenceWritableKeyPath<Shell, CGFloat?>) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { drag in
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) {
                    if !shell[keyPath: showing] {
                        shell[keyPath: showing] = true
                        hideKeyboard()
                    }
                    shell[keyPath: amount] = max(0, 1 - max(0, drag.translation.height) / 420)
                }
            }
            .onEnded { drag in
                let settings = showing == \Shell.showingSettings
                if drag.translation.height > 90 || drag.predictedEndTranslation.height > 220 {
                    shell.pullOut(settings: settings)
                } else {
                    shell.tuckIn(settings: settings)
                }
            }
    }

    /// Точки горят, когда в меню включено что-то необычное: режим
    /// изменений на странице дня или поиск не по всему архиву.
    private var dotsLit: Bool {
        switch shell.screen {
        case .today:    return store.editing(shell.tab)
        case .calendar, .map: return false
        case .search:   return shell.scope != .all
        }
    }

    private var dotsLabel: String {
        switch shell.screen {
        case .today:    return T("Меню страницы", "Page menu")
        case .calendar: return T("Меню календаря", "Calendar menu")
        case .map:      return T("Меню карты", "Map menu")
        case .search:   return T("Меню поиска", "Search menu")
        }
    }

    // MARK: - Экран

    /// Книга и два вкладыша.
    ///
    /// «Сегодня» — сама книга, она лежит всегда. Календарь и поиск наезжают
    /// на неё сверху — оба, как кладут сверху вкладыш в бумажном
    /// ежедневнике. Поиск выезжал снизу, из-под книги: снизу вещи не
    /// приходят, туда их убирают (решения P146, P178).
    ///
    /// Вкладыши не появляются и не исчезают, а стоят за краем экрана и
    /// выезжают: собирать их заново в начале хода — значит уронить первые
    /// кадры, а ход должен быть гладким.
    private var screen: some View {
        GeometryReader { geo in
            ZStack {
                // Под плашкой книга не отзывается. Иначе движение вбок по
                // поиску доставалось перелистыванию дней, и человека
                // выбрасывало на «Сегодня» (решение P160).
                panel(.today, from: .top, over: geo.size) {
                    DayPages().allowsHitTesting(shell.screen == .today)
                }
                panel(.calendar, from: .top, over: geo.size) { CalendarView() }
                // Карта — такая же плашка. Собирается заранее, через несколько
                // секунд после запуска, и дальше ждёт на своей плашке (P581);
                // о месте спрашивает, только когда её впервые открыли.
                // Прежде собиралась по нажатию и разбиралась после ухода (P242).
                panel(.map, from: .top, over: geo.size) {
                    if mapReady || shell.screen == .map { MapScreen() } else { Color.clear }
                }
                .accessibilityHidden(shell.screen != .map)
                panel(.search, from: .top, over: geo.size) { SearchView() }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    /// Вкладыш: лежит за краем экрана и выезжает на книгу.
    private func panel<V: View>(_ which: Shell.Screen, from edge: Edge,
                                over size: CGSize,
                                @ViewBuilder content: () -> V) -> some View {
        let down = shell.stack.contains(which)
        let on = shell.stack.last == which
        // Плашка уезжает ровно на свою высоту — не дальше.
        //
        // Раньше её уводили заведомо далеко, на 1200 точек, и она проходила
        // вдвое больше, чем видно на экране: разгон и торможение хода
        // приходились на путь за краем. Оттого приход выглядел мягким, а
        // уход — резким: на экране оставалась только разгонная половина
        // (решение P181). Толщина торца прибавляется: он тоже должен уйти
        // за край.
        //
        // До первой раскладки высота нулевая. Если поверить ей, плашки
        // окажутся на книге и мигнут при запуске — а ничто не должно
        // двигаться само (P113), — поэтому до измерения уводим их далеко.
        //
        // Сверх торца — ещё и его тень: стоящая за краем плашка не должна
        // бросать тень на экран. Тень под шапкой рисуется нарочно, одна на
        // все экраны (решение P192).
        let away = (edge == .top ? -1 : 1)
            * (size.height > 0 ? size.height + BoardEdge.depth + BoardEdge.shade : 1200)
        return content()
            .frame(width: size.width, height: size.height)
            .background(Look.chrome)
            // Торец стоит с той стороны, которой плашка идёт вперёд, и
            // выступает за её край — то есть лежит на книге, а не на самой
            // плашке. На месте он уходит за край экрана и не виден: толщина
            // показывается движением, а стоящее не должно ничего занимать.
            .overlay(alignment: edge == .top ? .bottom : .top) {
                BoardEdge(fromTop: edge == .top)
                    .offset(y: edge == .top ? BoardEdge.depth : -BoardEdge.depth)
            }
            .offset(y: down ? 0 : away)
            // Новая плашка ложится поверх прежних (P501).
            .zIndex(down ? Double((shell.stack.firstIndex(of: which) ?? 0) + 1) : 0)
            // Ловит касания только верхняя: под ней другая плашка или
            // живая книга.
            .allowsHitTesting(on)
    }

    // MARK: - Разделы

    private var tabbar: some View {
        HStack(spacing: 0) {
            // Сегодня, календарь, карта, поиск (P239). Глобус нарисован
            // автором (P248).
            section("календарь", T("Календарь", "Calendar"), .calendar, compact: true)
            section("сегодня", T("День", "Day"), .today, compact: true)
            section("карта", T("Карта", "Map"), .map, compact: true)
            section("поиск", T("Поиск", "Search"), .search, compact: true)
        }
        // Значки и названия — как у верхней строки, а сама полоса тоньше на
        // 15% (P506): не высота ряда только, а вся толщина вместе с отступом
        // над полосой «домой». Поля сверху и снизу по 2 (P510): при 4 надписи
        // не хватало места.
        .padding(.vertical, 2)
        .frame(height: 55)
        // Над полосой «домой» — её высота у самого окна, она не меняется
        // от клавиатуры (P447), меряется раскладкой (P450).
        .padding(.bottom, homeLift)
        // Крафт-картон с оторванным верхним краем, до самого низа экрана
        // (P297). Край заходит на строку вложений на глубину зубцов.
        .background(alignment: .top) {
            ZStack(alignment: .top) {
                KraftPaper()
                    .clipShape(TornEdge())
                // Только зубцы, не вся закрытая фигура — иначе обводка
                // прибавляла ещё и прямую черту понизу (P324).
                TornEdgeLine()
                    .stroke(Look.kraftEdge.opacity(0.55), lineWidth: 0.8)
                    .frame(height: TornEdge.depth + 1)
                    .clipped()
            }
            .padding(.top, -TornEdge.depth)
            .ignoresSafeArea(edges: .bottom)
        }
        // Где верх строки — по нему листок настроек кончается над значками
        // и рамкой открытого раздела (P424).
        .background {
            GeometryReader { g in
                Color.clear
                    .onAppear { shell.barTop = g.frame(in: .global).minY }
                    .onChange(of: g.frame(in: .global).minY) { _, y in shell.barTop = y }
            }
        }
    }

    /// Отступ под полосой «домой» и ещё немного вверх (P491): названия под
    /// значками стояли на самой нижней линии. Берётся и высота полосы у
    /// окна — мерка раскладкой иногда приходит нулём (P469).
    private var homeLift: CGFloat {
        max(0, max(homeBar, windowBottom) - 6)
    }

    private func scale(_ target: Shell.Screen) -> CGFloat {
        switch target {
        case .today:    return 1.10
        case .search:   return 1.05
        case .calendar, .map: return 1
        }
    }

    /// Касание по разделу — внизу экрана или в строке над клавиатурой
    /// (P423): одно и то же.
    private func tapSection(_ target: Shell.Screen) {
        // Открыта шторка «Подробности» — первое касание только убирает
        // её, второе уже открывает раздел (P342).
        if closeDrawer() { return }
        store.prune()
        // Раздел меняется сразу, а запись дня и перечитывание папки идут
        // следом, в следующем такте (P472): раньше они шли до смены экрана
        // и держали палец — перечитывание читает каждый файл папки, чем
        // больше дневник (и iCloud), тем дольше кнопка «думала». Только
        // уход на другой день пишет прежний день сразу — иначе запись
        // легла бы не в тот день.
        let again = shell.screen == target
        if !again { LaunchClock.opened("\(target)", since: Date()) }
        let changesDay = target == .today && again && !store.isToday
        if changesDay { store.save() }
        // Каждый раздел помнит, где его оставили (P576): ушли с прошлого дня,
        // месяца или находки на карту — по нажатию возвращаемся туда же.
        // Второе нажатие по открытому разделу — в исходное состояние:
        // «День» — на сегодня, календарь — на этот месяц, поиск — пустой,
        // карта — туда, где человек сейчас (P577). Прежде второе нажатие
        // убирало плашку (P501) — отменено.
        if again {
            switch target {
            case .today:
                if !store.isToday {
                    // Возвращаемся не мгновенно, а перелистнув страницы:
                    // дорога домой должна быть видна (решение P164).
                    shell.say(T("Вернулись на сегодня", "Back to today"))
                    shell.goHome = true
                }
                return
            case .calendar:
                shell.calendarHome = true
                return
            case .search:
                hideKeyboard()
                shell.query = ""
                shell.scope = .all
                shell.find = .all
                shell.searchHome += 1
                return
            case .map:
                shell.mapHome += 1
                return
            }
        }
        open(target)
        if target != .today {
            // Опись читается в стороне, запись дня — после того, как раздел
            // уже поехал (P483): ничто не стоит между касанием и ходом.
            archive.reloadSoon()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.save() }
    }

    private func section(_ icon: String, _ name: String, _ target: Shell.Screen,
                         system: Bool = false, small: Bool = false,
                         compact: Bool = false) -> some View {
        let on = shell.screen == target
        // Верхняя строка и нижняя — одних размеров (P500): значки и названия
        // на 15% мельче прежней нижней (P496).
        let k: CGFloat = (small || compact) ? 0.85 : 1
        let act = {
            if small {
                // Листок открыт — касание по строке только закрывает его.
                if shell.showingSettings { shell.tuckIn(settings: true); return }
                if shell.showingMenu { shell.tuckIn(settings: false); return }
            }
            tapSection(target)
        }
        // Срабатывает в миг касания (P565), а не когда палец отпустили, как
        // обычная кнопка iPhone; само касание кнопки — только если касания
        // не было (VoiceOver).
        return Button { if TouchDown.takeRelease() { act() } } label: {
            VStack(spacing: 3) {
                // Значки нарисованы автором от руки и обведены в вектор:
                // ежедневник, раскрытый в начале, посередине и в конце.
                Group {
                    if system {
                        Image(systemName: icon).resizable().scaledToFit().padding(4)
                    } else {
                        Image(icon).renderingMode(.template).resizable().scaledToFit()
                    }
                }
                // Книжка на 10%, микроскоп на 5% крупнее прочих (P227).
                .frame(width: 35 * k * scale(target), height: 35 * k * scale(target))
                // Того же размера, что в строке разделов над клавиатурой
                // (P425).
                Text(name).font(Look.sans(SectionsRow.font * k, weight: on ? .medium : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // Не сжимать по высоте (P510): в тесной нижней полосе
                    // надпись ужималась на 8%, и выходило мельче, чем вверху.
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Открытый раздел — на светлой подушке. Подушка выходит за
            // значок наружу и не меняет высоты полосы (P218).
            // Окантовка открытого раздела (P414) — тонкая рамка его цвета.
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(on ? Look.tabLit : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(on ? Look.accent.opacity(0.75) : .clear, lineWidth: 1.3))
                    .padding(.horizontal, -16)
                    .padding(.vertical, -3))
            .frame(maxWidth: .infinity)
            .foregroundStyle(on ? Look.accent : Look.kraftInk)
        }
        .buttonStyle(TouchDownStyle(action: act))
        .accessibilityIdentifier((small ? "top." : "bottom.") + "\(target)")
        // Долгого нажатия у кнопок нет (P492): действия дня — в меню на трёх
        // точках; системное меню задерживало и обычное касание.
    }

    /// Убрать шторку «Подробности», если открыта.
    /// Касание мимо них — по разделам внизу или по уголкам — сперва
    /// закрывает их, как и касание по странице (P342, P344). `true` —
    /// что-то убрали, больше ничего делать не надо.
    private func closeDrawer() -> Bool {
        guard shell.drawer != nil else { return false }
        hideKeyboard()
        store.save()
        withAnimation(.easeOut(duration: 0.26)) { shell.drawer = nil }
        return true
    }

    /// Открыть раздел: плашка надвигается на книгу, книга остаётся на месте.
    ///
    /// Ход тяжёлый: долгое торможение без отскока. Так ведёт себя предмет с
    /// весом — его не бросают, он доезжает сам и гасит скорость о воздух.
    /// Быстрый ход читался бы как смена экрана, а не как движение вещи.
    private func open(_ target: Shell.Screen) {
        // Уходя на карту, запомнить, где был курсор: точка с карты ляжет
        // туда (P240).
        if target == .map, shell.screen != .map {
            store.noteLeaving(fromToday: shell.screen == .today)
        }
        if target != shell.screen { hideKeyboard() }
        shell.screen = target
    }

    /// Опустить или убрать плашку вслед за сменой экрана (P501).
    ///
    /// Нажатие на раздел просто опускает его плашку поверх того, что было, —
    /// прежнюю никто не поднимает. «День» убирает все плашки. Второе
    /// нажатие плашку больше не убирает (P576, P577).
    private func follow(from old: Shell.Screen, to new: Shell.Screen) {
        // Быстрее прежних 0,46 (P565): медленный ход казался задумчивостью.
        let heavy = Animation.spring(response: 0.3, dampingFraction: 0.9)
        // Толчок — в начале хода, вместе с нажатием (P268).
        Feel.thud()
        if let i = shell.stack.firstIndex(of: new) {
            // Эта плашка уже лежит, но под другой: снимаем её без хода (её не
            // видно) и опускаем заново поверх.
            if i == shell.stack.count - 1 { return }
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { shell.stack.remove(at: i) }
            DispatchQueue.main.async { [shell] in
                guard shell.screen == new else { return }
                withAnimation(heavy) { shell.stack.append(new) }
            }
            return
        }
        withAnimation(heavy) { shell.stack.append(new) }
    }

    // MARK: - Сообщение

    private func toast(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Look.planBg)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 15)
            .padding(.vertical, 8)
            .background(Look.ink, in: Capsule())
            .padding(.horizontal, 24)
            .padding(.bottom, 80)
            .transition(.opacity)
            .allowsHitTesting(false)
    }
}

/// Уголок стикера, наклеенного выше экрана: слева торчит правый нижний
/// угол голубого стикера, справа — левый нижний угол желтоватого. Стикер
/// наклеен ровно, по вертикали; у него тень — он лежит поверх страницы
/// (P229, P231, P236).
struct Corner: View {
    static let size: CGFloat = 58
    /// Насколько верх уголка спрятан под верхней строкой (P496).
    static let lift: CGFloat = 2

    let leading: Bool
    let paper: Color
    let edge: Color
    let icon: String
    let tint: Color

    var body: some View {
        ZStack(alignment: leading ? .topLeading : .topTrailing) {
            // Сверху стикер растворяется в подложке — ни черты, ни резкого
            // края; черта — только сбоку и снизу, тень явнее (P416).
            // Растворяется выше значка (P425): значок стоит на чистой
            // бумаге, а не на переходе.
            // Тень — только от плотной части листка (P459): прежде её
            // отбрасывал и растворяющийся верх, и сквозь прозрачную бумагу
            // над листком проступала серая полоса — «неаккуратный верх».
            CornerShape(leading: leading, top: 0.2)
                .fill(paper)
                .shadow(color: .black.opacity(0.4), radius: 4, x: leading ? 2 : -2, y: 3.5)
            CornerShape(leading: leading)
                .fill(LinearGradient(stops: [.init(color: paper.opacity(0), location: 0),
                                             .init(color: paper, location: 0.11)],
                                     startPoint: .top, endPoint: .bottom))
            CornerEdge(leading: leading)
                .stroke(LinearGradient(stops: [.init(color: edge.opacity(0), location: 0),
                                               .init(color: edge, location: 0.14)],
                                       startPoint: .top, endPoint: .bottom),
                        lineWidth: 1)
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 30, height: 26)
                .padding(leading ? .leading : .trailing, 9)
                .padding(.top, 7)
        }
        .frame(width: Corner.size, height: Corner.size)
        .contentShape(CornerShape(leading: leading))
    }
}

/// Видимая часть стикера: от края экрана его нижняя сторона идёт вниз к
/// острому углу, от угла боковая сторона уходит вверх за край экрана.
struct CornerShape: Shape {
    let leading: Bool
    /// Откуда сверху начинается листок, доля высоты: тень берётся только с
    /// плотной части (P459).
    var top: CGFloat = 0

    func path(in r: CGRect) -> Path {
        // Точки для левого уголка; правый — зеркально.
        // Стикер наклеен ровно, без наклона: видна его нижняя сторона и
        // боковая, угол между ними прямой (P236).
        let points: [CGPoint] = [
            CGPoint(x: 0, y: top),
            CGPoint(x: 0.86, y: top),            // боковая сторона уходит за верх
            CGPoint(x: 0.86, y: 0.80),           // прямой угол
            CGPoint(x: 0, y: 0.80),              // нижняя сторона уходит за край
        ]
        var p = Path()
        for (i, pt) in points.enumerated() {
            let x = leading ? r.minX + pt.x * r.width : r.maxX - pt.x * r.width
            let at = CGPoint(x: x, y: r.minY + pt.y * r.height)
            if i == 0 { p.move(to: at) } else { p.addLine(to: at) }
        }
        p.closeSubpath()
        return p
    }
}

/// Кромка стикера-уголка (P416): только боковая сторона и нижняя, без
/// верхней — сверху он растворяется в подложке.
struct CornerEdge: Shape {
    let leading: Bool

    func path(in r: CGRect) -> Path {
        let side = leading ? r.minX + 0.86 * r.width : r.maxX - 0.86 * r.width
        let edge = leading ? r.minX : r.maxX
        var p = Path()
        p.move(to: CGPoint(x: side, y: r.minY))
        p.addLine(to: CGPoint(x: side, y: r.minY + 0.8 * r.height))
        p.addLine(to: CGPoint(x: edge, y: r.minY + 0.8 * r.height))
        return p
    }
}

/// Перевод имён папок (P353): пока идёт — экран закрыт, как при переносе;
/// кончился — отчёт. Отдельно от `RootView`: её цепочка и так длинная.
private struct RenameShown: ViewModifier {
    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var archive: Archive

    func body(content: Content) -> some View {
        content
            .overlay {
                if let m = vault.renaming {
                    MovingView(progress: m, title: T("Перевожу имена папок", "Renaming folders"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .ignoresSafeArea()
                }
            }
            .alert(T("Имена папок переведены", "Folders renamed"), isPresented: shown, presenting: vault.renamed) { _ in
                Button(T("Понятно", "OK")) { done() }
            } message: { r in
                Text(RootView.renameText(r))
            }
    }

    private var shown: Binding<Bool> {
        Binding(get: { vault.renamed != nil }, set: { if !$0 { vault.renamed = nil } })
    }

    private func done() {
        vault.renamed = nil
        store.load()
        archive.reload()
    }
}

/// Голосовая запись открывается небольшой шторкой снизу: имя, ход
/// записи, «играть» и «убрать» — весь экран ей ни к чему (P360).
private struct VoiceShown: ViewModifier {
    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var store: DayStore

    static func isVoice(_ opened: Shell.OpenedPhoto, _ store: DayStore) -> Bool {
        let links = store.links(opened.tab)
        let name = opened.url?.lastPathComponent
            ?? (links.indices.contains(opened.index) ? links[opened.index] : "")
        return Diary.kind(of: name) == .audio
    }

    private var shown: Binding<Shell.OpenedPhoto?> {
        Binding(get: { shell.openedPhoto.flatMap { Self.isVoice($0, store) ? $0 : nil } },
                set: { shell.openedPhoto = $0 })
    }

    func body(content: Content) -> some View {
        content.sheet(item: shown) { opened in
            VoiceSheet(opened: opened)
                .presentationDetents([.height(300)])
                .presentationDragIndicator(.visible)
        }
    }
}

private struct VoiceSheet: View {
    let opened: Shell.OpenedPhoto
    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var store: DayStore

    private var url: URL? {
        if let url = opened.url { return url }
        let links = store.links(opened.tab)
        return links.indices.contains(opened.index) ? store.photoURL(links[opened.index]) : nil
    }

    var body: some View {
        AttachmentViewer(
            url: url,
            onRemove: opened.url == nil && store.canEdit(opened.tab) ? { remove($0) } : nil,
            close: { shell.openedPhoto = nil },
            onTranscript: opened.tab == .diary && store.canEditDiary && link != nil
                ? { store.addTranscript($0, after: link ?? "") } : nil)
    }

    /// Ссылка на запись: из текста — своя, из полоски — по месту в ней.
    private var link: String? {
        if let l = opened.link { return l }
        let links = store.links(opened.tab)
        return links.indices.contains(opened.index) ? links[opened.index] : nil
    }

    private func remove(_ delete: Bool) {
        shell.openedPhoto = nil
        shell.say(store.removeAttachment(at: opened.index, from: opened.tab, delete: delete))
    }
}

/// Кнопка, которая срабатывает в миг касания, а не когда палец отпустили
/// (P565). Обычная кнопка iPhone ждёт отпускания — и раздел начинал ехать
/// с опозданием.
struct TouchDownStyle: ButtonStyle {
    let action: () -> Void

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .onChange(of: configuration.isPressed) { _, pressed in
                guard pressed else { return }
                TouchDown.pressed = Date()
                action()
            }
    }
}

enum TouchDown {
    /// Когда кнопка сработала от касания и ещё не отпущена.
    static var pressed: Date?

    /// Срабатывать ли кнопке при отпускании. Нет, если она уже сработала
    /// от касания этого же пальца (P578): прежде мерили 0,6 с от касания —
    /// подержал палец дольше или телефон замешкался, и кнопка срабатывала
    /// дважды; у «Дня» второе срабатывание уводило на сегодня. Касания не
    /// было (VoiceOver) — срабатывает сама. Давнее касание, после которого
    /// отпускания не пришло (палец ушёл с кнопки), не в счёт.
    static func takeRelease() -> Bool {
        defer { pressed = nil }
        guard let pressed else { return true }
        return Date().timeIntervalSince(pressed) > 10
    }
}
