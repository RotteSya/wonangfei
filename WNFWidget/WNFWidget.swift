import AppIntents
import OSLog
import SwiftUI
import UIKit
import WidgetKit

private struct WidgetPalette {
    // Mirrors WNFTheme's dynamic palette (Theme.swift is app-target only).
    static let bg = dynamic(0xFFF6E5, 0x16120E)
    static let surface = dynamic(0xFFFFFF, 0x251F17)
    static let accent = Color(red: 1.0, green: 0.7843, blue: 0.2392)
    static let ink = dynamic(0x0D0D0D, 0xF4ECDD)
    static let muted = dynamic(0x9A938A, 0x8E8372)

    private static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
    }
}

private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct WNFWidgetConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "窝囊费小组件" }
    static var description: IntentDescription { IntentDescription("显示今日窝囊费。v1 暂无可配置参数，后续可加入每个小组件独立主题和隐私设置。") }
}

private struct WNFWidgetEntry: TimelineEntry {
    var date: Date
    var snapshot: WNFWidgetSnapshot
    var isPreview: Bool
}

private struct WNFWidgetProvider: AppIntentTimelineProvider {
    private let logger = Logger(subsystem: "com.wonangfei.app.widget", category: "snapshot")

    func placeholder(in context: Context) -> WNFWidgetEntry {
        WNFWidgetEntry(date: Date(), snapshot: .sample, isPreview: true)
    }

    func snapshot(for configuration: WNFWidgetConfigurationIntent, in context: Context) async -> WNFWidgetEntry {
        WNFWidgetEntry(
            date: Date(),
            snapshot: context.isPreview ? .sample : loadSnapshot() ?? .sample,
            isPreview: context.isPreview
        )
    }

    func timeline(for configuration: WNFWidgetConfigurationIntent, in context: Context) async -> Timeline<WNFWidgetEntry> {
        let snapshot = context.isPreview ? WNFWidgetSnapshot.sample : loadSnapshot() ?? .sample
        let now = Date()
        let plan = WNFWidgetTimeline.plan(for: snapshot, now: now, isPreview: context.isPreview)
        let entries = plan.entryDates.map {
            WNFWidgetEntry(date: $0, snapshot: snapshot.projected(at: $0), isPreview: context.isPreview)
        }
        let policy: TimelineReloadPolicy = context.isPreview ? .never : .after(plan.reloadDate)
        return Timeline(entries: entries, policy: policy)
    }

    private func loadSnapshot() -> WNFWidgetSnapshot? {
        guard let userDefaults = UserDefaults(suiteName: WNFShared.appGroupID) else {
            logger.error("Widget App Group defaults unavailable; using sample snapshot.")
            return nil
        }

        guard let data = userDefaults.data(forKey: WNFShared.widgetSnapshotKey) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(WNFWidgetSnapshot.self, from: data)
        } catch {
            logger.error("Widget snapshot decode failed; using sample snapshot. error=\(String(describing: error), privacy: .public)")
            return nil
        }
    }
}

private struct WNFWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: WNFWidgetEntry

    var body: some View {
        content
            .containerBackground(for: .widget) {
                WidgetPalette.bg
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryInline:
            Text(inlineText)
        case .accessoryRectangular:
            rectangularView
        case .systemMedium:
            mediumView
        default:
            smallView
        }
    }

    private var inlineText: String {
        "窝囊费 \(moneyText)"
    }

    private var rectangularView: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("今日窝囊费")
                .font(.caption2.weight(.heavy))
            Text(moneyText)
                .font(.headline.weight(.black))
                .minimumScaleFactor(0.75)
            Text(entry.snapshot.statusLabel)
                .font(.caption2.weight(.semibold))
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 10) {
            widgetHeader
            Spacer(minLength: 0)
            Text(moneyText)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(WidgetPalette.ink)
                .minimumScaleFactor(0.65)
            Text(entry.snapshot.statusLabel)
                .font(.caption.weight(.heavy))
                .foregroundStyle(WidgetPalette.muted)
        }
        .padding()
    }

    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                widgetHeader
                Text(moneyText)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(WidgetPalette.ink)
                    .minimumScaleFactor(0.62)
                Text("已忍 \(duration(entry.snapshot.elapsedPaidMinutes))")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(WidgetPalette.muted)
            }
            Spacer()
            Text("¥")
                .font(.system(size: 54, weight: .black, design: .rounded))
                .foregroundStyle(WidgetPalette.accent)
                .frame(width: 78, height: 78)
                .background(WidgetPalette.surface, in: RoundedRectangle(cornerRadius: 24))
        }
        .padding()
    }

    private var widgetHeader: some View {
        HStack(spacing: 6) {
            Text("¥")
                .font(.caption.weight(.black))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(WidgetPalette.accent, in: RoundedRectangle(cornerRadius: 5))
            Text("窝囊费")
                .font(.caption.weight(.black))
                .foregroundStyle(WidgetPalette.ink)
        }
    }

    private var moneyText: String {
        entry.snapshot.hidesSensitiveInfo ? "¥•••.••" : money(entry.snapshot.earnedToday)
    }

    private func money(_ value: Double) -> String {
        String(format: "¥%.2f", value)
    }

    private func duration(_ minutes: Int) -> String {
        "\(minutes / 60)h\(minutes % 60)min"
    }
}

struct WNFWidget: Widget {
    let kind = "WNFWidget"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WNFWidgetConfigurationIntent.self, provider: WNFWidgetProvider()) { entry in
            WNFWidgetView(entry: entry)
        }
        .configurationDisplayName("窝囊费")
        .description("在桌面和锁屏查看今天的窝囊费。")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

@main
struct WNFWidgetBundle: WidgetBundle {
    var body: some Widget {
        WNFWidget()
        WNFLiveActivity()
    }
}

// MARK: - Live Activity（锁屏 + 灵动岛的黑金工牌）

private enum LiveActivityPalette {
    // The live activity is always the "black work badge" — scheme-independent.
    static let bg = Color(red: 0.07, green: 0.06, blue: 0.045)
    static let ink = Color(red: 0.957, green: 0.925, blue: 0.867)
    static let yellow = Color(red: 1.0, green: 0.7843, blue: 0.2392)
    static let muted = Color(red: 0.62, green: 0.57, blue: 0.49)
}

struct WNFLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WNFLiveActivityAttributes.self) { context in
            LiveActivityLockScreenView(state: context.state)
                .activityBackgroundTint(LiveActivityPalette.bg)
                .activitySystemActionForegroundColor(LiveActivityPalette.yellow)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.isDone ? "今日窝囊费 · 待领取" : "今日窝囊费")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(LiveActivityPalette.muted)
                        Text(moneyText(context.state))
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(LiveActivityPalette.ink)
                            .minimumScaleFactor(0.6)
                            .lineLimit(1)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.state.isDone ? "状态" : "离下班")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(LiveActivityPalette.muted)
                        countdown(context.state, size: 20)
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    progressBar(context.state)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                }
            } compactLeading: {
                Text("¥")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(LiveActivityPalette.yellow)
            } compactTrailing: {
                if context.state.isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LiveActivityPalette.yellow)
                } else {
                    countdown(context.state, size: 12)
                        .frame(maxWidth: 52)
                }
            } minimal: {
                Text("¥")
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(LiveActivityPalette.yellow)
            }
            .keylineTint(LiveActivityPalette.yellow)
        }
    }

    private func moneyText(_ state: WNFLiveActivityAttributes.ContentState) -> String {
        if state.hidesAmount { return "¥•••.••" }
        let exact = String(format: "¥%.2f", state.earnedAtRef)
        return state.isDone ? exact : "≈\(exact)"
    }

    private func countdown(_ state: WNFLiveActivityAttributes.ContentState, size: CGFloat) -> some View {
        Group {
            if state.isDone {
                Text("已下班")
                    .font(.system(size: size, weight: .black, design: .rounded))
                    .foregroundStyle(LiveActivityPalette.yellow)
            } else {
                Text(timerInterval: Date.now...max(Date.now, state.workdayEnd), countsDown: true)
                    .font(.system(size: size, weight: .black, design: .monospaced))
                    .foregroundStyle(LiveActivityPalette.ink)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
            }
        }
    }

    private func progressBar(_ state: WNFLiveActivityAttributes.ContentState) -> some View {
        Group {
            if state.isDone {
                ProgressView(value: 1)
            } else {
                ProgressView(
                    timerInterval: min(state.workdayStart, state.workdayEnd)...max(state.workdayStart, state.workdayEnd),
                    countsDown: false,
                    label: { EmptyView() },
                    currentValueLabel: { EmptyView() }
                )
            }
        }
        .progressViewStyle(.linear)
        .tint(LiveActivityPalette.yellow)
    }
}

private struct LiveActivityLockScreenView: View {
    var state: WNFLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 6) {
                    Text("¥")
                        .font(.caption2.weight(.black))
                        .foregroundStyle(.black)
                        .frame(width: 16, height: 16)
                        .background(LiveActivityPalette.yellow, in: RoundedRectangle(cornerRadius: 4.5))
                    Text(state.isDone ? "窝囊费 · 待领取" : "窝囊费 · 正在结算")
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(LiveActivityPalette.muted)
                }
                Spacer(minLength: 8)
                if state.isDone {
                    Text("已下班")
                        .font(.caption.weight(.black))
                        .foregroundStyle(LiveActivityPalette.yellow)
                } else {
                    HStack(spacing: 4) {
                        Text("离下班")
                            .font(.caption2.weight(.heavy))
                            .foregroundStyle(LiveActivityPalette.muted)
                        Text(timerInterval: Date.now...max(Date.now, state.workdayEnd), countsDown: true)
                            .font(.caption.weight(.black))
                            .monospacedDigit()
                            .foregroundStyle(LiveActivityPalette.ink)
                            .frame(maxWidth: 64)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Text(moneyText)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(LiveActivityPalette.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)

            Group {
                if state.isDone {
                    ProgressView(value: 1)
                } else {
                    ProgressView(
                        timerInterval: min(state.workdayStart, state.workdayEnd)...max(state.workdayStart, state.workdayEnd),
                        countsDown: false,
                        label: { EmptyView() },
                        currentValueLabel: { EmptyView() }
                    )
                }
            }
            .progressViewStyle(.linear)
            .tint(LiveActivityPalette.yellow)
        }
        .padding(14)
    }

    private var moneyText: String {
        if state.hidesAmount { return "¥•••.••" }
        let exact = String(format: "¥%.2f", state.earnedAtRef)
        return state.isDone ? exact : "≈\(exact)"
    }
}
