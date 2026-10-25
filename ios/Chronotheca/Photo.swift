import SwiftUI
import UIKit
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

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
        let side: CGFloat
        switch Prefs.squeezeKey {
        case "high":   side = 2560
        case "medium": side = 1600
        default:
            return (data, UTType(type)?.preferredFilenameExtension.map(Photo.ext) ?? "jpg")
        }
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

/// Уменьшенный снимок в клетке.
///
/// Клетка всегда одного размера, пока снимок читается, — место под него
/// уже отведено, и ничего не сдвигается, когда он приходит (P113).
struct PhotoThumb: View {

    let url: URL?
    /// Видео: вместо снимка — его первый кадр и знак «играть» (P214).
    var video = false
    @State private var image: UIImage?
    /// Чья картинка сейчас показана (P555): на том же месте ряда может
    /// оказаться другой снимок — тогда прежняя картинка не годится.
    @State private var shown: URL?

    init(url: URL?, video: Bool = false) {
        self.url = url
        self.video = video
        _image = State(initialValue: url.flatMap { Photo.cache.object(forKey: $0.path as NSString) })
    }

    var body: some View {
        Rectangle()
            .fill(Look.chrome)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: video ? "video" : "photo")
                        .font(.system(size: 16))
                        .foregroundStyle(Look.inkFaint)
                }
            }
            .overlay(alignment: .bottomLeading) {
                if video {
                    Image(systemName: "play.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(.black.opacity(0.45), in: Circle())
                        .padding(3)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Look.rule))
            .task(id: url) { await load() }
    }

    private func load() async {
        if shown != url {
            shown = url
            image = url.flatMap { Photo.cache.object(forKey: $0.path as NSString) }
        }
        guard image == nil, let url else { return }
        let got: UIImage?
        if video {
            got = await Photo.poster(url, side: 160)
        } else {
            got = await Task.detached(priority: .userInitiated) {
                Photo.load(url, side: 280)
            }.value
        }
        guard let got else { return }
        Photo.cache.setObject(got, forKey: url.path as NSString)
        image = got
    }
}

/// Прежние вложения дня — конец страницы, рядами по четыре (P546, P618):
/// снимки, видео, голос, файлы и точки. Превью берут долгим
/// нажатием своим жестом (P380, P541) — несут в текст, в план или на другое
/// место в ленте; подержали и не повели — крестик (P432).
struct PhotoStrip: View {

    let photos: [URL?]
    /// Точки на карте в ленте (P588) — по местам ряда; у файла — `nil`.
    var points: [GeoPoint?] = []
    var onOpen: ((Int) -> Void)?
    /// Своё перенесение превью (дневник, P380): долгое нажатие и ход
    /// пальца по экрану — вместо системного перетаскивания, у которого
    /// не было ни синей рамки, ни раздвигания строк.
    var onCarry: ((Int, Lift, CGPoint) -> Void)? = nil
    /// Превью, которое сейчас несут, — на своём месте оно бледное.
    var carried: Int? = nil
    /// Крестик (P432): подержали превью и не повели — у него крестик, как у
    /// точки в тексте; повели — крестик уходит, превью несут.
    var onRemove: ((Int) -> Void)? = nil
    /// Сторона превью: над клавиатурой они мельче (P541).
    var size: CGFloat = PhotoStrip.side
    @State private var armed: Int?
    /// Когда крестик появился — отпущенный палец не должен тут же его убрать.
    @State private var armedAt = Date.distantPast

    /// Как снимок в тексте — в пять строк дневника (P383; прежде 60,
    /// P275), с промежутком, как между снимками в тексте (P557).
    static let side: CGFloat = DiaryEditor.photoSize.width
    /// Промежуток тот же, что между снимками в тексте (P557).
    private let gap: CGFloat = DiaryEditor.photoGap

    var body: some View {
        // Рядами по четыре, как вложения в записи (P618): ленты, что
        // листалась вбок, больше нет.
        VStack(alignment: .leading, spacing: gap) {
            ForEach(Array(stride(from: 0, to: photos.count, by: 4)), id: \.self) { start in
                HStack(spacing: gap) {
                    ForEach(start..<min(start + 4, photos.count), id: \.self) { i in
                        cell(i)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func kind(_ i: Int) -> Diary.Kind {
        photos[i].map { Diary.kind(of: $0.lastPathComponent) } ?? .photo
    }

    /// Снимок — уменьшенной картинкой; голос и документ — плиткой с
    /// значком и расширением (P209).
    private func point(_ i: Int) -> GeoPoint? { points.indices.contains(i) ? points[i] : nil }

    @ViewBuilder private func face(_ i: Int) -> some View {
        if let point = point(i) {
            // Точка — тем же квадратом, что в записи и в плане (P588).
            PointSquare(point: point)
        } else {
            fileFace(i)
        }
    }

    @ViewBuilder private func fileFace(_ i: Int) -> some View {
        switch kind(i) {
        case .photo:
            PhotoThumb(url: photos[i])
        case .video:
            PhotoThumb(url: photos[i], video: true)
        case .audio:
            FileTile(icon: "waveform", label: T("голос", "voice"))
        case .file:
            FileTile(icon: "doc.text",
                     label: photos[i].map { $0.pathExtension.lowercased() } ?? T("файл", "file"))
        }
    }

    /// Касание по превью — открыть его; при крестике — только убрать крестик.
    private func tapped(_ i: Int) {
        // Палец только что отпустили после долгого нажатия — это
        // касание то же самое, оно крестик не убирает (P536): прежде
        // крестик мелькал и тут же пропадал.
        guard Date().timeIntervalSince(armedAt) > 0.5 else { return }
        if armed != nil { withAnimation(.easeOut(duration: 0.15)) { armed = nil } }
        else { onOpen?(i) }
    }

    private func cell(_ i: Int) -> some View {
        face(i)
            .frame(width: size, height: size)
            // Название — у самого превью, а не у всей клетки (P571): прежде
            // оно накрывало и крестик, и тот был не виден ни VoiceOver, ни
            // проверкам.
            .accessibilityElement()
            .accessibilityLabel(point(i) != nil ? T("Точка на карте", "Place on the map")
                                : kind(i) == .photo ? T("Фотография \(i + 1)", "Photo \(i + 1)")
                                : kind(i) == .video ? T("Видео", "Video")
                                : kind(i) == .audio ? T("Голосовая запись", "Voice note") : T("Файл", "File"))
            .contentShape(Rectangle())
            .onTapGesture { tapped(i) }
            // Долгое нажатие и касание — жестами iPhone поверх превью (P541):
            // быстро провели — ряд едет, подержали — превью взято, и ряд
            // уже не едет. Крестик ложится выше — его касание своё.
            .modifier(ThumbCarry(report: onCarry.map { f -> (Lift, CGPoint) -> Void in
                { phase, spot in
                    if case .began = phase { armed = nil }
                    f(i, phase, spot)
                }
            }, stayed: onRemove == nil ? nil : {
                armedAt = Date()
                withAnimation(.easeOut(duration: 0.15)) { armed = i }
            }, together: true, tap: { tapped(i) }))
            .overlay(alignment: .topTrailing) {
                if armed == i, let onRemove {
                    Button {
                        armed = nil
                        onRemove(i)
                    } label: {
                        // Тот же крестик, что у снимка в тексте (P536):
                        // крупный, с тенью. Внутри превью — ряд листается
                        // вбок и всё, что за краем превью, обрезает.
                        Image(uiImage: DiaryEditor.Coordinator.crossImage)
                            .resizable()
                            .frame(width: min(40, size * 0.5), height: min(40, size * 0.5))
                            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                            .frame(width: min(48, size * 0.6), height: min(48, size * 0.6))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                    .accessibilityLabel(T("Убрать", "Remove"))
                }
            }
            .opacity(carried == i ? 0.3 : 1)
            // Где превью на экране — чтобы, отпустив над полоской, поставить
            // взятое на место соседа (P380).
            .background(GeometryReader { geo in
                let frame = geo.frame(in: .global)
                Color.clear
                    .onAppear { if onCarry != nil { StripZones.cells[i] = frame } }
                    .onChange(of: frame) { _, now in if onCarry != nil { StripZones.cells[i] = now } }
            })
    }
}

/// Плитка голоса или документа в полоске.
struct FileTile: View {
    let icon: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 18))
            Text(label).font(Look.sans(9.5)).lineLimit(1).minimumScaleFactor(0.8)
        }
        .foregroundStyle(Look.inkSoft)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Look.chrome, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Look.rule))
    }
}

/// Строка-ссылка снимка, которую принёс палец, — из системного переноса.
enum PhotoDrop {
    /// Прочитать первую ссылку на снимок и отдать её. `false` — нечего.
    static func read(_ providers: [NSItemProvider], _ take: @escaping (String) -> Void) -> Bool {
        guard let provider = providers.first(where: { $0.canLoadObject(ofClass: NSString.self) })
        else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { item, _ in
            guard let text = (item as? NSString).map({ $0 as String }),
                  let link = Diary.anywhere(in: text).first?.link
            else { return }
            DispatchQueue.main.async {
                Feel.light()
                take(link)
            }
        }
        return true
    }
}

/// Снимки под делом в плане — в ряд, а не столбиком (P358). В режиме
/// изменений каждый можно взять пальцем и унести под другое дело или
/// назад в полоску внизу.
struct PlanPhotoRow: View {
    let links: [String]
    var resolve: ((String) -> URL?)?
    var open: ((URL?) -> Void)?
    /// Снимок несут пальцем под другое дело или назад в полоску (P377):
    /// своим жестом, а не системным перетаскиванием, — чтобы строки
    /// расступались там, куда он встанет. Ход и место пальца на экране.
    var onCarry: ((String, Lift, CGPoint) -> Void)?
    /// Снимок, который сейчас несут, — на своём месте он бледный.
    var carried: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(links, id: \.self) { link in
                    PlanPhotoThumb(url: resolve?(link)) { open?(resolve?(link)) }
                        .opacity(carried == link ? 0.25 : 1)
                        .modifier(ThumbCarry(report: report(link)))
                }
            }
            .padding(.horizontal, 14)
        }
        .scrollDisabled(links.count < 4 || carried != nil)
        .frame(height: PlanPhotoLine.height)
    }
    private func report(_ link: String) -> ((Lift, CGPoint) -> Void)? {
        guard let onCarry else { return nil }
        return { phase, spot in onCarry(link, phase, spot) }
    }
}

/// Где на экране превью полоски дневника и сама полоска (P380).
enum StripZones {
    static var cells: [Int: CGRect] = [:]
    static var strip: CGRect?

    /// Превью, ближайшее к пальцу по горизонтали, — куда встанет взятое.
    static func nearest(to spot: CGPoint, count: Int) -> Int? {
        cells.filter { $0.key < count }
            .min { abs($0.value.midX - spot.x) < abs($1.value.midX - spot.x) }?.key
    }
}

/// Снимок под делом берут долгим нажатием и ведут (P377). Сам он остаётся
/// на месте — за пальцем идёт его копия, нарисованная планом поверх всего.
struct ThumbCarry: ViewModifier {
    let report: ((Lift, CGPoint) -> Void)?
    /// Подержали и отпустили, не уводя пальца (P432).
    var stayed: (() -> Void)? = nil
    /// Жест вместе с прокруткой ряда (P539): лента внизу дневника листается
    /// вбок, а свой жест на каждом превью не давал ей сдвинуться.
    var together = false
    /// Касание по превью — когда жесты свои, UIKit (P541).
    var tap: (() -> Void)? = nil

    @State private var lifted = false
    /// Палец ушёл от места — рамка остаётся только у копии над пальцем.
    @State private var away = false
    @GestureState private var holding = false

    /// Ход долгого нажатия UIKit — те же отчёты, что у жеста SwiftUI.
    private func held(_ state: UIGestureRecognizer.State, _ spot: CGPoint, _ moved: CGSize,
                      _ report: (Lift, CGPoint) -> Void) {
        switch state {
        case .began:
            lifted = true
            away = false
            report(.began, spot)
        case .changed:
            guard lifted else { return }
            if hypot(moved.width, moved.height) >= 10 { away = true }
            report(.moved(moved), spot)
        case .ended:
            guard lifted else { return }
            let still = !away
            lifted = false
            away = false
            if still { stayed?() }
            report(.ended(.zero), spot)
        default:
            guard lifted else { return }
            lifted = false
            away = false
            report(.cancelled, .zero)
        }
    }

    func body(content: Content) -> some View {
        if let report, together {
            // Жестами iPhone (P541): совместный жест SwiftUI в 137-й отдавал
            // движение пальца прокрутке ряда — превью так и не бралось.
            content
                .overlay {
                    if lifted && !away {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Look.glow, lineWidth: 3)
                            .shadow(color: Look.glow.opacity(0.8), radius: 4)
                            .allowsHitTesting(false)
                    }
                }
                .scaleEffect(lifted && !away ? 1.05 : 1)
                .animation(.easeOut(duration: 0.12), value: lifted && !away)
                .overlay(HoldCatcher(hold: { state, spot, moved in
                    held(state, spot, moved, report)
                }, tap: tap))
        } else if let report {
            content
                // Подержали — превью сразу в синей рамке и чуть крупнее
                // (P391), как точка и дело: видно, что взято именно оно.
                .overlay {
                    if lifted && !away {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Look.glow, lineWidth: 3)
                            .shadow(color: Look.glow.opacity(0.8), radius: 4)
                            .allowsHitTesting(false)
                    }
                }
                .scaleEffect(lifted && !away ? 1.05 : 1)
                .animation(.easeOut(duration: 0.12), value: lifted && !away)
                .gesture(LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .updating($holding) { value, state, _ in
                        if case .second(true, _) = value { state = true }
                    }
                    .onChanged { value in
                        guard case .second(true, let drag) = value else { return }
                        if !lifted {
                            lifted = true
                            away = false
                            report(.began, drag?.location ?? .zero)
                        }
                        if let drag {
                            if hypot(drag.translation.width, drag.translation.height) >= 10 { away = true }
                            report(.moved(drag.translation), drag.location)
                        }
                    }
                    .onEnded { value in
                        guard lifted else { return }
                        let still = !away
                        lifted = false
                        away = false
                        if still { stayed?() }
                        var spot = CGPoint.zero
                        if case .second(true, let drag) = value, let drag { spot = drag.location }
                        report(.ended(.zero), spot)
                    })
                .onChange(of: holding) { _, now in
                    guard !now else { return }
                    DispatchQueue.main.async {
                        guard lifted else { return }
                        lifted = false
                        away = false
                        report(.cancelled, .zero)
                    }
                }
        } else {
            content
        }
    }
}

struct PlanPhotoThumb: View {
    let url: URL?
    var onOpen: (() -> Void)?
    @State private var image: UIImage?
    /// Чья картинка сейчас показана (P555): копия над пальцем — одна на все
    /// переносы, и прежде показывала снимок, который несли в прошлый раз.
    @State private var shown: URL?

    init(url: URL?, onOpen: (() -> Void)? = nil) {
        self.url = url
        self.onOpen = onOpen
        _image = State(initialValue: url.flatMap { Photo.cache.object(forKey: PhotoAttachment.key($0)) })
    }

    var body: some View {
        Image(uiImage: image ?? PhotoAttachment.empty)
            .resizable()
            .frame(width: DiaryEditor.photoSize.width, height: DiaryEditor.photoSize.height)
            .contentShape(Rectangle())
            .onTapGesture { onOpen?() }
            .task(id: url) {
                if shown != url {
                    shown = url
                    image = url.flatMap { Photo.cache.object(forKey: PhotoAttachment.key($0)) }
                }
                guard image == nil, let url else { return }
                let got = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                    guard let raw = Photo.load(url, side: 280) else { return nil }
                    return PhotoAttachment.frame(raw)
                }.value
                guard let got else { return }
                Photo.cache.setObject(got, forKey: PhotoAttachment.key(url))
                image = got
            }
            .accessibilityLabel(T("Фотография", "Photo"))
    }
}

/// Снимок во весь экран.
struct PhotoViewer: View {

    let url: URL?
    /// Убрать снимок из записи; `true` — и удалить файл в корзину (P371).
    /// Пусто — день закрыт для правки.
    var onRemove: ((Bool) -> Void)?
    /// Вернуть снимок из текста в полоску внизу (P216).
    var onReturn: (() -> Void)?
    let close: () -> Void
    /// Снимок ведут пальцем вбок (P583): сколько сдвинут — листатель
    /// двигает за пальцем весь ряд, с соседями.
    var onSlide: ((CGFloat) -> Void)?
    /// Палец отпустили: сдвиг и куда бы он долетел по инерции.
    var onSlideEnd: ((CGFloat, CGFloat) -> Void)?

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @State private var asking = false
    @State private var saved = false
    /// Насколько снимок стянут пальцем вниз (P270).
    @State private var pulled: CGSize = .zero
    /// Куда пошёл палец: решается по первому движению.
    @State private var sideways: Bool?

    /// Как далеко стянут: 0 — на месте, 1 — почти ушёл.
    private var gone: CGFloat { min(1, max(0, pulled.height) / 420) }

    var body: some View {
        ZStack {
            // Фон светлеет, пока снимок тянут вниз: под ним видна страница,
            // как в «Фото» Apple.
            Color.black.opacity(1 - gone).ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale * (1 - gone * 0.3))
                    .offset(x: pulled.width * 0.6, y: max(0, pulled.height))
                    .gesture(MagnificationGesture()
                        .onChanged { scale = max(1, $0) }
                        .onEnded { _ in withAnimation(.easeOut(duration: 0.2)) { scale = 1 } })
                    .simultaneousGesture(swipeDown)
            } else {
                ProgressView().tint(.white)
            }
        }
        // Кнопки — внизу (P428): «Готово · Поделиться · Удалить», у снятых
        // в приложении ещё «Сохранить на устройство».
        .overlay(alignment: .bottom) { bar.opacity(pulled == .zero ? 1 : 0) }
        // Под снимком — страница: её видно, пока снимок стягивают.
        .presentationBackground(.clear)
        .task {
            guard let url else { return }
            image = await Task.detached(priority: .userInitiated) {
                Photo.load(url, side: 1400)
            }.value
        }
        .modifier(RemoveQuestion(asking: $asking, act: onRemove))
    }


    /// Свайп вниз убирает снимок, как в «Фото» Apple (P270): потянул
    /// и отпустил — снимок уходит; не дотянул — возвращается на место.
    /// Увеличенный снимок не стягивается: там палец двигает картинку.
    private var swipeDown: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { v in
                guard scale == 1 else { return }
                // Куда пошёл палец — решается один раз: вбок листают
                // снимки, вниз — убирают (P278, P270). Одним жестом, чтобы
                // один не перехватывал другой.
                if sideways == nil {
                    sideways = abs(v.translation.width) > abs(v.translation.height)
                }
                if sideways == true {
                    onSlide?(v.translation.width)
                } else if v.translation.height > 0 || pulled != .zero {
                    pulled = v.translation
                }
            }
            .onEnded { v in
                defer { sideways = nil }
                guard scale == 1 else { return }
                if sideways == true {
                    onSlideEnd?(v.translation.width, v.predictedEndTranslation.width)
                    return
                }
                guard pulled != .zero else { return }
                if pulled.height > 110 || v.predictedEndTranslation.height > 280 {
                    Feel.light()
                    withAnimation(.easeOut(duration: 0.2)) {
                        pulled = CGSize(width: pulled.width, height: UIScreen.main.bounds.height)
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        var still = Transaction()
                        still.disablesAnimations = true
                        withTransaction(still) { close() }
                    }
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { pulled = .zero }
                }
            }
    }

    /// Кнопки над снимком — каждая на тёмной полупрозрачной подложке
    /// (P390): белые значки прямо на снимке пропадали на светлом — на
    /// снимке экрана, бумаге, небе.
    private var bar: some View {
        HStack(spacing: 10) {
            Button(action: close) {
                Text(T("Готово", "Done"))
                    .fontWeight(.semibold)
                    .modifier(OverPhoto())
            }
            Spacer()
            if let url {
                ShareLink(item: url) {
                    Image(systemName: "square.and.arrow.up").modifier(OverPhoto(round: true))
                }
            }
            if let onReturn {
                Button(action: onReturn) {
                    Label(T("В полоску", "To the strip"), systemImage: "arrow.down.to.line")
                        .font(.system(size: 15))
                        .modifier(OverPhoto())
                }
                .accessibilityLabel(T("Вернуть в полоску внизу страницы", "Move back to the strip at the bottom"))
            }
            if let url, let image, CameraShots.taken(url) {
                Button {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                    Feel.done()
                    saved = true
                } label: {
                    Image(systemName: saved ? "checkmark" : "square.and.arrow.down")
                        .modifier(OverPhoto(round: true))
                }
                .disabled(saved)
                .accessibilityLabel(T("Сохранить на устройство", "Save to the device"))
            }
            if onRemove != nil {
                Button { asking = true } label: {
                    Image(systemName: "trash").modifier(OverPhoto(round: true))
                }
                .accessibilityLabel(T("Убрать из записи", "Remove from entry"))
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .padding(.bottom, 14)
    }
}

/// Подложка кнопки над снимком (P390): тёмная полупрозрачная, с тонкой
/// светлой кромкой — видна и на светлом снимке, и на тёмном.
struct OverPhoto: ViewModifier {
    var round = false

    func body(content: Content) -> some View {
        content
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, round ? 0 : 14)
            .frame(minWidth: 40, minHeight: 40)
            .background(Capsule().fill(Color.black.opacity(0.55)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.35), lineWidth: 0.8))
            .shadow(color: .black.opacity(0.3), radius: 4, y: 1)
            .contentShape(Capsule())
    }
}

/// Вложения полоски во весь экран — листаются вбок (P278): влево —
/// следующее в полоске, вправо — прежнее. Жест один с «убрать вниз», в
/// самом просмотре снимка: общий листатель перехватывал бы то одно, то
/// другое. Видео, голос и документ вбок не листаются — там свои жесты.
struct StripViewer: View {
    let count: Int
    let url: (Int) -> URL?
    /// Что можно сделать с каждым: удалить (из ленты), вернуть в ленту (из
    /// записи) — у каждого своё (P564).
    var remove: (Int) -> ((Bool) -> Void)?
    var giveBack: (Int) -> (() -> Void)?
    let close: () -> Void

    @State private var index: Int
    /// Насколько ряд снимков сдвинут пальцем (P583).
    @State private var drag: CGFloat = 0
    /// Промежуток между снимками, пока их листают.
    private static let gap: CGFloat = 18

    init(count: Int, start: Int, url: @escaping (Int) -> URL?,
         remove: @escaping (Int) -> ((Bool) -> Void)?,
         giveBack: @escaping (Int) -> (() -> Void)? = { _ in nil },
         close: @escaping () -> Void) {
        self.count = count
        self.url = url
        self.remove = remove
        self.giveBack = giveBack
        self.close = close
        _index = State(initialValue: start)
    }

    /// Снимки листаются, как в «Фото» (P583): ряд едет за пальцем, сосед
    /// виден и въезжает, отпустили — ряд доезжает до снимка. Прежде снимок
    /// сменялся рывком, когда палец уже отпустили. Соседи собраны заранее
    /// и уже загружены: перелистнули — тот же вид становится открытым.
    var body: some View {
        GeometryReader { geo in
            let step = geo.size.width + Self.gap
            ZStack {
                ForEach(max(0, index - 1)...max(0, min(count - 1, index + 1)), id: \.self) { i in
                    page(i)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .offset(x: CGFloat(i - index) * step + drag)
                        .allowsHitTesting(i == index)
                }
            }
        }
        .presentationBackground(.clear)
    }

    @ViewBuilder private func page(_ i: Int) -> some View {
        let live = i == index
        AttachmentViewer(url: url(i),
                         onRemove: live ? remove(i) : nil,
                         onReturn: live ? giveBack(i) : nil,
                         close: close,
                         onSlide: live ? { slide($0) } : nil,
                         onSlideEnd: live ? { end($0, $1) } : nil)
    }

    /// За краем ряда — снимков нет: ряд тянется втрое туже.
    private func slide(_ x: CGFloat) {
        let edge = (x > 0 && index == 0) || (x < 0 && index == count - 1)
        drag = edge ? x / 3 : x
    }

    private func end(_ x: CGFloat, _ predicted: CGFloat) {
        let width = UIScreen.main.bounds.width
        let by = x < 0 ? 1 : -1
        let next = index + by
        let far = abs(x) > width * 0.25 || abs(predicted) > width * 0.5
        guard far, (0..<count).contains(next) else {
            if far { Feel.light() }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { drag = 0 }
            return
        }
        Feel.tick()
        let step = width + Self.gap
        withAnimation(.spring(response: 0.3, dampingFraction: 0.95)) {
            drag = CGFloat(-by) * step
        } completion: {
            var still = Transaction()
            still.disablesAnimations = true
            withTransaction(still) {
                index = next
                drag = 0
            }
        }
    }
}

/// Удаление вложения (P371): убрать только со страницы или удалить и сам
/// файл — в корзину на 30 дней. Одно окно на снимки, видео, голос и
/// документы.
struct RemoveQuestion: ViewModifier {
    @Binding var asking: Bool
    let act: ((Bool) -> Void)?

    /// Один короткий вопрос посередине экрана (P556): прежде — лист у
    /// превью с длинным объяснением, он мог уйти под клавиатуру, а снимку
    /// из текста задавался ещё и свой вопрос. Что файл в корзине и где её
    /// найти — говорит строчка после удаления.
    func body(content: Content) -> some View {
        content.alert(T("Что сделать с файлом?", "What should happen to the file?"),
                      isPresented: $asking) {
            Button(T("Убрать со страницы", "Remove from the page")) { act?(false) }
            Button(T("Удалить файл — в корзину на 30 дней",
                     "Delete the file — trash for 30 days"), role: .destructive) { act?(true) }
            Button(T("Отмена", "Cancel"), role: .cancel) { }
        }
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

/// Долгое нажатие и касание по превью — жестами iPhone (P541). Они сами
/// делят палец с прокруткой вокруг: провели быстро — едет ряд или
/// страница; подержали — нажатие взято, и прокрутки этого касания уже нет.
struct HoldCatcher: UIViewRepresentable {
    /// Ход нажатия, место пальца в окне и сдвиг от начала.
    var hold: (UIGestureRecognizer.State, CGPoint, CGSize) -> Void
    var tap: (() -> Void)?

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        let press = UILongPressGestureRecognizer(target: context.coordinator,
                                                 action: #selector(Coordinator.pressed(_:)))
        press.minimumPressDuration = 0.3
        view.addGestureRecognizer(press)
        let touch = UITapGestureRecognizer(target: context.coordinator,
                                           action: #selector(Coordinator.tapped))
        // Касание — только если это было не долгое нажатие (P561): прежде
        // подержанное превью, отпущенное на месте, ещё и открывалось.
        touch.require(toFail: press)
        view.addGestureRecognizer(touch)
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject {
        var parent: HoldCatcher
        private var start: CGPoint = .zero

        init(_ parent: HoldCatcher) { self.parent = parent }

        @objc func pressed(_ g: UILongPressGestureRecognizer) {
            let at = g.location(in: nil)
            if g.state == .began { start = at }
            parent.hold(g.state, at, CGSize(width: at.x - start.x, height: at.y - start.y))
        }

        @objc func tapped() { parent.tap?() }
    }
}

/// Высота строки снимка между делами плана (P204, P205). Сама строка
/// рисуется в ряду вложений; осталась только мерка.
enum PlanPhotoLine {
    static let height: CGFloat = DiaryEditor.photoSize.height + 16
}

/// Точка на карте квадратом (P587, P588): булавка и название, без названия —
/// «Место» и сколько до своего места. Один вид в ленте, в плане и в записи.
struct PointSquare: View {
    let point: GeoPoint

    var body: some View {
        let given = point.title.trimmingCharacters(in: .whitespaces)
        Image(uiImage: PointChip.square(given.isEmpty ? T("Место", "Place") : given,
                                        note: given.isEmpty ? Places.caption(for: point.at) : nil,
                                        glowing: false))
            .resizable()
            .scaledToFit()
    }
}

/// Картинки пробного архива (P589): дюжина разных снимков размером с
/// обычный снимок iPhone после сжатия приложения — с полосами и пятнами,
/// чтобы сжатие не сводило их к нескольким байтам.
enum SeedPictures {
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
