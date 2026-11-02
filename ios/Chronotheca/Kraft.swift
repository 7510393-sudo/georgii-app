import SwiftUI

/// Кожаный переплёт (P745, выбор автора; вместо крафта с оторванным краем
/// P297): нижняя строка разделов — край обложки дневника, на которой лежат
/// страницы. Тёмно-коричневая кожа с мелкой зернью, ровный край со
/// скруглённой кромкой и строчкой-швом вдоль него; значки — тиснением
/// светлым золотом. Рваные края остаются только у страниц: строка не лист,
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
                    LinearGradient(colors: [.black.opacity(0.28), .clear],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 5)
                    Spacer(minLength: 0)
                }
                Stitch()
                    .stroke(Leather.thread, style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [4.5, 3.5]))
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
/// тёмной теме — она и так тёмная.
enum Leather {
    static let top = Color(red: 0.36, green: 0.24, blue: 0.15)
    static let base = Color(red: 0.29, green: 0.19, blue: 0.12)
    static let deep = Color(red: 0.22, green: 0.14, blue: 0.09)
    static let rim = Color(red: 0.14, green: 0.09, blue: 0.05)
    static let sheen = Color(red: 0.55, green: 0.40, blue: 0.27).opacity(0.55)
    static let thread = Color(red: 0.84, green: 0.70, blue: 0.47).opacity(0.75)
    /// Тиснение значков и надписей — светлое золото.
    static let ink = Color(red: 0.88, green: 0.76, blue: 0.54)
    /// Открытый раздел — ярче и на светлой подушке.
    static let lit = Color(red: 0.98, green: 0.88, blue: 0.66)
    static let pad = Color(red: 0.98, green: 0.88, blue: 0.66).opacity(0.14)
    /// Насколько строчка ниже края — посередине полосы над значками (P746).
    static let stitchInset: CGFloat = 3.5
    /// Высота полосы над значками у нижней строки и у строки над
    /// клавиатурой — место под кромку и строчку, чтобы строчка не шла по
    /// значкам (P746; прежде — глубина зубцов рваного края, P517).
    static let lip: CGFloat = 8
    static let uiBase = UIColor(red: 0.29, green: 0.19, blue: 0.12, alpha: 1)

    /// Зернь кожи: мелкие поры — тёмные точки неправильной формы — и редкие
    /// светлые блики между ними. Узор один и тот же при каждом запуске —
    /// снимки не должны различаться от раза к разу (P114).
    static let grain: UIImage = {
        let side: CGFloat = 160
        var seed: UInt64 = 0x1EA7_4E12
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(seed >> 33) / CGFloat(UInt64(1) << 31)
        }
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { ctx in
            let cg = ctx.cgContext
            for _ in 0..<1400 {
                let x = next() * side, y = next() * side
                let w = 0.6 + next() * 1.6, h = 0.5 + next() * 1.2
                UIColor(red: 0.08, green: 0.05, blue: 0.02, alpha: 0.10 + next() * 0.14).setFill()
                cg.fillEllipse(in: CGRect(x: x, y: y, width: w, height: h))
            }
            for _ in 0..<500 {
                let x = next() * side, y = next() * side
                let r = 0.4 + next() * 0.8
                UIColor(red: 0.80, green: 0.62, blue: 0.44, alpha: 0.05 + next() * 0.07).setFill()
                cg.fillEllipse(in: CGRect(x: x, y: y, width: r, height: r))
            }
            // Мягкие морщинки кожи.
            for _ in 0..<40 {
                let x = next() * side, y = next() * side
                let length = 6 + next() * 14
                let angle = (next() - 0.5) * .pi
                let crease = UIBezierPath()
                crease.move(to: CGPoint(x: x, y: y))
                crease.addQuadCurve(to: CGPoint(x: x + cos(angle) * length, y: y + sin(angle) * length),
                                    controlPoint: CGPoint(x: x + cos(angle + 0.6) * length / 2,
                                                          y: y + sin(angle + 0.6) * length / 2))
                crease.lineWidth = 0.6
                UIColor(red: 0.06, green: 0.04, blue: 0.02, alpha: 0.12).setStroke()
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
