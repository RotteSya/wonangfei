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
                    .font(WNFTheme.display(21))
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
                        .background(state.privacyMode ? WNFTheme.inkSurface : WNFTheme.surface, in: RoundedRectangle(cornerRadius: 13))
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
                            .background(WNFTheme.surface, in: RoundedRectangle(cornerRadius: 13))
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
                .font(WNFTheme.mono(big ? 22 : 18))
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
        .background(WNFTheme.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(WNFTheme.hairline, lineWidth: 0.5))
    }
}

struct SectionCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(WNFTheme.display(13))
                .foregroundStyle(WNFTheme.muted)
                .tracking(1.5)
                .padding(.horizontal, 10)

            VStack(spacing: 0) {
                content
            }
            .background(WNFTheme.surface, in: RoundedRectangle(cornerRadius: 22))
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
                .fill(isOn ? WNFTheme.ink : WNFTheme.track)
                .frame(width: 50, height: 30)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle()
                        .fill(isOn ? WNFTheme.yellow : Color.white)
                        .overlay(Circle().stroke(WNFTheme.inkFixed.opacity(0.14), lineWidth: 0.8))
                        .frame(width: 26, height: 26)
                        .padding(2)
                        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 自绘数字键盘（替代系统 alert 输入）

struct WNFNumberPadSheet: View {
    var title: String
    var unit: String
    var initialText: String
    var onCommit: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String = ""
    /// Until the first keystroke the prefilled value acts as "selected all":
    /// typing replaces it wholesale, delete clears it.
    @State private var isPristine = true

    private let keys: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["⌫", "0", "✓"]
    ]

    var body: some View {
        VStack(spacing: 18) {
            Text(title)
                .font(WNFTheme.display(19))
                .foregroundStyle(WNFTheme.ink)
                .padding(.top, 24)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(draft.isEmpty ? "0" : formattedDraft)
                    .font(WNFTheme.mono(34))
                    .foregroundStyle(draft.isEmpty ? WNFTheme.muted : WNFTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.18), value: draft)
                Text(unit)
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(WNFTheme.muted)
            }
            .padding(.horizontal, 26)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(WNFTheme.surfaceSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 22)

            VStack(spacing: 10) {
                ForEach(keys, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach(row, id: \.self) { key in
                            keyButton(key)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 20)
        }
        .presentationDetents([.height(430)])
        .presentationCornerRadius(34)
        .presentationBackground(WNFTheme.bg)
        .onAppear {
            if draft.isEmpty { draft = initialText }
        }
    }

    private var formattedDraft: String {
        guard let value = Int(draft) else { return draft }
        return value.formatted(.number.grouping(.automatic))
    }

    private func keyButton(_ key: String) -> some View {
        Button {
            handle(key)
        } label: {
            Group {
                if key == "⌫" {
                    Image(systemName: "delete.backward.fill")
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(WNFTheme.ink)
                } else if key == "✓" {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .black))
                        .foregroundStyle(WNFTheme.inkFixed)
                } else {
                    Text(key)
                        .font(WNFTheme.mono(23))
                        .foregroundStyle(WNFTheme.ink)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(
                key == "✓" ? AnyShapeStyle(WNFTheme.yellow) : AnyShapeStyle(WNFTheme.surface),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(WNFTheme.hairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(.squish(0.94))
        .disabled(key == "✓" && draft.isEmpty)
        .opacity(key == "✓" && draft.isEmpty ? 0.4 : 1)
        .accessibilityLabel(key == "⌫" ? "删除" : key == "✓" ? "确定" : key)
    }

    private func handle(_ key: String) {
        WNFHaptics.rigid()
        switch key {
        case "⌫":
            if isPristine {
                draft = ""
                isPristine = false
            } else if !draft.isEmpty {
                draft.removeLast()
            }
        case "✓":
            onCommit(draft)
            dismiss()
        default:
            if isPristine {
                draft = ""
                isPristine = false
            }
            guard draft.count < 9 else { return }
            // Leading zeros never make sense for money/days.
            if draft == "0" { draft = "" }
            draft.append(key)
        }
    }
}

// MARK: - 自绘时间选择器（替代系统滚轮）

struct WNFTimePickerSheet: View {
    var title: String
    @Binding var components: DateComponents
    var onCommitted: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var hour: Int = 9
    @State private var minute: Int = 0

    private var minuteValues: [Int] {
        var values = Set(stride(from: 0, to: 60, by: 5))
        values.insert(minute)
        if let current = components.minute { values.insert(current) }
        return values.sorted()
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(title)
                .font(WNFTheme.display(19))
                .foregroundStyle(WNFTheme.ink)
                .padding(.top, 24)

            HStack(spacing: 0) {
                WNFSnapColumn(values: Array(0...23), selection: $hour)
                Text(":")
                    .font(WNFTheme.mono(26))
                    .foregroundStyle(WNFTheme.muted)
                    .padding(.horizontal, 2)
                WNFSnapColumn(values: minuteValues, selection: $minute)
            }
            .frame(height: 224)
            .background(alignment: .center) {
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(WNFTheme.yellow.opacity(0.24))
                    .frame(height: 46)
                    .padding(.horizontal, 30)
            }
            .padding(.horizontal, 22)

            Button {
                WNFHaptics.rigid()
                components = DateComponents(hour: hour, minute: minute)
                onCommitted?()
                dismiss()
            } label: {
                Text(String(format: "就定 %02d:%02d", hour, minute))
                    .font(.system(size: 16, weight: .black))
                    .foregroundStyle(WNFTheme.inkFixed)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(WNFTheme.yellow, in: Capsule())
            }
            .buttonStyle(.squish(0.96))
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
        .presentationDetents([.height(400)])
        .presentationCornerRadius(34)
        .presentationBackground(WNFTheme.bg)
        .onAppear {
            hour = components.hour ?? 9
            minute = components.minute ?? 0
        }
    }
}

/// One snapping column: centered selection, 5 rows visible, haptic per notch.
private struct WNFSnapColumn: View {
    var values: [Int]
    @Binding var selection: Int

    private let rowHeight: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            let inset = (proxy.size.height - rowHeight) / 2
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    ForEach(values, id: \.self) { value in
                        Text(String(format: "%02d", value))
                            .font(WNFTheme.mono(24))
                            .foregroundStyle(value == selection ? WNFTheme.ink : WNFTheme.muted.opacity(0.55))
                            .frame(maxWidth: .infinity)
                            .frame(height: rowHeight)
                            .id(value)
                    }
                }
                .scrollTargetLayout()
            }
            .contentMargins(.vertical, inset, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: scrollSelection, anchor: .center)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.22),
                        .init(color: .black, location: 0.78),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .frame(maxWidth: .infinity)
        .onChange(of: selection) { _, _ in
            WNFHaptics.selection()
        }
    }

    private var scrollSelection: Binding<Int?> {
        Binding {
            selection
        } set: { value in
            if let value { selection = value }
        }
    }
}
