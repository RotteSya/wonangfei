import SwiftUI

struct DailySettlementShareCard: View {
    var settlement: DailySettlement
    var displayedAmount: Double?
    var displayedBestMoment: String?
    var hidesSensitiveInfo: Bool
    var showsControls: Bool
    var isPreparingShare: Bool = false
    var onTogglePrivacy: () -> Void = {}
    var onTearBestMoment: (() -> Void)? = nil
    var onShare: () -> Void = {}
    var onDismiss: () -> Void = {}

    private var renderedAmount: Double {
        displayedAmount ?? settlement.earnedToday
    }

    private var renderedBestMoment: String {
        displayedBestMoment ?? settlement.bestMoment
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            cardBody
        }
        .background(WNFTheme.bg, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.white.opacity(0.72), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image("CowThreeQ")
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .padding(4)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("窝囊费")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.ink)
                Text("今日下班战绩")
                    .font(.system(size: 10, weight: .heavy))
                    .tracking(1.2)
                    .foregroundStyle(WNFTheme.inkSoft)
            }

            Spacer(minLength: 8)

            if showsControls {
                HStack(spacing: 8) {
                    WNFHeaderIconButton(
                        systemName: hidesSensitiveInfo ? "eye.slash" : "eye",
                        accessibilityLabel: hidesSensitiveInfo ? "显示敏感信息" : "隐藏敏感信息",
                        action: onTogglePrivacy
                    )
                    WNFHeaderIconButton(
                        systemName: "square.and.arrow.up",
                        accessibilityLabel: isPreparingShare ? "正在生成分享图" : "唤起系统分享",
                        isLoading: isPreparingShare,
                        isDisabled: isPreparingShare,
                        action: onShare
                    )
                    WNFHeaderIconButton(
                        systemName: "xmark",
                        accessibilityLabel: "退出结算",
                        action: onDismiss
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(WNFTheme.gold)
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 14) {
            Rectangle()
                .fill(Color.clear)
                .frame(height: 0)
                .overlay(
                    Rectangle()
                        .stroke(WNFTheme.muted.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [8, 8]))
                )
                .padding(.horizontal, -18)
                .padding(.top, -14)

            VStack(alignment: .leading, spacing: 8) {
                Text(settlement.headline)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.ink)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                    .fixedSize(horizontal: false, vertical: true)

                Text(settlement.subCopy)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(WNFTheme.inkSoft)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            amountPanel

            statsRow

            SettlementQuoteCard(
                iconName: "quote.opening",
                prefix: "今日最佳忍耐时刻：",
                content: renderedBestMoment,
                hint: onTearBestMoment == nil ? nil : "长按可换一句",
                onTear: onTearBestMoment
            )

            cumulativeRow

            HStack {
                Text("丧萌有理 · 自嘲无罪")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(WNFTheme.inkSoft)

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    YenBadge(size: 16)
                    Text("来自窝囊费")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(WNFTheme.ink)
                }
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [WNFTheme.bg.opacity(0.98), WNFTheme.surfaceSoft.opacity(0.78)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var cumulativeRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(WNFTheme.gold)
            Text("累积窝囊费")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(WNFTheme.inkSoft)
            Spacer(minLength: 12)
            Text(cumulativeText)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(WNFTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WNFTheme.surfaceSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(WNFTheme.hairline, lineWidth: 0.5)
        )
    }

    private var cumulativeText: String {
        if hidesSensitiveInfo { return "¥•••.••" }
        return WNFFormat.moneyDecimal(settlement.cumulativeEarned, privacy: false)
    }

    private var amountPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("今日窝囊费")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(WNFTheme.inkSoft)
                Spacer(minLength: 12)
                sentimentBadge
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.yellow)
                Group {
                    if hidesSensitiveInfo {
                        Text("•••.••")
                            .foregroundStyle(WNFTheme.muted)
                    } else {
                        Text(formattedAmount)
                            .foregroundStyle(WNFTheme.ink)
                            .contentTransition(.numericText(value: renderedAmount))
                            .animation(.easeOut(duration: 0.25), value: renderedAmount)
                    }
                }
                .font(.system(size: 44, weight: .black, design: .rounded))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(WNFTheme.muted.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .padding(6)
        )
    }

    private var formattedAmount: String {
        String(format: "%.2f", renderedAmount)
    }

    private var sentimentBadge: some View {
        HStack(spacing: 5) {
            Text(settlement.sentiment.emoji)
                .font(.system(size: 13))
            Text(settlement.sentiment.label)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(WNFTheme.ink)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(WNFTheme.surfaceSoft, in: Capsule())
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            settlementStatTile(
                title: "忍耐指数",
                value: settlement.sentiment.stars,
                outOf: settlement.sentiment.maxStars
            )
            settlementStatTile(
                title: "已忍时长",
                primary: durationPrimary,
                secondary: durationSecondary
            )
            settlementStatTile(
                title: "连续打工",
                primary: settlement.streakDays > 0 ? "\(settlement.streakDays)" : "—",
                secondary: settlement.streakDays > 0 ? "天" : "暂无"
            )
        }
    }

    private var durationPrimary: String {
        if hidesSensitiveInfo {
            return "••"
        }
        let h = settlement.elapsedPaidMinutes / 60
        if h > 0 { return "\(h)" }
        return "\(settlement.elapsedPaidMinutes)"
    }

    private var durationSecondary: String {
        if hidesSensitiveInfo {
            return "h••min"
        }
        let h = settlement.elapsedPaidMinutes / 60
        let m = settlement.elapsedPaidMinutes % 60
        if h > 0 {
            return m > 0 ? "h \(m)min" : "h"
        }
        return "min"
    }

    private func settlementStatTile(
        title: String,
        primary: String,
        secondary: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(WNFTheme.muted)
                .tracking(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(primary)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.ink)
                Text(secondary)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(WNFTheme.muted)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(WNFTheme.hairline, lineWidth: 0.5)
        )
    }

    private func settlementStatTile(
        title: String,
        value: Int,
        outOf max: Int
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .heavy))
                .foregroundStyle(WNFTheme.muted)
                .tracking(1)
            HStack(spacing: 2) {
                ForEach(0..<max, id: \.self) { index in
                    Image(systemName: index < value ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(index < value ? WNFTheme.yellow : WNFTheme.muted.opacity(0.5))
                }
            }
            .padding(.top, 5)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(WNFTheme.hairline, lineWidth: 0.5)
        )
    }
}

private struct SettlementQuoteCard: View {
    var iconName: String
    var prefix: String?
    var content: String
    var hint: String?
    var onTear: (() -> Void)?

    @State private var pressFeedback = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(WNFTheme.muted)
                    .padding(.top, 2)
                Text(combined)
                    // id-driven transition: when content changes, the old text fades + slides out
                    // and the new one slides in. The parent wraps the swap in withAnimation.
                    .id(combined)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(WNFTheme.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(
                        .asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .top)),
                            removal: .opacity
                                .combined(with: .scale(scale: 0.86, anchor: .leading))
                                .combined(with: .offset(y: 12))
                        )
                    )
                Spacer(minLength: 0)
            }

            if let hint, onTear != nil {
                HStack(spacing: 4) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 9, weight: .heavy))
                    Text(hint)
                        .font(.system(size: 10, weight: .heavy))
                }
                .foregroundStyle(WNFTheme.muted.opacity(0.7))
                .padding(.leading, 19)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(WNFTheme.hairline, lineWidth: 0.5)
        )
        .scaleEffect(pressFeedback ? 0.97 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: pressFeedback)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.4) {
            handleTear()
        } onPressingChanged: { isPressing in
            // visible feedback during the long-press hold so the user knows the gesture registered
            pressFeedback = isPressing && onTear != nil
        }
        .accessibilityHint(onTear == nil ? "" : "长按可以换一句")
    }

    private var combined: String {
        if let prefix { return "\(prefix)\(content)" }
        return content
    }

    private func handleTear() {
        guard let onTear else { return }
        onTear()
    }
}
