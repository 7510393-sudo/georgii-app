import EventKit
import EventKitUI
import SwiftUI
import UIKit

/// Событие Календаря в окне Apple: посмотреть, поправить время, название,
/// напоминание или удалить. Правит сам Календарь — мы туда не пишем.
struct EventSheet: UIViewControllerRepresentable {
    let event: EKEvent
    let done: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIViewController(context: Context) -> UINavigationController {
        let view = EKEventViewController()
        view.event = event
        view.allowsEditing = true
        view.allowsCalendarPreview = false
        view.delegate = context.coordinator
        return UINavigationController(rootViewController: view)
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}

    final class Coordinator: NSObject, EKEventViewDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }

        func eventViewController(_ controller: EKEventViewController,
                                 didCompleteWith action: EKEventViewAction) {
            done()
        }
    }
}
