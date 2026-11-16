import Foundation

// Нижний слой (P970): без экрана, только Foundation.

/// Можно ли править записи: проба не кончилась или приложение куплено.
///
/// Пишет `Purchase` (экран покупки), читает хранилище дня — через
/// настройку телефона, чтобы нижний слой не знал о покупках (P970; прежде
/// `Purchase.canWrite`). Пока не известно — можно.
enum WriteLock {
    static let key = "purchase.locked"

    static var open: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool != true
    }
}
