import SwiftUI
import UIKit
import MapKit

/// Поиск на карте (P251): круглая полупрозрачная кнопка с лупой; касание
/// раскрывает её в строку. Ищет свои места по названию и места на картах
/// Apple рядом с тем, что видно; координаты («59.93863, 30.31413» или
/// «geo:…») ставят точку сразу.
struct MapSearch: View {
    @Binding var open: Bool
    let places: [Place]
    let region: () -> MKCoordinateRegion?
    let pick: (String, CLLocationCoordinate2D) -> Void

    @State private var query = ""
    @State private var results: [Found] = []
    @State private var looking = false
    @State private var nothing = false
    /// Почему Карты Apple ничего не дали — если они ответили ошибкой (P370).
    @State private var trouble: String?
    @State private var engine = Engine()
    @FocusState private var typing: Bool

    /// Поиск держится, пока идёт: брошенный на полпути, он мог уйти, не
    /// ответив, — и строка говорила «ничего не нашлось» (P370).
    ///
    /// Подсказки по мере набора (P422) — как в Картах Apple: город, улица,
    /// заведение видны, пока пишут, без «Найти». Прежде, пока не нажали
    /// «Найти», искались только свои места — и город казался ненайденным.
    /// Подсказчик у Apple для того и сделан, чтобы спрашивать его на каждую
    /// букву: запросы он сам придерживает и отменяет устаревшие.
    final class Engine: NSObject, MKLocalSearchCompleterDelegate {
        var searches: [MKLocalSearch] = []
        let geocoder = CLGeocoder()
        var round = 0
        let completer = MKLocalSearchCompleter()
        /// Подсказки ещё нужны: после «Найти» или выбора — уже нет.
        var hinting = false
        var hinted: (([MKLocalSearchCompletion]) -> Void)?

        override init() {
            super.init()
            completer.delegate = self
            completer.resultTypes = [.address, .pointOfInterest]
        }

        func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
            guard hinting else { return }
            hinted?(completer.results)
        }

        func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
            guard hinting else { return }
            hinted?([])
        }
    }

    struct Found: Identifiable {
        let id = UUID()
        let title: String
        let subtitle: String
        let at: CLLocationCoordinate2D
        /// Значок, если это своё место.
        var mark: String?
        /// Настоящее ли это название, а не координаты, подставленные вместо
        /// него, — по нему решаем, предлагать ли сразу назвать точку (P330).
        var named = true
        /// Подсказка, у которой координат ещё нет: их спрашиваем, когда её
        /// выбрали (P422).
        var hint: MKLocalSearchCompletion?
    }

    /// Отдать находку наружу и очистить строку — иначе следующая вставленная
    /// координата оказывается поверх старого текста (P330).
    private func choose(_ found: Found) {
        if let hint = found.hint { return settle(hint) }
        query = ""
        results = []
        pick(found.named ? found.title : "", found.at)
    }

    /// Строка внизу, над клавиатурой; найденное — над строкой (P803).
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !results.isEmpty || looking || nothing { list }
            field
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { typing = true }
        }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Look.inkSoft)
            TextField(T("Место, адрес или координаты", "Place, address or coordinates"), text: $query)
                .focused($typing)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit(search)
                .onChange(of: query) { _, _ in ownOnly() }
            Button {
                query = ""
                results = []
                typing = false
                open = false
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Look.inkFaint)
            }
            .accessibilityLabel(T("Закрыть поиск", "Close search"))
        }
        .font(Look.sans(15))
        .padding(.horizontal, 14)
        .frame(height: 52)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Look.inkFaint.opacity(0.7), lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 4, x: 2, y: 2)
        .transition(.scale(scale: 0.2, anchor: .trailing).combined(with: .opacity))
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            if looking && results.isEmpty {
                Text(T("Ищу…", "Searching…")).font(Look.sans(13)).foregroundStyle(Look.inkSoft).padding(12)
            } else if nothing {
                Text(T("Ничего не нашлось. Попробуйте иначе или вставьте координаты.",
                       "Nothing found. Try other words or paste coordinates."))
                    .font(Look.sans(13)).foregroundStyle(Look.inkSoft).padding(12)
                if let trouble {
                    Text(trouble)
                        .font(Look.sans(12)).foregroundStyle(Color.red.opacity(0.8))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 12).padding(.bottom, 10)
                }
            }
            ForEach(results.prefix(8)) { found in
                Button { choose(found) } label: {
                    HStack(spacing: 10) {
                        Group {
                            if found.mark != nil {
                                GlyphIcon(size: 12)
                            } else {
                                Image(systemName: "mappin")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Look.inkSoft)
                            }
                        }
                        .frame(width: 24, height: 24)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(found.title).font(Look.sans(14.5)).foregroundStyle(Look.ink)
                                .lineLimit(1)
                            if !found.subtitle.isEmpty {
                                Text(found.subtitle).font(Look.sans(12)).foregroundStyle(Look.inkSoft)
                                    .lineLimit(1)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    /// Пока пишут — свои места сразу, ниже подсказки Карт Apple (P422).
    private func ownOnly() {
        nothing = false
        trouble = nil
        results = typed()
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, Pasted.find(text) == nil, Pasted.shortLink(in: text) == nil else {
            engine.hinting = false
            engine.completer.cancel()
            return
        }
        engine.hinting = true
        engine.hinted = { hints in
            guard !looking else { return }
            results = typed() + hints.prefix(6).map { hint in
                Found(title: hint.title, subtitle: hint.subtitle,
                      at: kCLLocationCoordinate2DInvalid, hint: hint)
            }
        }
        if let seen = region() { engine.completer.region = seen }
        engine.completer.queryFragment = text
    }

    /// Что видно сразу, без Карт Apple: свои места и вставленные координаты.
    private func typed() -> [Found] {
        var out = own(query)
        // Вставили координаты или ссылку с ними — точка видна сразу (P258).
        if let f = Pasted.find(query) {
            out.insert(Found(title: f.title ?? Geo.text(f.at),
                             subtitle: f.title == nil ? T("Координаты", "Coordinates") : Geo.text(f.at),
                             at: f.at, named: f.title != nil), at: 0)
        }
        return out
    }

    /// Выбрали подсказку — узнать, где она, и поставить туда (P422).
    private func settle(_ hint: MKLocalSearchCompletion) {
        engine.hinting = false
        engine.completer.cancel()
        engine.searches.forEach { $0.cancel() }
        results = []
        nothing = false
        trouble = nil
        looking = true
        engine.round += 1
        let round = engine.round
        let search = MKLocalSearch(request: MKLocalSearch.Request(completion: hint))
        engine.searches = [search]
        search.start { response, error in
            guard round == engine.round else { return }
            looking = false
            if let item = response?.mapItems.first {
                choose(Found(title: hint.title, subtitle: hint.subtitle, at: item.placemark.coordinate))
            } else {
                nothing = true
                if let error, !Self.empty(error) { trouble = Self.explain(error) }
            }
        }
    }

    private func own(_ text: String) -> [Found] {
        let needle = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return [] }
        return places.filter { $0.name.lowercased().contains(needle) || $0.text.lowercased().contains(needle) }
            .map { Found(title: $0.name, subtitle: T("Моё место", "My place"), at: $0.coordinate, mark: $0.mark) }
    }

    /// «Найти»: координаты — сразу туда; иначе свои места и места рядом.
    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Координаты в любом виде — Google, Apple, градусы с минутами,
        // ссылка (P258).
        if let f = Pasted.find(text) {
            return choose(Found(title: f.title ?? Geo.text(f.at),
                                subtitle: "", at: f.at, named: f.title != nil))
        }
        // Короткую ссылку надо открыть, чтобы узнать, куда она ведёт.
        if let link = Pasted.shortLink(in: text) {
            results = []
            looking = true
            Pasted.resolve(link) { f in
                looking = false
                if let f {
                    choose(Found(title: f.title ?? Geo.text(f.at),
                                subtitle: "", at: f.at, named: f.title != nil))
                } else {
                    nothing = true
                }
            }
            return
        }
        engine.hinting = false
        engine.completer.cancel()
        let mine = own(text)
        results = mine
        looking = true
        nothing = false
        trouble = nil
        // Три поиска разом (P370): адрес, улица, город, индекс — по всему
        // миру, через геокодер Apple; места на картах — и рядом с тем, что
        // видно, и везде. Прежде искали только в видимой части карты, и
        // улица или город за её краем не находились.
        engine.round += 1
        let round = engine.round
        engine.searches.forEach { $0.cancel() }
        engine.geocoder.cancelGeocode()
        var addresses: [Found] = []
        var near: [Found] = []
        var far: [Found] = []
        var errors: [Error] = []
        var left = 3
        let done = {
            left -= 1
            guard left == 0, round == engine.round else { return }
            looking = false
            results = Self.merged(mine + addresses + near + far)
            nothing = results.isEmpty
            if nothing, let e = errors.first { trouble = Self.explain(e) }
        }

        engine.geocoder.geocodeAddressString(text) { marks, error in
            if let error, !Self.empty(error) { errors.append(error) }
            addresses = (marks ?? []).prefix(5).compactMap { mark in
                guard let at = mark.location?.coordinate else { return nil }
                return Found(title: mark.name ?? text, subtitle: Self.line(mark), at: at)
            }
            done()
        }

        func local(_ region: MKCoordinateRegion?, _ put: @escaping ([Found]) -> Void) {
            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = text
            request.resultTypes = [.address, .pointOfInterest]
            if let region { request.region = region }
            let search = MKLocalSearch(request: request)
            engine.searches.append(search)
            search.start { response, error in
                if let error, !Self.empty(error) { errors.append(error) }
                put((response?.mapItems ?? []).prefix(8).map { item in
                    Found(title: item.name ?? text,
                          subtitle: item.placemark.title ?? "",
                          at: item.placemark.coordinate)
                })
                done()
            }
        }
        engine.searches = []
        if let seen = region() {
            local(seen) { near = $0 }
        } else {
            left -= 1
        }
        local(nil) { far = $0 }
    }

    /// Одно и то же место из разных поисков — один раз: ближе 50 метров и
    /// с тем же названием.
    private static func merged(_ all: [Found]) -> [Found] {
        var out: [Found] = []
        for f in all {
            let twin = out.contains { o in
                o.title == f.title
                    && CLLocation(latitude: o.at.latitude, longitude: o.at.longitude)
                        .distance(from: CLLocation(latitude: f.at.latitude, longitude: f.at.longitude)) < 50
            }
            if !twin { out.append(f) }
        }
        return out
    }

    /// Адрес строкой: «Baker Street, London NW1 6XE, England».
    private static func line(_ m: CLPlacemark) -> String {
        [m.thoroughfare.map { [m.subThoroughfare, $0].compactMap { $0 }.joined(separator: " ") },
         m.locality, m.postalCode, m.country]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// «Ничего не нашлось» — не ошибка: его и так скажет строка.
    private static func empty(_ e: Error) -> Bool {
        let ns = e as NSError
        if ns.domain == kCLErrorDomain {
            return ns.code == CLError.geocodeFoundNoResult.rawValue
                || ns.code == CLError.geocodeFoundPartialResult.rawValue
                || ns.code == CLError.geocodeCanceled.rawValue
        }
        if ns.domain == MKErrorDomain {
            return ns.code == Int(MKError.placemarkNotFound.rawValue)
                || ns.code == Int(MKError.directionsNotFound.rawValue)
        }
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    /// Почему Карты Apple не ответили — словами и с кодом.
    private static func explain(_ e: Error) -> String {
        let ns = e as NSError
        if (ns.domain == kCLErrorDomain && ns.code == CLError.network.rawValue)
            || (ns.domain == MKErrorDomain && ns.code == Int(MKError.serverFailure.rawValue)) {
            return T("Карты Apple не ответили — нет связи с интернетом? ", "Apple Maps did not answer — no internet connection? ")
                + "(\(ns.domain) \(ns.code))"
        }
        if ns.domain == MKErrorDomain, ns.code == Int(MKError.loadingThrottled.rawValue) {
            return T("Карты Apple просят подождать: слишком много поисков подряд. ", "Apple Maps asks to wait: too many searches in a row. ")
                + "(\(ns.domain) \(ns.code))"
        }
        return T("Карты Apple ответили ошибкой: ", "Apple Maps returned an error: ")
            + "\(ns.domain) \(ns.code)"
    }
}

/// Все свои места списком, с поиском по названию (P249). Касание — карта
/// на этом месте.
struct PlacesList: View {
    let places: [Place]
    let pick: (Place) -> Void

    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private var shown: [Place] {
        let sorted = places.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return sorted }
        return sorted.filter {
            $0.name.lowercased().contains(needle) || $0.text.lowercased().contains(needle)
        }
    }

    var body: some View {
        NavigationStack {
            List(shown) { place in
                Button { pick(place) } label: {
                    HStack(spacing: 12) {
                        GlyphIcon(size: 14)
                        .frame(width: 26, height: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(place.name).font(Look.sans(15)).foregroundStyle(Look.ink)
                            if !place.text.isEmpty {
                                Text(place.text).font(Look.sans(12.5)).foregroundStyle(Look.inkSoft)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .overlay {
                if places.isEmpty {
                    Text(T("Своих мест пока нет. Долгое нажатие на карту — новое место.",
                       "No places yet. A long press on the map makes a new one."))
                        .font(Look.sans(14))
                        .foregroundStyle(Look.inkSoft)
                        .multilineTextAlignment(.center)
                        .padding(32)
                }
            }
            .searchable(text: $query, prompt: T("Название или запись", "Name or note"))
            .navigationTitle(T("Мои места", "My places"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(T("Готово", "Done")) { dismiss() } }
            }
        }
    }
}
