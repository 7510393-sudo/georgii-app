import SwiftUI
import UIKit

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
