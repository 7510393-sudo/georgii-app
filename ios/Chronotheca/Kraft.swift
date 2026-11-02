import SwiftUI

/// Кожаный переплёт (P745, выбор автора; вместо крафта с оторванным краем
/// P297): нижняя строка разделов — край обложки дневника, на которой лежат
/// страницы. Светлая седельная кожа с крупной зернью (P748), ровный край со
/// скруглённой кромкой и крупной строчкой-швом вдоль него; значки —
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
                    .padding(.horizontal, 8)
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
    static let thread = Color(red: 0.96, green: 0.90, blue: 0.76).opacity(0.9)
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

    /// Зернь кожи (P748: «добавить фактуру кожи»): крупные бугорки —
    /// каждый с тёмной бороздкой снизу-справа и светлым бликом сверху-слева
    /// (свет слева сверху, P670), между ними мелкие поры и морщинки. Узор
    /// один и тот же при каждом запуске — снимки не должны различаться
    /// от раза к разу (P114).
    static let grain: UIImage = {
        let side: CGFloat = 200
        var seed: UInt64 = 0x1EA7_4E12
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
        }
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            let cg = ctx.cgContext
            // Каждое пятно рисуется ещё раз со сдвигом на сторону плитки —
            // у шва плитки узор не обрывается.
            func each(_ rect: CGRect, _ draw: (CGRect) -> Void) {
                for dx in [-side, 0, side] { for dy in [-side, 0, side] {
                    let moved = rect.offsetBy(dx: dx, dy: dy)
                    if moved.intersects(CGRect(x: 0, y: 0, width: side, height: side)) { draw(moved) }
                } }
            }
            // Бугорки.
            for _ in 0..<520 {
                let w = 3.0 + next() * 4.5, h = 2.6 + next() * 3.8
                let box = CGRect(x: next() * side, y: next() * side, width: w, height: h)
                each(box) { r in
                    UIColor(red: 0.20, green: 0.11, blue: 0.04, alpha: 0.16 + next() * 0.10).setStroke()
                    let groove = UIBezierPath(ovalIn: r)
                    groove.lineWidth = 0.7
                    cg.saveGState()
                    cg.clip(to: CGRect(x: r.midX - 0.5, y: r.midY - 0.5, width: r.width, height: r.height))
                    groove.stroke()
                    cg.restoreGState()
                    UIColor(red: 0.96, green: 0.84, blue: 0.66, alpha: 0.14 + next() * 0.10).setFill()
                    cg.fillEllipse(in: CGRect(x: r.minX + r.width * 0.18, y: r.minY + r.height * 0.15,
                                              width: r.width * 0.45, height: r.height * 0.4))
                }
            }
            // Мелкие поры.
            for _ in 0..<1600 {
                let w = 0.5 + next() * 1.1, h = 0.5 + next() * 0.9
                let box = CGRect(x: next() * side, y: next() * side, width: w, height: h)
                let alpha = 0.14 + next() * 0.16
                each(box) { r in
                    UIColor(red: 0.16, green: 0.09, blue: 0.03, alpha: alpha).setFill()
                    cg.fillEllipse(in: r)
                }
            }
            // Морщинки.
            for _ in 0..<45 {
                let x = next() * side, y = next() * side
                let length = 8 + next() * 18
                let angle = (next() - 0.5) * .pi
                let crease = UIBezierPath()
                crease.move(to: CGPoint(x: x, y: y))
                crease.addQuadCurve(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length),
                                    controlPoint: CGPoint(x: x + cos(angle + 0.6) * length / 2,
                                                          y: y + sin(angle + 0.6) * length / 2))
                crease.lineWidth = 0.7
                UIColor(red: 0.18, green: 0.10, blue: 0.04, alpha: 0.16).setStroke()
                crease.stroke()
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
