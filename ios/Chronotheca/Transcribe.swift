import Foundation
import Speech

/// Голосовая запись — в текст (P378). Распознаёт сам iPhone; где для
/// языка есть распознавание без сети, запись не уходит с телефона.
/// Сама запись остаётся — текст ложится рядом с ней.
enum Transcribe {

    /// Задача распознавания держится, пока идёт: иначе она обрывается.
    private static var running: SFSpeechRecognitionTask?

    /// Распознаватель на языке приложения: сперва с краем телефона
    /// («ru-RU», «en-GB»), потом любой с тем же языком.
    static func recognizer() -> SFSpeechRecognizer? {
        let code = Lang.code
        let phone = Locale.current
        if phone.language.languageCode?.identifier == code, let r = SFSpeechRecognizer(locale: phone) {
            return r
        }
        let found = SFSpeechRecognizer.supportedLocales()
            .filter { $0.language.languageCode?.identifier == code }
            .sorted { $0.identifier < $1.identifier }
        return found.first.flatMap(SFSpeechRecognizer.init(locale:)) ?? SFSpeechRecognizer()
    }

    /// Распознать файл. `done` — текст или что помешало, на главном потоке.
    static func run(_ url: URL, done: @escaping (String?, String?) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            guard status == .authorized else {
                return DispatchQueue.main.async {
                    done(nil, T("Нет разрешения на распознавание речи — его можно дать в Настройках iPhone.",
                                "No permission for speech recognition — you can allow it in iPhone Settings."))
                }
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let local = Attachment.fetch(url) ?? url
                DispatchQueue.main.async {
                    guard let r = recognizer(), r.isAvailable else {
                        return done(nil, T("Распознавание речи для этого языка сейчас недоступно.",
                                           "Speech recognition for this language is not available right now."))
                    }
                    let request = SFSpeechURLRecognitionRequest(url: local)
                    // Промежуточные ответы нужны: после каждой паузы iPhone
                    // начинает распознавать заново, и последний ответ несёт
                    // только последний кусок — из 20 секунд оставались два
                    // слова (P380). Куски собираются по порядку.
                    request.shouldReportPartialResults = true
                    request.addsPunctuation = true
                    if r.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
                    var pieces = Pieces()
                    running = r.recognitionTask(with: request) { result, error in
                        if let result {
                            pieces.take(result.bestTranscription)
                            guard result.isFinal else { return }
                            running = nil
                            let text = pieces.text
                            DispatchQueue.main.async {
                                text.isEmpty
                                    ? done(nil, T("Речи в записи не нашлось.", "No speech was found in the recording."))
                                    : done(text, nil)
                            }
                        } else if let error {
                            running = nil
                            let text = pieces.text
                            DispatchQueue.main.async {
                                text.isEmpty ? done(nil, error.localizedDescription) : done(text, nil)
                            }
                        }
                    }
                }
            }
        }
    }

    /// Куски распознанного: новый кусок узнаётся по тому, что его первое
    /// слово звучит позже, чем кончилось последнее слово прежнего.
    struct Pieces {
        private var done: [String] = []
        private var current = ""
        private var currentEnd: TimeInterval = 0

        mutating func take(_ t: SFTranscription) {
            let start = t.segments.first?.timestamp ?? 0
            if !current.isEmpty, start >= currentEnd - 0.05 {
                done.append(current)
            }
            current = t.formattedString
            currentEnd = t.segments.last.map { $0.timestamp + $0.duration } ?? currentEnd
        }

        var text: String {
            (done + [current]).map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }

    /// Распознаётся ли этот язык без сети — для честной строки под кнопкой.
    static var onPhone: Bool { recognizer()?.supportsOnDeviceRecognition ?? false }
}
