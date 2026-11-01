import SwiftUI
import UIKit

/// Пачка заготовок старой бумаги (P732, по слову автора: «заготовить листы
/// заранее и раскладывать готовые»). Лист рисуется один раз и в стороне от
/// экрана, хранится в памяти и в служебной папке приложения (Caches — не
/// папка с записями, её можно стереть без потерь) и дальше только
/// показывается. Пока листа нет, просящий получает `nil` и показывает просто
/// цвет прошлого; когда лист готов, `stock` растёт, и экраны перерисовываются
/// уже с ним. Так рисование бумаги не держит ни листание, ни клавиатуру.
final class PaperShop: ObservableObject {
    static let shared = PaperShop()

    /// Растёт, когда готов очередной лист: на него подписаны виды с бумагой.
    @Published private(set) var stock = 0

    /// Меняется, когда меняется рисунок бумаги, — старые заготовки не берутся.
    private static let version = "p732"

    private let queue = DispatchQueue(label: "graphomanus.paper", qos: .utility)
    private let lock = NSLock()
    private var waiting: Set<String> = []
    private let arts: NSCache<NSString, PageTexture.AgedArt> = {
        let cache = NSCache<NSString, PageTexture.AgedArt>()
        cache.countLimit = 400
        return cache
    }()
    private let pictures = NSCache<NSString, UIImage>()
    private var announce = false

    private lazy var folder: URL? = {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = caches.appendingPathComponent("OldPaper", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// Лист износа (края и маска рваного края) по ключу; `build` рисует его,
    /// если заготовки ещё нет ни в памяти, ни в служебной папке.
    func art(_ key: String, build: @escaping () -> PageTexture.AgedArt) -> PageTexture.AgedArt? {
        if let made = arts.object(forKey: key as NSString) { return made }
        order(key) { [weak self] in
            guard let self else { return }
            let art: PageTexture.AgedArt
            if let frame = self.load(key + "-f"), let cut = self.load(key + "-c") {
                art = PageTexture.AgedArt(frame: frame, cut: cut)
            } else {
                art = build()
                self.save(art.frame, key + "-f")
                self.save(art.cut, key + "-c")
            }
            self.arts.setObject(art, forKey: key as NSString)
        }
        return nil
    }

    /// Одна картинка (края страницы дня) по имени.
    func picture(_ name: String, build: @escaping () -> UIImage) -> UIImage? {
        if let made = pictures.object(forKey: name as NSString) { return made }
        order(name) { [weak self] in
            guard let self else { return }
            let image: UIImage
            if let saved = self.load(name) {
                image = saved
            } else {
                image = build()
                self.save(image, name)
            }
            self.pictures.setObject(image, forKey: name as NSString)
        }
        return nil
    }

    /// Ставит работу в очередь один раз на ключ; по готовности — сообщает
    /// экранам. Сообщения о многих готовых листах сливаются в одно.
    private func order(_ key: String, _ work: @escaping () -> Void) {
        lock.lock()
        let fresh = waiting.insert(key).inserted
        lock.unlock()
        guard fresh else { return }
        queue.async { [weak self] in
            work()
            guard let self else { return }
            self.lock.lock()
            self.waiting.remove(key)
            let first = !self.announce
            self.announce = true
            self.lock.unlock()
            guard first else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.lock.lock(); self.announce = false; self.lock.unlock()
                self.stock += 1
            }
        }
    }

    private func file(_ name: String) -> URL? {
        folder?.appendingPathComponent("\(Self.version)-\(name).png")
    }

    private func load(_ name: String) -> UIImage? {
        guard let url = file(name), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data, scale: 3)
    }

    private func save(_ image: UIImage, _ name: String) {
        guard let url = file(name), let data = image.pngData() else { return }
        try? data.write(to: url, options: .atomic)
    }
}
