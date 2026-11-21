import SwiftUI
import MapKit
import CoreLocation

/// Квадратик геоточки (P999, автор: «совершенно неинформативная карточка» —
/// булавка и «Сохранено…»): сверху — кусочек карты этого места с отметкой,
/// снизу — подпись. Подпись — своё название точки; нет его — что знают Карты
/// iPhone об этом месте (заведение, парк, улица, деревня, край); и этого
/// нет — координаты. Снимок карты и подпись — у приложения, в его кэше, не в
/// папке записей: файл дня от них не меняется. Для них координаты уходят в
/// Карты Apple — как и на экране «Карта».
enum PointTiles {
    /// Снимок или подпись пришли: квадратики этой точки перерисовываются.
    /// В `object` — ключ точки.
    static let ready = Notification.Name("PointTiles.ready")

    private static let memory = NSCache<NSString, UIImage>()
    private static var labels: [String: String] = [:]
    private static var asked: Set<String> = []
    private static var waiting: [CLLocationCoordinate2D] = []
    private static var naming = false
    private static let geocoder = CLGeocoder()

    /// Доля квадратика под картой.
    static let mapShare: CGFloat = 0.62

    /// В проверках карты и подписи нет: снимки сличаются попиксельно, а сеть
    /// там своя (P114).
    private static var on: Bool { !Vault.isUITest }

    private static let folder: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let url = caches.appendingPathComponent("point-tiles", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func key(_ at: CLLocationCoordinate2D) -> String {
        String(format: "%.5f_%.5f", at.latitude, at.longitude)
    }

    /// Что написать на квадратике: своё название; прежняя подпись «Сохранено
    /// 21 ноября» (P985) — как без названия; иначе — что знают Карты; нет —
    /// координаты.
    static func name(for point: GeoPoint) -> String {
        let given = point.name.trimmingCharacters(in: .whitespaces)
        if !given.isEmpty, !given.hasPrefix("Сохранено "), !given.hasPrefix("Saved ") { return given }
        if let found = label(point.at), !found.isEmpty { return found }
        return on ? Geo.text(point.at) : T("Место", "Place")
    }

    /// Снимок карты, если он уже есть: в памяти или в кэше приложения.
    static func map(_ at: CLLocationCoordinate2D, dark: Bool) -> UIImage? {
        guard on else { return nil }
        let k = key(at) + (dark ? "_dark" : "")
        if let image = memory.object(forKey: k as NSString) { return image }
        guard let url = folder?.appendingPathComponent(k + ".png"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data, scale: UIScreen.main.scale) else { return nil }
        memory.setObject(image, forKey: k as NSString)
        return image
    }

    private static func label(_ at: CLLocationCoordinate2D) -> String? {
        let k = key(at)
        if let known = labels[k] { return known }
        guard let url = folder?.appendingPathComponent(k + ".txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        labels[k] = text
        return text
    }

    /// Попросить снимок карты и подпись, если их ещё нет. Готово — `ready`.
    static func want(_ at: CLLocationCoordinate2D, dark: Bool) {
        guard on else { return }
        let k = key(at) + (dark ? "_dark" : "")
        guard !asked.contains(k) else { return }
        asked.insert(k)
        if map(at, dark: dark) == nil { snap(at, dark: dark) }
        if label(at) == nil {
            waiting.append(at)
            nameNext()
        }
    }

    /// Снимок карты вокруг точки — примерно 700 метров в поперечнике.
    private static func snap(_ at: CLLocationCoordinate2D, dark: Bool) {
        let side = DiaryEditor.photoSize.width
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: at, latitudinalMeters: 700, longitudinalMeters: 700)
        options.size = CGSize(width: side, height: ceil(side * mapShare))
        options.pointOfInterestFilter = .excludingAll
        options.traitCollection = UITraitCollection(userInterfaceStyle: dark ? .dark : .light)
        MKMapSnapshotter(options: options).start { shot, _ in
            guard let shot else { return }
            let image = shot.image
            let k = key(at) + (dark ? "_dark" : "")
            memory.setObject(image, forKey: k as NSString)
            if let url = folder?.appendingPathComponent(k + ".png"), let data = image.pngData() {
                try? data.write(to: url)
            }
            NotificationCenter.default.post(name: ready, object: key(at))
        }
    }

    /// Подписи — по одной: Карты Apple не любят частых вопросов.
    private static func nameNext() {
        guard !naming, !waiting.isEmpty else { return }
        naming = true
        let at = waiting.removeFirst()
        geocoder.reverseGeocodeLocation(CLLocation(latitude: at.latitude, longitude: at.longitude)) { marks, error in
            DispatchQueue.main.async {
                // Нет сети — спросить в другой раз; ничего не нашлось —
                // запомнить пустую подпись: будут координаты.
                if error == nil || marks?.isEmpty == false {
                    let text = marks?.first.flatMap(words) ?? ""
                    labels[key(at)] = text
                    if let url = folder?.appendingPathComponent(key(at) + ".txt") {
                        try? text.write(to: url, atomically: true, encoding: .utf8)
                    }
                    NotificationCenter.default.post(name: ready, object: key(at))
                } else {
                    asked = asked.filter { !$0.hasPrefix(key(at)) }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    naming = false
                    nameNext()
                }
            }
        }
    }

    /// Подпись по тому, что знают Карты: что здесь (заведение, парк, вода,
    /// улица) и где (район, город, деревня, край) — «Baker St, Marylebone».
    private static func words(_ mark: CLPlacemark) -> String? {
        let near = mark.subLocality ?? mark.locality ?? mark.subAdministrativeArea ?? mark.administrativeArea
        let spot = mark.areasOfInterest?.first ?? mark.inlandWater ?? mark.ocean ?? mark.thoroughfare
        switch (spot, near) {
        case let (spot?, near?) where spot != near: return spot + ", " + near
        case let (spot?, _): return spot
        case let (nil, near?): return near
        default: return mark.name
        }
    }
}
