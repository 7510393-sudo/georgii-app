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
    /// Что открыто сверху: панель названия или облачко места.
    @State private var panel: Panel?
    /// Плашка названия только что открылась, клавиатура ещё не поднялась:
    /// кнопки внизу ждут, а потом мягко становятся живыми (P509).
    @State private var settling = false
    @State private var focus: MapFocus?
    /// Карту уже открывали — место спрашивали (P581).
    @State private var begun = false
    @State private var locating = false
    @State private var asking = false
    @State private var choosingTab = false
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

    enum Panel { case naming, cloud }

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
                      onSelected: { withAnimation { panel = .cloud } },
                      onTapEmpty: tapEmpty,
                      onRegion: { seen.region = $0 })
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
                PointPanel(place: selected, cancel: cancel, done: name)
                    .id(selected.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else if let selected, panel == .cloud {
                PlaceCloud(place: selected, edit: { withAnimation { panel = .naming } })
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            // Крестика больше нет: карта — раздел внизу, уходят с неё
            // другим разделом, как с календаря и поиска (P239).
            // Поиск — в одной строке с шестерёнкой и тремя точками, между
            // уголками (P283): плашки новой точки и облачка ложатся ниже и
            // лупу не закрывают.
            MapSearch(open: $searching, places: places,
                      region: { seen.region }, pick: found)
                .padding(.leading, Corner.size + 8)
                .padding(.trailing, Corner.size + 8)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.easeOut(duration: 0.15), value: panel)
        .overlay(alignment: .bottom) { bar }
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
        .confirmationDialog(T("Куда записать точку?", "Where to note the place?"), isPresented: $choosingTab,
                            titleVisibility: .visible) {
            Button(T("В план", "To the plan")) { remember(to: .plan) }
            Button(T("В дневник", "To the diary")) { remember(to: .diary) }
            Button(T("Отмена", "Cancel"), role: .cancel) { }
        }
        // Карта собрана заранее и ждёт на плашке (P581): о месте и о своих
        // местах — только когда её открыли, а не когда собрали.
        .onAppear { if shell.screen == .map { opened() } }
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
            .shadow(color: .black.opacity(0.18), radius: 3, y: 1.5)

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
                    .shadow(color: .black.opacity(0.18), radius: 3, y: 1.5)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(shell.mapSatellite ? T("Показать схему", "Show the map")
                                                   : T("Показать спутник", "Show satellite"))
        }
        .padding(.trailing, 12)
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

    /// Кнопки внизу — овальные, поверх карты, а не сплошной полосой: карту
    /// видно между ними (P228). Стоят на тех же местах, что кнопки полоски
    /// вложений: «Запомнить точку» — ровно там, где «геоточка» (P213).
    /// Корзина, «скопировать» и «в навигатор» бледнеют, пока точка не
    /// выбрана (P219).
    /// Кнопки внизу: отступ от клавиатуры считается по тому, где низ карты на
    /// экране сейчас, а не по замеру, снятому раньше (P506).
    private var bar: some View {
        GeometryReader { g in
            barRow
                .padding(.bottom, keyboard > 0
                         ? max(6, g.frame(in: .global).maxY - (UIScreen.main.bounds.height - keyboard))
                         : 6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        .onChange(of: panel) { _, now in
            guard now == .naming else { settling = false; return }
            settling = true
            // Клавиатуры может и не быть (внешняя): через миг ждать перестаём.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { settling = false }
        }
        .onChange(of: keyboard) { _, now in if now > 0 { settling = false } }
        .animation(.easeOut(duration: 0.3), value: settling)
    }

    private var barRow: some View {
        let point = selected != nil && !settling
        return HStack(spacing: 0) {
            Button {
                guard point else { return hint() }
                asking = true
            } label: {
                oval(MapFace(icon: "trash", name: T("удалить", "delete"), tint: Look.inkSoft), on: point)
            }
            Button {
                guard let selected else { return hint() }
                MapActions.navigate(selected)
            } label: {
                oval(MapFace(icon: "arrow.triangle.turn.up.right.diamond", name: T("в навигатор", "directions"),
                             tint: Look.accent), on: point)
            }
            Button(action: remember) {
                if locating {
                    oval(ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity), on: true)
                } else {
                    oval(MapFace(icon: "pin.fill", name: saveName, tint: Look.accent), on: true)
                }
            }
            .accessibilityHint(point ? T("Запишет выбранную точку", "Saves the chosen place") : T("Запишет, где вы сейчас", "Saves where you are now"))
            // Слева направо: корзина, в навигатор, записать, скопировать
            // (P425).
            Button {
                guard let selected else { return hint() }
                MapActions.copy(selected)
                shell.say(T("Скопировано: ", "Copied: ") + Geo.text(selected.coordinate))
            } label: {
                oval(MapFace(icon: "doc.on.doc", name: T("скопировать", "copy"), tint: Look.inkSoft), on: point)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 4)
        // Клавиатура сама не поднимает низ приложения (P113) — над ней
        // кнопки поднимает этот отступ, вплотную к её верху (P306, P340).
        // Отступ от клавиатуры — в `bar` (P506).
    }

    /// Точка не выбрана — кнопка не пропадает, а бледнеет и объясняет, чего
    /// ей не хватает (P235).
    private func hint() {
        shell.say(T("Сначала выберите точку: долгое нажатие на карту или касание по своему месту.",
                    "First choose a place: long press on the map or tap one of your places."))
    }

    /// Овал под кнопкой. Неактивная — бледнее, но видна целиком (P235).
    private func oval<C: View>(_ face: C, on: Bool) -> some View {
        face
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(Capsule()
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.16), radius: 4, y: 2))
            // Кромка — кнопки чётче на пёстрой карте (P283).
            .overlay(Capsule().strokeBorder(Look.inkFaint.opacity(0.7), lineWidth: 1))
            .opacity(on ? 1 : 0.55)
            .padding(.horizontal, 4)
    }

    // MARK: - Действия

    /// Карту открыли: свои места — заново (их могли поменять), а в первый
    /// раз ещё и туда, где человек сейчас.
    private func opened() {
        places = Places.all(in: vault)
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
        panel = .cloud
        focus = MapFocus(center: point.at, meters: 1500)
    }

    /// Нашли в поиске: своё место — его облачко; чужое место или
    /// координаты — булавка, с которой работают кнопки внизу (P251).
    private func found(_ title: String, _ at: CLLocationCoordinate2D) {
        hideKeyboard()
        searching = false
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
        selected = Place(name: "", coordinate: at)
        withAnimation { panel = .naming }
    }

    /// Нажали на своё место: оно выбрано, сверху — облачко о нём.
    private func choose(_ place: Place) {
        hideKeyboard()
        selected = place
        withAnimation(.easeOut(duration: 0.15)) { panel = .cloud }
    }

    /// Касание по пустому месту карты: панель и облачко уходят, клавиатура
    /// опускается. Новая булавка без названия уходит вместе с панелью (P228).
    private func tapEmpty() {
        // Палец, поставивший точку, отпускают уже после неё — это не
        // касание по пустому месту (P235).
        guard Date().timeIntervalSince(picked) > 0.8 else { return }
        guard selected != nil || panel != nil else { return }
        hideKeyboard()
        if selected?.file == nil { selected = nil }
        if panel == .cloud { selected = nil }
        withAnimation { panel = nil }
    }

    private func cancel() {
        hideKeyboard()
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

    /// «Запомнить точку»: выбранную — или ту, где телефон сейчас. Пишется
    /// туда, откуда открыли карту: в план или в дневник на место курсора.
    private func remember() {
        hideKeyboard()
        // Куда — написано на самой кнопке (P358): в ту вкладку, что была
        // открыта последней. Спрашивать незачем. В день, который ещё не
        // наступил, дневника нет — точка встаёт в его план (P587): прежде
        // она не ложилась никуда.
        let tab: Shell.Tab = store.canEdit(shell.tab) || !store.canEditPlan ? shell.tab : .plan
        remember(to: tab)
    }

    /// Название кнопки — куда ляжет точка (P358).
    /// Одно слово на любую вкладку (P425): «записать». С P559 — «в этот
    /// день»: точка ложится в запись дня, а не в «Мои места».
    private var saveName: String { T("в этот день", "to this day") }

    private func remember(to tab: Shell.Tab) {
        guard store.canEdit(tab) else { return shell.say(store.closedReason) }
        if let place = selected {
            // Названием остались координаты — в текст они ляжут один раз.
            let title = place.name == Geo.text(place.coordinate) ? "" : place.name
            return write(GeoPoint(title: title, at: place.coordinate), to: tab)
        }
        locating = true
        Locator.shared.current { location in
            locating = false
            guard let at = location?.coordinate else {
                return shell.say(T("Не удалось узнать, где вы. Проверьте, разрешено ли приложению место.",
                                 "Could not find where you are. Check that the app may use Location."))
            }
            write(GeoPoint(title: "", at: at), to: tab, here: true)
            if let location { store.noteWeather(at: location) }
        }
    }

    private func write(_ point: GeoPoint, to tab: Shell.Tab, here: Bool = false) {
        // В ленту внизу страницы, как всё новое (P588).
        guard store.writePoint(point, to: tab, here: here) else {
            return shell.say(store.closedReason)
        }
        // В какой день — словами (P587): точка ложится в день, открытый в
        // «Дне», и человек видит, в какой.
        let day = store.isToday ? T("сегодня", "today") : Ru.shortDate(store.date)
        shell.say(T("Точка в ленте — ", "Place added to the strip — ") + day)
        Feel.light()
        // Записали — назад к странице дня, на ту вкладку, где точка теперь
        // видна.
        shell.tab = tab
        shell.screen = .today
    }

    private func openDay(_ date: Date) {
        store.go(to: date)
        shell.tab = .diary
        shell.screen = .today
    }
}

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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if open { field } else { button }
            if open && (!results.isEmpty || looking || nothing) { list }
        }
        .animation(.easeOut(duration: 0.2), value: open)
    }

    private var button: some View {
        Button {
            open = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { typing = true }
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Look.ink)
                .frame(width: 42, height: 42)
                .background(.ultraThinMaterial, in: Circle())
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .accessibilityLabel(T("Поиск на карте", "Search the map"))
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
        .frame(height: 42)
        .background(.regularMaterial, in: Capsule())
        .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        .transition(.scale(scale: 0.2, anchor: .leading).combined(with: .opacity))
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
                            if let mark = found.mark {
                                GlyphIcon(name: mark, size: 12)
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
                        Group {
                            GlyphIcon(name: place.mark, size: 14)
                        }
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

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = false
        map.showsScale = true
        // Знак «Карты» и ссылка «Правовые» Apple ставит по полям карты —
        // поднимаем нижнее поле над своими кнопками внизу (52 точки и отступ
        // 6), иначе кнопки ложатся на надпись, а её Apple велит оставлять
        // видимой (P533).
        map.layoutMargins = UIEdgeInsets(top: 8, left: 8, bottom: 64, right: 8)
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
                view.image = PlaceLabel.draw(shown, mark: mark.place.mark, solid: satellite,
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
        /// Что сейчас стоит на карте — чтобы не переставлять метки зря.
        private var drawn = ""

        init(_ parent: NativeMap) { self.parent = parent }

        func sync(_ map: MKMapView) {
            let draft = parent.selected.flatMap { $0.file == nil ? $0 : nil }
            var key = parent.places.map { "\($0.id)\($0.name)\($0.mark)\($0.latitude)\($0.longitude)" }
                .joined(separator: "|")
            key += parent.days.map { "\($0.stamp)\($0.today)" }.joined(separator: "|")
            key += "#" + parent.entries.map { "\($0.stamp)\($0.at.latitude)\($0.at.longitude)\($0.cover?.path ?? "")" }
                .joined(separator: "|")
            key += draft.map { "\($0.name)\($0.latitude)\($0.longitude)" } ?? "-"
            // Выбранное место рисуется иначе (P428) — сменился выбор, метки
            // ставятся заново.
            key += "|" + (parent.selected?.file ?? "")
            guard key != drawn else { return }
            drawn = key
            map.removeAnnotations(map.annotations.filter { !($0 is MKUserLocation) })
            map.addAnnotations(parent.days.map { DayMark($0) })
            map.addAnnotations(parent.places.map { PlaceMark($0) })
            map.addAnnotations(parent.entries.map { EntryMark($0) })
            if let draft { map.addAnnotation(DraftMark(draft)) }
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
                let picture = PlaceLabel.draw(shown, mark: mark.place.mark,
                                              solid: map.mapType != .standard, chosen: chosen)
                view.image = picture
                // Метка стоит на точке значком; у «невидимой» — плашкой
                // посередине (P409).
                view.centerOffset = mark.place.mark == Glyph.invisible ? .zero
                    : CGPoint(x: 0, y: picture.size.height / 2
                              - PlaceLabel.dot * PlaceLabel.scale(mark: mark.place.mark, chosen: chosen) / 2)
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

        func mapView(_ map: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegion(map.region)
        }

        func mapView(_ map: MKMapView, didSelect view: MKAnnotationView) {
            guard let annotation = view.annotation else { return }
            switch annotation {
            // Свои места и дни отвечают на своё касание сразу (P243).
            case is PlaceMark, is DayMark, is EntryMark, is MKClusterAnnotation: break
            case is DraftMark: parent.onSelected()
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
    /// `chosen` — место выбрано (P428): плашка и значок непрозрачные,
    /// значок в чёрном круге, у голых — чёрная кайма по контуру.
    /// «Невидимый», стрелка и пиратский флаг выбором не меняются.
    /// Выбранное место: значок в полтора раза крупнее (P439). Без контура и
    /// чёрного круга. «Невидимый», стрелка и пиратский флаг не меняются.
    static func scale(mark: String, chosen: Bool) -> CGFloat {
        chosen && ![Glyph.invisible, "стрелка", "пираты"].contains(mark) ? 1.5 : 1
    }

    static func draw(_ name: String, mark: String, solid: Bool = false, chosen: Bool = false) -> UIImage {
        let grow = scale(mark: mark, chosen: chosen)
        let chosen = grow > 1
        let big = dot * grow
        let font = UIFont.systemFont(ofSize: 12, weight: .semibold)
        let words: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(Look.ink)]
        // «Невидимый» (P409): только плашка; без названия — «Место».
        let invisible = mark == Glyph.invisible
        let given = name.trimmingCharacters(in: .whitespaces)
        let text = ((invisible && given.isEmpty ? T("Место", "Place") : name) as NSString)
        let named = invisible || !given.isEmpty
        let wide = named ? min(text.size(withAttributes: words).width, 150) : 0
        // Поля вокруг букв — 3 по бокам и 1 сверху и снизу (P474): шрифт тот же, плашка
        // теснее (было 6 и 3).
        let plate = named ? CGSize(width: wide + 6, height: font.lineHeight + 2) : .zero
        let above: CGFloat = invisible ? 0 : big + 4
        let size = CGSize(width: max(invisible ? 0 : big, plate.width) + 4,
                          height: named ? above + plate.height + 3 : big + 4)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let mid = size.width / 2
            if !invisible {
                let circle = CGRect(x: mid - dot / 2, y: 1 + (big - dot) / 2, width: dot, height: dot)
                // Тот же рисунок, увеличенный вокруг своего центра.
                ctx.cgContext.saveGState()
                ctx.cgContext.translateBy(x: circle.midX, y: circle.midY)
                ctx.cgContext.scaleBy(x: grow, y: grow)
                ctx.cgContext.translateBy(x: -circle.midX, y: -circle.midY)
                GlyphArt.draw(mark, in: circle, ctx: ctx.cgContext)
                ctx.cgContext.restoreGState()
            }
            guard named else { return }
            let box = CGRect(x: mid - plate.width / 2, y: invisible ? 1 : above,
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

/// Панель новой точки сверху карты: название и что здесь было.
/// Полупрозрачная — под ней видно, куда встала булавка; клавиатура
/// открывается сразу. В поле названия бледно стоят координаты: не назвали —
/// они и останутся названием. «Отмена» — внизу слева, «Готово» — внизу
/// справа (P213, P228).
struct PointPanel: View {

    @State var place: Place
    let cancel: () -> Void
    let done: (Place) -> Void

    private enum Field { case name, text }
    @FocusState private var focused: Field?
    @State private var copied = false

    /// Четырнадцать значков — два ряда по семь (P404).
    private static let iconColumns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            // Сверху значки, ниже название, ещё ниже запись (P238).
            // Каким значком отметить точку (P234).
            LazyVGrid(columns: Self.iconColumns, spacing: 6) {
                ForEach(Glyph.all.indices, id: \.self) { i in
                    let glyph = Glyph.all[i]
                    Button {
                        place.mark = glyph.name
                    } label: {
                        // Каждый значок своего цвета, как на карте (P397);
                        // выбранный — в синем кольце, а не на тёмном
                        // кружке: на тёмном пропал бы чёрный человек.
                        // Рисунок — тот же, что на карте, с подложкой или
                        // без (P404).
                        GlyphIcon(name: glyph.name, size: 14)
                            .frame(width: 32, height: 32)
                            .overlay(Circle().strokeBorder(place.mark == glyph.name ? Look.accent : .clear,
                                                           lineWidth: 2.5))
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel(T("Значок: ", "Icon: ") + Glyph.shown(glyph.name))
                }
            }
            // Поля — плотные, чтобы текст читался; прозрачна сама плашка
            // вокруг них (P340).
            // В пустом поле — «Название», а не координаты: они внизу
            // плашки (P404).
            TextField(T("Название", "Name"), text: $place.name)
                .focused($focused, equals: .name)
                .submitLabel(.next)
                .onSubmit { focused = .text }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Look.planBg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Look.inkFaint.opacity(0.6), lineWidth: 1))
            // Не выше шести строк; длиннее — прокручивается внутри.
            TextField(T("Что здесь было", "What happened here"), text: $place.text, axis: .vertical)
                .focused($focused, equals: .text)
                .lineLimit(1...6)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Look.planBg, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Look.inkFaint.opacity(0.6), lineWidth: 1))
            HStack {
                // «Отмена» и «Готово» — в окантовке, как кнопки (P414).
                Button(action: cancel) { Text(T("Отмена", "Cancel")).modifier(Outlined()) }
                    .buttonStyle(.plain)
                    .foregroundStyle(Look.accent)
                Spacer(minLength: 6)
                // Координаты точки — касание кладёт их в буфер обмена
                // (P340).
                Button {
                    PlaceActions.copy(place.coordinate)
                    Feel.light()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Text(copied ? T("скопировано", "copied") : Geo.text(place.coordinate))
                        .font(Look.mono(12))
                        .foregroundStyle(Look.inkSoft)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(T("Скопировать координаты", "Copy coordinates"))
                Spacer(minLength: 6)
                Button { done(place) } label: {
                    Text(T("Готово", "Done")).fontWeight(.semibold).modifier(Outlined(strong: true))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Look.accent)
            }
            .font(Look.sans(15))
            .padding(.horizontal, 4)
        }
        .font(Look.sans(15))
        .padding(12)
        // Плашка полупрозрачная — сквозь неё видно карту, — с тонкой
        // кромкой, чтобы очертания были чёткими (P340).
        .background(Look.chrome.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Look.inkSoft.opacity(0.6), lineWidth: 1))
        .padding(.horizontal, 10)
        .padding(.top, Corner.size + 2)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = .name }
        }
    }
}

/// Облачко выбранной точки сверху карты: название и что о ней написано —
/// и больше ничего. Дорога, копия и корзина — кнопками внизу (P228).
/// Клавиатура не открывается: точку смотрят, а не правят.
struct PlaceCloud: View {
    let place: Place
    let edit: () -> Void

    @State private var copied = false

    var body: some View {
        // Без пустот (P428): название, под ним пояснение, последней строкой
        // — координаты с копированием и «Изменить» справа внизу.
        VStack(alignment: .leading, spacing: 3) {
            if !place.name.isEmpty {
                Text(place.name)
                    .font(Look.serif(17, weight: .semibold))
                    .foregroundStyle(Look.ink)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !place.text.isEmpty {
                // Не выше шести строк; длиннее — прокручивается пальцем.
                ViewThatFits(in: .vertical) {
                    words
                    ScrollView { words }.frame(height: 6 * 20)
                }
                .frame(maxHeight: 6 * 20)
            }
            // Координаты видны всегда: в плане и дневнике их нет, они здесь
            // (P352). Касание копирует; их же можно выделить пальцем.
            HStack(alignment: .firstTextBaseline) {
                coordinates
                Spacer(minLength: 8)
                Button(place.file == nil ? T("Назвать", "Name it") : T("Изменить", "Edit"), action: edit)
                    .font(Look.sans(14))
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        // Та же кромка, что у кнопок внизу (P283) — плашка чётче на пёстрой
        // карте (P307).
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Look.inkFaint.opacity(0.7), lineWidth: 1))
        .padding(.horizontal, 10)
        .padding(.top, Corner.size + 2)
    }

    private var coordinates: some View {
        Button {
            PlaceActions.copy(place.coordinate)
            Feel.light()
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
        } label: {
            HStack(spacing: 5) {
                Text(Geo.text(place.coordinate))
                    .font(Look.sans(14).monospacedDigit())
                    .foregroundStyle(Look.inkSoft)
                    .textSelection(.enabled)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(Look.accent)
                if copied {
                    Text(T("скопировано", "copied")).font(Look.sans(12)).foregroundStyle(Look.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(T("Координаты ", "Coordinates ") + Geo.text(place.coordinate) + T(", скопировать", ", copy"))
    }

    private var words: some View {
        Text(place.text)
            .font(Look.serif(15))
            .foregroundStyle(Look.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Лицо овальной кнопки карты: значок и подпись в одну-две строки —
/// подпись не вылезает за овал (P235).
struct MapFace: View {
    let icon: String
    let name: String
    var tint: Color = Look.inkSoft

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: icon).font(.system(size: 16))
            Text(name.uppercased())
                .font(Look.sans(8.5))
                .tracking(0.3)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
    }
}

/// Действия с выбранной точкой — общие для полоски карты и её меню.
enum MapActions {
    static func navigate(_ place: Place) {
        PlaceActions.openInMaps(place.coordinate, name: place.name)
    }

    static func navigate(_ point: GeoPoint) {
        PlaceActions.openInMaps(point.at, name: point.title)
    }

    static func copy(_ place: Place) { PlaceActions.copy(place.coordinate) }
    static func copy(_ point: GeoPoint) { PlaceActions.copy(point.at) }

    /// Поделиться точкой: название, координаты и ссылка на Карты — её
    /// откроет любой iPhone, а на других телефонах — браузер (P222).
    static func share(_ point: GeoPoint) {
        var words = point.title.isEmpty ? "" : point.title + "\n"
        words += Geo.text(point.at)
        var link = URLComponents(string: "https://maps.apple.com/")
        link?.queryItems = [
            URLQueryItem(name: "ll", value: String(format: "%.5f,%.5f",
                                                  point.at.latitude, point.at.longitude)),
            URLQueryItem(name: "q", value: point.title.isEmpty ? T("Точка", "Place") : point.title),
        ]
        var items: [Any] = [words]
        if let url = link?.url { items.append(url) }
        let sheet = UIActivityViewController(activityItems: items, applicationActivities: nil)
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let shown = top.presentedViewController { top = shown }
        sheet.popoverPresentationController?.sourceView = top.view
        top.present(sheet, animated: true)
    }
}

/// Что можно сделать с точкой: открыть в Картах, скопировать.
enum PlaceActions {

    /// Открыть в Картах Apple с дорогой до точки.
    static func openInMaps(_ c: CLLocationCoordinate2D, name: String) {
        // Куда вести — из настроек: Карты Apple или Google Карты (P220,
        // P249). Ссылка Google открывает их приложение, а без него — сайт.
        if UserDefaults.standard.string(forKey: Prefs.navigator) == "google",
           let url = URL(string: String(format: "https://www.google.com/maps/dir/?api=1&destination=%.6f,%.6f",
                                        c.latitude, c.longitude)) {
            UIApplication.shared.open(url)
            return
        }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
        item.name = name
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey:
                                            MKLaunchOptionsDirectionsModeDefault])
    }

    /// Скопировать точку словами «59.93863, 30.31413» — их понимает любой
    /// навигатор и любые карты.
    static func copy(_ c: CLLocationCoordinate2D) {
        UIPasteboard.general.string = Geo.text(c)
    }
}

/// Кнопка в окантовке (P414): тонкая рамка цвета кнопки на светлой
/// подложке; главная — рамка толще.
struct Outlined: ViewModifier {
    var strong = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Look.planBg.opacity(0.85), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Look.accent.opacity(strong ? 0.9 : 0.6), lineWidth: strong ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}
