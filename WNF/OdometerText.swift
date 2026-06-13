import SwiftUI

/// Slot-machine money readout: every digit is its own wheel that rolls up as
/// the value grows (gas-pump style), with a spring overshoot and a slight
/// per-wheel stagger cascading from the cents leftward. Whole-yuan rollovers
/// pop a small `+¥1` chip off the top of the number and pulse the row.
///
/// Replaces the plain `contentTransition(.numericText)` readout on the home
/// page — this is the thing the user stares at all day, so it gets real
/// mechanics instead of a stock crossfade.
struct OdometerMoneyText: View {
    var value: Double
    var privacy: Bool
    /// Gates the shimmer clock so a hidden pager page costs zero frames.
    var isActive: Bool = true
    /// Width budget the row must fit inside (the readout column's content
    /// width). The row scales down deterministically when a big number would
    /// otherwise overrun it — no measurement pass, never clips.
    var maxWidth: CGFloat = .infinity

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var rowPulse = false
    @State private var risingChips: [RisingYuanChip] = []
    @State private var lastWholeYuan: Int?
    @State private var lastChipHapticAt = Date.distantPast

    private var totalCents: Int { max(0, Int((value * 100).rounded(.down))) }
    private var wholeYuan: Int { totalCents / 100 }
    private var centDigits: [Int] {
        let cents = totalCents % 100
        return [cents / 10, cents % 10]
    }

    /// Integer digits most-significant first.
    private var integerDigits: [Int] {
        var digits: [Int] = []
        var remaining = wholeYuan
        repeat {
            digits.append(remaining % 10)
            remaining /= 10
        } while remaining > 0
        return digits.reversed()
    }

    /// Big readout shrinks as the yuan amount gains digits. Sized so the common
    /// 3-digit daily wage stays bold but never crowds the right edge; the
    /// `fitScale` safety net below catches anything larger (and the privacy
    /// dots, and oversized accessibility widths).
    private var mainFontSize: CGFloat {
        switch integerDigits.count {
        case ...3: 78
        case 4: 68
        case 5: 58
        case 6: 50
        default: 44
        }
    }

    private var centsFontSize: CGFloat { (mainFontSize * 0.535).rounded() }

    private var commaCount: Int { max(0, (integerDigits.count - 1) / 3) }

    /// Conservative width estimate for the laid-out row. SF Rounded Black glyphs
    /// advance ≈ 0.72em including bearings; the estimate runs slightly high on
    /// purpose so the scale, when it engages, leaves real right margin.
    private var estimatedNaturalWidth: CGFloat {
        let glyph = mainFontSize * 0.72
        let yen = glyph + 4                                   // ¥ + HStack gap
        let integers = CGFloat(integerDigits.count) * glyph
        let commas = CGFloat(commaCount) * mainFontSize * 0.38
        let cents = centsFontSize * 0.40 + centsFontSize * 0.72 * 2  // "." + 2 digits
        return yen + integers + commas + cents
    }

    /// 1 when the natural row fits, shrinking toward 0.5 for very large values.
    private var fitScale: CGFloat {
        guard maxWidth.isFinite, maxWidth > 0, estimatedNaturalWidth > maxWidth else { return 1 }
        return max(0.5, maxWidth / estimatedNaturalWidth)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("¥")
                .font(.system(size: mainFontSize, weight: .black, design: .rounded))
                .foregroundStyle(WNFTheme.yellow)

            if privacy {
                Text("•••")
                    .tracking(4)
                    .font(.system(size: mainFontSize, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.ink)
                Text(".••")
                    .font(.system(size: centsFontSize, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.muted)
            } else {
                wheelsRow
            }
        }
        .goldShimmer(period: 6.4, intensity: 0.5, isActive: isActive && !privacy)
        .scaleEffect(fitScale * (rowPulse ? 1.035 : 1), anchor: .leading)
        .animation(.spring(response: 0.4, dampingFraction: 0.82), value: fitScale)
        .overlay(alignment: .topTrailing) {
            ZStack(alignment: .topTrailing) {
                ForEach(risingChips) { chip in
                    RisingYuanChipView(chip: chip) {
                        risingChips.removeAll { $0.id == chip.id }
                    }
                }
            }
            .accessibilityHidden(true)
        }
        .onChange(of: wholeYuan) { oldYuan, newYuan in
            handleYuanRollover(from: oldYuan, to: newYuan)
        }
        .onAppear {
            lastWholeYuan = wholeYuan
        }
        // Cap the LAYOUT width at the column budget. `scaleEffect` shrinks the
        // glyphs visually but a scaled view still *claims* its natural width;
        // without this cap a very wide number would stretch the enclosing
        // VStack and shove the TopBar's trailing buttons off-screen.
        .frame(maxWidth: maxWidth.isFinite ? maxWidth : nil, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(privacy ? "今日窝囊费已隐藏" : "今日窝囊费 \(wholeYuan) 元 \(totalCents % 100) 分")
        .accessibilityIdentifier("home.money")
    }

    private var wheelsRow: some View {
        let digits = integerDigits
        let count = digits.count
        // Identity anchored to the ones place (index from the right) so wheels
        // keep rolling smoothly when a new leading digit appears at 999 → 1000.
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            ForEach(Array(digits.enumerated()), id: \.offset) { index, digit in
                let placeFromRight = count - 1 - index
                if placeFromRight != count - 1 && (placeFromRight + 1).isMultiple(of: 3) {
                    Text(",")
                        .font(.system(size: mainFontSize, weight: .black, design: .rounded))
                        .foregroundStyle(WNFTheme.ink)
                }
                DigitWheel(
                    digit: digit,
                    fontSize: mainFontSize,
                    color: WNFTheme.ink,
                    staggerDelay: Double(min(placeFromRight, 5)) * 0.045,
                    reduceMotion: reduceMotion
                )
                .id("int-\(placeFromRight)")
            }

            Text(".")
                .font(.system(size: centsFontSize, weight: .black, design: .rounded))
                .foregroundStyle(WNFTheme.muted)
                .padding(.leading, 1)

            ForEach(Array(centDigits.enumerated()), id: \.offset) { index, digit in
                DigitWheel(
                    digit: digit,
                    fontSize: centsFontSize,
                    color: WNFTheme.muted,
                    staggerDelay: index == 0 ? 0.045 : 0,
                    reduceMotion: reduceMotion
                )
                .id("cent-\(index)")
            }
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: integerDigits.count)
    }

    private func handleYuanRollover(from oldYuan: Int?, to newYuan: Int) {
        defer { lastWholeYuan = newYuan }
        guard let oldYuan, newYuan > oldYuan else { return }
        // Ignore jumps from settings edits / day changes — only celebrate the
        // organic tick-up while watching money accrue.
        let gained = newYuan - oldYuan
        guard gained <= 5 else { return }

        if !reduceMotion {
            risingChips.append(RisingYuanChip(amount: gained))
            if risingChips.count > 3 {
                risingChips.removeFirst(risingChips.count - 3)
            }
            rowPulse = true
            withAnimation(.spring(response: 0.32, dampingFraction: 0.5).delay(0.05)) {
                rowPulse = false
            }
        }

        let now = Date()
        if now.timeIntervalSince(lastChipHapticAt) > 4 {
            lastChipHapticAt = now
            WNFHaptics.soft(intensity: 0.6)
        }
    }
}

private struct RisingYuanChip: Identifiable {
    let id = UUID()
    var amount: Int
    /// Tiny horizontal scatter so back-to-back chips don't stack exactly.
    var drift: CGFloat = .random(in: -14...8)
}

private struct RisingYuanChipView: View {
    var chip: RisingYuanChip
    var onFinished: () -> Void

    @State private var risen = false

    var body: some View {
        Text("+¥\(chip.amount)")
            .font(.system(size: 14, weight: .black, design: .rounded))
            .foregroundStyle(WNFTheme.yellow)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(WNFTheme.ink, in: Capsule())
            .opacity(risen ? 0 : 1)
            .scaleEffect(risen ? 1.0 : 0.6, anchor: .bottom)
            .offset(x: chip.drift, y: risen ? -46 : -6)
            .onAppear {
                withAnimation(.easeOut(duration: 1.0)) {
                    risen = true
                }
            }
            .task {
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                onFinished()
            }
            .allowsHitTesting(false)
    }
}

/// One rolling digit. The container keeps a fixed slot (sized by a hidden
/// template glyph) and the visible digit swaps identity on change, rolling
/// up-and-out / in-from-below with a spring — increases read as the wheel
/// spinning upward like a gas pump.
private struct DigitWheel: View {
    var digit: Int
    var fontSize: CGFloat
    var color: Color
    var staggerDelay: Double
    var reduceMotion: Bool

    var body: some View {
        ZStack {
            // Template glyph defines the slot's fixed metrics.
            Text("8")
                .font(.system(size: fontSize, weight: .black, design: .rounded))
                .monospacedDigit()
                .opacity(0)

            Text("\(digit)")
                .font(.system(size: fontSize, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .transition(rollTransition)
                .id(digit)
        }
        .clipped()
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.2)
                : .spring(response: 0.42, dampingFraction: 0.74).delay(staggerDelay),
            value: digit
        )
    }

    private var rollTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return .asymmetric(
            insertion: .move(edge: .bottom).combined(with: .opacity),
            removal: .move(edge: .top).combined(with: .opacity)
        )
    }
}

#Preview {
    struct OdometerPreview: View {
        @State private var value = 1138.92

        var body: some View {
            VStack(spacing: 30) {
                OdometerMoneyText(value: value, privacy: false)
                Button("+0.37") { value += 0.37 }
                Button("+1.02") { value += 1.02 }
            }
            .padding()
            .background(WNFTheme.bg)
        }
    }
    return OdometerPreview()
}
