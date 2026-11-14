import SwiftUI
import UIKit
import MapKit

/// Своя карта человека: его места с названиями и дни, где он был.
///
/// Открывается глобусом внизу. Сама карта — Карты Apple со всеми их
/// жестами: двойное касание приближает, касание двумя пальцами отдаляет,
/// щипок, поворот (P217). Долгое нажатие ставит булавку и открывает
/// сверху панель «Точка» — название и что здесь было. Кнопка «Запомнить
/// точку» стоит там же, где «геоточка», и пишет точку в план или в
/// дневник — туда, откуда открыли карту (P213).
///
/// Своих серверов у приложения нет (P198). Места — файлы в папке «Места»,
/// по файлу на место.
struct MapScreen: View {

    @EnvironmentObject private var vault: Vault
    @EnvironmentObject private var store: DayStore
    @EnvironmentObject private var archive: Archive
    @EnvironmentObject private var shell: Shell

    @State private var places: [Place] = []
    /// Выбранная точка: поставленная долгим нажатием, нажатое место или
    /// точка из текста. Её и запомнит кнопка внизу.
    @State private var selected: Place?
    /// Что открыто сверху: плашка точки (P803: одна, без облачка перед ней).
    @State private var panel: Panel?
    @State private var focus: MapFocus?
    /// Карту уже открывали — место спрашивали (P581).
    @State private var begun = false
    /// Плашка открыта на синей точке «я здесь» (P804): сохранить — с погодой.
    @State private var me: CLLocation?
    @State private var asking = false
    @State private var searching = false
    /// Что сейчас видно на карте — поиск ищет рядом. Не состояние экрана:
    /// карта двигается часто, перерисовывать всё незачем.
    @State private var seen = Seen()
    /// Насколько клавиатура закрывает низ карты — кнопки внизу поднимаются
    /// над ней, когда открыта панель «Точка» с полем названия (P306).
    @State private var keyboard: CGFloat = 0
    /// Сколько от низа карты до низа экрана — там нижняя строка разделов.
    /// Клавиатура закрывает и её, так что кнопки поднимаются не на всю
    /// высоту клавиатуры, а только на то, что она закрывает у самой карты
    /// (P340).
    @State private var belowMap: CGFloat = 0

    final class Seen { var region: MKCoordinateRegion? }
    /// Когда поставили последнюю точку долгим нажатием.
    @State private var picked = Date.distantPast

    enum Panel { case naming }

    /// Несколько записей под одним кружком — их список (P451).
    @State private var entryList: MapEntryGroup?

    var body: some View {
        ZStack(alignment: .top) {
            NativeMap(places: shell.mapEntries ? [] : places, days: days,
                      entries: shell.mapEntries ? entries : [],
                      selected: selected, focus: focus,
                      satellite: shell.mapSatellite,
                      onLongPress: longPress, onPlace: choose, onDay: openDay,
                      onEntries: openEntries,
                      onSelected: { withAnimation { panel = .naming } },
                      onTapEmpty: tapEmpty,
                      onRegion: { seen.region = $0 },
                      // Карту двигают пальцем — клавиатура уходит (P803).
                      onDrag: { hideKeyboard() },
                      onMe: here)
            // Справа сверху, под уголком с тремя точками: «мои места /
            // записи» и под ним «схема / спутник» (P451; спутник прежде —
            // внизу справа, P419). Плашки точки ложатся поверх, как и на
            // кнопку «где я». Пока плашка открыта, их нет: сквозь
            // полупрозрачную плашку они путались со значками (P461).
            if selected == nil || panel == nil {
                side
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity)
            }
            if let selected, panel == .naming {
                // Новая булавка — новая панель: поля не должны
                // остаться от прежней точки.
                PointPanel(place: selected, typeAtOnce: selected.file == nil && me == nil,
                           cancel: cancel, done: name,
                           remove: selected.file == nil ? nil : { asking = true },
                           navigate: { MapActions.navigate($0) },
                           save: save)
                    .id(selected.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            // Поиск — лупой внизу справа, строка над клавиатурой (P803;
            // прежде вверху между уголками, P283).
        }
        .animation(.easeOut(duration: 0.15), value: panel)
        .overlay(alignment: .bottom) { bar }
        // Вкладка у правого края посередине (P855): подсказывает, что
        // экран смахивается к «Дневнику». Касаний не берёт — край
        // по-прежнему тянется пальцем (P840).
        .overlay(alignment: .trailing) { SwipeTab() }
        .background(Look.chrome)
        .background(GeometryReader { geo in
            let bottom = geo.frame(in: .global).maxY
            Color.clear
                .onAppear { belowMap = max(0, UIScreen.main.bounds.height - bottom) }
                .onChange(of: bottom) { _, now in
                    belowMap = max(0, UIScreen.main.bounds.height - now)
                }
        })
        // Нижние разделы приложения клавиатура не поднимает нигде (P113) —
        // значит, и кнопки карты сами должны подняться над ней, пока
        // открыто поле названия новой точки (P306). Высота клавиатуры
        // считается до самого края экрана (P308), а низ карты стоит выше
        // края — на нижней строке разделов; её высота вычитается (P340).
        .keyboardHeight($keyboard, toScreenEdge: true)
        .confirmationDialog(T("Удалить точку?", "Delete the place?"), isPresented: $asking, titleVisibility: .visible) {
            Button(T("Удалить точку", "Delete place"), role: .destructive) { remove() }
            Button(T("Оставить точку", "Keep place"), role: .cancel) { }
        } message: {
            Text(selected?.file == nil ? T("Булавка уйдёт с карты.", "The pin will leave the map.")
                 : T("Файл этой точки будет удалён из папки «", "The file of this place will be deleted from the “")
                   + vault.name(.places) + T("».", "” folder."))
        }
        // Карта собрана заранее и ждёт на плашке (P581): о месте и о своих
        // местах — только когда её открыли, а не когда собрали.
        .onAppear { if shell.screen == .map { opened() } }
        // Снимок CI «плашка точки» (P813): записанное место с открытой плашкой.
        .onChange(of: shell.previewMapPoint) { _, _ in
            choose(Place(name: "Café on the corner",
                          coordinate: CLLocationCoordinate2D(latitude: 51.50135, longitude: -0.14189),
                          text: "Coffee with Anna", file: "preview.md"))
        }
        .onChange(of: shell.screen) { _, now in if now == .map { opened() } }
        // Карта ещё не ушла с экрана, а человек уже коснулся точки в
        // тексте, — плашка открывается и тогда.
        .onChange(of: shell.mapFocus) { _, point in
            if let point { show(point) }
        }
        // Из меню карты: все места разом и список мест (P249).
        .onChange(of: shell.mapShowAll) { _, _ in showAll() }
        // Второе нажатие на «Карту» — к тому месту, где вы сейчас (P577).
        .onChange(of: shell.mapHome) { _, _ in
            hideKeyboard()
            Locator.shared.current { location in
                guard let at = location?.coordinate else {
                    return shell.say(T("Не удалось узнать, где вы. Проверьте, разрешено ли приложению место.",
                                     "Could not find where you are. Check that the app may use Location."))
                }
                focus = MapFocus(center: at, meters: 2000)
            }
        }
        .sheet(isPresented: $shell.mapList) {
            PlacesList(places: places) { place in
                shell.mapList = false
                choose(place)
                focus = MapFocus(center: place.coordinate, meters: 1500)
            }
        }
        .sheet(item: $entryList) { group in
            MapEntriesList(entries: group.entries) { date in
                entryList = nil
                openDay(date)
            }
        }
        .onChange(of: selected) { _, now in
            shell.mapPoint = now.map { GeoPoint(title: $0.name, at: $0.coordinate) }
        }
        .onDisappear { shell.mapPoint = nil }
    }

    /// Точек дней на карте больше нет (P294): на карте — только свои
    /// места человека.
    private var days: [MapDay] { [] }

    /// Записи на карте (P451): день — на каждом своём месте, по точкам в
    /// тексте, заголовке, под делами и в ответах. Близкие точки одного
    /// дня — одно место.
    private var entries: [MapEntry] {
        // Только дни с точками (P572): прежде для каждого дня архива искался
        // файл обложки — на архиве за десять лет карта открывалась секундами.
        // Дни с точками отобраны заранее, при смене описи (P579).
        archive.withPoints.flatMap { day -> [MapEntry] in
            var seen = Set<String>()
            let cover = day.cover.flatMap { link -> (URL, Bool)? in
                let kind = Diary.kind(of: link)
                guard kind == .photo || kind == .video,
                      let url = vault.mediaURL(link, for: day.date) else { return nil }
                return (url, kind == .video)
            }
            return day.points.compactMap { at -> MapEntry? in
                let key = String(format: "%.4f,%.4f", at.latitude, at.longitude)
                guard seen.insert(key).inserted else { return nil }
                return MapEntry(stamp: day.stamp, date: day.date, at: at,
                                cover: cover?.0, video: cover?.1 ?? false, line: Self.line(of: day))
            }
        }
    }

    /// Чем день назван в списке записей: заголовок, начало записи, первое
    /// дело — без точек и ссылок.
    private static func line(of day: Archive.Day) -> String {
        let title = Geo.stripped(day.title).trimmingCharacters(in: .whitespaces)
        if !title.isEmpty { return title }
        if let first = day.preview.split(separator: "\n").first {
            return Geo.stripped(String(first)).trimmingCharacters(in: .whitespaces)
        }
        return day.tasks.first(where: { $0.isTask }).map { Geo.stripped($0.text) } ?? ""
    }

    /// Долгое нажатие ставит свою точку — только в «Моих местах»: на карте
    /// записей своих мест не видно, и новая булавка там сбивала бы.
    private func longPress(_ at: CLLocationCoordinate2D) {
        guard shell.mapEntries else { return pick(at) }
        shell.say(T("Свои точки ставятся в «Моих местах» — переключатель справа сверху.",
                    "You add your own places in “My places” — the switch at the top right."))
    }

    /// Одна запись — сразу её день; несколько — список (P451).
    private func openEntries(_ found: [MapEntry]) {
        var seen = Set<String>()
        let unique = found.sorted { $0.stamp > $1.stamp }.filter { seen.insert($0.stamp).inserted }
        if unique.count == 1, let one = unique.first {
            openDay(one.date)
        } else if !unique.isEmpty {
            entryList = MapEntryGroup(entries: unique)
        }
    }

    // MARK: - Справа сверху

    private var side: some View {
        VStack(spacing: 8) {
            // Переключатель: два значка в одной капсуле, выбранный — залит.
            VStack(spacing: 0) {
                sideMode(entries: false, icon: "mappin.and.ellipse",
                         label: T("Мои места", "My places"))
                Rectangle().fill(Look.inkFaint.opacity(0.4)).frame(width: 26, height: 0.8)
                sideMode(entries: true, icon: "photo.on.rectangle.angled",
                         label: T("Записи на карте", "Entries on the map"))
            }
            .background(Capsule().fill(Look.chrome.opacity(0.82)))
            .overlay(Capsule().strokeBorder(Look.inkFaint.opacity(0.4), lineWidth: 0.8))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.18), radius: 3, x: 1.5, y: 1.5)

            Button {
                Feel.light()
                shell.mapSatellite.toggle()
            } label: {
                Image(systemName: shell.mapSatellite ? "map" : "globe.europe.africa.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Look.accent)
                    .frame(width: MapSide.button, height: MapSide.button)
                    .background(Circle().fill(Look.chrome.opacity(0.82)))
                    .overlay(Circle().strokeBorder(Look.inkFaint.opacity(0.4), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.18), radius: 3, x: 1.5, y: 1.5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(shell.mapSatellite ? T("Показать схему", "Show the map")
                                                   : T("Показать спутник", "Show satellite"))

            // Все места — кнопкой на карте (P632; прежде в меню уголка).
            Menu {
                Button { shell.mapShowAll += 1 } label: {
                    Label(T("Показать все мои места", "Show all my places"), systemImage: "map")
                }
                Button { shell.mapList = true } label: {
                    Label(T("Все места списком", "All places as a list"), systemImage: "list.bullet")
                }
            } label: {
                Image(systemName: "list.bullet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Look.accent)
                    .frame(width: MapSide.button, height: MapSide.button)
                    .background(Circle().fill(Look.chrome.opacity(0.82)))
                    .overlay(Circle().strokeBorder(Look.inkFaint.opacity(0.4), lineWidth: 0.8))
                    .shadow(color: .black.opacity(0.18), radius: 3, x: 1.5, y: 1.5)
            }
            .accessibilityLabel(T("Все места", "All places"))
        }
        .padding(.trailing, 22)
        .padding(.top, MapSide.top)
    }

    private func sideMode(entries on: Bool, icon: String, label: String) -> some View {
        let chosen = shell.mapEntries == on
        return Button {
            guard !chosen else { return }
            Feel.light()
            if on {
                // Со своих мест на записи — выбранная точка и её плашка
                // уходят: на карте записей их нет.
                withAnimation { panel = nil }
                selected = nil
            }
            shell.mapEntries = on
            if on, archive.withPoints.isEmpty {
                shell.say(T("На карте пока нет записей: поставьте точку в тексте дня — и день появится здесь.",
                            "No entries on the map yet: add a place to a day's text and the day will appear here."))
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(chosen ? Color.white : Look.accent)
                .frame(width: MapSide.button, height: MapSide.segment)
                .background(chosen ? Look.accent : Color.clear)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    // MARK: - Кнопки внизу

    /// Внизу — только лупа справа (P804: «в навигатор» и «сохранить» —
    /// на плашке точки, «скопировать» — кнопка координат на ней). Отступ от
    /// клавиатуры считается по тому, где низ карты на экране сейчас (P506).
    private var bar: some View {
        GeometryReader { g in
            barRow
                .padding(.bottom, ownKeyboard
                         ? max(6, g.frame(in: .global).maxY - (UIScreen.main.bounds.height - keyboard))
                         : 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }

    /// Клавиатура — своя, карты: открыт раздел «Карта» и пишут название
    /// точки или ищут (P622). Чужая — с дневника, из которого коснулись
    /// места в записи, — кнопки не поднимает: прежде они оставались
    /// посреди карты (снимок автора 25.10).
    private var ownKeyboard: Bool {
        keyboard > 0 && shell.screen == .map && (panel == .naming || searching)
    }

    /// Ищут — на месте кнопок строка поиска, над клавиатурой (P803).
    @ViewBuilder private var barRow: some View {
        if searching {
            MapSearch(open: $searching, places: places,
                      region: { seen.region }, pick: found)
                .padding(.horizontal, 8)
        } else {
            buttons
        }
    }

    private var buttons: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { searching = true }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Look.ink)
                .frame(width: 52, height: 52)
                .background(Circle()
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.16), radius: 4, x: 2, y: 2))
                .overlay(Circle().strokeBorder(Look.inkFaint.opacity(0.7), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(T("Поиск на карте", "Search the map"))
        // Правее — полоска возврата к «Дневнику» (P805).
        .padding(.trailing, 22)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - Действия

    /// Карту открыли: свои места — заново (их могли поменять), а в первый
    /// раз ещё и туда, где человек сейчас.
    private func opened() {
        // Карта собирается заранее и слышит клавиатуру и тогда, когда её не
        // видно (P581): ушедшая клавиатура другого экрана не должна держать
        // кнопки посреди карты (P622, снимок автора). Раздел открывают —
        // своей клавиатуры у карты в этот миг нет.
        keyboard = 0
        // Места — сразу прочитанные в прошлый раз, свежие — следом, из
        // папки в стороне от экрана (P811): чтение на главном потоке
        // держало открытие карты до секунды.
        places = Places.known
        Places.loadSoon(vault) { places = $0 }
        if begun {
            if let point = shell.mapFocus { show(point) }
            return
        }
        begun = true
        begin()
    }

    /// Открыть карту: на точке из текста, на месте дня, иначе — где
    /// человек сейчас. Разрешение на место просится здесь, по его жесту.
    private func begin() {
        // Опись проверяет само нажатие на «Карту» (P579) — второй раз незачем.
        if let point = shell.mapFocus {
            show(point)
        } else if Vault.isPreview {
            // Снимок карты (P534): все свои места разом, без вопроса о месте.
            showAll()
        } else {
            // Где человек сейчас (P281, P294).
            Locator.shared.current { location in
                guard let at = location?.coordinate else { return }
                focus = MapFocus(center: at, meters: 2000)
            }
        }
    }

    /// Точка из плана или дневника: карта на ней, и сразу плашка — название,
    /// что там было, координаты (P213, P352).
    private func show(_ point: GeoPoint) {
        shell.mapFocus = nil
        let known = places.first { near($0.coordinate, point.at) }
        selected = known ?? Place(name: point.title, coordinate: point.at)
        panel = .naming
        focus = MapFocus(center: point.at, meters: 1500)
    }

    /// Нашли в поиске: своё место — его плашка; чужое место или
    /// координаты — булавка, с которой работают кнопки внизу (P251).
    private func found(_ title: String, _ at: CLLocationCoordinate2D) {
        hideKeyboard()
        searching = false
        me = nil
        focus = MapFocus(center: at, meters: 1200)
        if let own = places.first(where: { near($0.coordinate, at) }) {
            choose(own)
        } else if title.isEmpty {
            // Координаты без названия — предложить назвать сразу, тем же
            // способом, что и после долгого нажатия (P330).
            selected = Place(name: "", coordinate: at)
            withAnimation { panel = .naming }
        } else {
            selected = Place(name: title, coordinate: at)
            panel = nil
        }
    }

    /// Отдалить карту так, чтобы все свои места были видны разом.
    private func showAll() {
        guard !places.isEmpty else { return shell.say(T("Своих мест на карте пока нет.", "You have no places on the map yet.")) }
        let lats = places.map(\.latitude), lons = places.map(\.longitude)
        guard let s = lats.min(), let n = lats.max(), let w = lons.min(), let e = lons.max() else { return }
        let center = CLLocationCoordinate2D(latitude: (s + n) / 2, longitude: (w + e) / 2)
        let tall = (n - s) * 111_000
        let wide = (e - w) * 111_000 * cos(center.latitude * .pi / 180)
        focus = MapFocus(center: center, meters: max(tall, wide) * 1.5 + 1500)
    }

    private func near(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
        abs(a.latitude - b.latitude) < 0.00002 && abs(a.longitude - b.longitude) < 0.00002
    }

    /// Долгое нажатие: булавка на месте пальца и панель «Точка» сверху.
    private func pick(_ at: CLLocationCoordinate2D) {
        picked = Date()
        me = nil
        selected = Place(name: "", coordinate: at)
        withAnimation { panel = .naming }
    }

    /// Нажали на своё место: оно выбрано, сверху — сразу его плашка (P803:
    /// прежде сперва облачко и в нём «Изменить»).
    private func choose(_ place: Place) {
        hideKeyboard()
        me = nil
        selected = place
        withAnimation(.easeOut(duration: 0.15)) { panel = .naming }
    }

    /// Касание по пустому месту карты: плашка уходит, клавиатура опускается,
    /// выбор снят (P228).
    private func tapEmpty() {
        // Палец, поставивший точку, отпускают уже после неё — это не
        // касание по пустому месту (P235).
        guard Date().timeIntervalSince(picked) > 0.8 else { return }
        guard selected != nil || panel != nil else { return }
        hideKeyboard()
        me = nil
        selected = nil
        withAnimation { panel = nil }
    }

    private func cancel() {
        hideKeyboard()
        me = nil
        // Отмена у нового места убирает булавку; у записанного — только
        // закрывает правку.
        if selected?.file == nil { selected = nil }
        withAnimation { panel = nil }
    }

    /// «Готово»: точка ложится в папку «Места» и остаётся на карте. Не
    /// назвали — в файле названием остаются координаты (P228), на карте —
    /// один значок (P404).
    private func name(_ given: Place) {
        hideKeyboard()
        withAnimation { panel = nil }
        // Записанное место не меняли — файл не трогать.
        if given.file != nil && given == selected { return }
        var place = given
        let unnamed = place.name.trimmingCharacters(in: .whitespaces).isEmpty
        if unnamed { place.name = Geo.text(place.coordinate) }
        // Сохраняется и совсем пустая точка — белый кружок без названия
        // (P404; прежде такая не сохранялась и пропадала с карты, P284).
        guard let stored = Places.save(place, in: vault) else {
            selected = place
            return shell.say(T("Место не записалось. Проверьте папку в настройках.", "The place was not saved. Check the folder in Settings."))
        }
        places.removeAll { $0.id == place.id || ($0.file != nil && $0.file == place.file) }
        places.append(stored)
        selected = stored
    }

    private func remove() {
        guard let place = selected else { return }
        if place.file != nil { Places.delete(place, in: vault) }
        places.removeAll { $0.id == place.id }
        selected = nil
        withAnimation { panel = nil }
    }

    /// Касание по синей точке «я здесь» — плашка с её координатами (P804),
    /// как у любой точки: сохранить, назвать, в навигатор.
    private func here(_ location: CLLocation) {
        hideKeyboard()
        me = location
        selected = Place(name: "", coordinate: location.coordinate)
        withAnimation { panel = .naming }
    }

    /// «Сохранить в сегодня» (P804): точка всегда ложится в сегодняшний
    /// дневник, в ленту внизу страницы (P588). В прошлый день — скопировать
    /// координаты кнопкой на плашке и вставить (прежде кнопка писала в
    /// открытый день и его вкладку, P358, P587, P590).
    private func save(_ place: Place) {
        hideKeyboard()
        let mine = me.map { near($0.coordinate, place.coordinate) } ?? false
        let weather = mine ? me : nil
        // Названием остались координаты — в текст они ляжут один раз.
        let title = place.name == Geo.text(place.coordinate) ? "" : place.name
        store.go(to: DayStore.today())
        guard store.writePoint(GeoPoint(title: title, at: place.coordinate), to: .diary) else {
            return shell.say(store.closedReason)
        }
        if let weather { store.noteWeather(at: weather) }
        shell.say(T("Точка в ленте — ", "Place added to the strip — ") + T("сегодня", "today"))
        Feel.light()
        if place.file == nil { selected = nil }
        me = nil
        withAnimation { panel = nil }
        // Записали — к сегодняшнему дневнику, где точка теперь видна.
        shell.tab = .diary
        shell.screen = .today
    }

    private func openDay(_ date: Date) {
        store.go(to: date)
        shell.tab = .diary
        shell.screen = .today
    }
}

/// Вкладка у правого края карты (P855): маленькая, со скошенными краями и
/// стрелкой влево — заметна, но не мешает карте.
private struct SwipeTab: View {
    var body: some View {
        TabOutline()
            .fill(Look.chrome.opacity(0.85))
            .overlay(TabOutline().stroke(Look.inkSoft.opacity(0.5), lineWidth: 1))
            .overlay(
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Look.inkSoft)
                    .offset(x: 1))
            .frame(width: 16, height: 54)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Трапеция, прижатая к краю экрана: у края шире, внутрь скошена.
private struct TabOutline: Shape {
    func path(in r: CGRect) -> Path {
        let bevel: CGFloat = 8
        var p = Path()
        p.move(to: CGPoint(x: r.maxX + 1, y: r.minY))
        p.addLine(to: CGPoint(x: r.minX + 3, y: r.minY + bevel))
        p.addQuadCurve(to: CGPoint(x: r.minX, y: r.minY + bevel + 4),
                       control: CGPoint(x: r.minX, y: r.minY + bevel + 0.5))
        p.addLine(to: CGPoint(x: r.minX, y: r.maxY - bevel - 4))
        p.addQuadCurve(to: CGPoint(x: r.minX + 3, y: r.maxY - bevel),
                       control: CGPoint(x: r.minX, y: r.maxY - bevel - 0.5))
        p.addLine(to: CGPoint(x: r.maxX + 1, y: r.maxY))
        return p
    }
}
