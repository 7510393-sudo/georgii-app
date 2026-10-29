import SwiftUI

/// Поиск по архиву.
///
/// Ищет по тому, что лежит в файлах: по заголовку дня, по тексту записи, по
/// названиям дел и по ответам «Как прошло?». Показывает при этом только
/// заголовок и текст: ответы — служебная часть записи, в выдаче от них
/// рябит. Но если искомое слово нашлось именно в них, день всё равно
/// попадает в список — иначе поиск лгал бы.
struct SearchView: View {

    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var archive: Archive
    @EnvironmentObject private var shell: Shell
    @EnvironmentObject private var vault: Vault

    /// Строка поиска лежит в оболочке: её очищает и меню поиска.
    private var query: String { shell.query }
    @FocusState private var typing: Bool

    /// Насколько клавиатура закрывает список находок.
    @State private var keyboard: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            field
            if archive.newestFirst.isEmpty {
                message(T("Пока нечего искать.", "Nothing to search yet."),
                        T("Напишите первую запись — и она найдётся здесь.",
                          "Write your first entry, and it will turn up here."))
            } else if found.isEmpty {
                message(T("Ничего не нашлось.", "Nothing found."),
                        T("По запросу «\(query)» \(whereNot)записей нет.",
                          "No entries \(whereNot)match “\(query)”."))
            } else {
                list
            }
        }
        .keyboardHeight($keyboard)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Страница поиска — та же старая бумага, что у прошедших дней:
        // сливочный цвет гаммы, рельеф и янтарные края (P693; прежде
        // персиковая бумага с одним волокном, P684). Архив — это прошлое.
        .background(Scheme.current.past.overlay(PageTexture(tab: .diary, aged: true,
                                                            edgeTop: true, edgeBottom: true)))
    }

    /// Строка поиска стоит вместо заголовка «Поиск» — между уголками
    /// шестерёнки и трёх точек, лупа слева на том же месте, что и на
    /// карте (P334).
    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Look.inkFaint)
            TextField(prompt, text: $shell.query)
                .focused($typing)
                .submitLabel(.search)
            if !query.isEmpty {
                Button { shell.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(Look.inkFaint)
                    .accessibilityLabel(T("Очистить", "Clear"))
            }
            filterMenu
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Look.chrome, in: RoundedRectangle(cornerRadius: 10))
        // Тот же отступ от уголков, что у строки поиска на карте.
        .padding(.leading, Corner.size + 8)
        .padding(.trailing, Corner.size + 8)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    /// Где и что искать — меню в самой строке поиска (P632; прежде в меню
    /// уголка). Горит, когда ищем не по всему архиву.
    private var filterMenu: some View {
        Menu {
            scopeButton(T("Искать везде", "Search everywhere"), .all)
            scopeButton(T("Только в дневнике", "Only in the diary"), .diary)
            scopeButton(T("Только в плане", "Only in the plan"), .plan)
            Divider()
            ForEach(Shell.Find.allCases, id: \.self) { kind in
                Button {
                    shell.find = kind
                } label: {
                    let title = kind == .all ? T("Искать всё", "Find everything")
                                             : T("Только: ", "Only: ") + kind.title.lowercased()
                    if shell.find == kind { Label(title, systemImage: "checkmark") } else { Text(title) }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: 18))
                .foregroundStyle(shell.scope != .all || shell.find != .all ? Look.accent : Look.inkFaint)
        }
        .accessibilityLabel(T("Что и где искать", "What and where to search"))
    }

    private func scopeButton(_ title: String, _ scope: Shell.Scope) -> some View {
        Button {
            shell.scope = scope
        } label: {
            if shell.scope == scope { Label(title, systemImage: "checkmark") } else { Text(title) }
        }
    }

    /// Где ищем — видно прямо в строке поиска, а не только в меню: иначе,
    /// выбрав «только в плане» и забыв об этом, человек решит, что запись
    /// пропала.
    private var prompt: String {
        switch shell.scope {
        case .all:   return T("Поиск по словам", "Search")
        case .diary: return T("Поиск в дневнике", "Search the diary")
        case .plan:  return T("Поиск в плане", "Search the plan")
        }
    }

    private var whereNot: String {
        switch shell.scope {
        case .all:   return ""
        case .diary: return T("в дневнике ", "in the diary ")
        case .plan:  return T("в плане ", "in the plan ")
        }
    }

    /// Ответы «Как прошло?» — часть дневника: их пишут там, а не в плане.
    private var found: [Archive.Day] {
        let days = archive.newestFirst.filter(kept)
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        // Пока ничего не набрано, список начинается с последнего заполненного
        // дня: пустые будущие дни, заведённые планировщиком (повторы, дела
        // вперёд), в нём ничего не говорят (P426).
        guard !needle.isEmpty else {
            let today = DayStore.today()
            return days.filter { $0.date <= today || !$0.isPlanOnly }
        }
        let scope = shell.scope
        return days.filter { day in
            if scope != .plan {
                if day.title.lowercased().contains(needle) { return true }
                if day.text.lowercased().contains(needle) { return true }
                if day.answers.values.contains(where: { $0.lowercased().contains(needle) }) {
                    return true
                }
            }
            if scope != .diary {
                return day.tasks.contains { $0.text.lowercased().contains(needle) }
            }
            return false
        }
    }

    /// Подходит ли день под «что искать» из меню поиска (P249).
    private func kept(_ day: Archive.Day) -> Bool {
        let kinds = day.attachments.map { Diary.kind(of: $0) }
        switch shell.find {
        case .all:   return true
        case .photo: return kinds.contains(.photo)
        case .video: return kinds.contains(.video)
        case .audio: return kinds.contains(.audio)
        case .file:  return kinds.contains(.file)
        case .place:
            return day.place != nil || day.text.contains("geo:")
        }
    }

    private var list: some View {
        // Выборка считается один раз, а не на каждую карточку.
        let days = found
        return ScrollView {
            // Находки — карточки картотеки, вид сверху: нижняя лежит поверх
            // верхней и своим корешком с датой закрывает её низ; уходя
            // вверх, карточка уменьшается и бледнеет, будто уходит
            // вдаль (P694, P695).
            LazyVStack(spacing: -Search.tabHeight) {
                ForEach(days) { day in
                    SearchCard(stamp: Search.stamp(day.date)) { row(day) }
                        .scrollTransition(.interactive, axis: .vertical) { content, phase in
                            // value: от −1 (ушла за верх) до 0 (на месте) и
                            // до 1 (ещё не въехала); вдаль уходит только верх.
                            content
                                .scaleEffect(1 + min(phase.value, 0) * 0.08)
                                .opacity(1 + min(phase.value, 0) * 0.55)
                        }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)
            // Место под клавиатуру. Без него последние находки лежат под
            // ней и не достаются прокруткой: список кончается там, где
            // начинается клавиатура (решение P174).
            // Строки разделов над клавиатурой больше нет (P505).
            .padding(.bottom, keyboard > 0 ? keyboard + 4 : 0)
        }
        // Второе нажатие на «Поиск» — список заново, с начала (P576).
        .id(shell.searchHome)
        .scrollDismissesKeyboard(.interactively)
        .animation(.easeOut(duration: 0.25), value: keyboard)
    }

    private func row(_ day: Archive.Day) -> some View {
        Button {
            typing = false
            store.go(to: day.date)
            // Искали в плане — туда и открываем: там нашлось искомое.
            shell.tab = shell.scope == .plan || (day.text.isEmpty && !day.tasks.isEmpty)
                ? .plan : .diary
            shell.screen = .today
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    // Дата — на корешке карточки (P695): год, месяц, число —
                    // в этом порядке, при поиске по архиву сначала выбирают
                    // время, а не день недели (P282).
                    if !day.title.isEmpty {
                        Text(Geo.stripped(day.title))
                            .font(Look.serif(15, weight: .semibold))
                            .foregroundStyle(Look.ink)
                            .lineLimit(1)
                    }
                    if !day.text.isEmpty {
                        Text(day.preview)
                            .font(Look.serif(13.5))
                            .foregroundStyle(Look.inkSoft)
                            .lineLimit(day.title.isEmpty ? 5 : 4)
                            .multilineTextAlignment(.leading)
                    }
                }
                Spacer(minLength: 0)
                if let cover = day.cover { preview(cover, of: day) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
        }
        .buttonStyle(.plain)
    }

    /// Превью справа от находки: снимок, кадр видео, голос или документ
    /// (P215).
    @ViewBuilder private func preview(_ link: String, of day: Archive.Day) -> some View {
        let url = vault.mediaURL(link, for: day.date)
        Group {
            switch Diary.kind(of: link) {
            case .photo: PhotoThumb(url: url)
            case .video: PhotoThumb(url: url, video: true)
            case .audio: FileTile(icon: "waveform", label: T("голос", "voice"))
            case .file:  FileTile(icon: "doc.text",
                                  label: (link as NSString).pathExtension.lowercased())
            }
        }
        // Превью высотой в пять строк записи (P282).
        .frame(width: Search.previewSide, height: Search.previewSide)
        .padding(.top, 2)
    }

    private func message(_ head: String, _ tail: String) -> some View {
        VStack(spacing: 6) {
            Spacer()
            Text(head).font(Look.sans(15)).foregroundStyle(Look.inkSoft)
            Text(tail).font(Look.sans(13)).foregroundStyle(Look.inkFaint)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity)
    }
}

enum Search {
    /// Высота корешка карточки, она же наложение карточек (P695).
    static let tabHeight: CGFloat = 22

    /// «2026 сентябрь 22» — от крупного к мелкому, как ищут в архиве.
    static func stamp(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.day, .month, .year], from: date)
        // Промежутки — в один пробел, вдвое уже прежних (P282).
        return "\(c.year ?? 2026) \(Ru.monthNames[(c.month ?? 1) - 1]) \(c.day ?? 1)"
    }

    /// Превью находки — того же размера, что все превью: в пять строк
    /// дневника (P385; прежде 86 — пять строк мелкого текста находки).
    static let previewSide: CGFloat = DiaryEditor.photoSize.width
}


/// Карточка находки — лист картотеки с корешком (P695): на левой трети
/// сверху выступает корешок с датой, остальное — лист чуть светлее
/// страницы, с заранее нарисованной тенью вправо-вниз (лампа слева сверху,
/// P670, P675). Снизу оставлено место под корешок следующей карточки: она
/// лежит поверх этой и закрывает пустой низ.
private struct SearchCard<Content: View>: View {
    @Environment(\.colorScheme) private var scheme
    let stamp: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                tab.frame(maxWidth: .infinity)
                Color.clear.frame(maxWidth: .infinity)
                Color.clear.frame(maxWidth: .infinity)
            }
            .frame(height: Search.tabHeight)
            content()
                .padding(.top, 2)
                .padding(.bottom, Search.tabHeight)
                .frame(maxWidth: .infinity)
                .background {
                    paper
                        .clipShape(body_shape)
                        .overlay(body_shape.stroke(edge, lineWidth: 0.8))
                        .background(PaintedShadow(radius: 5, corner: 12, x: 2, y: 3,
                                                  opacity: scheme == .dark ? 0.5 : 0.28))
                }
        }
    }

    private var edge: Color { Scheme.current.kraftEdge.opacity(0.45) }

    /// Лист: цвет страницы и поверх светлая вуаль — непрозрачный, иначе
    /// корешок соседа просвечивал бы.
    private var paper: some View {
        ZStack {
            Scheme.current.past
            Color.white.opacity(scheme == .dark ? 0.06 : 0.32)
        }
    }

    private var body_shape: UnevenRoundedRectangle {
        // Левый верхний угол прямой: там лист переходит в корешок.
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 12,
                               bottomTrailingRadius: 12, topTrailingRadius: 12)
    }

    private var tab: some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 0,
                                           bottomTrailingRadius: 0, topTrailingRadius: 10)
        return Text(stamp)
            .font(Look.mono(11.5, weight: .medium))
            .tracking(0.3)
            .foregroundStyle(Look.dateBlue)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background { paper.clipShape(shape).overlay(shape.stroke(edge, lineWidth: 0.8)) }
            // Шов с листом закрываем: корешок и лист — одна бумага.
            .overlay(alignment: .bottom) { paper.frame(height: 1.5).padding(.horizontal, 0.8) }
    }
}
