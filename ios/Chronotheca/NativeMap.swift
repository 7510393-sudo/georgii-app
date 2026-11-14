import SwiftUI
import UIKit
import MapKit

/// Куда повести карту. Новая просьба — новый `id`.
struct MapFocus: Equatable {
    let id = UUID()
    let center: CLLocationCoordinate2D
    let meters: CLLocationDistance

    static func == (a: MapFocus, b: MapFocus) -> Bool { a.id == b.id }
}

/// День, в который человек отметил, где был.
struct MapDay {
    let stamp: String
    let date: Date
    let at: CLLocationCoordinate2D
    let today: Bool
}

/// Карты Apple как есть — с их жестами и кнопками (P217).
///
/// Прежняя карта была нарисована средствами SwiftUI, и у неё не работало
/// двойное касание: его перехватывал жест, ловивший место пальца. Здесь
/// жесты свои у карты, приложение добавляет только долгое нажатие.
struct NativeMap: UIViewRepresentable {

    var places: [Place]
    var days: [MapDay]
    /// Записи — на карте «Записи» вместо своих мест (P451).
    var entries: [MapEntry] = []
    var selected: Place?
    var focus: MapFocus?
    /// Спутник вместо схемы — из меню карты (P222).
    var satellite = false
    var onLongPress: (CLLocationCoordinate2D) -> Void
    var onPlace: (Place) -> Void
    var onDay: (Date) -> Void
    var onEntries: ([MapEntry]) -> Void = { _ in }
    var onSelected: () -> Void
    var onTapEmpty: () -> Void = {}
    var onRegion: (MKCoordinateRegion) -> Void = { _ in }
    var onDrag: () -> Void = {}
    /// Коснулись синей точки «я здесь» (P804).
    var onMe: (CLLocation) -> Void = { _ in }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = false
        map.showsScale = true
        // Знак «Карты» и ссылка «Правовые» Apple ставит по полям карты. Внизу
        // слева своих кнопок больше нет (P804: только лупа справа) — надпись
        // у самого низа (P819; прежде над кнопками, P533). Видимой её
        // оставлять Apple велит, и она видна.
        map.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 4, right: 8)
        map.register(MKMarkerAnnotationView.self,
                     forAnnotationViewWithReuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)

        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.pressed(_:)))
        press.minimumPressDuration = 0.45
        map.addGestureRecognizer(press)

        // Касание по пустому месту — закрыть панель. Ждёт, не будет ли
        // второго касания: двойное касание остаётся приближением.
        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.tapped(_:)))
        tap.delegate = context.coordinator
        let inner = (map.gestureRecognizers ?? [])
            + map.subviews.flatMap { $0.gestureRecognizers ?? [] }
        for case let double as UITapGestureRecognizer in inner where double.numberOfTapsRequired == 2 {
            tap.require(toFail: double)
        }
        // Долгое нажатие — не касание: отпущенный после него палец не
        // должен тут же закрывать только что поставленную точку (P235).
        tap.require(toFail: press)
        map.addGestureRecognizer(tap)

        // «Где я» и компас — справа сверху, как в Картах.
        let track = MKUserTrackingButton(mapView: map)
        let compass = MKCompassButton(mapView: map)
        compass.compassVisibility = .adaptive
        track.backgroundColor = UIColor(Look.chrome).withAlphaComponent(0.92)
        track.layer.cornerRadius = 8
        track.clipsToBounds = true
        for control in [track, compass] as [UIView] {
            control.translatesAutoresizingMaskIntoConstraints = false
            map.addSubview(control)
        }
        NSLayoutConstraint.activate([
            // Справа сверху, под уголком с тремя точками (P228).
            track.trailingAnchor.constraint(equalTo: map.trailingAnchor, constant: -12),
            // Под переключателем записей и кнопкой спутника (P451).
            track.topAnchor.constraint(equalTo: map.topAnchor, constant: MapSide.bottom),
            compass.trailingAnchor.constraint(equalTo: map.trailingAnchor, constant: -12),
            compass.topAnchor.constraint(equalTo: track.bottomAnchor, constant: 10),
        ])
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let keeper = context.coordinator
        keeper.parent = self
        let kind: MKMapType = satellite ? .hybrid : .standard
        if map.mapType != kind {
            map.mapType = kind
            // На спутнике плашки названий плотнее (P420) — перерисовать
            // те, что уже стоят.
            for case let mark as PlaceMark in map.annotations {
                guard let view = map.view(for: mark) else { continue }
                let shown = mark.place.name == Geo.text(mark.place.coordinate) ? "" : mark.place.name
                view.image = PlaceLabel.draw(shown, solid: satellite,
                                             chosen: mark.place.file != nil && selected?.file == mark.place.file)
            }
        }
        keeper.sync(map)
        if let focus, focus != keeper.focused {
            keeper.focused = focus
            let region = MKCoordinateRegion(center: focus.center,
                                            latitudinalMeters: focus.meters,
                                            longitudinalMeters: focus.meters)
            map.setRegion(region, animated: keeper.shown)
        }
        keeper.shown = true
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: NativeMap
        var focused: MapFocus?
        var shown = false
        /// Что сейчас стоит на карте — по метке на каждую: чтобы не
        /// переставлять метки зря.
        private var drawn: [String: MKAnnotation] = [:]

        init(_ parent: NativeMap) { self.parent = parent }

        /// Метки сличаются по тому, что на них видно, и переставляются только
        /// изменившиеся (P870). Прежде в сличение шёл внутренний номер места,
        /// а он новый при каждом чтении папки — карта открывалась или уезжала
        /// вбок, места перечитывались, и все метки снимались и ставились
        /// заново: названия моргали.
        func sync(_ map: MKMapView) {
            let draft = parent.selected.flatMap { $0.file == nil ? $0 : nil }
            var wanted: [(key: String, make: () -> MKAnnotation)] = []
            var used: [String: Int] = [:]
            func want(_ key: String, _ make: @escaping () -> MKAnnotation) {
                // Две одинаковые метки — обе на месте.
                let n = used[key, default: 0]
                used[key] = n + 1
                wanted.append((n == 0 ? key : key + "#\(n)", make))
            }
            for day in parent.days {
                want("d|\(day.stamp)|\(day.today)") { DayMark(day) }
            }
            for place in parent.places {
                // Выбранное место рисуется иначе (P428).
                let chosen = place.file != nil && parent.selected?.file == place.file
                want("p|\(place.file ?? "")|\(place.name)|\(place.mark)|\(place.latitude)|\(place.longitude)|\(chosen)|\(place.text.hashValue)") {
                    PlaceMark(place)
                }
            }
            for entry in parent.entries {
                want("e|\(entry.stamp)|\(entry.at.latitude)|\(entry.at.longitude)|\(entry.cover?.path ?? "")") {
                    EntryMark(entry)
                }
            }
            if let draft {
                want("x|\(draft.name)|\(draft.latitude)|\(draft.longitude)") { DraftMark(draft) }
            }
            let keys = Set(wanted.map(\.key))
            let gone = drawn.filter { !keys.contains($0.key) }
            if !gone.isEmpty {
                map.removeAnnotations(Array(gone.values))
                for key in gone.keys { drawn[key] = nil }
            }
            var added: [MKAnnotation] = []
            for item in wanted where drawn[item.key] == nil {
                let mark = item.make()
                drawn[item.key] = mark
                added.append(mark)
            }
            if !added.isEmpty { map.addAnnotations(added) }
        }

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let map = g.view as? MKMapView else { return }
            // Касание по метке — это выбор метки, а не пустое место.
            var hit = map.hitTest(g.location(in: map), with: nil)
            while let view = hit {
                if view is MKAnnotationView { return }
                hit = view.superview
            }
            parent.onTapEmpty()
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func pressed(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let map = g.view as? MKMapView else { return }
            let at = map.convert(g.location(in: map), toCoordinateFrom: map)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            parent.onLongPress(at)
        }

        func mapView(_ map: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            switch annotation {
            case let mark as PlaceMark:
                // Своя метка: спокойный кружок со значком и название на
                // светлой плашке — его не спутать с подписями самой карты
                // (P234).
                let view = MKAnnotationView(annotation: mark, reuseIdentifier: "место")
                // Названием остались координаты — на карте их не пишем (P404).
                let shown = mark.place.name == Geo.text(mark.place.coordinate) ? "" : mark.place.name
                let chosen = mark.place.file != nil && parent.selected?.file == mark.place.file
                let picture = PlaceLabel.draw(shown, solid: map.mapType != .standard, chosen: chosen)
                view.image = picture
                // Метка стоит на точке значком.
                view.centerOffset = CGPoint(x: 0, y: picture.size.height / 2 - PlaceLabel.dot / 2)
                view.displayPriority = .required
                view.collisionMode = .rectangle
                quick(view)
                return view
            case let mark as DraftMark:
                let view = MKMarkerAnnotationView(annotation: mark, reuseIdentifier: "точка")
                view.markerTintColor = .systemRed
                view.animatesWhenAdded = true
                view.titleVisibility = .visible
                view.displayPriority = .required
                return view
            case let mark as EntryMark:
                // Запись: превью снимка дня. Близкие сливаются в кружок с
                // числом — это делает сама карта (P451).
                let view = MKAnnotationView(annotation: mark, reuseIdentifier: "запись")
                view.clusteringIdentifier = "записи"
                // Не «обязательная»: такие карта в кружки не сливает.
                view.displayPriority = .defaultHigh
                show([mark.entry], in: view, for: mark)
                quick(view)
                return view
            case let cluster as MKClusterAnnotation:
                let members = cluster.memberAnnotations.compactMap { ($0 as? EntryMark)?.entry }
                guard !members.isEmpty else { return nil }
                let view = MKAnnotationView(annotation: cluster, reuseIdentifier: "записи")
                view.displayPriority = .required
                show(members, in: view, for: cluster)
                quick(view)
                return view
            case let mark as DayMark:
                let view = MKAnnotationView(annotation: mark, reuseIdentifier: "день")
                // Точка дня подписана датой: иначе непонятно, что за точка
                // (P281). Сама точка — ровно на месте, подпись под ней.
                let picture = DayMark.dot(today: mark.day.today,
                                          label: mark.day.today ? T("сегодня", "today") : Ru.shortDate(mark.day.date))
                view.image = picture
                view.centerOffset = CGPoint(x: 0, y: picture.size.height / 2 - 8)
                view.displayPriority = .defaultHigh
                quick(view)
                return view
            default:
                return nil
            }
        }

        /// Своё касание на метке: откликается сразу. Карта сама выбирает
        /// метку, лишь дождавшись, не будет ли второго касания, — это почти
        /// полсекунды, и человеку казалось, что она тормозит (P243).
        private func quick(_ view: MKAnnotationView) {
            let tap = UITapGestureRecognizer(target: self, action: #selector(markTapped(_:)))
            view.addGestureRecognizer(tap)
        }

        @objc func markTapped(_ g: UITapGestureRecognizer) {
            guard let annotation = (g.view as? MKAnnotationView)?.annotation else { return }
            switch annotation {
            case let mark as PlaceMark: parent.onPlace(mark.place)
            case let mark as DayMark: parent.onDay(mark.day.date)
            case let mark as EntryMark: parent.onEntries([mark.entry])
            case let cluster as MKClusterAnnotation:
                parent.onEntries(cluster.memberAnnotations.compactMap { ($0 as? EntryMark)?.entry })
            default: return
            }
        }

        /// Превью записи (или кружка записей) на карте: сразу — рамка с
        /// числом, снимок дорисовывается, когда прочитан с диска (P451).
        private func show(_ entries: [MapEntry], in view: MKAnnotationView, for annotation: MKAnnotation) {
            let count = Set(entries.map(\.stamp)).count
            let newest = entries.sorted { $0.stamp > $1.stamp }
            let cover = newest.first(where: { $0.cover != nil })
            let key = cover.flatMap { $0.cover.map { "карта|" + $0.path } }
            let ready = key.flatMap { Photo.cache.object(forKey: $0 as NSString) }
            view.image = EntryPin.draw(ready, count: count)
            view.centerOffset = EntryPin.offset
            guard ready == nil, let cover, let url = cover.cover, let key else { return }
            Task { @MainActor [weak view] in
                let image: UIImage?
                if cover.video {
                    image = await Photo.poster(url, side: EntryPin.side)
                } else {
                    image = await Task.detached { Photo.load(url, side: EntryPin.side) }.value
                }
                guard let image else { return }
                Photo.cache.setObject(image, forKey: key as NSString)
                // Карта могла уже отдать эту рамку другой метке.
                guard let view, view.annotation === annotation else { return }
                view.image = EntryPin.draw(image, count: count)
            }
        }

        /// Карту тронул палец, а не программа (P803).
        func mapView(_ map: MKMapView, regionWillChangeAnimated animated: Bool) {
            let touched = map.subviews.first?.gestureRecognizers?.contains {
                $0.state == .began || $0.state == .changed
            } ?? false
            if touched { parent.onDrag() }
        }

        func mapView(_ map: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegion(map.region)
        }

        func mapView(_ map: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation else { return }
            switch annotation {
            // Свои места и дни отвечают на своё касание сразу (P243).
            case is PlaceMark, is DayMark, is EntryMark, is MKClusterAnnotation: break
            case is DraftMark: parent.onSelected()
            case let mine as MKUserLocation:
                if let location = mine.location { parent.onMe(location) }
            default: return
            }
            // Снять выбор сразу — чтобы ту же метку можно было нажать снова.
            map.deselectAnnotation(annotation, animated: false)
        }
    }
}

/// Где стоят кнопки справа сверху на карте (P451): переключатель «мои
/// места / записи» из двух половин и под ним «схема / спутник»; ниже —
/// «где я» и компас.
enum MapSide {
    static let button: CGFloat = 42
    static let segment: CGFloat = 40
    static var top: CGFloat { Corner.size + 6 }
    static var bottom: CGFloat { top + 2 * segment + 1 + 8 + button + 10 }
}

/// День на карте «Записи» — на одном из своих мест (P451).
struct MapEntry {
    let stamp: String
    let date: Date
    let at: CLLocationCoordinate2D
    /// Снимок или видео дня для превью.
    let cover: URL?
    let video: Bool
    /// Заголовок или начало записи — для списка.
    let line: String
}

/// Несколько записей под одним кружком — для листка со списком.
struct MapEntryGroup: Identifiable {
    let id = UUID()
    let entries: [MapEntry]
}

final class EntryMark: NSObject, MKAnnotation {
    let entry: MapEntry
    var coordinate: CLLocationCoordinate2D { entry.at }
    var title: String? { Ru.shortDate(entry.date) }
    init(_ entry: MapEntry) { self.entry = entry }
}

/// Превью записи на карте: снимок в белой рамке с хвостиком к месту и,
/// если записей несколько, — число в синем кружке.
enum EntryPin {
    static let side: CGFloat = 48
    private static let size = CGSize(width: side + 16, height: side + 17)
    private static let card = CGRect(x: 4, y: 8, width: side, height: side)

    /// Хвостик рамки — ровно на месте.
    static var offset: CGPoint {
        CGPoint(x: size.width / 2 - card.midX, y: -(card.maxY + 6 - size.height / 2))
    }

    static func draw(_ photo: UIImage?, count: Int) -> UIImage {
        UIGraphicsImageRenderer(size: size).image { ctx in
            let g = ctx.cgContext
            let frame = UIBezierPath(roundedRect: card, cornerRadius: 9)
            let tail = UIBezierPath()
            tail.move(to: CGPoint(x: card.midX - 6, y: card.maxY - 1))
            tail.addLine(to: CGPoint(x: card.midX, y: card.maxY + 6))
            tail.addLine(to: CGPoint(x: card.midX + 6, y: card.maxY - 1))
            tail.close()
            g.saveGState()
            g.setShadow(offset: CGSize(width: 0, height: 1.5), blur: 3,
                        color: UIColor.black.withAlphaComponent(0.3).cgColor)
            UIColor.white.setFill()
            frame.fill()
            tail.fill()
            g.restoreGState()

            let inner = card.insetBy(dx: 2.5, dy: 2.5)
            g.saveGState()
            UIBezierPath(roundedRect: inner, cornerRadius: 7).addClip()
            if let photo, photo.size.width > 0, photo.size.height > 0 {
                let scale = max(inner.width / photo.size.width, inner.height / photo.size.height)
                let w = photo.size.width * scale, h = photo.size.height * scale
                photo.draw(in: CGRect(x: inner.midX - w / 2, y: inner.midY - h / 2, width: w, height: h))
            } else {
                // Записи без снимка — бумажка с книжкой.
                UIColor(Look.sticker).setFill()
                UIRectFill(inner)
                if let book = UIImage(systemName: "book.closed",
                                      withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .medium))?
                    .withTintColor(UIColor(Look.inkSoft), renderingMode: .alwaysOriginal) {
                    book.draw(at: CGPoint(x: inner.midX - book.size.width / 2,
                                          y: inner.midY - book.size.height / 2))
                }
            }
            g.restoreGState()

            guard count > 1 else { return }
            let text = (count > 999 ? "999+" : "\(count)") as NSString
            let font = UIFont.systemFont(ofSize: 11, weight: .bold)
            let words: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let width = max(20, ceil(text.size(withAttributes: words).width) + 10)
            let badge = CGRect(x: min(size.width - width, card.maxX - width / 2 - 2), y: 0,
                               width: width, height: 20)
            UIColor(Look.accent).setFill()
            UIBezierPath(roundedRect: badge, cornerRadius: 10).fill()
            UIColor.white.setStroke()
            let ring = UIBezierPath(roundedRect: badge.insetBy(dx: 0.75, dy: 0.75), cornerRadius: 9.25)
            ring.lineWidth = 1.5
            ring.stroke()
            let used = text.size(withAttributes: words)
            text.draw(at: CGPoint(x: badge.midX - used.width / 2, y: badge.midY - used.height / 2),
                      withAttributes: words)
        }
    }
}

/// Список записей под одним кружком карты (P451): дата, начало записи,
/// превью; касание — открыть день.
struct MapEntriesList: View {
    let entries: [MapEntry]
    let open: (Date) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(entries, id: \.stamp) { entry in
                Button { open(entry.date) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Group {
                            if let url = entry.cover {
                                PhotoThumb(url: url, video: entry.video)
                            } else {
                                Image(systemName: "book.closed")
                                    .font(.system(size: 18))
                                    .foregroundStyle(Look.inkSoft)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Look.sticker)
                            }
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(Search.stamp(entry.date))
                                .font(Look.sans(13))
                                .foregroundStyle(Look.inkSoft)
                            Text(entry.line)
                                .font(Look.serif(16))
                                .foregroundStyle(Look.ink)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle(T("Записи здесь", "Entries here"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(T("Готово", "Done")) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Своё место на карте.
final class PlaceMark: NSObject, MKAnnotation {
    let place: Place
    var coordinate: CLLocationCoordinate2D { place.coordinate }
    var title: String? { place.name }
    init(_ place: Place) { self.place = place }
}

/// Метка своего места: значок, под ним — название на плашке. Без
/// названия — один значок: координаты на карте только загораживают вид,
/// они есть внизу плашки ввода (P404).
enum PlaceLabel {
    static let dot: CGFloat = PlaceLabelSize.dot

    /// `solid` — карта со спутника (P420): пёстрый снимок сквозь
    /// прозрачную плашку мешает читать — плашка плотнее.
    /// `chosen` — место выбрано (P428): плашка непрозрачная. Стрелка
    /// выбором не меняется.
    static func draw(_ name: String, solid: Bool = false, chosen: Bool = false) -> UIImage {
        let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let words: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(Look.ink)]
        let given = name.trimmingCharacters(in: .whitespaces)
        let text = name as NSString
        let named = !given.isEmpty
        let wide = named ? min(text.size(withAttributes: words).width, 150) : 0
        // Поля вокруг букв — 3 по бокам и 1 сверху и снизу (P474): шрифт тот же, плашка
        // теснее (было 6 и 3).
        let plate = named ? CGSize(width: wide + 6, height: font.lineHeight + 2) : .zero
        let above: CGFloat = dot + 4
        let size = CGSize(width: max(dot, plate.width) + 4,
                          height: named ? above + plate.height + 3 : dot + 4)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let mid = size.width / 2
            GlyphArt.draw(in: CGRect(x: mid - dot / 2, y: 1, width: dot, height: dot))
            guard named else { return }
            let box = CGRect(x: mid - plate.width / 2, y: above,
                             width: plate.width, height: plate.height)
            ctx.cgContext.setShadow(offset: CGSize(width: 0, height: 1), blur: 2,
                                    color: UIColor.black.withAlphaComponent(0.12).cgColor)
            // Полупрозрачная: много названий рядом не должны закрывать карту
            // (0.34 — P372; 0.42 — P361; 0.62 — P330; почти непрозрачная — P244).
            UIColor(Look.sticker).withAlphaComponent(chosen ? 1 : solid ? 0.88 : 0.34).setFill()
            UIBezierPath(roundedRect: box, cornerRadius: 4).fill()
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            // Кромка — чтобы плашка читалась на пёстрой карте (P244).
            UIColor(Look.inkSoft).withAlphaComponent(0.55).setStroke()
            let edge = UIBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 4)
            edge.lineWidth = 1
            edge.stroke()
            text.draw(with: CGRect(x: box.minX + 3, y: box.minY + 1, width: wide, height: font.lineHeight),
                      options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                      attributes: words, context: nil)
        }
    }
}

/// Точка, выбранная долгим нажатием, пока у неё нет файла.
final class DraftMark: NSObject, MKAnnotation {
    let place: Place
    var coordinate: CLLocationCoordinate2D { place.coordinate }
    var title: String? { place.name.isEmpty ? T("Точка", "Place") : place.name }
    init(_ place: Place) { self.place = place }
}

/// День, в который человек отметил, где был.
final class DayMark: NSObject, MKAnnotation {
    let day: MapDay
    var coordinate: CLLocationCoordinate2D { day.at }
    init(_ day: MapDay) { self.day = day }

    var title: String? { day.today ? T("Сегодня", "Today") : Ru.shortDate(day.date) }

    /// Точка дня и под ней — дата на светлой плашке.
    static func dot(today: Bool, label: String) -> UIImage {
        let side: CGFloat = 16
        let font = UIFont.systemFont(ofSize: 10.5, weight: .medium)
        let words: [NSAttributedString.Key: Any] = [.font: font,
                                                     .foregroundColor: UIColor(Look.inkSoft)]
        let text = (label as NSString).size(withAttributes: words)
        let plate = CGSize(width: ceil(text.width) + 10, height: ceil(text.height) + 4)
        let size = CGSize(width: max(side, plate.width), height: side + 2 + plate.height)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let box = CGRect(x: (size.width - side) / 2 + 2, y: 2, width: side - 4, height: side - 4)
            UIColor.white.setFill()
            UIBezierPath(ovalIn: box).fill()
            UIColor(today ? Look.accent : Look.inkSoft).setFill()
            UIBezierPath(ovalIn: box.insetBy(dx: 2, dy: 2)).fill()
            let back = CGRect(x: (size.width - plate.width) / 2, y: side + 2,
                              width: plate.width, height: plate.height)
            UIColor.white.withAlphaComponent(0.85).setFill()
            UIBezierPath(roundedRect: back, cornerRadius: plate.height / 2).fill()
            (label as NSString).draw(at: CGPoint(x: back.minX + 5, y: back.minY + 2),
                                     withAttributes: words)
        }
    }
}
