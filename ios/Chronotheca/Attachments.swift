import SwiftUI
import UIKit
import AVFoundation
import AVKit
import QuickLook
import Photos
import PhotosUI
import UniformTypeIdentifiers

// MARK: - Голос

/// Запись голоса. Одна большая кнопка: нажал — пишет, нажал ещё раз —
/// готово. Запись ложится файлом в «Аудио», ссылкой — в файл дня (P209).
struct Recorder: View {

    /// Готовая запись — временный файл; положить его в папку — забота
    /// того, кто позвал.
    let done: (URL) -> Void
    let cancel: () -> Void
    /// Где по ширине стоит кнопка вызова диктофона в строке вложений —
    /// доля от 0 до 1. Кнопка записи встаёт ровно над ней (P330).
    var align: CGFloat = 0.5

    @State private var recorder: AVAudioRecorder?
    @State private var started: Date?
    @State private var denied = false

    var body: some View {
        VStack(spacing: 22) {
            Text(started == nil ? T("Голосовая запись", "Voice note") : T("Идёт запись", "Recording"))
                .font(Look.sans(17, weight: .semibold))
                .foregroundStyle(Look.ink)

            TimelineView(.periodic(from: .now, by: 0.5)) { clock in
                Text(Recorder.clock(started.map { clock.date.timeIntervalSince($0) } ?? 0))
                    .font(Look.mono(34))
                    .foregroundStyle(started == nil ? Look.inkFaint : Look.ink)
            }
            if started != nil {
                Text(T("Пишет и при погасшем экране. Квадрат — закончить и сохранить.",
                       "Keeps recording with the screen off. The square stops and saves."))
                    .font(Look.sans(12.5))
                    .foregroundStyle(Look.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            GeometryReader { geo in
                Button(action: toggle) {
                    ZStack {
                        Circle().fill(Color.red.opacity(0.12)).frame(width: 96, height: 96)
                        if started == nil {
                            Circle().fill(Color.red).frame(width: 64, height: 64)
                        } else {
                            RoundedRectangle(cornerRadius: 6).fill(Color.red)
                                .frame(width: 34, height: 34)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(started == nil ? T("Начать запись", "Start recording") : T("Закончить запись", "Stop recording"))
                .position(x: geo.size.width * align, y: geo.size.height / 2)
            }
            .frame(height: 96)

            if denied {
                Text(T("Приложению не разрешён микрофон. Разрешить можно в Настройках iPhone → Graphomanus.",
                       "The app has no access to the microphone. Allow it in iPhone Settings → Graphomanus."))
                    .font(Look.sans(13))
                    .foregroundStyle(Look.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Button(T("Отмена", "Cancel")) {
                recorder?.stop()
                recorder?.deleteRecording()
                recorder = nil
                started = nil
                cancel()
            }
            .font(Look.sans(15))
        }
        .padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Look.chrome)
        // Пока идёт запись, панель не закрывается ни касанием мимо, ни
        // смахиванием вниз — только квадратом или «Отменой» (P343).
        .interactiveDismissDisabled(started != nil)
        // Если панель всё же закрылась посреди записи — записанное не
        // выбрасывается, а ложится в «Аудио», как по квадрату (P343).
        .onDisappear {
            guard let recorder, started != nil else { return }
            recorder.stop()
            try? AVAudioSession.sharedInstance().setActive(false)
            started = nil
            done(recorder.url)
        }
    }

    static func clock(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private func toggle() {
        if let recorder, started != nil {
            recorder.stop()
            try? AVAudioSession.sharedInstance().setActive(false)
            started = nil
            done(recorder.url)
            return
        }
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                guard granted else { denied = true; return }
                begin()
            }
        }
    }

    private func begin() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".m4a")
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ]
            let r = try AVAudioRecorder(url: url, settings: settings)
            guard r.record() else { return }
            recorder = r
            started = Date()
        } catch {
            denied = true
        }
    }
}

/// Прослушать голосовую запись.
struct AudioPlayerView: View {

    let url: URL?

    @State private var player: AVAudioPlayer?
    @State private var playing = false
    @State private var failed = false
    /// Бегунок тянут пальцем (P393): где он сейчас — запись перейдёт туда,
    /// когда палец отпустят.
    @State private var dragging: Double?

    var body: some View {
        VStack(spacing: 12) {
            Text(url.map { ($0.lastPathComponent as NSString).deletingPathExtension } ?? "")
                .font(Look.mono(13))
                .foregroundStyle(Look.inkSoft)
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let length = player?.duration ?? 0
                let at = dragging ?? player?.currentTime ?? 0
                VStack(spacing: 6) {
                    // Бегунок можно передвинуть вперёд и назад (P393).
                    Slider(value: Binding(get: { min(at, max(length, 0.1)) },
                                          set: { dragging = $0 }),
                           in: 0...max(length, 0.1),
                           onEditingChanged: { editing in
                               guard !editing, let to = dragging else { return }
                               player?.currentTime = to
                               dragging = nil
                               Feel.tick()
                           })
                        .tint(Look.accent)
                        .disabled(player == nil)
                    HStack {
                        Text(Recorder.clock(at))
                        Spacer()
                        Text(Recorder.clock(length))
                    }
                    .font(Look.mono(12))
                    .foregroundStyle(Look.inkFaint)
                }
                .padding(.horizontal, 32)
                .onChange(of: player?.isPlaying ?? false) { _, now in playing = now }
            }
            HStack(spacing: 36) {
                skip(-15)
                Button {
                    guard let player else { return }
                    if player.isPlaying { player.pause() } else { player.play() }
                    playing = player.isPlaying
                } label: {
                    Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(Look.accent)
                }
                .buttonStyle(.plain)
                skip(15)
            }
            if failed {
                Text(T("Запись не открылась — возможно, она ещё не скачана из iCloud.",
                         "The recording did not open — perhaps it is not downloaded from iCloud yet."))
                    .font(Look.sans(13))
                    .foregroundStyle(Look.inkSoft)
            }
        }
        .task {
            guard let url else { return }
            let data = await Task.detached { Attachment.read(url) }.value
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            guard let data, let p = try? AVAudioPlayer(data: data) else { failed = true; return }
            p.prepareToPlay()
            player = p
        }
        .onDisappear { player?.stop() }
    }

    /// Назад или вперёд на 15 секунд (P393).
    private func skip(_ by: Double) -> some View {
        Button {
            guard let player else { return }
            player.currentTime = min(max(player.currentTime + by, 0), player.duration)
            Feel.tick()
        } label: {
            Image(systemName: by < 0 ? "gobackward.15" : "goforward.15")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(Look.accent)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .opacity(player == nil ? 0.4 : 1)
        .accessibilityLabel(by < 0 ? T("Назад на 15 секунд", "Back 15 seconds")
                                   : T("Вперёд на 15 секунд", "Forward 15 seconds"))
    }
}

// MARK: - Документы

/// Системное окно выбора файлов. Файл копируется: приложению не нужен
/// доступ к чужой папке — только к самому документу, и только в эту минуту.
///
/// Само окно помнит, где его закрыли в прошлый раз. Открыть сразу «Обзор»
/// iOS приложению не даёт; папку ему больше не подсказываем (P384, прежде
/// — папка над «Graphomanus», P351): тогда окно, закрытое на «Обзоре»,
/// там и открывается.
struct DocumentPicker: UIViewControllerRepresentable {

    /// С какой папки начать; `nil` — где окно закрыли в прошлый раз.
    var start: URL? = nil
    let pick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = true
        picker.directoryURL = start
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(pick: pick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let pick: ([URL]) -> Void
        init(pick: @escaping ([URL]) -> Void) { self.pick = pick }

        func documentPicker(_ controller: UIDocumentPickerViewController,
                            didPickDocumentsAt urls: [URL]) { pick(urls) }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { pick([]) }
    }
}

/// Показ документа — системный, тот же, что в «Файлах».
struct QuickLookView: UIViewControllerRepresentable {

    let url: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        return preview
    }

    func updateUIViewController(_ preview: QLPreviewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController,
                               previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
    }
}

// MARK: - Общее

enum Attachment {

    /// Прочитать вложение через системного посредника — он дождётся, пока
    /// файл придёт из iCloud.
    static func read(_ url: URL) -> Data? {
        var data: Data?
        var trouble: NSError?
        NSFileCoordinator(filePresenter: nil)
            .coordinate(readingItemAt: url, options: [], error: &trouble) { real in
                data = try? Data(contentsOf: real)
            }
        return data
    }

    /// Скачать вложение, если оно в iCloud, и вернуть путь к нему.
    static func fetch(_ url: URL) -> URL? {
        var ready: URL?
        var trouble: NSError?
        NSFileCoordinator(filePresenter: nil)
            .coordinate(readingItemAt: url, options: [], error: &trouble) { real in
                ready = FileManager.default.fileExists(atPath: real.path) ? url : nil
            }
        return ready
    }
}

/// Вложение во весь экран: снимок, голос или документ.
struct AttachmentViewer: View {

    let url: URL?
    var onRemove: ((Bool) -> Void)?
    var onReturn: (() -> Void)?
    let close: () -> Void
    /// Снимок ведут пальцем вбок и отпускают — листает `StripViewer` (P583).
    var onSlide: ((CGFloat) -> Void)? = nil
    var onSlideEnd: ((CGFloat, CGFloat) -> Void)? = nil
    /// Голос — в текст дневника (P378). Пусто — кнопки нет.
    var onTranscript: ((String) -> Void)? = nil

    @State private var ready: URL?
    @State private var transcribing = false
    @State private var transcriptNote: String?
    @State private var player: AVPlayer?
    @State private var asking = false

    var body: some View {
        switch url.map({ Diary.kind(of: $0.lastPathComponent) }) ?? .photo {
        case .photo:
            PhotoViewer(url: url, onRemove: onRemove, onReturn: onReturn, close: close,
                        onSlide: onSlide, onSlideEnd: onSlideEnd)
        case .video:
            framed {
                if let player { VideoPlayer(player: player) } else { ProgressView() }
            }
            // Видео начинает играть само, как только открыто: касание по
            // превью и есть «играть» (P225).
            .task {
                guard let url,
                      let ready = await Task.detached(operation: { Attachment.fetch(url) }).value
                else { return }
                try? AVAudioSession.sharedInstance().setCategory(.playback)
                let p = AVPlayer(url: ready)
                player = p
                p.play()
            }
            .onDisappear { player?.pause() }
        case .audio:
            framed {
                VStack(spacing: 14) {
                    AudioPlayerView(url: url)
                    if let onTranscript, let url { transcribeButton(url, onTranscript) }
                }
            }
        case .file:
            framed {
                if let ready { QuickLookView(url: ready) } else { ProgressView() }
            }
            .task {
                guard let url else { return }
                ready = await Task.detached { Attachment.fetch(url) }.value
            }
        }
    }

    /// «Расшифровать в текст»: распознаёт сам iPhone, запись остаётся.
    @ViewBuilder private func transcribeButton(_ url: URL, _ put: @escaping (String) -> Void) -> some View {
        VStack(spacing: 6) {
            Button {
                transcribing = true
                transcriptNote = nil
                Transcribe.run(url) { text, trouble in
                    transcribing = false
                    if let text {
                        put(text)
                        Feel.done()
                        transcriptNote = T("Текст лёг в дневник под записью.", "The text is in your diary, under the recording.")
                    } else {
                        transcriptNote = trouble
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    if transcribing { ProgressView().controlSize(.small) } else { Image(systemName: "text.quote") }
                    Text(T("Расшифровать в текст", "Transcribe to text"))
                }
            }
            .buttonStyle(.bordered)
            .disabled(transcribing)
            Text(transcriptNote ?? (Transcribe.onPhone
                ? T("Распознаёт сам iPhone, без интернета.", "Recognised on the iPhone itself, offline.")
                : T("Для этого языка iPhone распознаёт через Apple.", "For this language the iPhone recognises via Apple.")))
                .font(Look.sans(12))
                .foregroundStyle(Look.inkSoft)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 20)
    }

    private func framed<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        NavigationStack {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Look.chrome)
                .navigationTitle(url?.lastPathComponent ?? "")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(T("Готово", "Done"), action: close).fontWeight(.semibold)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        HStack(spacing: 18) {
                            if let url { ShareLink(item: url) { Image(systemName: "square.and.arrow.up") } }
                            if onRemove != nil {
                                Button { asking = true } label: { Image(systemName: "trash") }
                                    .accessibilityLabel(T("Убрать со страницы", "Remove from the page"))
                            }
                        }
                    }
                }
                .modifier(RemoveQuestion(asking: $asking, act: onRemove))
        }
    }
}


// MARK: - Окно галереи

/// Системное окно выбора снимков и видео — тем же способом, что камера и
/// «Добавить файл»: листом поверх экрана, который у нас показывается
/// всегда. Прежний `.photosPicker` молча не открывался, когда его просили
/// следом за уходящим рядом галереи (P525).
struct LibraryPicker: UIViewControllerRepresentable {

    let done: ([PHPickerResult]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        // С галереей телефона: у выбранного есть номер снимка, по нему
        // взятое больше не предлагается в ленте (P538). Разрешения на всю
        // галерею это не просит.
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = 0
        config.filter = .any(of: [.images, .videos])
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let done: ([PHPickerResult]) -> Void
        init(done: @escaping ([PHPickerResult]) -> Void) { self.done = done }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            done(results)
        }
    }
}
