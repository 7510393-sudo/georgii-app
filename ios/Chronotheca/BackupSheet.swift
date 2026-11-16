import SwiftUI
import UniformTypeIdentifiers


/// Окно резервной копии: что это, куда, одна кнопка «Скопировать» и пять
/// ступеней — каждая своей строкой: идёт, прошла или не вышло и почему
/// (P375). Каждый шаг — нажатием человека, и перед ним сказано, что будет.
struct BackupSheet: View {

    @EnvironmentObject private var vault: Vault
    @Environment(\.dismiss) private var dismiss

    enum Stage: Equatable {
        case waiting
        case running(String)
        case done(String)
        case warn(String)
        case failed(String)
    }

    @State private var choosing = false
    @State private var placeName = Backup.placeName
    @State private var warning: String?
    @State private var problem: String?
    @State private var stages: [Stage] = Array(repeating: .waiting, count: 5)
    @State private var running = false
    /// Копия кончилась (P602): `true` — полная, `false` — неполная. Кнопка
    /// говорит, что вышло, — прежде после хода внизу оставалась простыня
    /// ступеней, а кнопка стояла как ни в чём не бывало.
    @State private var finished: Bool?
    /// Не все файлы пришли из iCloud — ждём ответа человека.
    @State private var pending: (Backup.Session, Backup.Inventory)?
    /// С прошлой копии этих файлов в архиве не стало (P377).
    @State private var vanished: [String] = []
    @State private var broughtBack: String?
    @State private var archiveSize: Int64?
    @State private var free: Int64?

    private static var names: [String] {
        [T("Место копии", "Backup place"),
         T("Опись архива", "List of files"),
         T("Копирование", "Copying"),
         T("Проверка копии", "Checking the backup"),
         T("Опись в самой копии", "Note inside the backup")]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(T("Копия — это вторая папка с теми же записями, снимками и видео, но в другом месте: "
                           + "на флешке или в другом облаке (Google Диск, OneDrive, Dropbox). Случится что-то "
                           + "с телефоном или iCloud — записи останутся там.",
                           "A backup is a second folder with the same entries, photos and videos, kept somewhere "
                           + "else: on a USB stick or in another cloud (Google Drive, OneDrive, Dropbox). If "
                           + "something happens to your phone or iCloud, your entries stay there."))
                    // Копия в том же iCloud — не копия (P575): удалённое там
                    // удалится на всех устройствах сразу.
                    Text(T("Копия в той же папке iCloud удалится вместе с записями — поэтому её лучше держать вне iCloud.",
                           "A backup in the same iCloud folder would be deleted together with your entries — so it is better kept outside iCloud."))
                        .foregroundStyle(Look.inkSoft)
                    Text(T("Копируется только новое и изменённое. В копии ничего не стирается, даже если "
                           + "запись удалили здесь. Сами записи копия не трогает.",
                           "Only new and changed files are copied. Nothing is ever deleted from the backup, "
                           + "even if you delete an entry here. Your entries themselves are left untouched."))
                        .foregroundStyle(Look.inkSoft)

                    // Что и куда — до копирования (P428): откуда, сколько
                    // весит архив, куда и сколько там свободно.
                    VStack(alignment: .leading, spacing: 6) {
                        Text(T("Что копируем", "What is copied")).font(Look.sans(13, weight: .semibold))
                        Text(vault.friendlyPath).font(Look.sans(13)).foregroundStyle(Look.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(T("Весь архив: ", "The whole archive: ")
                             + (archiveSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
                                ?? T("считаю…", "counting…")))
                            .font(Look.sans(13)).foregroundStyle(Look.inkSoft)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(T("Куда копировать", "Where to copy")).font(Look.sans(13, weight: .semibold))
                        Text(placeName ?? T("ещё не выбрано", "not chosen yet"))
                            .foregroundStyle(placeName == nil ? Look.inkFaint : Look.ink)
                        if placeName != nil, let free {
                            Text(T("Свободно там: ", "Free there: ")
                                 + ByteCountFormatter.string(fromByteCount: free, countStyle: .file))
                                .font(Look.sans(13))
                                .foregroundStyle(archiveSize.map { $0 > free } == true ? .red : Look.inkSoft)
                        }
                        Button(placeName == nil ? T("Выбрать место…", "Choose a place…")
                                                : T("Выбрать другое место…", "Choose another place…")) {
                            choosing = true
                        }
                        .buttonStyle(.bordered)
                        .disabled(running)
                        if let warning {
                            Text(warning).font(Look.sans(13)).foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        // После копирования — куда и сколько легло (P428).
                        Text(T("Последняя копия: ", "Last backup: ") + Backup.detail(size: nil))
                            .foregroundStyle(Look.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            copy()
                        } label: {
                            Text(running ? T("Копирую…", "Copying…")
                                 : finished == true ? T("✓ Скопировано", "✓ Copied")
                                 : finished == false ? T("Скопировано не всё — ещё раз", "Not everything was copied — again")
                                 : T("Скопировать сейчас", "Copy now"))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(placeName == nil || running || finished == true)
                    }

                    if stages.contains(where: { $0 != .waiting }) {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(0..<5, id: \.self) { i in row(i) }
                        }
                        .padding(12)
                        .background(Look.chrome, in: RoundedRectangle(cornerRadius: 10))
                    }
                    if let pending { question(pending.1.away.count) }
                    if !vanished.isEmpty || broughtBack != nil { vanishedNote }
                    if let problem {
                        Text(problem).font(Look.sans(14)).foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .font(Look.sans(15))
                .padding(20)
            }
            .navigationTitle(T("Резервная копия", "Backup"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(T("Закрыть", "Close")) { dismiss() }.disabled(running)
                }
            }
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.folder]) { picked in
                guard case .success(let url) = picked else { return }
                pick(url)
            }
        }
        .interactiveDismissDisabled(running)
        .onAppear(perform: measure)
        .onChange(of: placeName) { _, _ in
            finished = nil
            measure()
        }
        .onChange(of: running) { _, now in if !now { measure() } }
    }

    /// Объём архива и свободное место у копии — в стороне от экрана.
    private func measure() {
        let root = vault.root
        DispatchQueue.global(qos: .utility).async {
            let size = root.map(Backup.size(of:))
            let space = Backup.freeSpace()
            DispatchQueue.main.async {
                archiveSize = size
                free = space
            }
        }
    }

    // MARK: - Ступени на экране

    private func row(_ i: Int) -> some View {
        let stage = stages[i]
        return HStack(alignment: .top, spacing: 10) {
            Group {
                switch stage {
                case .waiting:
                    Image(systemName: "circle").foregroundStyle(Look.inkFaint)
                case .running:
                    ProgressView().controlSize(.small)
                case .done:
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                case .warn:
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                case .failed:
                    Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
                }
            }
            .frame(width: 22, height: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(i + 1). " + Self.names[i])
                    .font(Look.sans(14, weight: .semibold))
                    .foregroundStyle(stage == .waiting ? Look.inkFaint : Look.ink)
                if let text = detail(stage) {
                    Text(text)
                        .font(Look.sans(13))
                        .foregroundStyle(color(stage))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func detail(_ s: Stage) -> String? {
        switch s {
        case .waiting: return nil
        case .running(let t), .done(let t), .warn(let t), .failed(let t): return t
        }
    }

    private func color(_ s: Stage) -> Color {
        switch s {
        case .warn: return .orange
        case .failed: return .red
        default: return Look.inkSoft
        }
    }

    /// Не все файлы пришли из iCloud: подождать ещё или копировать без них.
    private func question(_ count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(T("Файлов нет на телефоне — они только в iCloud: \(count). Без них копия будет неполной.",
                   "Files not on this phone — only in iCloud: \(count). Without them the backup will be incomplete."))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button(T("Подождать ещё", "Wait longer")) { waitMore() }
                    .buttonStyle(.borderedProminent)
                Button(T("Копировать без них", "Copy without them")) { goOn() }
                    .buttonStyle(.bordered)
            }
            Button(T("Отменить", "Cancel"), role: .cancel) { cancel() }
                .font(Look.sans(14))
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    /// «С прошлой копии не стало файлов» — и кнопка вернуть их из копии.
    private var vanishedNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !vanished.isEmpty {
                Text(T("С прошлой копии в записях не стало файлов: \(vanished.count). Если вы удаляли их сами — "
                       + "всё в порядке. Если нет — они целы в копии.",
                       "Since the last backup, files are gone from your entries: \(vanished.count). If you deleted "
                       + "them yourself, all is well. If not, they are safe in the backup."))
                    .fixedSize(horizontal: false, vertical: true)
                Text(vanished.prefix(5).joined(separator: "\n") + (vanished.count > 5 ? "\n…" : ""))
                    .font(Look.mono(11.5))
                    .foregroundStyle(Look.inkSoft)
                // Что произойдёт — словами до нажатия (P458).
                Text(T("«Вернуть из копии» положит эти файлы обратно в папку записей — туда, где они лежали. Ничего не удаляется и не заменяется: файл, который уже на месте, не трогается. Если файл вы удалили нарочно, просто не нажимайте.",
                       "“Bring them back” puts these files back into your entries folder, where they were. Nothing is deleted or replaced: a file already in place is left alone. If you deleted a file on purpose, just don’t tap."))
                    .font(Look.sans(13))
                    .foregroundStyle(Look.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                Button(T("Вернуть из копии", "Bring them back from the backup")) { bringBack() }
                    .buttonStyle(.borderedProminent)
                    .disabled(running)
            }
            if let broughtBack {
                Text(broughtBack).font(Look.sans(14, weight: .medium))
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private func bringBack() {
        guard let root = vault.root else { return }
        let list = vanished
        running = true
        DispatchQueue.global(qos: .userInitiated).async {
            let n = Backup.bringBack(list, archive: root)
            DispatchQueue.main.async {
                running = false
                vanished = []
                broughtBack = T("Возвращено файлов: \(n). Те, что уже лежали на месте, не тронуты.",
                                "Files brought back: \(n). Files already in place were left alone.")
                Feel.done()
            }
        }
    }

    // MARK: - Ход

    private func pick(_ url: URL) {
        problem = nil
        if let root = vault.root, let t = Backup.trouble(with: url, archive: root) {
            problem = t
            return
        }
        if let t = Backup.choose(url) {
            problem = t
            return
        }
        placeName = Backup.placeName
        stages = Array(repeating: .waiting, count: 5)
        warning = vault.root.map { Backup.sameCloud(url, archive: $0) } == true
            ? T("Это тот же iCloud, где лежат записи: от беды с iCloud такая копия не спасёт и займёт там "
                + "вдвое больше места. Лучше флешка или другое облако.",
                "This is the same iCloud your entries are in: such a backup will not help if something "
                + "happens to iCloud, and it takes twice the space there. A USB stick or another cloud is better.")
            : nil
    }

    private func set(_ i: Int, _ s: Stage) {
        DispatchQueue.main.async { stages[i] = s }
    }

    private static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    private func copy() {
        guard let root = vault.root else { return }
        // Копия как раз дописывается сама (P902) — два хода разом не нужны.
        if Backup.autoRunning {
            problem = T("Копия сейчас дописывается сама — загляните через минуту.",
                        "The backup is updating itself right now — look again in a minute.")
            return
        }
        problem = nil
        running = true
        finished = nil
        vanished = []
        broughtBack = nil
        stages = Array(repeating: .waiting, count: 5)
        DispatchQueue.global(qos: .userInitiated).async {
            set(0, .running(T("Проверяю, можно ли туда писать…", "Checking that the place can be written to…")))
            let session: Backup.Session
            switch Backup.openPlace(archive: root) {
            case .failure(let e):
                set(0, .failed(e.text))
                DispatchQueue.main.async { running = false }
                return
            case .success(let s):
                session = s
            }
            set(0, .done(Backup.placeName ?? ""))
            set(1, .running(T("Составляю опись…", "Listing the files…")))
            var inv = Backup.inventory(root)
            if !inv.away.isEmpty {
                fetch(inv.away)
                inv = Backup.inventory(root)
            }
            if inv.away.isEmpty {
                proceed(session, inv, root: root)
            } else {
                DispatchQueue.main.async { pending = (session, inv) }
            }
        }
    }

    /// Попросить iPhone скачать файлы из iCloud и подождать.
    private func fetch(_ away: [URL]) {
        _ = Backup.fetch(away) { got, all in
            set(1, .running(T("Скачиваю из iCloud: \(got) из \(all)", "Downloading from iCloud: \(got) of \(all)")))
        }
    }

    private func waitMore() {
        guard let p = pending, let root = vault.root else { return }
        let session = p.0
        pending = nil
        DispatchQueue.global(qos: .userInitiated).async {
            fetch(p.1.away)
            let fresh = Backup.inventory(root)
            if fresh.away.isEmpty {
                proceed(session, fresh, root: root)
            } else {
                DispatchQueue.main.async { pending = (session, fresh) }
            }
        }
    }

    private func goOn() {
        guard let p = pending, let root = vault.root else { return }
        pending = nil
        DispatchQueue.global(qos: .userInitiated).async { proceed(p.0, p.1, root: root) }
    }

    private func cancel() {
        pending?.0.close()
        pending = nil
        stages[1] = .warn(T("Отменено — ничего не скопировано.", "Cancelled — nothing was copied."))
        running = false
    }

    /// Ступени 2–5 после описи. Работает в стороне от главного потока.
    private func proceed(_ session: Backup.Session, _ inv: Backup.Inventory, root: URL) {
        defer { session.close() }
        let target = session.target
        let todo = Backup.toCopy(inv, into: target)
        let need = todo.reduce(0) { $0 + $1.size }
        if let t = Backup.space(needed: need, at: target) {
            set(1, .failed(t))
            DispatchQueue.main.async { running = false }
            return
        }
        var listed = T("Файлов: \(inv.items.count) · \(Self.bytes(inv.bytes))",
                       "Files: \(inv.items.count) · \(Self.bytes(inv.bytes))")
        if !inv.away.isEmpty {
            listed += T(" · только в iCloud, без них: \(inv.away.count)",
                        " · only in iCloud, left out: \(inv.away.count)")
        }
        set(1, inv.away.isEmpty ? .done(listed) : .warn(listed))
        let gone = Backup.vanished(inv, previous: Backup.previousList(), root: root, target: target)
        if !gone.isEmpty { DispatchQueue.main.async { vanished = gone } }

        // 3. Копирование.
        var failed: [String] = []
        var done: Int64 = 0
        let all = Self.bytes(need)
        for (i, item) in todo.enumerated() {
            if i % 5 == 0 {
                set(2, .running(T("Копирую: \(i) из \(todo.count) · \(Self.bytes(done)) из \(all)",
                                  "Copying: \(i) of \(todo.count) · \(Self.bytes(done)) of \(all)")))
            }
            if !Backup.copyOne(item, into: target) { failed.append(item.rel) }
            done += item.size
        }
        let copied = todo.count - failed.count
        let copiedText = todo.isEmpty
            ? T("Нового нет — копия и так свежая.", "Nothing new — the backup was already up to date.")
            : T("Скопировано и сверено байт в байт: \(copied) · \(all)",
                "Copied and checked byte for byte: \(copied) · \(all)")
        if failed.isEmpty {
            set(2, .done(copiedText))
        } else {
            set(2, .warn(copiedText + T(" · не скопировались: \(failed.count)", " · could not copy: \(failed.count)")))
        }

        // 4. Проверка.
        set(3, .running(T("Сверяю копию с описью…", "Comparing the backup with the list…")))
        let missing = Backup.verify(inv, in: target)
        let complete = missing.isEmpty && inv.away.isEmpty
        if complete {
            set(3, .done(T("Копия полная: \(inv.items.count) файлов, \(Self.bytes(inv.bytes))",
                           "The backup is complete: \(inv.items.count) files, \(Self.bytes(inv.bytes))")))
        } else {
            let names = (missing + inv.away.map(\.lastPathComponent)).prefix(5).joined(separator: ", ")
            set(3, .warn(T("Копия неполная: нет файлов — \(missing.count + inv.away.count): \(names)",
                           "The backup is incomplete: \(missing.count + inv.away.count) files missing: \(names)")))
        }

        // 5. Опись в копии.
        let device = DispatchQueue.main.sync { UIDevice.current.name }
        if Backup.writeNote(inv, missing: missing, away: inv.away, in: target, device: device) {
            set(4, .done(Backup.noteName + T(" — её можно открыть и без приложения.", " — it opens without the app.")))
        } else {
            set(4, .warn(T("Опись не записалась; сама копия цела.", "The note could not be written; the backup itself is fine.")))
        }

        Backup.record(size: Backup.size(of: root), complete: complete,
                      missing: missing.count + inv.away.count)
        // Опись этой копии — чтобы в следующий раз заметить исчезнувшее.
        // О тех, что исчезли сейчас, спрашиваем один раз: в копии они целы.
        Backup.saveList(inv, root: root)
        DispatchQueue.main.async {
            if complete { Feel.done() } else { Feel.light() }
            finished = complete
            running = false
        }
    }
}

/// Копия сама и напоминание о ней (P368, P902): при возвращении в
/// приложение. Место копии выбрано и прошла неделя — приложение дописывает
/// туда новое само, молча. Напоминание приходит, только когда копии нет
/// вовсе или сама она не получилась (места копии сейчас нет), не чаще раза
/// в три дня после «Позже».
struct BackupReminder: ViewModifier {
    @EnvironmentObject private var vault: Vault
    @Environment(\.scenePhase) private var phase

    @State private var message: String?
    @State private var showing = false

    func body(content: Content) -> some View {
        content
            .onChange(of: phase) { _, now in if now == .active { check() } }
            .onAppear(perform: check)
            .alert(T("Пора сделать резервную копию", "Time to make a backup"),
                   isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button(T("Сделать копию", "Make a backup")) {
                    message = nil
                    showing = true
                }
                Button(T("Позже", "Later"), role: .cancel) {
                    Backup.later()
                    message = nil
                }
            } message: {
                Text((message ?? "") + T(" Место для копии выбирается один раз — дальше приложение само дописывает туда новое раз в неделю.",
                                         " You choose the place once — after that the app adds what is new by itself, once a week."))
            }
            .sheet(isPresented: $showing) { BackupSheet().environmentObject(vault) }
    }

    private func check() {
        guard !Vault.isPreview, let root = vault.root else { return }
        DispatchQueue.global(qos: .utility).async {
            // Сперва — копия сама (P902); напоминать — только если не вышло.
            Backup.autoRun(archive: root)
            var say = Backup.reminder(size: Backup.size(of: root))
            if say != nil, let why = Backup.autoTrouble {
                say = T("Копия сама не получилась: ", "The backup could not update itself: ") + why
            }
            DispatchQueue.main.async { if let say { message = say } }
        }
    }
}
