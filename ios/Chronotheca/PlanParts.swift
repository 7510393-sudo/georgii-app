import EventKit
import SwiftUI
import UIKit
import CoreLocation
import UniformTypeIdentifiers

extension View {
    /// Убрать клавиатуру. Поднявшуюся клавиатуру должно быть чем опустить,
    /// иначе экран заперт.
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

/// Пустой день. Общий для открытой страницы и соседних.
/// Запись дня не дошла до папки (P900): спокойная строка вверху страницы,
/// пока запись не пройдёт. Текст цел — он на экране и в страховке.
struct UnsavedNote: View {
    let why: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(T("Запись пока не дошла до папки", "This entry has not reached your folder yet"))
                .font(Look.sans(13, weight: .semibold))
                .foregroundStyle(Look.ink)
            Text(T("Текст цел: приложение хранит его у себя и пробует записать снова.",
                   "Your text is safe: the app is keeping it and trying again."))
                .font(Look.sans(12))
                .foregroundStyle(Look.inkSoft)
            Text(why)
                .font(Look.sans(11))
                .foregroundStyle(Look.inkFaint)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Look.chrome.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Look.accent.opacity(0.5), lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("unsavedNote")
    }
}

/// Строка вверху страницы: папку вела более новая версия приложения, здесь
/// только чтение (P953). Без слов из P482.
struct NewerArchiveNote: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(T("Эту папку вела более новая версия приложения",
                   "This folder was kept by a newer version of the app"))
                .font(Look.sans(13, weight: .semibold))
                .foregroundStyle(Look.ink)
            Text(T("Записи видны и ищутся. Писать здесь можно будет после обновления приложения.",
                   "Entries can be read and searched. Writing here opens after the app is updated."))
                .font(Look.sans(12))
                .foregroundStyle(Look.inkSoft)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Look.chrome.opacity(0.7)))
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("newerArchiveNote")
    }
}

struct PlanEmpty: View {
    /// Файл плана лежит в iCloud и ещё не скачан. Пустая страница здесь
    /// не значит пустой день — так и надо сказать (решение P182).
    var inCloud = false

    var body: some View {
        VStack(spacing: 4) {
            if inCloud {
                Text(T("План этого дня ещё загружается из iCloud.", "This plan is still downloading from iCloud."))
                Text(T("Как только придёт, он появится здесь.", "It will appear here as soon as it arrives."))
            } else {
                Text(T("На этот день ничего не запланировано.", "Nothing planned for this day."))
                Text(T("Нажмите «+», чтобы вписать дело.", "Tap “+” to add a task."))
            }
        }
        .font(Look.sans(14))
        .lineSpacing(5)
        .foregroundStyle(Look.inkFaint)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.horizontal, 22)
    }
}

/// Строка плана, которая не дело: снимок, поставленный между делами в
/// прежних сборках, или точка с карты. Прочие строки файла не рисуются,
/// но в файле остаются (P210, P213).
struct PlanExtraLine: View {
    let line: String
    var resolve: ((String) -> URL?)?
    var open: ((URL?) -> Void)?
    /// Касание по точке — карта на ней. Пусто — на соседних страницах.
    var openPoint: ((GeoPoint) -> Void)?
    /// Точку цепляют долгим нажатием и несут к нужному делу (P226, P241,
    /// P362, P374): ход пальца и где он на экране.
    var onCarry: ((Lift, CGPoint) -> Void)?
    /// Крестик у точки — строка уходит из плана (P352). Запомненное место
    /// остаётся на карте: из плана уходит только ссылка на него.
    var onDelete: (() -> Void)?
    /// Точку подержали и отпустили, не сдвинув: она крупнее, у неё крестик
    /// (P362). Касание по ней — крестик убрать.
    var armed = false
    /// Точку несут пальцем — она обведена синим.
    var carried = false
    var onArm: ((Bool) -> Void)?
    /// Снимок из ряда под делом несут пальцем (P377).
    var onPhoto: ((String, Lift, CGPoint) -> Void)? = nil
    var carriedPhoto: String? = nil
    /// Крестик у снимка под делом (P623, общий `Cross` — P713).
    var onRemovePhoto: ((String) -> Void)? = nil
    /// Куда в сетке встанет несомое — соседи расступаются сразу (P660).
    var photoSlot: Int? = nil

    var body: some View {
        if Plan.isPhotoRow(line) {
            // Снимки под делом — в ряд; каждый несут пальцем под другое
            // дело или назад в полоску (P358, P362).
            // Ряд — целое число клеток листа (P413).
            // Вплотную к плашке своего дела или события, запас — снизу, до
            // следующего (P651, вариант автора «А»): плашка и её вложения —
            // одно целое.
            GridSnap(top: true) {
                PlanPhotoRow(links: Plan.items(in: line), resolve: resolve, open: open,
                             openPoint: tapPoint, onCarry: onPhoto, carried: carriedPhoto,
                             onRemove: onRemovePhoto,
                             slot: photoSlot)
            }
        } else if let point = Geo.point(in: line) {
            GridSnap {
                PlanPointLine(point: point, open: tapPoint, armed: armed, glowing: carried,
                              onDelete: onDelete, onDisarm: { onArm?(false) })
            }
            .modifier(Carry(report: onCarry))
        }
    }

    /// Касание по точке: с крестиком — убрать крестик, без него — карта.
    /// Касание, которое на деле было концом долгого нажатия, — ни то ни
    /// другое: прежде после него открывалась карта (P374).
    private var tapPoint: ((GeoPoint) -> Void)? {
        guard let openPoint else { return nil }
        return { point in
            guard Date().timeIntervalSince(PlanHold.ended) > 0.4 else { return }
            if armed { onArm?(false) } else { openPoint(point) }
        }
    }
}

/// Вопрос о деле из серии: только этот день или этот и все следующие
/// (P359). Отдельно от плана: его цепочка и так длинная.
struct SeriesQuestion: ViewModifier {
    @EnvironmentObject private var store: DayStore

    func body(content: Content) -> some View {
        content.confirmationDialog(title, isPresented: shown, titleVisibility: .visible,
                                   presenting: store.seriesAsk) { ask in
            Button(only(ask)) { store.answerSeries(ask, all: false) }
            if ask.delete {
                Button(all(ask), role: .destructive) { store.answerSeries(ask, all: true) }
            } else {
                Button(all(ask)) { store.answerSeries(ask, all: true) }
            }
            Button(T("Отмена", "Cancel"), role: .cancel) { cancel(ask) }
        }
    }

    private var title: String { T("Это повторяющееся дело", "This is a repeating task") }

    private var shown: Binding<Bool> {
        Binding(get: { store.seriesAsk != nil }, set: { if !$0 { store.seriesAsk = nil } })
    }

    private func only(_ ask: DayStore.SeriesAsk) -> String {
        ask.delete ? T("Удалить только в этот день", "Delete this day only")
                   : T("Изменить только этот день", "Change this day only")
    }

    private func all(_ ask: DayStore.SeriesAsk) -> String {
        ask.delete ? T("Удалить этот и все следующие", "Delete this and all following")
                   : T("Изменить этот и все следующие", "Change this and all following")
    }

    /// Правку уже не отменить — она остаётся только в этом дне.
    private func cancel(_ ask: DayStore.SeriesAsk) {
        if ask.delete { store.seriesAsk = nil } else { store.answerSeries(ask, all: false) }
    }
}

/// Где на экране строки открытой страницы плана — дела, снимки и точки:
/// по ним ищется, куда встанет несомая точка (P374).
enum PlanZones {
    static var rows: [UUID: CGRect] = [:]

    /// Дело, под которое встанет принесённое из дневника или полоски
    /// (P409): последнее дело выше пальца. `nil` — палец не над планом.
    static func task(at spot: CGPoint, tasks: [PlanRow]) -> UUID? {
        guard spot != .zero else { return nil }
        let frames = tasks.compactMap { t in rows[t.id].map { (t.id, $0) } }
        guard let top = frames.map(\.1.minY).min() else { return nil }
        let bottom = rows.values.map(\.maxY).max() ?? top
        guard spot.y >= top - 8, spot.y <= bottom + 24 else { return nil }
        return frames.last { $0.1.minY < spot.y }?.0 ?? frames.first?.0
    }
    /// События Календаря (P376) — по их ключам.
    static var events: [String: CGRect] = [:]
    /// Отметка каждого события на экране — чтобы вложение из записи могло
    /// встать под него (стадия 3).
    static var marks: [String: DayEvents.Mark] = [:]

    /// Событие Календаря, под которое встанет принесённое, — по тому же
    /// правилу, что перенос из самого плана (P625): из дел и событий цель —
    /// та плашка, чей верх выше картинки и ближе всех к ней. Прежде событие
    /// засчитывалось, только если картинка стояла прямо на его плашке, — а её
    /// опускают чуть ниже, туда, где лягут вложения, и перенос уходил к делу
    /// выше (P651). `nil` — ближе дело или палец не над планом.
    static func event(at spot: CGPoint, tasks: [PlanRow]) -> DayEvents.Mark? {
        guard spot != .zero else { return nil }
        let frames = Array(rows.values) + Array(events.values)
        guard let top = frames.map(\.minY).min() else { return nil }
        let bottom = frames.map(\.maxY).max() ?? top
        guard spot.y >= top - 8, spot.y <= bottom + 24 else { return nil }
        guard let event = events.filter({ $0.value.minY < spot.y })
            .max(by: { $0.value.minY < $1.value.minY }) else { return nil }
        let taskTop = tasks.compactMap { rows[$0.id]?.minY }.filter { $0 < spot.y }.max() ?? -.infinity
        guard event.value.minY > taskTop else { return nil }
        return marks[event.key]
    }
    /// Полоска снимков внизу — туда снимок возвращают (P377).
    static var strip: CGRect?
    /// Верх заголовка «Дневник» на экране: снимок, отпущенный ниже, уходит в
    /// конец записи (P623) — ленты, по которой его узнавали, больше нет.
    static var diaryTop: CGFloat?
}

/// Записать, где строка на экране.
struct Zone: ViewModifier {
    let id: UUID

    func body(content: Content) -> some View {
        // Без пересчёта на каждом кадре свайпа вбок (P833).
        content.trackFrame(appear: { PlanZones.rows[id] = $0 },
                           change: { PlanZones.rows[id] = $0 },
                           gone: { PlanZones.rows[id] = nil })
    }
}

/// Когда кончилось последнее долгое нажатие на точку: касание сразу после
/// него — это тот же палец, а не просьба открыть карту (P374).
enum PlanHold {
    static var ended = Date.distantPast
}

/// Точку в плане цепляют долгим нажатием и несут вверх-вниз (P374).
/// Толчок и отклик — в тот миг, когда нажатие стало долгим, а не когда
/// палец убрали. Точка едет за пальцем; куда она встанет, решает план.
private struct Carry: ViewModifier {
    let report: ((Lift, CGPoint) -> Void)?

    /// Подъём уже объявлен.
    @State private var lifted = false
    /// Палец повёл — это перенос, а не просьба о крестике.
    @State private var moved = false
    @State private var dragged: CGFloat = 0
    /// Жест жив. Оборвался сам (палец увела прокрутка) — точка встаёт на
    /// место.
    @GestureState private var holding = false

    func body(content: Content) -> some View {
        if let report {
            content
                .offset(y: dragged)
                .shadow(color: .black.opacity(dragged == 0 ? 0 : 0.18), radius: 8, x: 3, y: 3)
                .gesture(LongPressGesture(minimumDuration: Cross.hold)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .updating($holding) { value, state, _ in
                        if case .second(true, _) = value { state = true }
                    }
                    .onChanged { value in
                        guard case .second(true, let drag) = value else { return }
                        if !lifted {
                            lifted = true
                            moved = false
                            report(.began, .zero)
                        }
                        guard let drag else { return }
                        if !moved, abs(drag.translation.height) > 10 || abs(drag.translation.width) > 10 {
                            moved = true
                        }
                        guard moved else { return }
                        dragged = drag.translation.height
                        report(.moved(drag.translation), drag.location)
                    }
                    .onEnded { value in
                        guard lifted else { return }
                        lifted = false
                        dragged = 0
                        var way = CGSize.zero
                        if case .second(true, let drag) = value, let drag { way = drag.translation }
                        report(.ended(way), .zero)
                    })
                .onChange(of: holding) { _, now in
                    guard !now else { return }
                    DispatchQueue.main.async {
                        guard lifted else { return }
                        lifted = false
                        dragged = 0
                        report(.cancelled, .zero)
                    }
                }
                .accessibilityHint(T("Долгое нажатие — перетащить к другому делу", "Long press to drag next to another task"))
        } else {
            content
        }
    }
}

/// Точка в плане — та же кнопочка, что в дневнике: булавка и название, без
/// координат (P345); касание открывает карту на ней (P213). Подержали —
/// крупнее и с крестиком «удалить», как значок на экране «Домой» (P362).
struct PlanPointLine: View {
    let point: GeoPoint
    var open: ((GeoPoint) -> Void)?
    var armed = false
    /// Синий контур: точку несут (P374).
    var glowing = false
    var onDelete: (() -> Void)?
    /// Крестик убрали касанием мимо него.
    var onDisarm: (() -> Void)? = nil
    /// Где квадрат точки в окне — по нему крестик встаёт на угол (P713).
    @State private var place: CGRect = .zero

    var body: some View {
        HStack(spacing: 0) {
            // Такой же квадрат, как снимок и точка в дневнике (P587).
            PointSquare(point: point)
                .frame(width: DiaryEditor.photoSize.width, height: DiaryEditor.photoSize.height)
                // Без перерисовки на каждом кадре свайпа вбок (P833).
                .trackFrame(appear: { place = $0 }, change: { place = $0 })
                .contentShape(Rectangle())
                .onTapGesture { open?(point) }
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(T("Точка на карте: ", "Place on the map: ") + point.label)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .frame(height: PlanPhotoLine.height)
        // Подержали — крестик сразу, ещё под пальцем, как у всех вложений
        // (P713, P720); повели — крестик уходит.
        .onChange(of: armed) { _, now in
            guard now else { Cross.hide(); return }
            guard let onDelete else { return }
            Cross.show(at: place, label: T("Удалить точку", "Delete place"),
                       onCross: onDelete, onDismiss: onDisarm)
        }
        // Строка точки — в тонкой синей рамке, пока точку несут; рамка едет
        // вместе с точкой (P380).
        .background {
            if glowing {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Look.planBg.opacity(0.6))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Look.glow, lineWidth: 1.5))
                    .shadow(color: Look.glow.opacity(0.5), radius: 4)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// Кнопочка точки для SwiftUI — нарисована тем же кодом, что в тексте
/// дневника, чтобы не расходилась с ним.
struct PointChipView: View {
    let point: GeoPoint

    var body: some View {
        // Как в тексте дневника: булавка, у точки с названием — и название,
        // без координат; координаты — на карте, куда ведёт касание (P345).
        let picture = PointChip.mark(glowing: false, title: point.title)
        Image(uiImage: picture)
            .frame(width: picture.size.width, height: picture.size.height)
    }
}
