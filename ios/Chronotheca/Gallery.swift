import SwiftUI
import Photos
import UIKit

/// Снимки галереи для дня: найти, взять в день, достать видео и данные.
/// Ряд галереи над полоской (P273, P344, P350) убран (P551): «фото» сразу
/// открывает окно галереи (P537), снимки дня — в конце ленты превью (P538).
enum GalleryRow {

    /// Превью снимков галереи — того же размера, что все превью (P385).
    static let side: CGFloat = DiaryEditor.photoSize.width

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
    /// Сторона плиток — та же, что у превью рядом (P545): прежде плитки были
    /// крупнее превью и вылезали из ленты под кнопки.
    var side: CGFloat = PhotoStrip.side
    let add: (PHAsset) -> Void

    var body: some View {
        if model.shows {
            HStack(spacing: DiaryEditor.photoGap) {
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

    /// Между взятыми и предложенными — только воздух (P547): без черты и
    /// без подписи.
    private var divider: some View {
        Color.clear.frame(width: 10, height: side)
    }

    /// Предложенное — бледнее, без рамки, со знаком «+» в углу (P547:
    /// пунктир выглядел неаккуратно).
    private var veil: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.white.opacity(0.28))
    }

    private func tile(_ asset: PHAsset) -> some View {
        GalleryThumb(asset: asset)
            .frame(width: side, height: side)
            .opacity(0.6)
            .overlay(veil)
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
            .background(veil)
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Look.rule, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
