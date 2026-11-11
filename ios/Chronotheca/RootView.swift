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
    /// Какая страница ленты разделов стоит на экране (P799).
    @State private var pageAt: Shell.Screen? = .today
    /// Насколько ленту разделов увели полоской у края карты (P819): лента
    /// едет за пальцем, «Дневник» выезжает справа. Своим предметом (P857):
    /// сдвиг на каждом кадре перерисовывал весь экран — кадры терялись.
    @StateObject private var mapPull = SidePull()

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
    @AppStorage(Prefs.font) private var fontKey = "newyork"
    /// Цветовая гамма (P498): меняется — страницы и строки собираются заново.
    @AppStorage(Prefs.calendarTint) private var palette = "distance"
    @AppStorage(Prefs.plainPast) private var plainPast = false
    @State private var locked = UserDefaults.standard.bool(forKey: Prefs.lock)


    private var scheme: ColorScheme? {
        theme == "light" ? .light : theme == "dark" ? .dark : nil
    }

    private func unlock() {
        LockView.check(reason: T("Открыть записи", "Open your entries")) { ok in
            if ok {
                locked = false
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
            // Бумага прошедших дней — в стороне, пока запускаемся (P679).
            PageTexture.prepareSoon()
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
                // Верхней строки разделов нет (P613): разделы — в нижней
                // строке, а пока поднята клавиатура — над ней.
                canvas
                    // Сменили размер или шрифт записи — страницы собираются
                    // заново: поля UIKit помнят свой шрифт (P274).
                    .id("\(fontKey)|\(systemText)|\(palette)")
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
            // Над календарём и поиском — их стол (P755).
            .background {
                Group {
                    if shell.screen == .today { Ru.tint(store.date) }
                    else if shell.screen == .calendar || shell.screen == .search { Desk() }
                    else { Look.chrome }
                }
                .ignoresSafeArea()
            }

            // Верхней строки больше нет: шестерёнка и три точки нарисованы
            // на уголках бумаги, торчащих сверху слева и справа, а имя дня
            // поднялось между ними (P229).
            corners

            // Листки висят от верха экрана под строкой часов; выезжают они
            // из-под неё, поэтому всё, что выше, обрезано.
            // Листок лежит наложением на пустое место во весь экран (P658):
            // выше места он раздвигал весь экран, и тот вставал посередине —
            // страница дёргалась вверх при открытии и ещё раз, когда листок
            // вставал, а шапка «Настройки» заезжала под часы (запись автора
            // к 186; P655 этого не исправил). Наложение размер экрана не
            // меняет; лишнее уходит вниз, под нижнюю строку.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) {
                    ZStack(alignment: .topTrailing) {
                        if let m = shell.movingTask {
                            MoveDaySticker(task: m)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }
                        if shell.showingSettings {
                            SettingsSticker().frame(maxWidth: .infinity, alignment: .topTrailing)
                        }
                    }
                }
                .clipped()
            // Листок кончается над нижней строкой (P667): копии строки
            // поверх листка больше нет.
            // Над клавиатурой разделы — частью самой клавиатуры (P613,
            // `KeyboardBar`): у полей дня. На карте и в поиске их там нет.
            // Подсказки для первого знакомства (P427) — поверх всего, когда
            // экран спокоен.
            HintLayer(screen: shell.screen,
                      quiet: !shell.showingSettings
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
                // Большой архив сложен (P589).
                if vault.bigReady {
                    Text("bigReady")
                        .font(.system(size: 2))
                        .opacity(0.02)
                        .allowsHitTesting(false)
                        .accessibilityIdentifier("bigReady")
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                }
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
            // Карта собирается при первом открытии и дальше остаётся
            // (P814, вместо сборки заранее P581, P582).
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
                            // Снимок из записи — в конец записи (P216, P620).
                            giveBack: { i in
                                let one = all[i]
                                guard store.canEditDiary, !store.stripLinks.contains(one) else { return nil }
                                return {
                                    store.moveToEnd(one)
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
                // Снимок из текста — в конец записи (P216, P620).
                onReturn: opened.link != nil && store.canEdit(opened.tab) ? {
                    if let link = opened.link { store.moveToEnd(link) }
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
            // Раздел, выбранный над клавиатурой (P613), — сюда, как и с
            // нижней строки.
            // Опись архива нужна не только календарю и поиску: без неё
            // облачко «…помнишь?» не знает, есть ли что вспомнить, и не
            // появляется никогда. Читаем папку сразу при запуске.
            LagWatch.start()
            // В стороне (P565): прежде папка читалась целиком до первого
            // кадра — чем больше дневник, тем дольше открывалось приложение.
            archive.reloadSoon()
            // Свои места — для подписи точек в дневнике (P559), тоже в стороне.
            Places.loadSoon(vault)
            // Свайп между разделами (P778).
            wireRibbon()
            LaunchClock.step(T("первый экран", "first screen"))
            // Открываемся там, где закрыли, если день тот же (P686).
            shell.tab = .plan
            shell.restoreLeft(store)
            shell.openRequestedScreen(store)
            // Первое открытие: страница сверху (P346, P607).
            shell.freshStart += 1
        }
    }

    /// Область содержимого: шторка «Подробности» живёт только внутри неё.
    private var canvas: some View {
        ZStack(alignment: .trailing) {
            screen
            // Шторки «Подробности» больше нет (P408).
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Обрезано сверху и по бокам; снизу открыто (P744): список поиска
        // заходит под нижнюю строку, она лежит поверх.
        .clipShape(OpenBelow())
    }

    // MARK: - Шапка

    /// Шестерёнка — на уголке бумаги, торчащем сверху слева. Уголка с тремя
    /// точками больше нет (P632): действия дня — по касанию даты в шапке,
    /// карты — в плашке точки и на самой карте, поиска — в строке поиска.
    /// У уголка тень — он лежит поверх страницы (P229); кнопка не
    /// пропадает, что бы ни было открыто (P188).
    private var corners: some View {
        HStack(alignment: .top) {
            // Шестерёнка — справа (P793): слева сверху у «Дня» теперь
            // корешок с его датой, как у карточек.
            Spacer(minLength: 0)
            Button {
                if closeDrawer() { return }
                // Открытая клавиатура и строка над ней не должны мешать
                // листку настроек — убираются вниз, как при касании по
                // точке на карте (P309).
                hideKeyboard()
                shell.pullOut()
            } label: {
                Corner(icon: "gearshape",
                       tint: shell.showingSettings ? Look.accent : Look.inkSoft)
                    // Пока листок вытянут, его угол — это и есть уголок.
                    .opacity(shell.showingSettings ? 0 : 1)
            }
            .buttonStyle(.plain)
            // Уголок тянут вниз, и бумажка идёт за пальцем (P233).
            .simultaneousGesture(pull(\.showingSettings, \.settingsPull))
            .accessibilityLabel(T("Настройки", "Settings"))
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
                if drag.translation.height > 90 || drag.predictedEndTranslation.height > 220 {
                    shell.pullOut()
                } else {
                    shell.tuckIn()
                }
            }
    }

    // MARK: - Экран

    /// Разделы — одна лента вбок (P799, вместо плашек, опускавшихся сверху,
    /// P501, и самодельного свайпа P778–P790, который на телефоне не
    /// брался): «Карта», «Дневник», «Календарь» (P805). Листает сам iPhone — он и
    /// отличает ход вбок от прокрутки вверх-вниз. Кнопки внизу ведут ленту к
    /// своей странице. Без круга: от карты — только назад к «Дневнику».
    private var screen: some View {
        GeometryReader { geo in
            ScrollView(.horizontal) {
                // Карта слева, календарь справа (P805).
                HStack(spacing: 0) {
                    mapPage(width: geo.size.width)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .background(Look.chrome)
                        .id(Shell.Screen.map)
                    dayPage(geo.size)
                        .frame(width: geo.size.width, height: geo.size.height)
                        // Черта между разделами (P818): на ходу видно, где
                        // кончается один и начинается другой.
                        .overlay(alignment: .leading) { PageSeam() }
                        .id(Shell.Screen.today)
                    CalendarView()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .background(Desk())
                        .overlay(alignment: .leading) { PageSeam() }
                        .id(Shell.Screen.calendar)
                }
                .scrollTargetLayout()
                .modifier(PullShift(pull: mapPull))
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $pageAt)
            // С самого начала — «Дневник», средняя страница.
            .defaultScrollAnchor(.center)
            .scrollIndicators(.hidden)
            // Карточки ленты заходят под нижнюю строку (P744).
            .scrollClipDisabled()
            .scrollDisabled(!pagingFree)
            // Толчок — когда страница перевалила за середину; раздел
            // меняется, когда лента встала (P800: прежде менялся на ходу,
            // экран перестраивался посреди хода и дёргался в миг толчка).
            .modifier(PageWatch(at: $pageAt,
                                skip: { $0 == current }, feel: { Feel.thud() }, landed: { landed(on: $0) }))
        }
    }

    /// Страница «Дневника»: лист дня, под ним — лента картотеки (P777).
    private func dayPage(_ size: CGSize) -> some View {
        ZStack {
            // Стол — под всей страницей, не под лентой (P831): лист «Дня»
            // уходит под картотеку будущего, и стол ленты закрыл бы его.
            SearchView(height: size.height)
                .frame(width: size.width, height: size.height)
                // Картотека проступает плавно, по мере того как лист уходит
                // (P858): прежде появлялась разом с первым движением.
                .modifier(RibbonFade(ribbon: shell.ribbon, live: shell.ribbonLive,
                                     card: shell.dayCard))
                .allowsHitTesting(shell.screen == .search)
                .accessibilityHidden(!shell.ribbonLive)
                .zIndex(0)
            // Пока открыта лента, день пропускает касания к ней: ленту
            // листают и по месту дня (P777). Справа от корешка — стол (P797).
            // Своего стола у дня нет (P842): стол — под всей страницей; справа
            // от корешка листа ничего не закрашено (P849) — видно то, что под
            // листом: в покое стол, при тяге — картотека.
            // Полоски «Сегодня» над будущим днём нет (P876, кольцо; отменяет
            // P865, P867): «Сегодня» — корешком снизу, как у прошлого.
            // Схема карточки, в которую складывается закрытый день (P886).
            FoldGhost(ribbon: shell.ribbon, on: shell.dayCard,
                      live: shell.ribbonLive, size: size)
                .zIndex(0.5)
            DayPages()
                .frame(width: size.width, height: size.height)
                .modifier(FollowRibbon(ribbon: shell.ribbon, live: shell.ribbonLive))
                // У края остаётся только лист сегодняшнего дня (P863).
                .onChange(of: store.isToday, initial: true) { _, today in shell.ribbon.stick = today }
                // День закрыт в карточку (P834) — листа нет: место дня из
                // ленты ушло, и лист повисал бы где придётся (снимок проверки:
                // полэкрана листа, под ним пустой стол).
                // Тает, а не пропадает разом (P859): низ поднятого листа,
                // что торчал у верха экрана, исчезал рывком. Обратно — сразу.
                // Тает, а складывается в карточку его схема — `FoldGhost`
                // под ним (P886, вместо сжатия самого листа P883).
                .animation(shell.dayCard ? .easeOut(duration: 0.2) : nil) {
                    $0.opacity(shell.dayCard ? 0 : 1)
                }
                .allowsHitTesting(shell.screen == .today)
        }
        // Где ты в картотеке (P845): линия от середины левого края.
        .overlay(alignment: .leading) {
            if shell.ribbonLive {
                TimeLine(ribbon: shell.ribbon, height: size.height)
            }
        }
        // Лист «Сегодня» с экрана не уходит (P860): касание по корешку внизу
        // или по полоске низа листа вверху — назад в день. Прошедший день
        // закрыт в карточку (P834) — внизу корешок «Сегодня» сам по себе.
        // Открыт не сегодняшний день — корешок «Сегодня» торчит внизу поверх
        // него всегда (P862).
        .overlay(alignment: .topLeading) {
            TodayPeek(ribbon: shell.ribbon, live: shell.ribbonLive,
                      open: shell.screen == .search && shell.ribbonOpen,
                      card: shell.dayCard, todaySheet: store.isToday,
                      size: size) { riseToday() }
        }
        .background(Desk())
    }

    /// Страница карты. Палец двигает карту, поэтому лента на ней не листается
    /// — к «Дневнику» ведёт полоска у правого края: ведёшь по ней влево
    /// (P805; карта слева от «Дневника»).
    /// Карта собирается при первом открытии и дальше остаётся (P814).
    /// Лента едет за пальцем (P819; прежде стояла и по отпусканию прыгала):
    /// отпустили дальше четверти экрана или взмахом — доезжает до «Дневника»,
    /// иначе мягко возвращается.
    private func mapPage(width: CGFloat) -> some View {
        ZStack(alignment: .trailing) {
            if mapReady || shell.screen == .map { MapScreen() } else { Color.clear }
            Color.clear
                .frame(width: 18)
                .contentShape(Rectangle())
                // Мерить в окне: полоска едет вместе с лентой.
                .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onChanged { drag in
                        if mapPull.x == 0 { Feel.warm() }
                        mapPull.x = min(0, drag.translation.width)
                    }
                    .onEnded { drag in
                        let go = drag.translation.width < -width / 4
                            || drag.predictedEndTranslation.width < -width / 2
                        let glide = Animation.spring(response: 0.35, dampingFraction: 0.9)
                        guard go else {
                            withAnimation(glide) { mapPull.x = 0 }
                            return
                        }
                        // Скорость и ширина — для хода одним движением (P857, `follow`).
                        mapPull.speed = drag.velocity.width
                        mapPull.width = width
                        // Сперва раздел (P840): на карте лента разделов
                        // заперта — палец двигает карту, — и ход ленты,
                        // заказанный до смены раздела, не шёл (P829: карта
                        // возвращалась, потом мелькал календарь). Раздел
                        // меняется — лента отпирается, и `follow` ведёт её к
                        // «Дневнику» тем же ходом, каким уходит сдвиг за
                        // пальцем: одно движение с места, где отпустили.
                        tapSection(.today)
                    })
        }
        .accessibilityHidden(shell.screen != .map)
    }

    /// Ленту разделов можно листать пальцем: не на карте, не пока тянут
    /// картотеку или несут дело, не под листком и не во время переезда.
    private var pagingFree: Bool {
        !shell.pulling && !shell.holding && !shell.showingSettings && shell.settingsPull == nil
            && shell.movingTask == nil && shell.drawer == nil && shell.screen != .map
            && vault.moving == nil
    }

    /// Открытый раздел; лента картотеки — продолжение «Дневника».
    private var current: Shell.Screen {
        shell.screen == .search ? .today : shell.screen
    }

    /// Лента встала на страницу. Если её пролистали пальцем — раздел
    /// меняется, как по касанию внизу; если её повела кнопка — уже сменился.
    private func landed(on page: Shell.Screen) {
        guard page != current else { return }
        if shell.ribbonOpen { closeRibbonNow() }
        store.prune()
        LaunchClock.opened("\(page)", since: Date())
        open(page)
        if page != .today { archive.reloadSoon() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.save() }
    }

    // MARK: - Разделы

    private var tabbar: some View {
        HStack(spacing: 0) {
            // Календарь, день, карта (P773; прежде и поиск, P239): картотеку
            // вытягивают из «Дня». Глобус нарисован автором (P248).
            // Как лента вбок: карта, дневник, календарь (P805).
            section("карта", T("Карта", "Map"), .map)
            section("сегодня", T("Дневник", "Diary"), .today)
            section("календарь", T("Календарь", "Calendar"), .calendar)
        }
        // Тоньше на пару миллиметров (P613; прежде 55 — P506): та же
        // строка встаёт над клавиатурой и не должна занимать там много.
        .padding(.vertical, 1)
        .frame(height: SectionsRow.height)
        // Над значками — полоса под кромку и строчку (P746): строчка шла
        // прямо по верху значков и рамке открытого раздела.
        .padding(.top, Leather.lip)
        // Над полосой «домой» — её высота у самого окна, она не меняется
        // от клавиатуры (P447), меряется раскладкой (P450).
        .padding(.bottom, homeLift)
        // Кожаный переплёт с ровным краем и строчкой, до самого низа экрана
        // (P745, вместо крафта с оторванным краем P297).
        .background(alignment: .top) {
            // Без старой бумаги — крафт с ровным верхом (P751).
            BarCover()
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
    /// Выше прежнего на 10 точек (P686): кнопки лежали над самой полосой, и
    /// смах «домой» задевал их. Ещё на 8 выше (P761: «чтобы пальцем не
    /// захватывать нижнюю кнопку айфона») — кожа под значками шире.
    private var homeLift: CGFloat {
        let bar = max(homeBar, windowBottom)
        return bar > 0 ? bar + 12 : 0
    }

    /// Порог у дня в открытой картотеке (P779) и «несут пальцем» (P799).
    private func wireRibbon() {
        Hold.report = { [shell] now in
            if shell.holding != now { shell.holding = now }
        }
        shell.ribbon.walls = { [shell] in
            // У прошедшего дня, закрытого в карточку, места дня в ленте нет —
            // нет и стены (P834).
            shell.screen == .search && shell.ribbonOpen && !shell.pulling && !shell.dayCard
        }
        // В день тягой (P828): сперва лента доезжает до места дня, раздел
        // меняется, когда встала, — как и при открытии картотеки. Прежде
        // раздел менялся в миг отпускания, экран перестраивался, и ход
        // догонял прыжком.
        // Лента дошла до края к сегодня — «Сегодня» (P871), как касание
        // его корешка.
        shell.ribbon.toToday = { [shell] in
            guard shell.screen == .search else { return }
            riseToday()
        }
        shell.ribbon.wantDay = { [shell] in
            guard shell.screen == .search else { return }
            backToDay {
                // Толчок был на пороге (P800).
                shell.ribbon.felt = false
                var still = Transaction()
                still.disablesAnimations = true
                withTransaction(still) { shell.screen = .today }
            }
        }
    }

    /// Касание по разделу — внизу экрана или в строке над клавиатурой
    /// (P423): одно и то же.
    private func tapSection(_ target: Shell.Screen) {
        // Открыта шторка «Подробности» — первое касание только убирает
        // её, второе уже открывает раздел (P342).
        if closeDrawer() { return }
        // Открыты настройки — касание по нижней строке только убирает их
        // (P656, P659); раздел открывает уже следующее касание.
        if shell.showingSettings {
            shell.tuckIn()
            return
        }
        store.prune()
        // «Дневник» из картотеки, когда открыт прошедший день, — на сегодня
        // (P850): прежде лента доезжала к открытому дню, и кнопка вела в
        // прошлое. Сразу, без хода, как касание карточки (P796).
        if target == .today && (shell.screen == .search || (shell.screen == .today && !store.isToday)) {
            riseToday()
            return
        }
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
                    // Без загиба листа (P779; прежде дорога домой
                    // листалась, P164).
                    shell.say(T("Вернулись на сегодня", "Back to today"))
                    shell.goHome = true
                }
                return
            case .calendar:
                shell.calendarHome = true
                return
            case .search:
                // Кнопки «Поиск» больше нет (P773).
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
                         system: Bool = false) -> some View {
        let on = shell.screen == target
        let k = SectionsRow.scale
        let act = { tapSection(target) }
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
                .frame(width: 35 * k * SectionsRow.grow(target), height: 35 * k * SectionsRow.grow(target))
                // Того же размера, что в строке разделов над клавиатурой
                // (P425, P613).
                Text(name).font(Look.sans(SectionsRow.font, weight: on ? .medium : .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // Не сжимать по высоте (P510): в тесной нижней полосе
                    // надпись ужималась на 8%, и выходило мельче, чем вверху.
                    .fixedSize(horizontal: false, vertical: true)
            }
            // На коже — тиснением (P759).
            .modifier(Embossed(on: !plainPast))
            // Открытый раздел — на светлой подушке. Подушка выходит за
            // значок наружу и не меняет высоты полосы (P218).
            // Окантовка открытого раздела (P414) — тонкая рамка его цвета.
            // На коже (P745, P748): значки тёмными чернилами, открытый
            // раздел — темнее, на светлой подушке с окантовкой.
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(on ? BarInk.pad(plainPast) : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(on ? BarInk.frame(plainPast) : .clear, lineWidth: 1.3))
                    .padding(.horizontal, -16)
                    .padding(.vertical, -3))
            .frame(maxWidth: .infinity)
            .foregroundStyle(on ? BarInk.lit(plainPast) : BarInk.ink(plainPast))
        }
        .buttonStyle(TouchDownStyle(action: act))
        .accessibilityIdentifier("bottom.\(target)")
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
        if target != shell.screen { hideKeyboard() }
        shell.screen = target
    }

    /// Лента разделов — к открытому разделу (P799). Касание внизу ведёт её
    /// ходом, с виджета, из напоминания, после паузы — сразу (P583).
    private func follow(from old: Shell.Screen, to new: Shell.Screen) {
        // Лента картотеки (P777) — не раздел, а продолжение дня.
        if new == .search {
            shell.instant = false
            shell.ribbonOpen = true
            return
        }
        let instant = shell.instant
        shell.instant = false
        if shell.ribbonOpen {
            // Из ленты в день: лента доезжает до места дня (P777).
            if old == .search && new == .today && !instant {
                if !shell.ribbon.felt { Feel.thud() }
                shell.ribbon.felt = false
                backToDay()
                return
            }
            closeRibbonNow()
        }
        guard pageAt != new else { return }
        // С карты за пальцем — одним движением (P857): лента сразу встаёт на
        // «Дневник», а сдвиг пересчитывается так, что на экране ничто не
        // двинулось, — и уходит в ноль одной пружиной со скоростью пальца.
        // Прежде ход ленты и возврат сдвига шли двумя разными ходами, и в
        // миг отпускания экран дёргался (видео автора к 258).
        if old == .map, new == .today, !instant, mapPull.x < 0, mapPull.width > 0 {
            Feel.thud()
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                mapPull.x += mapPull.width
                pageAt = new
            }
            let start = mapPull.x
            let speed = start > 1 ? min(20, max(0, -mapPull.speed / start)) : 0
            withAnimation(.interpolatingSpring(duration: 0.35, bounce: 0, initialVelocity: speed)) {
                mapPull.x = 0
            }
            return
        }
        if instant {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) { pageAt = new }
        } else {
            // Толчок — вместе с нажатием (P268).
            Feel.thud()
            // С карты за пальцем (P840): сдвиг уходит тем же ходом, что
            // лента, — вместе одно движение.
            withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                pageAt = new
                mapPull.x = 0
            }
        }
    }

    /// Лента доезжает местом дня на экран, и день снова живой (P777).
    private func backToDay(then: (() -> Void)? = nil) {
        let ribbon = shell.ribbon
        let finish = { [shell, archive] in
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                shell.ribbonOpen = false
                shell.fileFrom = 0
            }
            // Опись — когда лента уже закрыта (P797).
            archive.reloadSoon()
            then?()
        }
        if ribbon.seen {
            ribbon.glide(to: 0, then: finish)
        } else {
            // Место дня далеко в ленте: сперва лента встаёт у дня (день за
            // краем, с той стороны, где он был), затем доезжает до него.
            ribbon.settle(ribbon.y < 0 ? -1 : 1) {
                ribbon.glide(to: 0, then: finish)
            }
        }
    }

    /// «Сегодня» из картотеки — касанием корешка, кнопкой «Дневник» или у
    /// края ленты (P878, автор: «лист всегда должен подниматься снизу, вне
    /// зависимости от того, куда его смахивали перед этим; плавно и
    /// равномерно — сейчас он просто вскакивает»). Одним путём, что бы ни
    /// было открыто до того: лист встаёт корешком внизу, на место корешка
    /// «Сегодня», и плавно поднимается. Прежде открытый прошедший или будущий
    /// день сменялся сегодняшним сразу (P850), а после кольца лист
    /// опускался сверху.
    private func riseToday() {
        guard shell.screen == .search || (shell.screen == .today && !store.isToday),
              !shell.ribbon.busy else { return }
        let ribbon = shell.ribbon
        var still = Transaction()
        still.disablesAnimations = true
        Feel.thud()
        ribbon.felt = true
        // Открыт прошедший или будущий день (P879, автор: «перед тем как
        // сегодняшний лист поднимется, предыдущий должен стандартно
        // сложиться и встать на своё место в картотеке»): сперва он
        // складывается в свою карточку (P877), картотека открыта на ней, —
        // потом поднимается «Сегодня».
        if !store.isToday && !shell.dayCard {
            hideKeyboard()
            withTransaction(still) {
                shell.fileFrom = 1
                ribbon.frozen = true
                ribbon.opened()
                ribbon.folding = true
                shell.dayCard = true
                shell.ribbonOpen = true
                shell.screen = .search
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { liftToday() }
            return
        }
        liftToday()
    }

    /// Вторая половина `riseToday`: сегодняшний лист — корешком внизу и
    /// плавно вверх.
    private func liftToday() {
        let ribbon = shell.ribbon
        var still = Transaction()
        still.disablesAnimations = true
        if !store.isToday {
            store.save()
            // Пока лента пересобирается вокруг сегодня, не видно ни листа, ни
            // ленты (P888): иначе на глазах мелькали дальние карточки. Лист
            // встаёт корешком внизу уже сегодняшним.
            ribbon.veiled = true
            withTransaction(still) {
                ribbon.frozen = true
                shell.dayCard = true
                store.go(to: DayStore.today())
            }
        }
        ribbon.opened()
        ribbon.settle(1) { [shell] in
            withTransaction(still) {
                shell.dayCard = false
                shell.fileFrom = 1
            }
            ribbon.place(ribbon.restY(1))
            ribbon.refresh()
            ribbon.veiled = false
            backToDay {
                ribbon.felt = false
                withTransaction(still) { shell.screen = .today }
            }
        }
    }

    /// Закрыть ленту без хода — она под другой плашкой, её не видно.
    private func closeRibbonNow() {
        guard shell.ribbonOpen || shell.pulling else { return }
        var still = Transaction()
        still.disablesAnimations = true
        withTransaction(still) {
            shell.ribbonOpen = false
            shell.pulling = false
            shell.fileFrom = 0
        }
        shell.ribbon.release()
        shell.ribbon.park()
        archive.reloadSoon()
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

/// Уголок листка, заложенного выше экрана: слева торчит его правый нижний
/// угол с шестерёнкой (P229, P236); у него тень — он лежит поверх
/// страницы. С P735 — старая бумага, как прошлое.
struct Corner: View {
    static let size: CGFloat = 58
    /// Насколько верх уголка спрятан за верхним краем (P496).
    static let lift: CGFloat = 2
    /// Листок заходит за левый край экрана и под верх: рваными видны только
    /// правый и нижний края (P735).
    private static let hidden: CGFloat = 10

    let icon: String
    let tint: Color
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Prefs.plainPast) private var plainPast = false
    @State private var art: PageTexture.AgedArt?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Уголок — справа (P793): листок зеркально, рваные — левый и
            // нижний края, за правый край экрана он заходит.
            sticker
                .scaleEffect(x: -1, y: 1)
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(tint)
                .frame(width: 30, height: 26)
                .padding(.trailing, 9)
                .padding(.top, 7)
        }
        .frame(width: Corner.size, height: Corner.size, alignment: .topTrailing)
        // Сверху листок уходит под край ровно — без растворения (P735:
        // переход цвета сверху выбивался из старой бумаги).
        .clipShape(BelowTop())
        .contentShape(CornerShape())
    }

    /// Старая бумага, потрёпанная сильнее карточек — за уголок берутся
    /// часто (P735, по слову автора): шире охра и подпалина, рваный край.
    /// Лист — из пачки заготовок (P732); пока его нет — ровная бумага.
    private var sticker: some View {
        let w = (Corner.size * 0.86 + Corner.hidden).rounded()
        let h = (Corner.size * 0.80 + Corner.hidden).rounded()
        let order = PageTexture.agedOrder(size: CGSize(width: w, height: h), band: 16, seed: 5)
        let ready = plainPast ? nil : (art ?? PageTexture.agedReady(order))
        return ZStack {
            // Без «Ретро» (P737) — прежняя белая бумага листков, ровная.
            if plainPast {
                // Как листок настроек, который за него тянут (P757).
                Desk()
            } else {
                Scheme.current.past
                Image(uiImage: PageTexture.paper)
                    .resizable(resizingMode: .tile)
                    .opacity(scheme == .dark ? 0.2 : 0.3)
            }
            if let ready {
                Image(uiImage: ready.frame)
                    .resizable()
                    .opacity(scheme == .dark ? 0.35 : 1)
            }
        }
        .frame(width: w, height: h)
        .mask {
            if let ready { Image(uiImage: ready.cut).resizable() } else { Rectangle() }
        }
        .compositingGroup()
        .shadow(color: .black.opacity(0.4), radius: 4, x: 3, y: 3.5)
        .offset(x: -Corner.hidden, y: -Corner.hidden)
        .task(id: order) {
            guard !plainPast else { return }
            art = await PageTexture.aged(order)
        }
    }
}

/// Всё, что ниже верхнего края уголка: тень и бумага справа и снизу не
/// обрезаются, сверху листок уходит под край.
private struct BelowTop: Shape {
    func path(in r: CGRect) -> Path {
        Path(CGRect(x: r.minX - 40, y: r.minY, width: r.width + 80, height: r.height + 40))
    }
}

/// Видимая часть уголка — для касаний.
struct CornerShape: Shape {
    func path(in r: CGRect) -> Path {
        // Уголок справа (P793).
        Path(CGRect(x: r.maxX - r.width * 0.86, y: r.minY, width: r.width * 0.86, height: r.height * 0.80))
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

/// Рамка без нижней стороны (P744): всё, что ниже, может выходить под
/// нижнюю строку.
private struct OpenBelow: Shape {
    func path(in r: CGRect) -> Path {
        Path(CGRect(x: r.minX, y: r.minY, width: r.width, height: r.height + 400))
    }
}

/// Лента страниц (разделы, месяцы календаря) под пальцем (P800).
/// Толчок — когда страница перевалила за середину, перемена — когда лента
/// встала. Прежде её место читали прямо в виде, и он перестраивался посреди
/// хода: лента подтягивала новую страницу к краю рывком, в миг толчка.
/// Здесь место читается только в откликах, и вид посреди хода не трогается.
struct PageWatch<ID: Hashable>: ViewModifier {
    @Binding var at: ID?
    /// Эту страницу не отмечать толчком (уже открыта кнопкой).
    let skip: (ID) -> Bool
    /// Какой толчок: у разделов — потвёрже, у месяцев — лёгкий.
    let feel: () -> Void
    let landed: (ID) -> Void

    final class Seen { var last: AnyHashable? }
    @State private var seen = Seen()

    init(at: Binding<ID?>, skip: @escaping (ID) -> Bool = { _ in false },
         feel: @escaping () -> Void = { Feel.light() }, landed: @escaping (ID) -> Void) {
        _at = at
        self.skip = skip
        self.feel = feel
        self.landed = landed
    }

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content
                .onScrollTargetVisibilityChange(idType: ID.self, threshold: 0.5) { ids in
                    guard let id = ids.first else { return }
                    if let last = seen.last, last != AnyHashable(id), !skip(id) { feel() }
                    seen.last = AnyHashable(id)
                }
                .onScrollPhaseChange { _, now in
                    // Палец лёг — отклик будится заранее (P829).
                    if now == .interacting { Feel.warm() }
                    if now == .idle, let at { landed(at) }
                }
        } else {
            content.onChange(of: at) { old, now in
                guard let now else { return }
                if old != nil && old != now && !skip(now) { feel() }
                landed(now)
            }
        }
    }
}

/// Черта между соседними разделами ленты (P818): тонкая линия и лёгкая тень
/// на левом соседе. Стоит за левым краем раздела — в покое за экраном, видна
/// только на ходу. Касаний не ловит.
private struct PageSeam: View {
    var body: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black.opacity(0.12)],
                           startPoint: .leading, endPoint: .trailing)
                .frame(width: 8)
            Rectangle()
                .fill(Look.ink.opacity(0.35))
                .frame(width: 1)
        }
        .offset(x: -9)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Сдвиг ленты разделов за пальцем у края карты (P857).
final class SidePull: ObservableObject {
    @Published var x: CGFloat = 0
    /// Скорость пальца и ширина страницы в миг отпускания.
    var speed: CGFloat = 0
    var width: CGFloat = 0
}

/// Сдвиг читается только здесь — экран целиком не перерисовывается.
private struct PullShift: ViewModifier {
    @ObservedObject var pull: SidePull
    func body(content: Content) -> some View {
        content.offset(x: pull.x)
    }
}

/// Картотека под листом проступает по мере тяги (P858): в покое её нет —
/// так легче телефону, — а с первыми точками хода место справа от корешка
/// плавно рассеивается и из него выходят карточки.
private struct RibbonFade: ViewModifier {
    @ObservedObject var ribbon: Ribbon
    let live: Bool
    let card: Bool

    func body(content: Content) -> some View {
        let shown: Double = !live ? 0 : card ? 1 : Double(min(1, abs(ribbon.y) / 90))
        content
            .opacity(shown)
            // Пересобирается вокруг другого дня — не видна (P888).
            .animation(.easeInOut(duration: 0.15)) { $0.opacity(ribbon.veiled ? 0 : 1) }
    }
}

/// Где взяться за лист «Сегодня» (P860): корешок внизу. Открыт не
/// сегодняшний день — или он закрыт в карточку (P834, P875) — внизу поверх
/// него лежит корешок «Сегодня» сам по себе, всегда (P862). Кольцо (P876,
/// автор): лист «Сегодня» уходит вверх — и корешком выходит снизу, будто
/// прошёл круг внутри телефона; тянут будущее вниз к сегодня — лист
/// вытягивается сверху, а корешок в ту же меру уходит вниз.
private struct TodayPeek: View {
    @ObservedObject var ribbon: Ribbon
    /// Картотеку тянут или она открыта.
    let live: Bool
    /// Лента открыта и стоит — за лист можно взяться.
    let open: Bool
    /// Не сегодняшний день закрыт в карточку.
    let card: Bool
    /// На листе — сегодняшний день.
    let todaySheet: Bool
    let size: CGSize
    let go: () -> Void

    var body: some View {
        let low = size.height - FollowRibbon.peekBottom
        // Корешок сам по себе — когда на листе не сегодня или листа нет.
        let alone = card || !todaySheet
        let shown = FollowRibbon.shown(live ? ribbon.y : 0, height: size.height)
        let sheetLow = todaySheet && !card && live && ribbon.y > 0 && shown >= low - 0.5
        // Кольцо (P884, автор: «когда низ листа доходит до верхнего края на
        // такое же расстояние, на какое выглядывает снизу корешок, — только
        // тогда лист начинает появляться снизу, в той же динамике, в
        // которой уходит нижний край сверху»): видно сверху и снизу вместе —
        // не больше корешка. Низ листа над верхним краем на `bottom` —
        // корешка снизу видно на столько, сколько ему не хватает до корешка.
        let ring = todaySheet && !card && live && ribbon.y < 0
        let bottom = shown + size.height
        let peek = min(FollowRibbon.peekBottom, max(0, FollowRibbon.peekBottom - bottom))
        let tabY = ring ? size.height - peek : low
        ZStack(alignment: .topLeading) {
            TodayTab()
                .frame(width: size.width)
                .offset(y: tabY)
                // В кольце — только когда правда выходит снизу (P886: стоило
                // тронуть лист «Сегодня», корешок проступал бледной тенью).
                .opacity(ring && peek < 0.5 ? 0 : 1)
                .animation(.easeOut(duration: 0.35)) { $0.opacity(alone || ring ? 1 : 0) }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if (alone && (open || !live)) || (open && (sheetLow || ring)) {
                TodayGrip(up: true, go: go)
                    .frame(width: size.width * DayPage.folder.tabShare, height: FollowRibbon.peekBottom)
                    .offset(y: tabY)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// Схема карточки (P886, автор: «не нужно рисовать карточку со всем
/// текстом — как только смахивают открытую страницу прошлого или будущего,
/// она после виброотклика плавно превращается в схематичное изображение
/// карточки, уменьшается и вставляется в нужное место картотеки; это
/// изображение для всех карточек одинаковое»; вместо сжатия самого листа
/// P883). Пустой контур карточки цвета бумаги: в миг закрытия он во весь
/// лист — лист над ним тает, — потом сжимается в рамку карточки в ряду и
/// тает над ней.
private struct FoldGhost: View {
    @ObservedObject var ribbon: Ribbon
    let on: Bool
    let live: Bool
    let size: CGSize

    var body: some View {
        let folding = on && ribbon.folding
        let top = FollowRibbon.shown(live ? ribbon.y : 0, height: size.height, stick: ribbon.stick)
        let start = CGRect(x: 0, y: top, width: size.width, height: size.height)
        let r = ribbon.foldTo ?? start
        let shape = FolderShape(tabHeight: Search.tabHeight, tabShare: Search.tabShare)
        shape
            .fill(Scheme.current.past)
            .overlay(shape.stroke(Scheme.current.kraftEdge.opacity(0.7), lineWidth: 1))
            .frame(width: r.width, height: r.height)
            .offset(x: r.minX, y: r.minY)
            // Сжатие над гнездом и опускание в гнездо — по 0,35 с (P889).
            .animation(ribbon.foldTo == nil ? nil
                       : ribbon.foldLanded ? nil : .easeInOut(duration: 0.35), value: ribbon.foldTo)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .opacity(folding ? 1 : 0)
            .animation(ribbon.foldLanded ? .easeIn(duration: 0.15) : nil) {
                $0.opacity(ribbon.foldLanded ? 0 : 1)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// За что взяться (P860): касание — в день; тяга от края к середине — тоже.
private struct TodayGrip: View {
    let up: Bool
    let go: () -> Void

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { go() }
            .gesture(DragGesture(minimumDistance: 10).onEnded { drag in
                let pulled = up ? -drag.translation.height : drag.translation.height
                if pulled > 30 { go() }
            })
            .accessibilityElement()
            .accessibilityLabel(T("Вернуться в день", "Back to the day"))
            .accessibilityAddTraits(.isButton)
    }
}

/// Корешок «Сегодня» сам по себе (P860) — когда листа нет: прошедший день
/// закрыт в карточку. Тот же контур, цвет, имя и дата, что у шапки листа.
private struct TodayTab: View {
    var body: some View {
        let today = DayStore.today()
        ZStack(alignment: .topLeading) {
            Ru.tint(today)
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(DayPage.title(for: today))
                        .font(.system(size: 21, weight: .semibold))
                        .tracking(-0.2)
                        .foregroundStyle(Look.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    (Text(Ru.headDate(today))
                        .foregroundColor(Look.inkSoft)
                     + Text(",  " + Ru.weekday(today))
                        .foregroundColor(Ru.dayColor(today))
                        .tracking(0.4))
                        .font(Look.sans(12.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.leading, 14)
                .padding(.top, 4)
                .frame(height: DayPage.headLine + 8)
                Spacer(minLength: 6)
            }
            .padding(.leading, 8)
            .padding(.top, 2)
        }
        .frame(height: FollowRibbon.peekBottom + DayPage.under)
        .clipShape(DayPage.folder)
        .overlay { DayPage.folder.stroke(DayPage.edge, lineWidth: 1) }
    }
}
