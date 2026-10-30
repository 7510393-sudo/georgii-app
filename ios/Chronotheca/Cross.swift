import SwiftUI
import UIKit

/// Крестик «удалить» у вложения — один на всё приложение (P713).
///
/// Снимок, видео, голос, файл и точку подержали и отпустили, не уводя
/// пальца, — где бы они ни лежали: в тексте записи, в ряду внизу страницы,
/// в плане под делом, в заголовке дня или в ответе «Как прошло?». Дальше
/// всё одинаково, как у значка на экране «Домой»: экран чуть темнеет,
/// предмет поверх него в синей рамке и чуть крупнее, на его верхнем правом
/// углу — снаружи — красный крестик; касание мимо крестика — всё как было.
/// Прежде у каждого места был свой крестик: у одних внутри рамки, у
/// других снаружи, у третьих другой рисунок, и убирались они по-разному.
enum Cross {

    /// Покрывало поверх окна, на нём — копия предмета и крестик.
    private static var veil: UIControl?
    /// Что сделать, когда покрывало убрали касанием мимо крестика.
    private static var dismissed: (() -> Void)?

    /// Показать крестик у предмета.
    ///
    /// `frame` — где предмет в окне. `picture` — его картинка (так у
    /// вложений в тексте); без неё берётся снимок этого места экрана.
    /// `chip` — кнопочка посреди фразы: она круглая, растёт сильнее, и
    /// крестик встаёт справа от неё, а не на углу.
    static func show(at frame: CGRect, picture: UIImage? = nil, chip: Bool = false,
                     label: String, onCross: @escaping () -> Void,
                     onDismiss: (() -> Void)? = nil) {
        guard let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first,
              frame.width > 0, frame.height > 0
        else { return }
        hide(silently: true)
        Feel.light()

        let cover = UIControl(frame: window.bounds)
        cover.backgroundColor = UIColor.black.withAlphaComponent(0.06)
        cover.addAction(UIAction { _ in hide(silently: false) }, for: .touchDown)

        // Копия предмета поверх покрывала: его не затемняет.
        let copy: UIView
        if let picture {
            copy = UIImageView(image: picture)
            copy.bounds = CGRect(origin: .zero, size: frame.size)
        } else if let shot = window.resizableSnapshotView(from: frame, afterScreenUpdates: false,
                                                          withCapInsets: .zero) {
            copy = shot
        } else {
            copy = UIView(frame: CGRect(origin: .zero, size: frame.size))
        }
        copy.center = CGPoint(x: frame.midX, y: frame.midY)
        copy.clipsToBounds = false
        // Синяя кромка — та же, что у поднятого дела (P374).
        copy.layer.borderColor = UIColor(Look.glow).cgColor
        copy.layer.borderWidth = chip ? 2 : 3
        copy.layer.cornerRadius = chip ? frame.height / 2 : 8
        copy.layer.shadowOpacity = 0.25
        copy.layer.shadowRadius = 6
        copy.layer.shadowOffset = CGSize(width: 2, height: 2)
        cover.addSubview(copy)
        // Снимок и так крупный — он лишь чуть приподнимается (P392).
        let grow: CGFloat = chip ? 1.4 : 1.05

        let cross = UIControl(frame: CGRect(x: 0, y: 0, width: 56, height: 56))
        let mark = UIImageView(image: image)
        mark.frame = CGRect(x: 6, y: 6, width: 44, height: 44)
        mark.isUserInteractionEnabled = false
        cross.addSubview(mark)
        cross.layer.shadowColor = UIColor.black.cgColor
        cross.layer.shadowOpacity = 0.3
        cross.layer.shadowRadius = 3
        cross.layer.shadowOffset = CGSize(width: 1, height: 1)
        cross.isAccessibilityElement = true
        cross.accessibilityTraits = .button
        cross.accessibilityLabel = label
        let right = window.bounds.maxX - 10
        if chip {
            cross.center = CGPoint(x: min(frame.midX + frame.width * grow / 2 + 22, right),
                                   y: frame.midY)
        } else {
            // На верхнем правом углу, снаружи — как у значка на экране «Домой».
            cross.center = CGPoint(x: min(frame.midX + frame.width * grow / 2, right),
                                   y: frame.midY - frame.height * grow / 2 + 4)
        }
        cross.addAction(UIAction { _ in
            hide(silently: true)
            Feel.light()
            onCross()
        }, for: .touchUpInside)
        cross.alpha = 0
        cover.addSubview(cross)

        window.addSubview(cover)
        veil = cover
        dismissed = onDismiss
        UIView.animate(withDuration: 0.15) {
            copy.transform = CGAffineTransform(scaleX: grow, y: grow)
            cross.alpha = 1
        }
    }

    /// Крестик сейчас на экране.
    static var shown: Bool { veil != nil }

    /// Убрать крестик. `silently` — без отклика «убрали мимо крестика».
    static func hide(silently: Bool = true) {
        veil?.removeFromSuperview()
        veil = nil
        let done = dismissed
        dismissed = nil
        if !silently { done?() }
    }

    /// Крестик: белая кайма, красный круг, белый крест.
    static let image: UIImage = UIGraphicsImageRenderer(size: CGSize(width: 44, height: 44)).image { _ in
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(x: 2, y: 2, width: 40, height: 40)).fill()
        UIColor(Look.pin).setFill()
        UIBezierPath(ovalIn: CGRect(x: 6, y: 6, width: 32, height: 32)).fill()
        let x = UIBezierPath()
        x.move(to: CGPoint(x: 16, y: 16)); x.addLine(to: CGPoint(x: 28, y: 28))
        x.move(to: CGPoint(x: 28, y: 16)); x.addLine(to: CGPoint(x: 16, y: 28))
        x.lineWidth = 3.4
        x.lineCapStyle = .round
        UIColor.white.setStroke()
        x.stroke()
    }

    /// Сколько держать палец, чтобы взять вложение или вызвать крестик, —
    /// везде одинаково (P713): прежде в тексте 0,25 с, в ряду и в плане
    /// 0,3 с, в ответе «Как прошло?» 0,45 с.
    static let hold: TimeInterval = 0.25
}
