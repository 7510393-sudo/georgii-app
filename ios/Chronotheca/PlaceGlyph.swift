import SwiftUI
import UIKit

/// Значок места для списков — тот же рисунок, что на карте (P404).
struct GlyphIcon: View {
    var size: CGFloat = 13

    var body: some View {
        Image(uiImage: GlyphArt.image)
            .resizable()
            .scaledToFit()
            .frame(width: size * 2, height: size * 2)
    }
}

/// Рисунок значка места: стрелка вниз, белая с тёмным контуром (P409,
/// единственная — P609).
enum GlyphArt {

    /// Значок на прозрачном поле 26 × 26.
    static let image: UIImage = {
        let side = PlaceLabelSize.dot + 2
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            draw(in: CGRect(x: 1, y: 1, width: PlaceLabelSize.dot, height: PlaceLabelSize.dot))
        }
    }()

    static func draw(in circle: CGRect) {
        arrow(in: circle.insetBy(dx: 2, dy: 1))
    }

    /// Своя стрелка, на десятую уже системной и с острыми углами.
    private static func arrow(in r: CGRect) {
        let mid = r.midX
        let shaft = r.width * 0.15, head = r.width * 0.36
        let top = r.minY + 1, waist = r.minY + r.height * 0.48, tip = r.maxY - 0.5
        let p = UIBezierPath()
        p.move(to: CGPoint(x: mid - shaft, y: top))
        p.addLine(to: CGPoint(x: mid + shaft, y: top))
        p.addLine(to: CGPoint(x: mid + shaft, y: waist))
        p.addLine(to: CGPoint(x: mid + head, y: waist))
        p.addLine(to: CGPoint(x: mid, y: tip))
        p.addLine(to: CGPoint(x: mid - head, y: waist))
        p.addLine(to: CGPoint(x: mid - shaft, y: waist))
        p.close()
        p.lineJoinStyle = .miter
        p.miterLimit = 6
        p.lineWidth = 2.4
        UIColor(white: 0.1, alpha: 0.9).setStroke()
        p.stroke()
        UIColor.white.setFill()
        p.fill()
    }
}

/// Размер кружка значка — общий для карты и списков.
enum PlaceLabelSize {
    static let dot: CGFloat = 24
}
