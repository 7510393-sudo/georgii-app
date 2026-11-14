import SwiftUI
import UIKit
import MapKit

/// Плашка точки сверху карты — новой и записанной, одна (P803, вместо
/// облачка с «Изменить» перед ней): название, что здесь было, координаты
/// кнопкой, «Удалить», «Отмена», «Готово» (P213, P228). Полупрозрачная —
/// под ней видно булавку. Клавиатура открывается сразу только у новой.
struct PointPanel: View {

    @State var place: Place
    /// Клавиатура сразу — у новой булавки; записанное место и синюю точку
    /// «я здесь» сперва смотрят (P803, P804).
    let typeAtOnce: Bool
    let cancel: () -> Void
    let done: (Place) -> Void
    /// Удалить записанное место; у новой булавки — нет.
    let remove: (() -> Void)?
    let navigate: (Place) -> Void
    /// Сохранить в сегодняшний дневник (P804).
    let save: (Place) -> Void

    private enum Field { case name, text }
    @FocusState private var focused: Field?
    @State private var copied = false

    var body: some View {
        VStack(spacing: 8) {
            // Сверху название, ниже запись (P238; значков на выбор нет — P609).
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
            // Строки координат нет (P851, отменяет тихую строку P813):
            // копирует их «Копировать» внизу.
            // Все кнопки плашки — одного вида (P813): надпись в окантовке,
            // равной ширины в ряду. Вверху — куда деть точку (P804).
            HStack(spacing: 6) {
                key(T("В навигатор", "Directions")) { navigate(place) }
                key(T("В сегодня", "To today")) { save(place) }
                key(T("Поделиться", "Share")) {
                    MapActions.share(GeoPoint(title: place.name, at: place.coordinate))
                }
            }
            // Внизу — «Копировать» в одном ряду с «Отмена» и «Готово»;
            // «Удалить» — у записанной точки (P803), у новой булавки её
            // убирает «Отмена».
            HStack(spacing: 6) {
                if let remove {
                    key(T("Удалить", "Delete"), run: remove)
                }
                key(copied ? T("Скопировано", "Copied") : T("Копировать", "Copy")) {
                    PlaceActions.copy(place.coordinate)
                    Feel.light()
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                }
                .accessibilityLabel(T("Скопировать координаты ", "Copy coordinates ") + Geo.text(place.coordinate))
                key(T("Отмена", "Cancel"), run: cancel)
                key(T("Готово", "Done"), strong: true) { done(place) }
            }
        }
        .font(Look.sans(15))
        .padding(12)
        // Плашка полупрозрачная — сквозь неё видно карту, — с тонкой
        // кромкой, чтобы очертания были чёткими (P340).
        .background(Look.chrome.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Look.inkSoft.opacity(0.6), lineWidth: 1))
        .padding(.horizontal, 10)
        // Плашка — у самого верха (P851, вместо «под уголком» —
        // шестерёнка заходит на поле названия, так решил автор).
        .padding(.top, 4)
        .onAppear {
            // Клавиатура — только у новой точки: записанное место сперва
            // смотрят (P803).
            guard typeAtOnce else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { focused = .name }
        }
    }

    /// Кнопка плашки (P813): у всех один вид — надпись в окантовке, одна
    /// высота, равная ширина в ряду; «Готово» — окантовкой плотнее.
    private func key(_ name: String, strong: Bool = false, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Text(name)
                .font(Look.sans(14, weight: strong ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 24)
                .modifier(Outlined(strong: strong, narrow: true))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Look.accent)
    }
}

/// Действия с выбранной точкой — общие для полоски карты и её меню.
enum MapActions {
    static func navigate(_ place: Place) {
        PlaceActions.openInMaps(place.coordinate, name: place.name)
    }

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
        // Нет Google Карт — сразу Карты Apple; есть — короткий выбор (P633;
        // прежде выбор лежал в настройках, P220, P249).
        let appleMaps = {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
            item.name = name
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey:
                                                MKLaunchOptionsDirectionsModeDefault])
        }
        guard let probe = URL(string: "comgooglemaps://"), UIApplication.shared.canOpenURL(probe),
              let google = URL(string: String(format: "comgooglemaps://?daddr=%.6f,%.6f&directionsmode=driving",
                                              c.latitude, c.longitude))
        else { return appleMaps() }
        let sheet = UIAlertController(title: T("Построить маршрут в", "Directions in"),
                                      message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: T("Карты Apple", "Apple Maps"), style: .default) { _ in appleMaps() })
        sheet.addAction(UIAlertAction(title: "Google", style: .default) { _ in UIApplication.shared.open(google) })
        sheet.addAction(UIAlertAction(title: T("Отмена", "Cancel"), style: .cancel))
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return appleMaps() }
        while let shown = top.presentedViewController { top = shown }
        sheet.popoverPresentationController?.sourceView = top.view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 60,
                                                                 width: 1, height: 1)
        top.present(sheet, animated: true)
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
    /// Узкие поля по бокам — кнопки в ряд по четыре (P813).
    var narrow = false

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, narrow ? 4 : 12)
            .padding(.vertical, 6)
            .background(Look.planBg.opacity(0.85), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9)
                .strokeBorder(Look.accent.opacity(strong ? 0.9 : 0.6), lineWidth: strong ? 1.5 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}
