import SwiftUI

/// Что сейчас на карте (P932, `docs/68` §2.2): спутник или схема, свои места
/// или записи, просьбы к карте из нижней строки и из текста дня.
///
/// Прежде эти поля лежали в `Shell`, и на каждую их смену пересчитывалось
/// всё, что смотрит на оболочку, — и «День», и картотека. Теперь их смотрит
/// одна карта. В файл ничего не пишется, кроме двух выборов вида карты.
final class MapState: ObservableObject {

    /// Точка, на которой открыть карту: её нажали в тексте дня (P213).
    @Published var focus: GeoPoint?
    /// Карта снимком со спутника, а не схемой (P222). Выбор запоминается
    /// (P419): открыли карту снова — она такая, какой её оставили.
    @Published var satellite = UserDefaults.standard.bool(forKey: "map.satellite") {
        didSet { UserDefaults.standard.set(satellite, forKey: "map.satellite") }
    }
    /// Карта показывает записи — дни с точками, превью и числом, — а не
    /// свои места (P451). Выбор запоминается, как спутник.
    @Published var entries = UserDefaults.standard.bool(forKey: "map.entries") {
        didSet { UserDefaults.standard.set(entries, forKey: "map.entries") }
    }

    /// Просьбы к карте из её меню: показать все места, открыть список мест.
    @Published var showAll = 0
    @Published var list = false
    /// Второе нажатие на «Карту» — карта к тому месту, где человек сейчас
    /// (P577).
    @Published var home = 0
    /// Снимок плашки точки на карте (P813): растёт — карта открывает плашку.
    @Published var previewPoint = 0
}
