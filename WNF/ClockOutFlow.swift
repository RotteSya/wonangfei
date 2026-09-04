import SwiftUI

struct ClockOutDecisionOverlay: View {
    var onConfirm: () -> Void
    var onOvertime: () -> Void
    var onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color.black
                .opacity(0.62)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .accessibilityHidden(true)

            VStack(spacing: 18) {
                Text("到点了")
                    .font(WNFTheme.display(40))
                    .foregroundStyle(WNFTheme.yellow)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("clockout.overlay")

                Color.clear
                    .frame(height: 72)

                Button(action: onOvertime) {
                    Text("加班…")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(WNFTheme.inkFixed)
                        .minimumScaleFactor(0.8)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                        .background(WNFTheme.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.squish(0.97))
                .accessibilityLabel("加班")
                .accessibilityHint("选一个明确的加班时长，继续算钱")
                .accessibilityIdentifier("clockout.overtime")
            }
            .padding(.horizontal, 28)

            Button(action: onConfirm) {
                Text("下班！")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.inkFixed)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 72)
                    .background(WNFTheme.yellow, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .shadow(color: WNFTheme.yellow.opacity(0.5), radius: 18, y: 8)
            }
            .buttonStyle(.squish(0.97))
            .padding(.horizontal, 28)
            .accessibilityLabel("下班！")
            .accessibilityHint("把今天的窝囊费收进个人时间")
            .accessibilityIdentifier("clockout.confirm")

            VStack {
                HStack {
                    Spacer()
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .heavy))
                            .foregroundStyle(WNFTheme.inkFixed.opacity(0.72))
                            .frame(width: 42, height: 42)
                            .background(WNFTheme.paper, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭")
                    .accessibilityIdentifier("clockout.dismiss")
                }
                .padding(.horizontal, 22)
                .padding(.top, 58)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .environment(\.colorScheme, .light)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: reduceMotion)
    }
}

struct OvertimeDurationSheet: View {
    var now: Date
    var startOfDay: Date
    var onConfirm: (TimeInterval) -> Void
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedDuration: TimeInterval = ClockOutRuntimeEngine.defaultOvertimeDuration

    private var options: [TimeInterval] {
        ClockOutRuntimeEngine.overtimeDurationOptions(now: now, startOfDay: startOfDay)
    }

    private var estimatedEnd: Date {
        now.addingTimeInterval(selectedDuration)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("还要再熬多久？")
                .font(WNFTheme.display(22))
                .foregroundStyle(WNFTheme.ink)
                .padding(.top, 24)
                .accessibilityAddTraits(.isHeader)

            if options.isEmpty {
                Text("今天已经到头了")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(WNFTheme.muted)
                    .padding(.vertical, 36)
            } else {
                Picker("加班时长", selection: $selectedDuration) {
                    ForEach(options, id: \.self) { duration in
                        Text(ClockOutRuntimeEngine.durationLabel(for: duration))
                            .tag(duration)
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 148)
                .accessibilityIdentifier("overtime.duration")

                Text("预计熬到 \(ClockOutRuntimeEngine.clockText(for: estimatedEnd))")
                    .font(.system(size: 15, weight: .heavy, design: .rounded))
                    .foregroundStyle(WNFTheme.inkSoft)
            }

            Button {
                onConfirm(selectedDuration)
            } label: {
                Text("认了，继续算钱")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.inkFixed)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
                    .background(WNFTheme.yellow, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.squish(0.97))
            .disabled(options.isEmpty)
            .opacity(options.isEmpty ? 0.4 : 1)
            .accessibilityIdentifier("overtime.confirm")
            .padding(.horizontal, 22)

            Button("取消", action: onCancel)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(WNFTheme.muted)
                .padding(.bottom, 18)
                .accessibilityIdentifier("overtime.cancel")
        }
        .presentationDetents([.height(420)])
        .presentationCornerRadius(34)
        .presentationBackground(WNFTheme.bg)
        .onAppear {
            selectedDuration = ClockOutRuntimeEngine.defaultOvertimeSelection(in: options)
        }
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: selectedDuration)
    }
}
