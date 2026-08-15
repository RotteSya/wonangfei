import SwiftUI

// MARK: - 窝囊费发放凭证 · shared voucher components
//
// The share cards are "official documents" issued by the fictional 窝囊费办公室:
// yellow-header memo, mono figures, sawtooth ticket edges, and a coral seal.
// Everything here is deterministic per day — re-rendering the same day must
// produce the identical voucher (no randomness at render time).

// MARK: Ticket edge

/// Rounded rectangle whose top and bottom edges are torn ticket sawtooth.
struct VoucherEdgeShape: Shape {
    var toothWidth: CGFloat = 14
    var toothHeight: CGFloat = 5

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let teeth = max(2, Int((rect.width / toothWidth).rounded(.down)))
        let step = rect.width / CGFloat(teeth)

        path.move(to: CGPoint(x: rect.minX, y: rect.minY + toothHeight))
        // Top edge: valleys between teeth pointing up.
        for i in 0..<teeth {
            let x0 = rect.minX + CGFloat(i) * step
            path.addLine(to: CGPoint(x: x0 + step / 2, y: rect.minY))
            path.addLine(to: CGPoint(x: x0 + step, y: rect.minY + toothHeight))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - toothHeight))
        // Bottom edge: mirrored teeth, right to left.
        for i in stride(from: teeth - 1, through: 0, by: -1) {
            let x0 = rect.minX + CGFloat(i) * step
            path.addLine(to: CGPoint(x: x0 + step / 2, y: rect.maxY))
            path.addLine(to: CGPoint(x: x0, y: rect.maxY - toothHeight))
        }
        path.closeSubpath()
        return path
    }
}

// MARK: Serial / document number

enum VoucherStationery {
    /// 「窝费发〔2026〕第227号」 — year + day-of-year, stable all day.
    static func documentNumber(for date: Date = Date()) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: date)
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        return "窝费发〔\(year)〕第\(day)号"
    }

    /// Deterministic pseudo-serial like NO.20260815-042 for the footer.
    static func serial(for date: Date = Date()) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        let mix = (y * 73 + m * 37 + d * 11) % 1000
        return String(format: "NO.%04d%02d%02d-%03d", y, m, d, mix)
    }

    static func dateLine(for date: Date = Date()) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        return "\(y) 年 \(m) 月 \(d) 日"
    }
}

// MARK: Conversion engine

/// 把窝囊费换算成打工人的硬通货。Unit choice is seeded by the calendar day so
/// the voucher never changes wording mid-day.
enum WNFConversion {
    struct Unit {
        var name: String
        var price: Double
        var counter: String
        var quip: String
    }

    static let units: [Unit] = [
        Unit(name: "蜜雪冰城柠檬水", price: 4, counter: "杯", quip: "快乐是按杯算的"),
        Unit(name: "瑞幸生椰拿铁", price: 9.9, counter: "杯", quip: "咖啡因回血成功"),
        Unit(name: "沙县蒸饺", price: 6, counter: "笼", quip: "碳水就是正义"),
        Unit(name: "麻辣烫自选", price: 15, counter: "碗", quip: "先涮为敬"),
        Unit(name: "便利店饭团", price: 5.5, counter: "个", quip: "工位速食之光"),
        Unit(name: "华莱士全鸡", price: 12, counter: "只", quip: "全鸡在手，委屈我有"),
        Unit(name: "地铁通勤", price: 3, counter: "趟", quip: "挣的钱够坐回去了"),
        Unit(name: "Switch 大作", price: 298, counter: "份", quip: "打工是为了打游戏"),
        Unit(name: "加油站 95 号", price: 8.2, counter: "升", quip: "油箱和心态一起加满")
    ]

    struct Result {
        var unit: Unit
        var count: Double

        var line: String {
            let countText = count >= 10
                ? "\(Int(count.rounded(.down)))"
                : String(format: "%.1f", count)
            return "\(unit.name) \(countText) \(unit.counter)"
        }
    }

    /// Deterministic pick: rotates the unit by day, prefers a unit whose count
    /// lands in a satisfying 1...99 range for the given amount.
    static func convert(amount: Double, date: Date = Date()) -> Result {
        let calendar = Calendar(identifier: .gregorian)
        let seed = (calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
            + calendar.component(.year, from: date)

        let ordered = (0..<units.count).map { units[(seed + $0) % units.count] }
        let best = ordered.first { amount / $0.price >= 1 && amount / $0.price < 100 }
            ?? ordered[0]
        return Result(unit: best, count: max(0, amount / best.price))
    }
}

// MARK: Header band

/// The yellow "红头文件" band, reimagined in brand yellow.
struct VoucherHeader: View {
    var title: String
    var subtitle: String
    var date: Date = Date()
    /// Extra room on the first row's trailing edge, for overlaid controls.
    var trailingInset: CGFloat = 0

    var body: some View {
        VStack(spacing: 5) {
            HStack(alignment: .center, spacing: 8) {
                Image("CowThreeQ")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 27, height: 27)

                Text("窝囊费办公室")
                    .font(WNFTheme.display(17))
                    .foregroundStyle(WNFTheme.inkFixed)
                    .tracking(2)

                Spacer(minLength: 6)

                if trailingInset > 0 {
                    Spacer(minLength: trailingInset)
                } else {
                    Text(VoucherStationery.documentNumber(for: date))
                        .font(WNFTheme.mono(9, weight: .regular))
                        .foregroundStyle(WNFTheme.inkFixed.opacity(0.62))
                }
            }

            Rectangle()
                .fill(WNFTheme.inkFixed.opacity(0.85))
                .frame(height: 1.5)

            HStack {
                Text(title)
                    .font(WNFTheme.display(21))
                    .foregroundStyle(WNFTheme.inkFixed)
                    .tracking(3)
                Spacer(minLength: 6)
                Text(subtitle)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(WNFTheme.inkFixed.opacity(0.66))
            }
        }
        .padding(.horizontal, 15)
        .padding(.top, 15)
        .padding(.bottom, 11)
        .background(WNFTheme.gold)
    }
}

// MARK: Ledger row

/// One printed statement line: label, dotted leader, mono value.
struct VoucherRow: View {
    var label: String
    var value: String
    var valueColor: Color = WNFTheme.inkFixed
    var big = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(WNFTheme.inkFixed.opacity(0.6))
                .layoutPriority(1)

            Line()
                .stroke(WNFTheme.inkFixed.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [1.5, 3]))
                .frame(height: 1)
                .offset(y: -3)

            Text(value)
                .font(WNFTheme.mono(big ? 23 : 13))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .layoutPriority(1)
        }
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: CGPoint(x: rect.minX, y: rect.midY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            return p
        }
    }
}

// MARK: Seal

/// 「窝囊费办公室」coral seal. `progress` drives the stamping animation:
/// 0 = hovering above the paper, 1 = pressed.
struct VoucherSeal: View {
    var size: CGFloat = 86
    var progress: CGFloat = 1

    var body: some View {
        ZStack {
            Circle()
                .stroke(sealColor, lineWidth: size * 0.035)

            Circle()
                .stroke(sealColor.opacity(0.9), lineWidth: size * 0.012)
                .padding(size * 0.075)

            SealArcText(text: "窝囊费办公室", radius: size * 0.335, fontSize: size * 0.135, color: sealColor)

            Text("¥")
                .font(.system(size: size * 0.3, weight: .black, design: .rounded))
                .foregroundStyle(sealColor)
                .offset(y: size * 0.02)

            Text("丧萌有理")
                .font(.system(size: size * 0.088, weight: .heavy))
                .foregroundStyle(sealColor.opacity(0.92))
                .tracking(size * 0.02)
                .offset(y: size * 0.27)
        }
        .frame(width: size, height: size)
        // Ink is never uniform: grain the seal so it reads as rubber stamp.
        .paperGrain(0.42)
        .opacity(0.6 + 0.4 * progress)
        .rotationEffect(.degrees(-14 + 6 * progress))
        .scaleEffect(1 + (1 - progress) * 1.35)
    }

    private var sealColor: Color {
        WNFTheme.coral.opacity(0.94)
    }
}

/// Characters laid along the upper arc of the seal ring.
private struct SealArcText: View {
    var text: String
    var radius: CGFloat
    var fontSize: CGFloat
    var color: Color

    var body: some View {
        let chars = Array(text)
        let arc = Double(140)
        let step = chars.count > 1 ? arc / Double(chars.count - 1) : 0
        ZStack {
            ForEach(chars.indices, id: \.self) { i in
                let angle = -arc / 2 + step * Double(i)
                Text(String(chars[i]))
                    .font(.system(size: fontSize, weight: .black))
                    .foregroundStyle(color)
                    .rotationEffect(.degrees(angle))
                    .offset(
                        x: radius * CGFloat(sin(angle * .pi / 180)),
                        y: -radius * CGFloat(cos(angle * .pi / 180))
                    )
            }
        }
    }
}

// MARK: Barcode

/// Decorative footer barcode; bar widths derive from the serial so each day
/// prints a slightly different (but stable) pattern.
struct VoucherBarcode: View {
    var seedText: String
    var height: CGFloat = 16

    var body: some View {
        let seeds = seedText.unicodeScalars.map { Int($0.value) }
        HStack(alignment: .bottom, spacing: 1.5) {
            ForEach(seeds.indices, id: \.self) { i in
                let s = seeds[i]
                Rectangle()
                    .fill(WNFTheme.inkFixed.opacity(0.82))
                    .frame(width: s % 3 == 0 ? 2.5 : 1.2, height: height * (s % 2 == 0 ? 1 : 0.72))
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: Tear line

struct VoucherTearLine: View {
    var caption: String = "沿虚线撕下 · 撕了也不退窝囊"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "scissors")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(WNFTheme.inkFixed.opacity(0.35))
            Rectangle()
                .fill(Color.clear)
                .frame(height: 1)
                .overlay(
                    Rectangle()
                        .stroke(WNFTheme.inkFixed.opacity(0.28), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                )
            Text(caption)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundStyle(WNFTheme.inkFixed.opacity(0.35))
                .fixedSize()
        }
    }
}
