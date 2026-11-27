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

/// Рисунок значка места: стрелка вниз (P409, единственная — P609). С P1098
/// (автор: «изящнее; может, жёлтая, но мельче — чтобы на больших объёмах не
/// тянула внимание и не загораживала карту, но была заметна, как в других
/// приложениях») — тоньше и мельче, тёплая жёлтая с тонким тёмным контуром
/// и лёгкой тенью: так метки делают карты Apple и Google — насыщенный цвет,
/// который карта сама не использует, тонкая кромка и тень, чтобы метка
/// читалась и на светлой карте, и на спутнике. Прежде — белая с толстым
/// контуром, 24 точки.
enum GlyphArt {

    /// Значок на прозрачном поле.
    static let image: UIImage = {
        let side = PlaceLabelSize.dot + 2
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { _ in
            draw(in: CGRect(x: 1, y: 1, width: PlaceLabelSize.dot, height: PlaceLabelSize.dot))
        }
    }()

    static func draw(in circle: CGRect) {
        arrow(in: circle.insetBy(dx: 3, dy: 1))
    }

    /// Метка вдали (P1099, автор: «вдали — маленькие точки»): жёлтая точка
    /// с той же кромкой и тенью, на месте середины стрелки.
    static func drawFar(in circle: CGRect) {
        let round = UIBezierPath(ovalIn: CGRect(x: circle.midX - 4, y: circle.midY - 4, width: 8, height: 8))
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        context?.setShadow(offset: CGSize(width: 0, height: 0.6), blur: 1.2,
                           color: UIColor.black.withAlphaComponent(0.35).cgColor)
        fill.setFill()
        round.fill()
        context?.restoreGState()
        round.lineWidth = 1
        edge.setStroke()
        round.stroke()
    }

    /// Яркий жёлтый (P1100, автор: «более яркого цвета; сейчас какие-то
    /// морковно приглушённые»; было 0,98 · 0,77 · 0,20 с тёмно-коричневой
    /// кромкой) — заметен на зелени парков, сером городе и снимке со
    /// спутника; одинаков днём и ночью. Кромка — тёмно-оливковая, тоньше.
    static let fill = UIColor(red: 1.0, green: 0.87, blue: 0.08, alpha: 1)
    static let edge = UIColor(red: 0.36, green: 0.28, blue: 0.0, alpha: 0.85)

    /// Стрелка с узким древком и острым наконечником.
    private static func arrow(in r: CGRect) {
        let mid = r.midX
        let shaft = r.width * 0.12, head = r.width * 0.42
        let top = r.minY + 0.5, waist = r.minY + r.height * 0.5, tip = r.maxY - 0.5
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
        p.miterLimit = 8
        p.lineWidth = 1
        let context = UIGraphicsGetCurrentContext()
        context?.saveGState()
        // Лёгкая тень — метка лежит над картой, а не в ней.
        context?.setShadow(offset: CGSize(width: 0, height: 0.8), blur: 1.5,
                           color: UIColor.black.withAlphaComponent(0.35).cgColor)
        fill.setFill()
        p.fill()
        context?.restoreGState()
        edge.setStroke()
        p.stroke()
    }
}

/// Размер кружка значка — общий для карты и списков.
enum PlaceLabelSize {
    /// Мельче прежних 24 (P1098).
    static let dot: CGFloat = 20
}
