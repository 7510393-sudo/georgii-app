import SwiftUI
import Photos
import UIKit

/// Снимки и видео галереи, сделанные в этот день, — рядом над полоской
/// вложений, как в Diarium (P273, P344). Касание ставит или снимает
/// галочку; ряд убирается любым касанием мимо — и отмеченное ложится в
/// день, ничего не отмечено — просто убирается (P350). Долгое нажатие
/// открывает снимок во весь экран — рассмотреть. Первая плитка «Все фото»
/// открывает обычное окно галереи — там поиск и снимки других дней.
///
/// Разрешение смотреть галерею спрашивается, когда ряд открыли впервые.
/// Не дали — ряд говорит, где разрешить, а «Все фото» работает и без
/// него: то окно не просит доступа ко всей галерее.
struct GalleryRow: View {

    /// День страницы: в ряду — снимки, сделанные в этот день, по той же
    /// границе суток, что и у самого приложения.
    var day: Date = DayStore.today()
    /// Отмеченное — в день. Зовётся один раз, когда ряд убирают.
    let add: ([PHAsset]) -> Void
    let more: () -> Void

    @State private var assets: [PHAsset] = []
    @State private var loaded = false
    @State private var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    /// Отмеченные галочкой — по порядку касаний: так они и лягут.
    @State private var taken: [String] = []
    /// Снимок, открытый во весь экран.
    @State private var looking: Looked?

    struct Looked: Identifiable {
        let asset: PHAsset
        var id: String { asset.localIdentifier }
    }

    /// Превью в ряду галереи над клавиатурой — того же размера, что все
    /// превью: в пять строк дневника (P385; прежде 60).
    static let side: CGFloat = DiaryEditor.photoSize.width
    static let height: CGFloat = side + 16

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                Button(action: more) {
                    VStack(spacing: 3) {
                        Image(systemName: "photo.on.rectangle.angled")
                            .font(.system(size: 17))
                        Text(T("все фото", "all photos")).font(Look.sans(9.5))
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(Look.accent)
                    .frame(width: Self.side, height: Self.side)
                    .background(Look.chrome, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Look.rule))
                }
                .buttonStyle(.plain)
                if status == .denied || status == .restricted {
                    Text(T("Галерея закрыта для приложения: Настройки iPhone → Graphomanus → Фото",
                           "The app has no access to Photos: iPhone Settings → Graphomanus → Photos"))
                        .font(Look.sans(12))
                        .foregroundStyle(Look.inkSoft)
                        .frame(width: 230, alignment: .leading)
                } else if loaded && assets.isEmpty {
                    Text(T("За этот день снимков в галерее нет. Другие — в «все фото».",
                           "No photos from this day. Others are in “all photos”."))
                        .font(Look.sans(12))
                        .foregroundStyle(Look.inkSoft)
                        .frame(width: 230, alignment: .leading)
                        .padding(.leading, 10)
                }
                ForEach(assets, id: \.localIdentifier) { asset in
                    GalleryThumb(asset: asset)
                        .overlay(alignment: .bottomLeading) {
                            if asset.mediaType == .video {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 2)
                                    .padding(4)
                            }
                        }
                        .overlay(alignment: .topTrailing) {
                            if taken.contains(asset.localIdentifier) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 15))
                                    .foregroundStyle(.white, Look.accent)
                                    .padding(3)
                            }
                        }
                        .onTapGesture { mark(asset) }
                        .onLongPressGesture(minimumDuration: 0.4) {
                            Feel.light()
                            looking = Looked(asset: asset)
                        }
                        .accessibilityLabel(asset.mediaType == .video ? T("Видео из галереи", "Video from Photos")
                                                                      : T("Снимок из галереи", "Photo from Photos"))
                        .accessibilityAddTraits(.isButton)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(height: Self.height)
        .background(Look.chrome)
        .overlay(alignment: .top) { Rectangle().fill(Look.rule).frame(height: 1) }
        .task { await load() }
        // Ряд убрали — касанием мимо, разделом, уголком, «все фото»:
        // отмеченное ложится в день (P350).
        .onDisappear {
            // Снимок во весь экран закрывает ряд, но ряд не убран.
            guard looking == nil else { return }
            let chosen = taken.compactMap { id in assets.first { $0.localIdentifier == id } }
            taken = []
            if !chosen.isEmpty { add(chosen) }
        }
        .fullScreenCover(item: $looking) { looked in
            GalleryPreview(asset: looked.asset,
                           already: taken.contains(looked.id),
                           cancel: { looking = nil },
                           add: {
                               if !taken.contains(looked.id) { taken.append(looked.id) }
                               Feel.light()
                               looking = nil
                           })
        }
    }

    private func mark(_ asset: PHAsset) {
        Feel.light()
        if let i = taken.firstIndex(of: asset.localIdentifier) {
            taken.remove(at: i)
        } else {
            taken.append(asset.localIdentifier)
        }
    }

    private func load() async {
        if status == .notDetermined {
            status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        }
        guard status == .authorized || status == .limited else { return }
        assets = Self.assets(of: day)
        loaded = true
    }

    /// Снимки и видео галереи, сделанные в этот день. Сутки дня — с той же
    /// границы, что у приложения: снимок в час ночи принадлежит ещё
    /// вчерашнему дню (P17).
    static func assets(of day: Date, limit: Int = 120) -> [PHAsset] {
        let cal = Calendar.current
        let start = cal.date(byAdding: .hour, value: DayStore.boundaryHour,
                             to: cal.startOfDay(for: day)) ?? day
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let options = PHFetchOptions()
        options.predicate = NSPredicate(
            format: "(mediaType == %d OR mediaType == %d) AND creationDate >= %@ AND creationDate < %@",
            PHAssetMediaType.image.rawValue, PHAssetMediaType.video.rawValue,
            start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        let found = PHAsset.fetchAssets(with: options)
        var list: [PHAsset] = []
        found.enumerateObjects { asset, _, _ in list.append(asset) }
        return list
    }

    /// Снимки и видео из галереи — в день, в план или дневник (P273, P350,
    /// P538). Взятое запоминается и больше не предлагается в ленте.
    static func take(_ assets: [PHAsset], store: DayStore, tab: Shell.Tab,
                     say: @escaping (String) -> Void) {
        DaySuggestions.markTaken(assets.map(\.localIdentifier))
        var left = assets.count
        var failed = 0
        let finish: () -> Void = {
            left -= 1
            guard left == 0 else { return }
            if failed > 0 {
                say(T("Не удалось взять из галереи: \(failed)", "Could not take from Photos: \(failed)"))
            } else if assets.count > 1 {
                say(T("Положено в папку: \(assets.count)", "Saved to the folder: \(assets.count)"))
            }
        }
        for asset in assets {
            if asset.mediaType == .video {
                movie(of: asset) { found in
                    guard let found else { failed += 1; finish(); return }
                    // Крупный ролик — до 1080p, если так в настройках (P365).
                    Movie.shrink(found) { url in
                        defer {
                            finish()
                            try? FileManager.default.removeItem(at: found)
                            if url != found { try? FileManager.default.removeItem(at: url) }
                        }
                        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
                              store.addAttachment(data, to: .videos,
                                                  name: Vault.moment(store.date) + "."
                                                      + (url.pathExtension.isEmpty ? "mov" : url.pathExtension.lowercased()),
                                                  tab: tab)
                        else { failed += 1; return }
                    }
                }
            } else {
                data(of: asset) { data in
                    defer { finish() }
                    guard let data, store.addPhoto(data, to: tab) else { failed += 1; return }
                }
            }
        }
    }

    /// Видео целиком, файлом во временной папке: ролик может весить
    /// гигабайт, в память его не берём. Из iCloud докачивается (P350).
    static func movie(of asset: PHAsset, done: @escaping (URL?) -> Void) {
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .fullSizeVideo })
                ?? resources.first(where: { $0.type == .video })
        else { return done(nil) }
        let ext = (resource.originalFilename as NSString).pathExtension
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "." + (ext.isEmpty ? "mov" : ext))
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { error in
            DispatchQueue.main.async { done(error == nil ? url : nil) }
        }
    }

    /// Снимок целиком — чтобы положить его в папку как есть (A6: только
    /// оригинал). Из iCloud докачивается.
    static func data(of asset: PHAsset, done: @escaping (Data?) -> Void) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.version = .current
        options.deliveryMode = .highQualityFormat
        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            DispatchQueue.main.async { done(data) }
        }
    }
}

/// Уменьшенный снимок из галереи.
struct GalleryThumb: View {
    let asset: PHAsset
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Look.chrome
            }
        }
        .frame(width: GalleryRow.side, height: GalleryRow.side)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onAppear {
            guard image == nil else { return }
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .opportunistic
            PHImageManager.default().requestImage(for: asset,
                                                  targetSize: CGSize(width: 360, height: 360),
                                                  contentMode: .aspectFill,
                                                  options: options) { got, _ in
                if let got { image = got }
            }
        }
    }
}

/// Снимок из ряда галереи во весь экран: рассмотреть, прежде чем класть в
/// день (P344). Внизу слева — «Отменить», справа — «Добавить»: он ставит
/// галочку, как касание в ряду (P350). Видео — первым кадром.
struct GalleryPreview: View {
    let asset: PHAsset
    /// Снимок уже положен в этот раз — второй раз не кладётся.
    let already: Bool
    let cancel: () -> Void
    let add: () -> Void

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .ignoresSafeArea(edges: .horizontal)
            } else {
                ProgressView().tint(.white)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button(action: cancel) {
                    Text(T("Отменить", "Cancel"))
                        .font(Look.sans(17))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(.white.opacity(0.14), in: Capsule())
                }
                Spacer()
                Button(action: add) {
                    Text(already ? T("Уже отмечен", "Selected") : T("Добавить", "Add"))
                        .font(Look.sans(17, weight: .semibold))
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(already ? Color.white.opacity(0.14) : Look.glow, in: Capsule())
                }
                .disabled(already)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
        .onAppear(perform: load)
    }

    private func load() {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        let scale = UIScreen.main.scale
        let size = CGSize(width: UIScreen.main.bounds.width * scale,
                          height: UIScreen.main.bounds.height * scale)
        PHImageManager.default().requestImage(for: asset, targetSize: size,
                                              contentMode: .aspectFit,
                                              options: options) { got, _ in
            if let got { image = got }
        }
    }
}

/// Камера iPhone — снимок сразу в день (P289). Снимок ложится в папку
/// «Фотографии» так же, как выбранный из галереи.
struct CameraPicker: UIViewControllerRepresentable {
    let done: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (Data?) -> Void
        init(done: @escaping (Data?) -> Void) { self.done = done }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // Формат iPhone — HEIC (P365); сжатие — дальше, по настройке.
            let image = info[.originalImage] as? UIImage
            done(image?.heicData() ?? image?.jpegData(compressionQuality: 0.92))
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            done(nil)
        }
    }
}

/// Снимки сегодняшнего дня из галереи — предложением в ленте превью внизу
/// дневника (P538). Только сегодня и только когда галерея открыта
/// приложению; взятое (из ленты или из окна галереи) запоминается по номеру
/// снимка в галерее и больше не предлагается.
final class DaySuggestions: ObservableObject {

    @Published private(set) var assets: [PHAsset] = []
    @Published private(set) var status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    /// Сегодняшняя страница, и это не снимки для сборки.
    @Published private(set) var active = false

    static let changed = Notification.Name("DaySuggestions.changed")
    private static let key = "gallery.taken"

    /// Есть что показать: предложенные снимки или плитка «снимки дня»,
    /// пока приложение о галерее ещё не спрашивало.
    var shows: Bool { active && (!assets.isEmpty || status == .notDetermined) }

    static var taken: Set<String> { Set(UserDefaults.standard.stringArray(forKey: key) ?? []) }

    static func markTaken(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        var list = UserDefaults.standard.stringArray(forKey: key) ?? []
        list.append(contentsOf: ids.filter { !list.contains($0) })
        UserDefaults.standard.set(Array(list.suffix(3000)), forKey: key)
        NotificationCenter.default.post(name: changed, object: nil)
    }

    func reload(today: Bool) {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        active = today && !Vault.isPreview
        guard active, status == .authorized || status == .limited else {
            if !assets.isEmpty { assets = [] }
            return
        }
        let taken = Self.taken
        assets = GalleryRow.assets(of: DayStore.today(), limit: 40)
            .filter { !taken.contains($0.localIdentifier) }
    }

    /// Спросить о галерее — только по касанию человека.
    func ask() {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.reload(today: self.active)
            }
        }
    }

    /// Взяли — плитка уходит сразу, не дожидаясь, пока снимок ляжет.
    func drop(_ asset: PHAsset) {
        assets.removeAll { $0.localIdentifier == asset.localIdentifier }
    }
}

/// Предложенные снимки в ленте (P538): за тонкой чертой с подписью, бледные,
/// в пунктире и с «+». Касание — снимок берётся в день и встаёт к
/// добавленным, левее черты.
struct SuggestedRow: View {
    @ObservedObject var model: DaySuggestions
    let add: (PHAsset) -> Void

    private var side: CGFloat { PhotoStrip.side }

    var body: some View {
        if model.shows {
            HStack(spacing: 6) {
                divider
                if model.status == .notDetermined {
                    askTile
                } else {
                    ForEach(model.assets, id: \.localIdentifier) { asset in
                        tile(asset)
                    }
                }
            }
            .padding(.leading, 6)
        }
    }

    /// Черта и подпись поперёк: правее — ещё не ваше.
    private var divider: some View {
        HStack(spacing: 3) {
            Rectangle().fill(Look.inkFaint).frame(width: 1.5, height: side)
            Text(T("сегодня в галерее", "today in Photos"))
                .font(Look.sans(11))
                .foregroundStyle(Look.inkFaint)
                .lineLimit(1)
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 14, height: side)
        }
    }

    private var dashed: some View {
        RoundedRectangle(cornerRadius: 6)
            .strokeBorder(Look.inkSoft.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
    }

    private func tile(_ asset: PHAsset) -> some View {
        GalleryThumb(asset: asset)
            .frame(width: side, height: side)
            .opacity(0.5)
            .overlay(dashed)
            .overlay(alignment: .bottomLeading) {
                if asset.mediaType == .video {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .padding(5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.white, Look.accent)
                    .shadow(color: .black.opacity(0.25), radius: 2)
                    .padding(5)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                Feel.light()
                model.drop(asset)
                add(asset)
            }
            .accessibilityLabel(T("Добавить снимок из галереи", "Add photo from Photos"))
            .accessibilityAddTraits(.isButton)
    }

    /// Приложение о галерее ещё не спрашивало — спросит по касанию, само
    /// окно с вопросом не выскакивает.
    private var askTile: some View {
        Button { model.ask() } label: {
            VStack(spacing: 4) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 18))
                Text(T("показывать снимки дня", "show today’s photos"))
                    .font(Look.sans(10.5))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 6)
            }
            .foregroundStyle(Look.accent)
            .frame(width: side, height: side)
            .overlay(dashed)
        }
        .buttonStyle(.plain)
    }
}
