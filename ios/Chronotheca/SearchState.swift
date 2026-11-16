import SwiftUI

/// Строка поиска, где искать и что искать (P964, `docs/68` §2.2).
///
/// Прежде эти поля лежали в `Shell`, и каждая набранная буква пересчитывала
/// всё, что смотрит на оболочку, — и страницу «Дня», и нижнюю строку. Теперь
/// их смотрит одна картотека (`SearchView`). Живут не в самом поиске: их
/// меняет и меню поиска, и проверки движения. В файл ничего не пишется.
final class SearchState: ObservableObject {

    /// Где искать: везде, только в дневнике или только в плане.
    enum Scope { case all, diary, plan }

    /// Слово поиска.
    @Published var query = ""
    @Published var scope: Scope = .all

    /// Что искать: всё или только дни со снимками, видео, голосом,
    /// файлами, местами (P249).
    enum Find: String, CaseIterable { case all = "Всё", photo = "Снимки", video = "Видео",
                                          audio = "Голос", file = "Файлы", place = "Места"
        var title: String {
            switch self {
            case .all: return T("Всё", "Everything")
            case .photo: return T("Снимки", "Photos")
            case .video: return T("Видео", "Videos")
            case .audio: return T("Голос", "Voice")
            case .file: return T("Файлы", "Files")
            case .place: return T("Места", "Places")
            }
        }
    }
    @Published var find: Find = .all
}
