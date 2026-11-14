import SwiftUI
import UIKit

/// Точка в тексте записи: кнопочка с названием и координатами, бледная,
/// как отметка времени (P213).
final class PointChip: NSTextAttachment {

    /// Точка своей строкой — квадрат размером со снимок (P559): булавка
    /// и подпись — название, а без него — «Место» и, если рядом своё место,
    /// сколько до него. Как голос и файл, все вложения — одного вида.
    init(tile point: GeoPoint, glowing: Bool = false) {
        super.init(data: nil, ofType: nil)
        let given = point.title.trimmingCharacters(in: .whitespaces)
        let name = given.isEmpty ? T("Место", "Place") : given
        let note = given.isEmpty ? Places.caption(for: point.at) : nil
        let picture = PointChip.square(name, note: note, glowing: glowing)
        image = picture
        bounds = CGRect(origin: CGPoint(x: 0, y: -4), size: picture.size)
        accessibilityLabel = T("Точка на карте: ", "Place on the map: ") + point.label
    }

    static func square(_ name: String, note: String?, glowing: Bool) -> UIImage {
        let size = DiaryEditor.photoSize
        let red = UIColor(Look.pin)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let box = CGRect(origin: .zero, size: size).insetBy(dx: 0.75, dy: 0.75)
            let shape = UIBezierPath(roundedRect: box, cornerRadius: 6)
            UIColor(Look.planBg).setFill()
            shape.fill()
            red.withAlphaComponent(0.10).setFill()
            shape.fill()
            (glowing ? UIColor(Look.glow) : red.withAlphaComponent(0.6)).setStroke()
            shape.lineWidth = glowing ? 2.2 : 1.2
            shape.stroke()
            if let pin = UIImage(systemName: "mappin.circle.fill",
                                 withConfiguration: UIImage.SymbolConfiguration(pointSize: size.width * 0.26,
                                                                                weight: .semibold))?
                .withTintColor(red, renderingMode: .alwaysOriginal) {
                pin.draw(at: CGPoint(x: (size.width - pin.size.width) / 2, y: size.height * 0.12))
            }
            let style = NSMutableParagraphStyle()
            style.alignment = .center
            style.lineBreakMode = .byTruncatingTail
            let title: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: max(11, size.width * 0.125), weight: .semibold),
                .foregroundColor: UIColor(Look.ink), .paragraphStyle: style,
            ]
            let small: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10.5),
                .foregroundColor: UIColor(Look.inkSoft), .paragraphStyle: style,
            ]
            let top = size.height * 0.52
            let lines: CGFloat = note == nil ? 2 : 1
            let titleFont = title[.font] as! UIFont
            (name as NSString).draw(
                with: CGRect(x: 5, y: top, width: size.width - 10, height: titleFont.lineHeight * lines),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: title, context: nil)
            if let note {
                (note as NSString).draw(
                    with: CGRect(x: 4, y: top + titleFont.lineHeight + 2, width: size.width - 8,
                                 height: UIFont.systemFont(ofSize: 10.5).lineHeight * 2),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    attributes: small, context: nil)
            }
        }
    }

    /// Булавка; у точки с названием — и название рядом (P284). Красная
    /// булавка на светло-красной подложке с красной кромкой — точку видно в
    /// тексте сразу (P358).
    static func mark(glowing: Bool, title: String = "") -> UIImage {
        let pad: CGFloat = glowing ? 3 : 0
        let red = UIColor(Look.pin)
        let font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
        let words: [NSAttributedString.Key: Any] = [.font: font,
                                                     .foregroundColor: UIColor(Look.ink)]
        // Точка без названия подписана «Место» (P380): одна булавка в
        // строке не читалась как запись.
        let given = title.trimmingCharacters(in: .whitespaces)
        let name = given.isEmpty ? T("Место", "Place") : given
        let wide = min(ceil((name as NSString).size(withAttributes: words).width), 180)
        let chip = CGSize(width: name.isEmpty ? 24 : 24 + wide + 8, height: 21)
        let size = CGSize(width: chip.width + pad * 2, height: chip.height + pad * 2)
        let pin = UIImage(systemName: "mappin.circle.fill",
                          withConfiguration: UIImage.SymbolConfiguration(pointSize: 13.5,
                                                                         weight: .semibold))?
            .withTintColor(red, renderingMode: .alwaysOriginal)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            let box = CGRect(x: pad, y: pad, width: chip.width, height: chip.height)
                .insetBy(dx: 0.6, dy: 0.6)
            let shape = UIBezierPath(roundedRect: box, cornerRadius: 7)
            if glowing {
                ctx.cgContext.setShadow(offset: .zero, blur: 4, color: UIColor(Look.glow).cgColor)
            }
            UIColor(Look.planBg).setFill()
            shape.fill()
            ctx.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
            red.withAlphaComponent(0.13).setFill()
            shape.fill()
            (glowing ? UIColor(Look.glow) : red.withAlphaComponent(0.75)).setStroke()
            shape.lineWidth = glowing ? 1.6 : 1.2
            shape.stroke()
            if let pin {
                let s = pin.size
                pin.draw(in: CGRect(x: pad + (24 - s.width) / 2,
                                    y: pad + (chip.height - s.height) / 2,
                                    width: s.width, height: s.height))
            }
            if !name.isEmpty {
                (name as NSString).draw(
                    with: CGRect(x: pad + 22, y: pad + (chip.height - font.lineHeight) / 2,
                                 width: wide, height: font.lineHeight),
                    options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                    attributes: words, context: nil)
            }
        }
    }

    required init?(coder: NSCoder) { nil }

}

/// Голос, видео или документ в тексте записи (P377) — кнопочка со значком
/// и именем файла, как точка. Касание открывает, долгое нажатие несёт.
final class FileChip: NSTextAttachment {

    init(link: String) {
        super.init(data: nil, ofType: nil)
        let picture = FileChip.draw(link)
        image = picture
        bounds = CGRect(origin: CGPoint(x: 0, y: -5), size: picture.size)
        accessibilityLabel = FileChip.name(link)
    }

    required init?(coder: NSCoder) { nil }

    static func name(_ link: String) -> String {
        ((link as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    static func draw(_ link: String) -> UIImage {
        let icon: String
        switch Diary.kind(of: link) {
        case .audio: icon = "waveform"
        case .video: icon = "film"
        default: icon = "doc"
        }
        let font = UIFont.systemFont(ofSize: 12.5, weight: .semibold)
        let words: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(Look.ink)]
        let name = Self.name(link)
        let wide = min(ceil((name as NSString).size(withAttributes: words).width), 180)
        let size = CGSize(width: 26 + wide + 9, height: 21)
        let tint = UIColor(Look.accent)
        let glyph = UIImage(systemName: icon,
                            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))?
            .withTintColor(tint, renderingMode: .alwaysOriginal)
        return UIGraphicsImageRenderer(size: size).image { _ in
            let shape = UIBezierPath(roundedRect: CGRect(origin: .zero, size: size).insetBy(dx: 0.6, dy: 0.6),
                                     cornerRadius: 7)
            UIColor(Look.planBg).setFill()
            shape.fill()
            tint.withAlphaComponent(0.1).setFill()
            shape.fill()
            tint.withAlphaComponent(0.7).setStroke()
            shape.lineWidth = 1.2
            shape.stroke()
            if let glyph {
                let s = glyph.size
                glyph.draw(in: CGRect(x: (26 - s.width) / 2, y: (size.height - s.height) / 2,
                                      width: s.width, height: s.height))
            }
            (name as NSString).draw(
                with: CGRect(x: 24, y: (size.height - font.lineHeight) / 2, width: wide, height: font.lineHeight),
                options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                attributes: words, context: nil)
        }
    }
}

/// Снимок в тексте записи.
///
/// Строку-ссылку для файла хранит пометка текста `photoKey`, а не сам снимок:
/// по ней поле возвращает в файл ту же строку, какая там и была (P204).
final class PhotoAttachment: NSTextAttachment {

    let url: URL?
    /// Картинку уже прочитали или читают — второй раз не надо.
    var loaded = false

    init(link: String, url: URL?) {
        self.url = url
        super.init(data: nil, ofType: nil)
        bounds = CGRect(origin: CGPoint(x: 0, y: -4), size: DiaryEditor.photoSize)
        // Голос, видео, документ — плитка со значком того же размера, что
        // снимок (P456). Читать с диска нечего.
        if Diary.kind(of: link) != .photo {
            image = PhotoAttachment.tile(link)
            loaded = true
            accessibilityLabel = FileChip.name(link)
            return
        }
        if let url, let cached = Photo.cache.object(forKey: PhotoAttachment.key(url)) {
            image = cached
            loaded = true
        } else {
            image = PhotoAttachment.empty
        }
    }

    required init?(coder: NSCoder) { nil }

    static func key(_ url: URL) -> NSString { ("в тексте:" + url.path) as NSString }

    /// Пустая клетка, пока картинка идёт с диска.
    static let empty: UIImage = UIGraphicsImageRenderer(size: DiaryEditor.photoSize).image { _ in
        let box = CGRect(origin: .zero, size: DiaryEditor.photoSize)
        UIColor(Look.chrome).setFill()
        UIBezierPath(roundedRect: box, cornerRadius: 6).fill()
    }

    /// Плитка голоса, видео или документа — как в полоске внизу: значок и
    /// подпись на бумаге с тонкой рамкой (P456).
    static func tile(_ link: String) -> UIImage {
        let size = DiaryEditor.photoSize
        let kind = Diary.kind(of: link)
        let icon = kind == .audio ? "waveform" : kind == .video ? "play.rectangle" : "doc.text"
        let label = kind == .audio ? T("голос", "voice") : kind == .video ? T("видео", "video")
            : ((link as NSString).pathExtension.lowercased().isEmpty
                ? T("файл", "file") : (link as NSString).pathExtension.lowercased())
        return UIGraphicsImageRenderer(size: size).image { _ in
            let box = CGRect(origin: .zero, size: size)
            let shape = UIBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5), cornerRadius: 6)
            UIColor(Look.chrome).setFill()
            shape.fill()
            UIColor(Look.rule).setStroke()
            shape.lineWidth = 1
            shape.stroke()
            let tint = UIColor(Look.inkSoft)
            if let symbol = UIImage(systemName: icon,
                                    withConfiguration: UIImage.SymbolConfiguration(pointSize: size.width * 0.22,
                                                                                   weight: .regular))?
                .withTintColor(tint, renderingMode: .alwaysOriginal) {
                symbol.draw(at: CGPoint(x: box.midX - symbol.size.width / 2,
                                        y: box.midY - symbol.size.height * 0.85))
            }
            let words: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: max(10, size.width * 0.1)),
                .foregroundColor: tint,
            ]
            let text = label as NSString
            let used = text.size(withAttributes: words)
            text.draw(at: CGPoint(x: box.midX - min(used.width, box.width - 8) / 2, y: box.midY + 6),
                      withAttributes: words)
        }
    }

    /// Снимок, обрезанный по клетке и со скруглёнными углами.
    static func frame(_ image: UIImage) -> UIImage {
        let size = DiaryEditor.photoSize
        return UIGraphicsImageRenderer(size: size).image { _ in
            let box = CGRect(origin: .zero, size: size)
            UIBezierPath(roundedRect: box, cornerRadius: 6).addClip()
            let scale = max(size.width / image.size.width, size.height / image.size.height)
            let w = image.size.width * scale, h = image.size.height * scale
            image.draw(in: CGRect(x: (size.width - w) / 2, y: (size.height - h) / 2,
                                  width: w, height: h))
        }
    }
}

extension DiaryEditor {
    /// Вложение, которое сейчас несут: в показе «куда ляжет» его место —
    /// пунктирная рамка (P593). Пусто — ничего не несут.
    static var awaiting: String?
}

/// Пунктирная рамка размером со снимок — сюда ляжет несомое (P593).
final class AwaitingSlot: NSTextAttachment {
    override init(data contentData: Data?, ofType uti: String?) {
        super.init(data: contentData, ofType: uti)
        let size = DiaryEditor.photoSize
        image = UIGraphicsImageRenderer(size: size).image { _ in
            let box = CGRect(origin: .zero, size: size).insetBy(dx: 1.5, dy: 1.5)
            let shape = UIBezierPath(roundedRect: box, cornerRadius: 6)
            UIColor(Look.glow).withAlphaComponent(0.08).setFill()
            shape.fill()
            shape.lineWidth = 2
            shape.setLineDash([7, 5], count: 2, phase: 0)
            UIColor(Look.glow).withAlphaComponent(0.85).setStroke()
            shape.stroke()
        }
        bounds = CGRect(origin: CGPoint(x: 0, y: -4), size: size)
    }

    convenience init() { self.init(data: nil, ofType: nil) }

    required init?(coder: NSCoder) { nil }
}
