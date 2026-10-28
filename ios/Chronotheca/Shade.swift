import SwiftUI
import UIKit

/// Тень, нарисованная заранее (P675): одна картинка, растянутая по фигуре,
/// вместо размытия `.shadow(radius:)`, которое пересчитывается на каждом
/// кадре хода (листки, плашки). Картинка рисуется один раз на каждый вид
/// тени и лежит в памяти.
struct PaintedShadow: View {

    /// Как у `.shadow`: размытие, сдвиг и густота.
    let radius: CGFloat
    var corner: CGFloat = 0
    var x: CGFloat = 0
    var y: CGFloat = 0
    var opacity: Double = 0.3

    /// Докуда достаёт размытие за край фигуры.
    private var reach: CGFloat { ceil(radius * 2) }

    var body: some View {
        let inset = reach + corner
        Image(uiImage: Self.image(radius: radius, corner: corner, opacity: opacity))
            .resizable(capInsets: EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset),
                       resizingMode: .stretch)
            .padding(-reach)
            .offset(x: x, y: y)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private static var cache: [String: UIImage] = [:]

    /// Только тень, без самой фигуры: фигура рисуется далеко за картинкой,
    /// в картинку попадает одна её тень. Середина — пара точек, их и тянут.
    private static func image(radius: CGFloat, corner: CGFloat, opacity: Double) -> UIImage {
        let key = "\(radius)/\(corner)/\(opacity)"
        if let hit = cache[key] { return hit }
        let reach = ceil(radius * 2)
        let side = (reach + corner) * 2 + 2
        let far: CGFloat = 4000
        let img = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            let cg = ctx.cgContext
            cg.setShadow(offset: CGSize(width: -far, height: 0), blur: radius * 2,
                         color: UIColor.black.withAlphaComponent(opacity).cgColor)
            UIColor.black.setFill()
            let rect = CGRect(x: reach + far, y: reach, width: side - reach * 2, height: side - reach * 2)
            UIBezierPath(roundedRect: rect, cornerRadius: corner).fill()
        }
        let result = img.resizableImage(withCapInsets: .zero)
        cache[key] = result
        return result
    }
}
