import Foundation
import UIKit
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

// Нижний слой (P970): без экрана (P973). Картинки пока через UIKit — годится для iPad и Mac.

/// Фотографии дня: как их класть в папку и как показывать.
///
/// Фотография — обычный файл в папке «Фотографии», запись дня ссылается на
/// него строкой. Ничего не встраивается в текст: запись остаётся простым
/// текстом, а снимок — снимком, который открывается чем угодно (P200).
enum Photo {

    /// Снимок как файл — в том формате, в котором его снял iPhone (P365):
    /// HEIC остаётся HEIC, JPEG — JPEG. Прежде всё перегонялось в JPEG, и
    /// снимок вырастал на 30–50% без всякой пользы.
    ///
    /// Сжатие — по настройке: «без сжатия» — файл как есть, байт в байт;
    /// «среднее» — 2560 точек по длинной стороне; «высокое» — 1600.
    /// Сведения снимка — где и когда он сделан — переносятся вместе с ним:
    /// из них потом берётся геометка дня. Возвращает данные и расширение.
    static func stored(from data: Data) -> (data: Data, ext: String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        let type = (CGImageSourceGetType(source) as String?) ?? UTType.jpeg.identifier
        let isJPEG = UTType(type)?.conforms(to: .jpeg) ?? false
        // Среднее сжатие, одно на всех (P633): на экране не отличить от
        // оригинала, места в 5–6 раз меньше.
        let side: CGFloat = 2560
        // Уменьшенный снимок — тем же форматом. Снимок iPhone — HEIC;
        // снятый «как совместимый» — JPEG; прочее (снимки экрана в PNG) —
        // HEIC, родной формат iPhone. Не вышло записать HEIC — JPEG.
        if !isJPEG, let out = shrunk(source, side: side, as: .heic, quality: 0.7) {
            return (out, "heic")
        }
        let quality: CGFloat = side > 2000 ? 0.8 : 0.72
        guard let out = shrunk(source, side: side, as: .jpeg, quality: quality) else {
            return (data, UTType(type)?.preferredFilenameExtension.map(Photo.ext) ?? "jpg")
        }
        return (out, "jpg")
    }

    /// «jpeg» → «jpg»: привычнее и короче; остальное как есть.
    private static func ext(_ e: String) -> String { e.lowercased() == "jpeg" ? "jpg" : e.lowercased() }

    /// Снимок, уменьшенный по длинной стороне (меньший не растягивается),
    /// со сведениями оригинала. Поворот уже применён — в сведениях он
    /// сбрасывается, иначе снимок повернулся бы дважды.
    private static func shrunk(_ source: CGImageSource, side: CGFloat, as type: UTType,
                               quality: CGFloat) -> Data? {
        let options = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                       kCGImageSourceCreateThumbnailWithTransform: true,
                       kCGImageSourceThumbnailMaxPixelSize: side] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let out = NSMutableData()
        guard let target = CGImageDestinationCreateWithData(
                out, type.identifier as CFString, 1, nil)
        else { return nil }
        var props = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        props[kCGImagePropertyOrientation] = 1
        if var tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] {
            tiff[kCGImagePropertyTIFFOrientation] = 1
            props[kCGImagePropertyTIFFDictionary] = tiff
        }
        props[kCGImagePropertyPixelWidth] = nil
        props[kCGImagePropertyPixelHeight] = nil
        props[kCGImageDestinationLossyCompressionQuality] = quality
        CGImageDestinationAddImage(target, image, props as CFDictionary)
        guard CGImageDestinationFinalize(target) else { return nil }
        return out as Data
    }

    /// Уменьшенные снимки, уже прочитанные с диска. Страница, которую
    /// перелистнули туда и обратно, не читает их заново и не мигает.
    static let cache = NSCache<NSString, UIImage>()

    /// Сторона превью, по которой снимок читается с диска (P672): клетка
    /// ряда — около 86 точек, самое крупное превью (поиск, «А вот когда-то…»)
    /// — около 114. Прежде читалось по 280 точек — картинка 840×840, вдесятеро
    /// больше нужного, и при листании превью не успевали.
    static let thumbSide: CGFloat = 130

    /// Прочитать превью в память заранее (P669). Как — знает экран
    /// (`PhotoWarm`, рамка превью в тексте — его дело); нижний слой только
    /// просит (P973). Ставит приложение при запуске.
    static var warmer: (([(url: URL, plan: Bool)]) -> Void)?

    static func warm(_ items: [(url: URL, plan: Bool)]) { warmer?(items) }

    /// Прочитать снимок уменьшенным до `side` точек по большей стороне.
    ///
    /// Через системного посредника: снимок мог уйти в iCloud, и посредник
    /// дождётся, пока он придёт. Читать надо в стороне от экрана.
    static func load(_ url: URL, side: CGFloat) -> UIImage? {
        var image: UIImage?
        var trouble: NSError?
        NSFileCoordinator(filePresenter: nil)
            .coordinate(readingItemAt: url, options: [], error: &trouble) { real in
                guard let source = CGImageSourceCreateWithURL(real as CFURL, nil) else { return }
                let options = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: side * 3,
                    // Раскрыть картинку сразу здесь, в стороне, а не при
                    // первом показе на экране (P672).
                    kCGImageSourceShouldCacheImmediately: true,
                ] as CFDictionary
                if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options) {
                    image = UIImage(cgImage: cg)
                }
            }
        return image
    }

    /// Первый кадр видео, уменьшенный до `side` точек (P214).
    static func poster(_ url: URL, side: CGFloat) async -> UIImage? {
        guard let ready = await Task.detached(operation: { Attachment.fetch(url) }).value
        else { return nil }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: ready))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: side * 3, height: side * 3)
        guard let frame = try? await generator.image(at: .zero).image else { return nil }
        return UIImage(cgImage: frame)
    }

    /// Снимок для показа: туман над полем. Нужен только снимкам экрана.
    static func sample() -> Data {
        let size = CGSize(width: 1200, height: 900)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            let colors = [UIColor(red: 0.80, green: 0.83, blue: 0.84, alpha: 1).cgColor,
                          UIColor(red: 0.47, green: 0.55, blue: 0.50, alpha: 1).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors as CFArray, locations: [0, 1]) {
                ctx.cgContext.drawLinearGradient(gradient, start: .zero,
                                                 end: CGPoint(x: 0, y: size.height),
                                                 options: [])
            }
            UIColor(white: 0.25, alpha: 0.55).setFill()
            for i in 0..<9 {
                let x = CGFloat(i) * 140 + 30
                ctx.cgContext.fillEllipse(in: CGRect(x: x, y: 560, width: 90, height: 180))
            }
        }
        return image.jpegData(compressionQuality: 0.8) ?? Data()
    }
}

/// Снимки, снятые камерой из приложения (P428): их, в отличие от взятых из
/// «Фото», есть смысл сохранить на устройство — в «Фото» их ещё нет.
/// Помнит телефон, по имени файла.
enum CameraShots {
    private static let key = "photos.camera"

    static func mark(_ link: String) {
        var all = UserDefaults.standard.stringArray(forKey: key) ?? []
        all.append((link as NSString).lastPathComponent)
        UserDefaults.standard.set(Array(all.suffix(2000)), forKey: key)
    }

    static func taken(_ url: URL) -> Bool {
        (UserDefaults.standard.stringArray(forKey: key) ?? []).contains(url.lastPathComponent)
    }
}

/// Картинки пробного архива (P589): дюжина разных снимков размером с
/// обычный снимок iPhone после сжатия приложения — с полосами и пятнами,
/// чтобы сжатие не сводило их к нескольким байтам.
enum SeedPictures {
    /// Настоящие фото автора для снимков App Store (P1086): папка на машине
    /// CI, путь — в переменной окружения; симулятор читает её напрямую. В
    /// приложение фото не входят; в руках человека переменной нет.
    static func real() -> [Data] {
        guard Vault.isPreview,
              let path = ProcessInfo.processInfo.environment["CHRONOTHECA_PHOTOS"],
              let names = try? FileManager.default.contentsOfDirectory(atPath: path)
        else { return [] }
        return names.filter { $0.hasSuffix(".jpg") }.sorted().compactMap {
            try? Data(contentsOf: URL(fileURLWithPath: path).appendingPathComponent($0))
        }
    }

    static func make() -> [Data] {
        let size = CGSize(width: 1200, height: 900)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return (0..<12).compactMap { i -> Data? in
            let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
                let hue = CGFloat(i) / 12
                UIColor(hue: hue, saturation: 0.35, brightness: 0.85, alpha: 1).setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                var seed = UInt64(i + 1) &* 6_364_136_223_846_793_005
                func next() -> CGFloat {
                    seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
                }
                for _ in 0..<900 {
                    UIColor(hue: hue + next() * 0.2, saturation: 0.2 + next() * 0.6,
                            brightness: 0.3 + next() * 0.7, alpha: 0.6).setFill()
                    let r = CGRect(x: next() * size.width, y: next() * size.height,
                                   width: 8 + next() * 90, height: 8 + next() * 90)
                    ctx.cgContext.fillEllipse(in: r)
                }
            }
            return image.jpegData(compressionQuality: 0.7)
        }
    }
}
