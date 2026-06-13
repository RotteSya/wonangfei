import SwiftUI

struct TopBar: View {
    @EnvironmentObject private var state: WageState
    var onShare: (() -> Void)?

    var body: some View {
        HStack {
            HStack(spacing: 7) {
                Image("CowThreeQ")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 26, height: 28)
                Text("窝囊费")
                    .font(.system(size: 21, weight: .black, design: .rounded))
                YenBadge(size: 16)
            }

            Spacer()

            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        state.privacyMode.toggle()
                    }
                    WNFHaptics.selection()
                } label: {
                    Image(systemName: state.privacyMode ? "eye.slash" : "eye")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(state.privacyMode ? WNFTheme.yellow : WNFTheme.ink)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 40, height: 40)
                        .background(state.privacyMode ? WNFTheme.ink : Color.white, in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(WNFTheme.hairline, lineWidth: 0.5))
                        .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                }
                .buttonStyle(.squish)
                .accessibilityLabel(state.privacyMode ? "显示工资" : "隐藏工资")
                .accessibilityIdentifier("home.privacy")

                if let onShare {
                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(WNFTheme.ink)
                            .frame(width: 40, height: 40)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(WNFTheme.hairline, lineWidth: 0.5))
                            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
                    }
                    .buttonStyle(.squish)
                    .accessibilityLabel("分享今日窝囊费")
                    .accessibilityIdentifier("home.share")
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
        .padding(.top, 8)
    }
}

struct YenBadge: View {
    var size: CGFloat = 14

    var body: some View {
        Text("¥")
            .font(.system(size: size * 0.7, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                LinearGradient(colors: [Color(red: 1, green: 0.9, blue: 0.5), WNFTheme.gold], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.22)
            )
            .shadow(color: .black.opacity(0.16), radius: 1, y: 1)
    }
}

struct StatusChip: View {
    var label: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 7) {
            statusDot
            Text(label)
                .font(.system(size: 12, weight: .heavy))
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.3), value: label)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(WNFTheme.surfaceSoft, in: Capsule())
    }

    @ViewBuilder
    private var statusDot: some View {
        let dot = Circle()
            .fill(WNFTheme.coral)
            .frame(width: 7, height: 7)

        if reduceMotion {
            dot
        } else {
            // Live heartbeat: the dot breathes with a soft halo, signalling
            // "the meter is running" without a single extra word on screen.
            dot.phaseAnimator([false, true]) { view, pulsing in
                view
                    .scaleEffect(pulsing ? 1.0 : 0.72)
                    .opacity(pulsing ? 1.0 : 0.6)
                    .background(
                        Circle()
                            .fill(WNFTheme.coral.opacity(pulsing ? 0 : 0.35))
                            .frame(width: 13, height: 13)
                            .scaleEffect(pulsing ? 1.5 : 0.6)
                    )
            } animation: { _ in
                .easeInOut(duration: 1.15)
            }
        }
    }
}

struct MetricTile: View {
    var label: String
    var value: String
    var subtitle: String?
    var accent: Color = WNFTheme.yellow
    var big = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundStyle(WNFTheme.muted)
                Spacer()
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
            }

            Text(value)
                .font(.system(size: big ? 23 : 19, weight: .black, design: .monospaced))
                .foregroundStyle(WNFTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.32), value: value)

            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WNFTheme.muted)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: big ? 94 : 84, alignment: .topLeading)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(WNFTheme.hairline, lineWidth: 0.5))
    }
}

struct SectionCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(WNFTheme.muted)
                .tracking(1.5)
                .padding(.horizontal, 10)

            VStack(spacing: 0) {
                content
            }
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(WNFTheme.hairline, lineWidth: 0.5))
        }
    }
}

struct SettingsRow<Content: View>: View {
    var title: String
    var isLast = false
    @ViewBuilder var content: Content

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(WNFTheme.ink)
            Spacer(minLength: 12)
            content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !isLast {
                Rectangle()
                    .fill(WNFTheme.hairline)
                    .frame(height: 0.5)
                    .padding(.leading, 16)
            }
        }
    }
}

struct WNFToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) {
                isOn.toggle()
            }
        } label: {
            RoundedRectangle(cornerRadius: 999)
                .fill(isOn ? WNFTheme.ink : Color(red: 0.84, green: 0.82, blue: 0.77))
                .frame(width: 50, height: 30)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? WNFTheme.yellow : Color.white)
                        .frame(width: 26, height: 26)
                        .padding(2)
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                }
        }
        .buttonStyle(.plain)
    }
}
