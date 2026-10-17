import SwiftUI
import UIKit

/// Крафт-картон нижней строки разделов (P297).
///
/// Строка — обложка блокнота: одна и та же во все дни, с волокнами
/// картона и неровным, будто оторванным верхним краем. Рисованные значки
/// на ней — как штампы тёмно-коричневыми чернилами.
struct KraftPaper: View {
    /// Гамма меняется — картон перекрашивается (P498).
    @AppStorage(Prefs.calendarTint) private var scheme = "distance"

    var body: some View {
        ZStack {
            Look.kraft
            Image(uiImage: KraftPaper.fibre)
                .resizable(resizingMode: .tile)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Волокна картона: крапины и короткие волоски, светлые и тёмные.
    /// Узор один и тот же при каждом запуске — снимки не должны
    /// различаться от раза к разу (P114).
    static let fibre: UIImage = {
        let side: CGFloat = 180
        var seed: UInt64 = 0xC4AF_7297
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
        }
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            for _ in 0..<900 {
                let x = next() * side, y = next() * side
                let r = 0.4 + next() * 0.9
                let dark = next() < 0.55
                (dark ? UIColor(red: 0.35, green: 0.24, blue: 0.12, alpha: 0.06 + next() * 0.06)
                      : UIColor(white: 1, alpha: 0.10 + next() * 0.10)).setFill()
                ctx.cgContext.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
            for _ in 0..<90 {
                let x = next() * side, y = next() * side
                let angle = (next() - 0.5) * 0.9
                let length = 4 + next() * 10
                let fibre = UIBezierPath()
                fibre.move(to: CGPoint(x: x, y: y))
                fibre.addQuadCurve(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length),
                                   controlPoint: CGPoint(x: x + cos(angle + 0.5) * length / 2,
                                                         y: y + sin(angle + 0.5) * length / 2))
                fibre.lineWidth = 0.5
                (next() < 0.6 ? UIColor(red: 0.30, green: 0.20, blue: 0.10, alpha: 0.10)
                              : UIColor(white: 1, alpha: 0.18)).setStroke()
                fibre.stroke()
            }
        }
    }()
}

/// Неровный верхний край — картон оторван, а не отрезан (P297).
///
/// Зубцы мелкие и неправильные, но всегда одни и те же: край не должен
/// меняться от поворота или перерисовки (P113).
struct TornEdge: Shape {
    /// Глубина зубцов (P517: вдвое больше прежних 3,5 — края стали заметнее).
    static let depth: CGFloat = 7

    /// Сами зубцы — общие для заливки и обводки, чтобы обе совпадали
    /// точь-в-точь (P324).
    static func teeth(in rect: CGRect) -> [CGPoint] {
        var seed: UInt64 = 0x70_2E_ED_6E
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
        }
        var points: [CGPoint] = [CGPoint(x: rect.minX, y: rect.minY + next() * depth)]
        var x = rect.minX
        while x < rect.maxX {
            x += 3.5 + next() * 8
            points.append(CGPoint(x: min(x, rect.maxX), y: rect.minY + next() * depth))
        }
        return points
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        // По одной точке, не addLines: у неё своя, отдельная от уже
        // начатого пути точка старта — «улица без начала» получала левый
        // низ сама по себе, а зубцы съезжали в свой кусок, и закрытие пути
        // тянуло между ними одну косую черту через всю строку (P328).
        for point in Self.teeth(in: rect) { p.addLine(to: point) }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

/// Только сама рваная черта — без боков и низа. Обводка закрытой фигуры
/// `TornEdge` рисовала ещё и прямую линию понизу: она дублировала
/// неровный край серой чертой сразу под ним (P324).
struct TornEdgeLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let teeth = TornEdge.teeth(in: rect)
        if let first = teeth.first {
            p.move(to: first)
            for point in teeth.dropFirst() { p.addLine(to: point) }
        }
        return p
    }
}

/// Нижний край верхней строки — вторая половина той же рваной бумаги
/// (P517). Зубцы те же, что у верхнего края нижней строки, и в том же
/// направлении: где у верхней половины выступ вниз, у нижней — выемка, и
/// два куска сложились бы по линии разрыва.
struct TornEdgeBottom: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        let drop = rect.height - TornEdge.depth
        for point in TornEdge.teeth(in: rect) {
            p.addLine(to: CGPoint(x: point.x, y: point.y + drop))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

/// Только рваная черта нижнего края верхней строки.
struct TornEdgeBottomLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let drop = rect.height - TornEdge.depth
        let teeth = TornEdge.teeth(in: rect)
        if let first = teeth.first {
            p.move(to: CGPoint(x: first.x, y: first.y + drop))
            for point in teeth.dropFirst() { p.addLine(to: CGPoint(x: point.x, y: point.y + drop)) }
        }
        return p
    }
}

/// Строка вложений — нижний край листа этого дня: цвет страницы, на тон
/// гуще, с той же бумажной фактурой (P297).
struct DayStrip: View {
    let date: Date

    var body: some View {
        ZStack {
            Ru.tint(date)
            Color.black.opacity(0.06)
            Image(uiImage: PageTexture.grain)
                .resizable(resizingMode: .tile)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
