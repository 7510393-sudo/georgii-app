import SwiftUI
import UIKit

/// Обложка нижней строки, строки над клавиатурой и «＋» (P751): при старой
/// бумаге — кожаный переплёт (P745), без неё — крафт-картон (P297) с ровным
/// верхним краем вместо рваного.
struct BarCover: View {
    /// Кромка по верху — у строк; у «＋» её нет.
    var edged = true
    @AppStorage(Prefs.plainPast) private var plainPast = false
    /// Гамма меняется — картон перекрашивается (P498).
    @AppStorage(Prefs.calendarTint) private var palette = "distance"

    var body: some View {
        if plainPast {
            ZStack(alignment: .top) {
                KraftPaper()
                if edged {
                    Rectangle().fill(Look.kraftEdge.opacity(0.7)).frame(height: 1)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        } else {
            LeatherCover(stitched: edged)
        }
    }
}

/// Цвета значков и открытого раздела на обложке (P751): на коже — свои
/// (`Leather`), на крафте — прежние чернила гаммы и голубая рамка.
enum BarInk {
    static func ink(_ plain: Bool) -> Color { plain ? Look.kraftInk : Leather.ink }
    static func lit(_ plain: Bool) -> Color { plain ? Look.accent : Leather.lit }
    static func pad(_ plain: Bool) -> Color { plain ? Look.tabLit : Leather.pad }
    static func frame(_ plain: Bool) -> Color { plain ? Look.accent.opacity(0.75) : Leather.lit.opacity(0.6) }
    static func rim(_ plain: Bool) -> Color { plain ? Look.kraftEdge.opacity(0.55) : Leather.rim }
}

/// Крафт-картон (P297): волокна и крапины поверх цвета гаммы.
struct KraftPaper: View {
    var body: some View {
        ZStack {
            Look.kraft
            Image(uiImage: KraftPaper.fibre)
                .resizable(resizingMode: .tile)
        }
    }

    /// Волокна картона: крапины и короткие волоски, светлые и тёмные.
    /// Узор один и тот же при каждом запуске (P114).
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

/// Кожаный переплёт (P745, выбор автора; вместо крафта с оторванным краем
/// P297): нижняя строка разделов — край обложки дневника, на которой лежат
/// страницы. Светлая седельная кожа с морщинками и потёртостями (P748, P749), ровный край со
/// скруглённой кромкой и крупной коричневой строчкой-швом вдоль него; значки —
/// тёмными чернилами. Рваные края остаются только у страниц: строка не лист,
/// а то, на чём листы лежат.
struct LeatherCover: View {
    /// Строчка вдоль верхнего края — у нижней строки и у строки над
    /// клавиатурой; у кнопки «＋» её нет.
    var stitched = true

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Leather.top, Leather.base, Leather.deep],
                           startPoint: .top, endPoint: .bottom)
            Image(uiImage: Leather.grain)
                .resizable(resizingMode: .tile)
            if stitched {
                VStack(spacing: 0) {
                    // Скруглённая кромка: тёмная черта по краю и светлый
                    // блик под ней, как у подвёрнутой кожи.
                    Rectangle().fill(Leather.rim).frame(height: 1)
                    Rectangle().fill(Leather.sheen).frame(height: 1)
                    // Тень от страниц, лежащих сверху.
                    LinearGradient(colors: [.black.opacity(0.22), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 5)
                    Spacer(minLength: 0)
                }
                Stitch()
                    .stroke(Leather.thread, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, dash: [8, 5]))
                    .frame(height: 1)
                    // Во всю ширину, до самого края экрана (P750).
                    .padding(.horizontal, -4)
                    .padding(.top, Leather.stitchInset)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Цвета и зернь кожи переплёта (P745). Кожа одна во всех гаммах и в
/// тёмной теме. Светлая седельная кожа (P748: «более светлого цвета…
/// оставить неинвертированные значки»): значки и надписи — тёмными
/// чернилами, как на бумаге, а не золотом.
enum Leather {
    static let top = Color(red: 0.72, green: 0.53, blue: 0.34)
    static let base = Color(red: 0.64, green: 0.46, blue: 0.28)
    static let deep = Color(red: 0.55, green: 0.38, blue: 0.22)
    static let rim = Color(red: 0.36, green: 0.23, blue: 0.12)
    static let sheen = Color(red: 0.86, green: 0.71, blue: 0.52).opacity(0.7)
    /// Нить — коричневая (P749), темнее кожи.
    static let thread = Color(red: 0.30, green: 0.17, blue: 0.07).opacity(0.9)
    /// Значки и надписи — тёмные чернила.
    static let ink = Color(red: 0.20, green: 0.12, blue: 0.06)
    /// Открытый раздел — ещё темнее, на светлой подушке.
    static let lit = Color(red: 0.12, green: 0.07, blue: 0.03)
    static let pad = Color(red: 0.98, green: 0.92, blue: 0.80).opacity(0.38)
    /// Насколько строчка ниже края — посередине полосы над значками (P746).
    static let stitchInset: CGFloat = 4
    /// Высота полосы над значками у нижней строки и у строки над
    /// клавиатурой — место под кромку и строчку, чтобы строчка не шла по
    /// значкам (P746; прежде — глубина зубцов рваного края, P517).
    static let lip: CGFloat = 9
    static let uiBase = UIColor(red: 0.64, green: 0.46, blue: 0.28, alpha: 1)

    /// Фактура кожи (P749: «не пупырышки, а линии и потёртости»;
    /// бугорки P748 убраны): мягкие светлые потёртости и тёмные пятна
    /// тона, сеть тонких морщинок — у длинных светлый блик рядом, как у
    /// вдавленной складки (свет слева сверху, P670), — и редкие светлые
    /// царапины. Каждый след рисуется и со сдвигом на сторону плитки — шва
    /// нет. Узор один и тот же при каждом запуске (P114).
    static let grain: UIImage = {
        let side: CGFloat = 240
        var seed: UInt64 = 0x1EA7_4E12
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
        }
        let tile = CGRect(x: 0, y: 0, width: side, height: side)
        return UIGraphicsImageRenderer(size: tile.size).image { ctx in
            let cg = ctx.cgContext
            func wrapped(_ around: CGPoint, reach: CGFloat, _ draw: (CGPoint) -> Void) {
                for dx in [-side, 0, side] { for dy in [-side, 0, side] {
                    let at = CGPoint(x: around.x + dx, y: around.y + dy)
                    if tile.insetBy(dx: -reach, dy: -reach).contains(at) { draw(at) }
                } }
            }
            let space = CGColorSpaceCreateDeviceRGB()
            // Пятно: мягкий овал, тающий к краю.
            func patch(_ at: CGPoint, w: CGFloat, h: CGFloat, turn: CGFloat, color: UIColor) {
                guard let gradient = CGGradient(colorsSpace: space,
                                                colors: [color.cgColor, color.withAlphaComponent(0).cgColor] as CFArray,
                                                locations: [0, 1]) else { return }
                cg.saveGState()
                cg.translateBy(x: at.x, y: at.y)
                cg.rotate(by: turn)
                cg.scaleBy(x: w, y: h)
                cg.drawRadialGradient(gradient, startCenter: .zero, startRadius: 0,
                                      endCenter: .zero, endRadius: 1, options: [])
                cg.restoreGState()
            }
            // Тёмные пятна тона.
            for _ in 0..<10 {
                let at = CGPoint(x: next() * side, y: next() * side)
                let w = 30 + next() * 50, h = 14 + next() * 26, turn = next() * .pi
                let alpha = 0.06 + next() * 0.06
                wrapped(at, reach: w) { patch($0, w: w, h: h, turn: turn,
                                              color: UIColor(red: 0.30, green: 0.18, blue: 0.08, alpha: alpha)) }
            }
            // Светлые потёртости — вытянутые, вдоль строки.
            for _ in 0..<12 {
                let at = CGPoint(x: next() * side, y: next() * side)
                let w = 18 + next() * 40, h = 4 + next() * 10, turn = (next() - 0.5) * 0.8
                let alpha = 0.10 + next() * 0.12
                wrapped(at, reach: w) { patch($0, w: w, h: h, turn: turn,
                                              color: UIColor(red: 0.93, green: 0.80, blue: 0.62, alpha: alpha)) }
            }
            cg.setLineCap(.round)
            // Линия-морщинка: изогнутая, иногда с бликом рядом.
            func crease(_ a: CGPoint, length: CGFloat, angle: CGFloat, bend: CGFloat,
                        width: CGFloat, dark: CGFloat, lit: Bool) {
                let b = CGPoint(x: a.x + cos(angle) * length, y: a.y + sin(angle) * length)
                let c = CGPoint(x: (a.x + b.x) / 2 - sin(angle) * bend, y: (a.y + b.y) / 2 + cos(angle) * bend)
                let line = UIBezierPath()
                line.move(to: a); line.addQuadCurve(to: b, controlPoint: c)
                line.lineWidth = width
                UIColor(red: 0.20, green: 0.11, blue: 0.04, alpha: dark).setStroke()
                line.stroke()
                if lit {
                    line.apply(CGAffineTransform(translationX: 0.6, y: 0.7))
                    line.lineWidth = width * 0.8
                    UIColor(red: 0.95, green: 0.84, blue: 0.68, alpha: dark * 0.7).setStroke()
                    line.stroke()
                }
            }
            // Сеть тонких морщинок: короткие, по нескольку в одну сторону.
            for _ in 0..<70 {
                let base = CGPoint(x: next() * side, y: next() * side)
                let angle = next() * .pi
                for _ in 0..<(2 + Int(next() * 3)) {
                    let a = CGPoint(x: base.x + (next() - 0.5) * 10, y: base.y + (next() - 0.5) * 10)
                    let length = 4 + next() * 9, bend = (next() - 0.5) * 3
                    let turn = angle + (next() - 0.5) * 0.7
                    let dark = 0.10 + next() * 0.10
                    wrapped(a, reach: 16) { crease($0, length: length, angle: turn, bend: bend,
                                                   width: 0.45, dark: dark, lit: false) }
                }
            }
            // Длинные складки с бликом.
            for _ in 0..<9 {
                let a = CGPoint(x: next() * side, y: next() * side)
                let length = 22 + next() * 40, angle = (next() - 0.5) * 1.2, bend = (next() - 0.5) * 10
                let dark = 0.16 + next() * 0.08
                wrapped(a, reach: 70) { crease($0, length: length, angle: angle, bend: bend,
                                               width: 0.8, dark: dark, lit: true) }
            }
            // Светлые царапины.
            for _ in 0..<14 {
                let a = CGPoint(x: next() * side, y: next() * side)
                let length = 8 + next() * 22, angle = next() * .pi
                let end = CGPoint(x: a.x + cos(angle) * length, y: a.y + sin(angle) * length)
                let alpha = 0.12 + next() * 0.12
                wrapped(a, reach: 32) { at in
                    let line = UIBezierPath()
                    line.move(to: at)
                    line.addLine(to: CGPoint(x: end.x - a.x + at.x, y: end.y - a.y + at.y))
                    line.lineWidth = 0.5
                    UIColor(red: 0.96, green: 0.87, blue: 0.72, alpha: alpha).setStroke()
                    line.stroke()
                }
            }
        }
    }()
}

/// Строчка вдоль края переплёта — прямая через всю ширину.
private struct Stitch: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        return p
    }
}
