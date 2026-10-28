import Foundation
import EventKit

/// Готовые страницы соседних дней (P679).
///
/// Прежде страница, которую листали, при появлении сама читала два файла
/// дня, разбирала их и спрашивала Календарь — всё на главном потоке, пока
/// идёт поворот; при быстром листании таких страниц подряд набиралась
/// стопка, и поворот «захлёбывался». Теперь соседние дни (по три в каждую
/// сторону) собираются заранее, в стороне, и лежат в памяти готовыми:
/// страница берёт готовое и только рисует. Картинки этих дней читаются
/// следом (`Photo.warm`).
///
/// Собранное одно и то же для открытой и соседних страниц — рисуются они
/// тем же кодом (P114); здесь только данные.
final class ReadyPages {

    static let shared = ReadyPages()

    /// Всё, что страница берёт из файлов дня и Календаря.
    struct Page {
        let rows: [PlanRow]
        let planPhotos: [String]
        let title: String
        let text: String
        let answers: [String: String]
        let photos: [String]
        let weather: String?
        let events: [DayEvents.Shown]
        /// Превью, которые стоит прочитать заранее: адрес и «под делом ли».
        let thumbs: [(url: URL, plan: Bool)]
    }

    private let lock = NSLock()
    private var pages: [String: Page] = [:]
    private var latest = 0
    private let queue = DispatchQueue(label: "готовые страницы", qos: .userInitiated)

    private init() {
        // Календарь поправили — готовые события устарели.
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil,
                                               queue: nil) { [weak self] _ in self?.forget() }
    }

    /// Готовая страница дня — или `nil`, если её ещё не собрали.
    func page(for date: Date) -> Page? {
        lock.lock(); defer { lock.unlock() }
        return pages[Vault.stamp(date)]
    }

    private func put(_ page: Page, for date: Date) {
        lock.lock(); defer { lock.unlock() }
        pages[Vault.stamp(date)] = page
    }

    /// Готовая страница или собранная сейчас — для случая, когда листают
    /// быстрее, чем успели приготовить.
    func pageNow(for date: Date, vault: Vault) -> Page {
        if let ready = page(for: date) { return ready }
        let built = Self.build(date, vault: vault)
        put(built, for: date)
        // Не успели приготовить — хотя бы картинки этого дня читаются сразу.
        Photo.warm(built.thumbs)
        return built
    }

    /// Выбросить один день (его записали) или все (вернулись в приложение,
    /// сменилась папка, поправили Календарь).
    func forget(_ date: Date? = nil) {
        lock.lock(); defer { lock.unlock() }
        if let date { pages[Vault.stamp(date)] = nil } else { pages.removeAll() }
    }

    /// Приготовить по три дня в каждую сторону от открытого, ближние первыми.
    /// Вызывается на главном потоке и сразу уходит в сторону; если человек
    /// успел уйти дальше, прежний обход бросается.
    func warm(around date: Date, vault: Vault) {
        guard vault.root != nil else { return }
        lock.lock()
        latest += 1
        let mine = latest
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            let cal = Calendar.current
            var keep: Set<String> = [Vault.stamp(date)]
            for step in [-1, 1, -2, 2, -3, 3] {
                self.lock.lock(); let current = self.latest; self.lock.unlock()
                guard current == mine else { return }
                guard let day = cal.date(byAdding: .day, value: step, to: date) else { continue }
                keep.insert(Vault.stamp(day))
                let page = self.page(for: day) ?? {
                    let built = Self.build(day, vault: vault)
                    self.put(built, for: day)
                    return built
                }()
                Photo.warm(page.thumbs)
            }
            // Дальних дней в памяти не держим.
            self.lock.lock()
            self.pages = self.pages.filter { keep.contains($0.key) }
            self.lock.unlock()
        }
    }

    /// Собрать страницу дня из файлов и Календаря.
    static func build(_ date: Date, vault: Vault) -> Page {
        let (rows, planPhotos) = Plan.splitPhotos(
            Plan.rows(from: DayFile(text: vault.read(.planner, for: date)).body))
        let file = DayFile(text: vault.read(.diary, for: date))
        // Ответы «Как прошло?» — по настоящим названиям дел, как у открытой
        // страницы (P155, P441).
        let diary = Diary(body: file.body, known: rows.map(\.text))
        let events = DayEvents.shown(DayEvents.items(for: date), marks: DayEvents.marks(in: rows))
        var thumbs: [(url: URL, plan: Bool)] = []
        let underTasks = rows.compactMap(\.verbatim).filter(Plan.isPhotoRow).flatMap(Plan.items(in:))
        for (links, plan) in [(underTasks, true), (diary.photos + planPhotos, false)] {
            for link in links where !Diary.isPoint(link) && Diary.kind(of: link) == .photo {
                if let url = vault.mediaURL(link, for: date) { thumbs.append((url, plan)) }
            }
        }
        return Page(rows: rows, planPhotos: planPhotos,
                    title: file.value("title") ?? "", text: diary.text,
                    answers: diary.answers, photos: diary.photos,
                    weather: file.value("weather"), events: events, thumbs: thumbs)
    }
}
