import AVFoundation

/// Видео по настройке (P365): «до 1080p» — ролик крупнее 1920 точек по
/// длинной стороне пережимается в 1080p (HEVC, родной формат iPhone);
/// меньший и «без сжатия» — ложится как есть. Не вышло — тоже как есть:
/// лучше большой ролик, чем никакого.
enum Movie {

    static func shrunk(_ url: URL) async -> URL {
        guard Prefs.videoTo1080 else { return url }
        let asset = AVURLAsset(url: url)
        guard let track = (try? await asset.loadTracks(withMediaType: .video))?.first,
              let size = try? await track.load(.naturalSize),
              max(abs(size.width), abs(size.height)) > 1920
        else { return url }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHEVC1920x1080)
                ?? AVAssetExportSession(asset: asset, presetName: AVAssetExportPreset1920x1080)
        else { return url }
        let out = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mov")
        session.outputURL = out
        session.outputFileType = .mov
        // Где и когда снято — с роликом, как у снимков.
        session.metadata = (try? await asset.load(.metadata)) ?? []
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { done.resume() }
        }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: out)
            return url
        }
        return out
    }

    /// То же для мест, где ждать нельзя: ответ — на главной очереди.
    static func shrink(_ url: URL, done: @escaping (URL) -> Void) {
        Task {
            let result = await shrunk(url)
            DispatchQueue.main.async { done(result) }
        }
    }
}
