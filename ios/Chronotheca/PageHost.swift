import SwiftUI
import UIKit

/// Страница дня или календаря в своей рамке.
///
/// Прежде это была книга системы с загибом листа (P178, P266, P475, P485):
/// лист загибался под пальцем, по стрелкам и по дороге домой. Загиб убран
/// (P779): разделы меняются свайпом, а следующий день или месяц просто
/// встаёт на место. Рамка UIKit оставлена ради одного: страница не
/// подбирается ни под клавиатуру, ни под края экрана.
/// Под клавиатуру — иначе весь экран вместе с шестерёнкой и нижними
/// разделами вздрагивает, едва человек ставит курсор. Под края — иначе
/// календарь, наезжая сверху, проходит под часами и вырезом камеры:
/// страница отступает от них, а у места отступ снимается, и текст прыгает
/// в самом конце хода. Своё место на экране страница получает от оболочки
/// (решение P191).
struct PageHost<Content: View>: UIViewControllerRepresentable {

    let content: () -> Content

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = UIColor(Look.chrome)
        host.view.isOpaque = true
        host.safeAreaRegions = []
        return host
    }

    func updateUIViewController(_ host: UIHostingController<Content>, context: Context) {
        host.rootView = content()
    }
}
