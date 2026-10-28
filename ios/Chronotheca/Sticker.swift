import SwiftUI

/// Приклеенная бумажка.
///
/// Свешивается с верхнего края, закрывая часть экрана: из-под неё видно,
/// где человек остался. Не отдельная страница и не лист снизу — канцелярский
/// стикер, приклеенный к стенке. Меню страницы на жёлтой бумаге, настройки
/// на голубой; порода одна, чтобы рука узнавала их одинаково.
/// С какого края приклеена бумажка. Отдельно от самой бумажки: обводке
/// эта сторона тоже нужна, а через обобщённый тип она не проходит.
enum StickerSide { case leading, trailing }

struct Sticker<Content: View>: View {

    @EnvironmentObject private var shell: Shell

    let side: StickerSide
    let title: String
    var paper: Color = Look.sticker
    var edge: Color = Look.stickerEdge
    /// Ширина бумажки. У настроек она больше: там живут пути и списки.
    var width: CGFloat = 262
    /// Высота листка, если она задана заранее (P669): листок настроек
    /// кончается над нижней строкой, и его низ не дорастает на глазах.
    var height: CGFloat? = nil
    let close: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: side == .trailing ? .topTrailing : .topLeading) {
            Color.black.opacity(0.001)
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
            sheet
        }
        // Появление и уход — не переходом, а тем, насколько листок вытянут
        // (P237): им управляет уголок.
    }

    /// Насколько листок ещё за краем: 1 — торчит один угол, 0 — весь виден.
    private var amount: CGFloat {
        shell.settingsPull ?? 0
    }

    private var sheet: some View {
        VStack(spacing: 0) {
            head
            content()
        }
        .frame(maxWidth: width)
        .frame(height: height, alignment: .top)
        // Содержимое — только в пределах листка (P669): прежде нижняя плашка
        // настроек выглядывала из-под листка поверх нижней строки. Обрезка
        // прямоугольником, не скруглённой фигурой (P497).
        .clipped()
        // Без обрезки по скруглённой фигуре (P497): она заставляла рисовать
        // весь листок отдельным слоем на каждом кадре выезда — листок шёл
        // ступеньками. Низ листка не доходит до скруглённого угла.
        .padding(.bottom, 8)
        // Тень — у одной простой фигуры под листком, а не у всего его
        // содержимого (P428): тень по сложному содержимому считается
        // заново на каждом кадре выезда, и длинный листок настроек
        // дёргался. Вид тот же.
        .background(shape.fill(paper).shadow(color: .black.opacity(0.32), radius: 14, y: 6))
        .overlay(StickerBorder(radius: 12, side: side).stroke(edge, lineWidth: 1))
        // Спрятанный листок стоит так, что его нижний угол — ровно уголок
        // над экраном; вытягивают его за этот угол (P237).
        .visualEffect { [amount, side] content, geo in
            let cornerW = Corner.size * 0.86
            let cornerH = Corner.size * 0.80
            let x = side == .leading ? cornerW - geo.size.width : geo.size.width - cornerW
            let y = cornerH - Corner.lift - geo.size.height
            return content.offset(x: x * amount, y: y * amount)
        }
        .padding(side == .trailing ? .leading : .trailing, 24)
    }

    private var shape: UnevenRoundedRectangle {
        side == .trailing
            ? UnevenRoundedRectangle(bottomLeadingRadius: 12)
            : UnevenRoundedRectangle(bottomTrailingRadius: 12)
    }

    private var head: some View {
        // Название слева, крестик справа — у обоих листков одинаково (P600;
        // прежде у настроек было зеркально).
        HStack(alignment: .top, spacing: 8) {
            label
            Spacer(minLength: 0)
            closeButton
        }
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) {
            Rectangle().fill(edge).frame(height: 1)
        }
    }

    /// Заголовок листка — крупно и чётко (P381): прежние мелкие бледные
    /// заглавные буквы читались с трудом.
    private var label: some View {
        Text(title)
            .font(Look.serif(21, weight: .semibold))
            .foregroundStyle(Look.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.top, 16)
            .padding(.horizontal, 14)
    }

    private var closeButton: some View {
        Button(action: close) {
            CloseMark()
                .frame(width: 44, height: 38)
        }
        .padding(.top, 12)
        .accessibilityLabel(T("Закрыть", "Close"))
    }
}

/// Крестик «закрыть» у настроек, меню страницы и «Подробностей» (P386):
/// толстый крест в кружке с чертой — прежний тонкий «✕» бледным цветом
/// терялся на бумаге.
struct CloseMark: View {
    var body: some View {
        Image(systemName: "xmark")
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(Look.ink)
            .frame(width: 32, height: 32)
            .background(Circle().fill(Look.ink.opacity(0.06)))
            .overlay(Circle().strokeBorder(Look.inkSoft.opacity(0.6), lineWidth: 1.3))
    }
}

/// Как бумажку тянут и отпускают: тяжело, без отскока — как экраны (P202).
extension Animation {
    static let pull = Animation.spring(response: 0.6, dampingFraction: 0.9)
    static let tuck = Animation.easeIn(duration: 0.28)
}

/// Обводка бумажки: низ и внутренний бок. Сверху и со своего края она
/// приклеена — там обводки нет.
struct StickerBorder: Shape {

    let radius: CGFloat
    var side: StickerSide = .trailing

    func path(in r: CGRect) -> Path {
        var p = Path()
        if side == .trailing {
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY - radius))
            p.addArc(center: CGPoint(x: r.minX + radius, y: r.maxY - radius), radius: radius,
                     startAngle: .degrees(180), endAngle: .degrees(90), clockwise: true)
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        } else {
            p.move(to: CGPoint(x: r.maxX, y: r.minY))
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - radius))
            p.addArc(center: CGPoint(x: r.maxX - radius, y: r.maxY - radius), radius: radius,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: r.minX, y: r.maxY))
        }
        return p
    }
}
