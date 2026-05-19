import SwiftUI
import UIKit

private final class OnboardingImageStore: ObservableObject {
    @Published private var preparedImages: [String: UIImage] = [:]

    private var requestedImageNames = Set<String>()
    private let decodeQueue = DispatchQueue(label: "com.wonangfei.onboarding-image-decode", qos: .userInitiated)

    func image(named name: String) -> UIImage? {
        preparedImages[name]
    }

    func preload(_ names: [String]) {
        let pendingNames = names.filter { preparedImages[$0] == nil && !requestedImageNames.contains($0) }
        guard !pendingNames.isEmpty else { return }

        requestedImageNames.formUnion(pendingNames)

        decodeQueue.async { [weak self] in
            let decodedImages = pendingNames.compactMap { name -> (String, UIImage)? in
                guard let sourceImage = UIImage(named: name) else { return nil }
                return (name, sourceImage.preparingForDisplay() ?? sourceImage)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                var nextImages = self.preparedImages
                decodedImages.forEach { name, image in
                    nextImages[name] = image
                }
                self.preparedImages = nextImages
            }
        }
    }
}

struct OnboardingView: View {
    @StateObject private var imageStore = OnboardingImageStore()
    @State private var page: Int

    var onFinish: () -> Void

    private let pageCount = 4

    init(initialPage: Int = 0, onFinish: @escaping () -> Void) {
        _page = State(initialValue: min(max(initialPage, 0), 3))
        self.onFinish = onFinish
    }

    var body: some View {
        GeometryReader { proxy in
            let visualHeight = min(max(proxy.size.height * 0.28, 204), 260)
            let introVisualHeight = min(max(proxy.size.height * 0.40, 300), 370)

            VStack(spacing: 0) {
                OnboardingHeader(
                    title: headerTitle,
                    canSkip: page < pageCount - 1,
                    onSkip: { go(to: pageCount - 1) }
                )
                .padding(.top, 6)

                TabView(selection: $page) {
                    OnboardingIntroPage(
                        title: "准备开工！看看今天能挣多少窝囊费？",
                        lead: "上班已经够委屈了，至少知道自己每秒能挣多少。",
                        visualHeight: introVisualHeight
                    )
                    .tag(0)

                    OnboardingPage(
                        title: "输入月薪，别让公司糊弄你。",
                        lead: "税前税后都行，能拿多少才是真。"
                    ) {
                        OnboardingImagePanel(imageName: "OnboardingP2", height: visualHeight)
                    } accessory: {
                        SalarySetupCard()
                    }
                    .tag(1)

                    OnboardingPage(
                        title: "再确认一下，公司有没有午休。",
                        lead: "没有午休就直接关掉，时薪会按真实计薪时长计算。"
                    ) {
                        LunchImagePanel(height: visualHeight)
                    } accessory: {
                        WorkTimeSetupCard()
                    }
                    .tag(2)

                    OnboardingPage(
                        title: "开始挣窝囊费啦！",
                        lead: "这还得熬多久......？"
                    ) {
                        OnboardingImagePanel(imageName: "OnboardingP4", height: visualHeight)
                    } accessory: {
                        SummarySetupCard()
                    }
                    .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .environmentObject(imageStore)

                OnboardingFooter(
                    page: page,
                    pageCount: pageCount,
                    onBack: { go(to: page - 1) },
                    onNext: { page == pageCount - 1 ? finish() : go(to: page + 1) },
                    onSelect: go
                )
                .padding(.horizontal, 22)
                .padding(.bottom, max(proxy.safeAreaInsets.bottom, 14))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                LinearGradient(
                    colors: [Color.white, WNFTheme.bg, WNFTheme.bgWarm.opacity(0.82)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            )
        }
        .onAppear {
            warmInitialImages()
        }
        .onChange(of: page) { _, newPage in
            warmImages(for: newPage)
        }
    }

    private var headerTitle: String {
        switch page {
        case 1: "月薪设置"
        case 2: "作息确认"
        case 3: "设置完成"
        default: "窝囊费"
        }
    }

    private func go(to target: Int) {
        warmImages(for: target)
        withAnimation(.snappy(duration: 0.32)) {
            page = min(max(target, 0), pageCount - 1)
        }
    }

    private func finish() {
        withAnimation(.snappy(duration: 0.3)) {
            onFinish()
        }
    }

    private func warmInitialImages() {
        imageStore.preload(["OnboardingP1", "OnboardingP2"])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            imageStore.preload(["OnboardingLunchSleep", "OnboardingLunchWake", "OnboardingP4"])
        }
    }

    private func warmImages(for targetPage: Int) {
        switch targetPage {
        case 0:
            imageStore.preload(["OnboardingP1", "OnboardingP2"])
        case 1:
            imageStore.preload(["OnboardingP2", "OnboardingLunchSleep", "OnboardingLunchWake"])
        case 2:
            imageStore.preload(["OnboardingLunchSleep", "OnboardingLunchWake", "OnboardingP4"])
        default:
            imageStore.preload(["OnboardingP4"])
        }
    }
}

private struct OnboardingHeader: View {
    var title: String
    var canSkip: Bool
    var onSkip: () -> Void

    var body: some View {
        HStack {
            HStack(spacing: 7) {
                Text(title)
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.ink)
                YenBadge(size: 18)
            }

            Spacer()

            if canSkip {
                Button("跳过") {
                    onSkip()
                }
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(WNFTheme.muted)
                .buttonStyle(.plain)
                .accessibilityLabel("跳到最后一步")
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 24)
    }
}

private struct OnboardingPage<Visual: View, Accessory: View>: View {
    var title: String
    var lead: String
    @ViewBuilder var visual: Visual
    @ViewBuilder var accessory: Accessory

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            visual

            VStack(alignment: .leading, spacing: 9) {
                Text(title)
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(lead)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(WNFTheme.muted)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            accessory

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

private struct OnboardingIntroPage: View {
    var title: String
    var lead: String
    var visualHeight: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingImagePanel(
                imageName: "OnboardingP1",
                height: visualHeight,
                imageScale: 1.12,
                imageOffset: CGSize(width: 0, height: 8)
            )

            Spacer(minLength: 28)

            VStack(alignment: .leading, spacing: 11) {
                Text(title)
                    .font(.system(size: 31, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.ink)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)

                Text(lead)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WNFTheme.muted)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            Spacer(minLength: 14)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 6)
    }
}

private struct OnboardingImagePanel: View {
    @EnvironmentObject private var imageStore: OnboardingImageStore

    var imageName: String
    var height: CGFloat
    var maxImageWidth: CGFloat? = nil
    var imageScale: CGFloat = 1
    var imageOffset: CGSize = .zero

    var body: some View {
        ZStack {
            Circle()
                .fill(WNFTheme.yellow.opacity(0.14))
                .frame(width: height * 1.26, height: height * 0.86)
                .blur(radius: 24)
                .offset(x: -height * 0.16, y: height * 0.10)

            Circle()
                .fill(Color.white.opacity(0.34))
                .frame(width: height * 1.18, height: height * 0.78)
                .blur(radius: 26)
                .offset(x: height * 0.16, y: -height * 0.06)

            CachedOnboardingImage(imageName: imageName)
                .scaledToFit()
                .frame(maxWidth: maxImageWidth)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .scaleEffect(imageScale)
                .offset(imageOffset)
                .blendMode(.multiply)
                .saturation(1.05)
                .contrast(1.02)
                .shadow(color: .black.opacity(0.06), radius: 12, y: 7)
                .accessibilityHidden(true)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .onAppear {
            imageStore.preload([imageName])
        }
    }
}

private struct LunchImagePanel: View {
    @EnvironmentObject private var imageStore: OnboardingImageStore
    @EnvironmentObject private var state: WageState

    var height: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(WNFTheme.yellow.opacity(0.14))
                .frame(width: height * 1.26, height: height * 0.86)
                .blur(radius: 24)
                .offset(x: -height * 0.16, y: height * 0.10)

            Circle()
                .fill(Color.white.opacity(0.34))
                .frame(width: height * 1.18, height: height * 0.78)
                .blur(radius: 26)
                .offset(x: height * 0.16, y: -height * 0.06)

            ZStack {
                CachedOnboardingImage(imageName: "OnboardingLunchWake")
                    .scaledToFit()
                    .opacity(state.hasLunchBreak ? 0 : 1)
                    .scaleEffect(state.hasLunchBreak ? 0.98 : 1)
                    .blendMode(.multiply)
                    .saturation(1.05)
                    .contrast(1.02)

                CachedOnboardingImage(imageName: "OnboardingLunchSleep")
                    .scaledToFit()
                    .opacity(state.hasLunchBreak ? 1 : 0)
                    .scaleEffect(state.hasLunchBreak ? 1 : 0.98)
                    .blendMode(.multiply)
                    .saturation(1.05)
                    .contrast(1.02)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .animation(.easeInOut(duration: 0.48), value: state.hasLunchBreak)
            .shadow(color: .black.opacity(0.06), radius: 12, y: 7)
            .accessibilityHidden(true)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .onAppear {
            imageStore.preload(["OnboardingLunchWake", "OnboardingLunchSleep", "OnboardingP4"])
        }
    }
}

private struct CachedOnboardingImage: View {
    @EnvironmentObject private var imageStore: OnboardingImageStore

    var imageName: String

    var body: some View {
        Group {
            if let image = imageStore.image(named: imageName) {
                Image(uiImage: image)
                    .resizable()
            } else {
                Image(imageName)
                    .resizable()
            }
        }
    }
}

private struct SalarySetupCard: View {
    @EnvironmentObject private var state: WageState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("月薪")
                    .font(.system(size: 12, weight: .black))
                    .foregroundStyle(WNFTheme.muted)
                Spacer()
                Text("\(Int(state.monthlySalary / 1000))k")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(WNFTheme.inkSoft)
            }

            HStack(spacing: 10) {
                IconControlButton(systemName: "minus") {
                    updateSalary(by: -500)
                }
                Text("¥\(Int(state.monthlySalary).formatted())")
                    .font(.system(size: 27, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.68)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(WNFTheme.ink, in: RoundedRectangle(cornerRadius: 18))
                IconControlButton(systemName: "plus") {
                    updateSalary(by: 500)
                }
            }

            Slider(value: salaryBinding, in: 3_000...80_000, step: 500)
                .tint(WNFTheme.ink)
                .accessibilityLabel("月薪")
        }
        .padding(14)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(WNFTheme.hairline, lineWidth: 0.5))
    }

    private func updateSalary(by delta: Double) {
        withAnimation(.snappy(duration: 0.18)) {
            state.adjustMonthlySalary(by: delta)
        }
    }

    private var salaryBinding: Binding<Double> {
        Binding {
            state.monthlySalary
        } set: { value in
            state.setMonthlySalary(value)
        }
    }
}

private struct WorkTimeSetupCard: View {
    @EnvironmentObject private var state: WageState

    private var lunchLength: Int {
        max(0, state.lunchEnd.minutesInDay - state.lunchStart.minutesInDay)
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 7) {
                LunchChoice(title: "有午休", isSelected: state.hasLunchBreak) {
                    withAnimation(.easeInOut(duration: 0.48)) {
                        state.hasLunchBreak = true
                    }
                }
                LunchChoice(title: "没有午休", isSelected: !state.hasLunchBreak) {
                    withAnimation(.easeInOut(duration: 0.48)) {
                        state.hasLunchBreak = false
                    }
                }
            }

            HStack {
                Text("\(WNFFormat.duration(state.calculation.workdayMinutes)) 计薪")
                Spacer()
                Text(state.hasLunchBreak ? "午休 \(WNFFormat.duration(lunchLength))" : "没有午休")
            }
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(WNFTheme.muted)

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    OnboardingTimePicker(title: "上班", components: $state.workStart)
                    OnboardingTimePicker(title: "下班", components: $state.workEnd)
                }

                HStack(spacing: 8) {
                    OnboardingTimePicker(title: "午休开始", components: $state.lunchStart)
                        .opacity(state.hasLunchBreak ? 1 : 0.36)
                        .disabled(!state.hasLunchBreak)
                    OnboardingTimePicker(title: "午休结束", components: $state.lunchEnd)
                        .opacity(state.hasLunchBreak ? 1 : 0.36)
                        .disabled(!state.hasLunchBreak)
                }
            }
            .animation(.easeInOut(duration: 0.24), value: state.hasLunchBreak)
        }
        .padding(10)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(WNFTheme.hairline, lineWidth: 0.5))
    }
}

private struct IconControlButton: View {
    var systemName: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 17, weight: .black))
                .foregroundStyle(WNFTheme.ink)
                .frame(width: 44, height: 44)
                .background(WNFTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

private struct LunchChoice: View {
    var title: String
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(isSelected ? Color.white : WNFTheme.muted)
                .frame(maxWidth: .infinity, minHeight: 36)
                .background(isSelected ? WNFTheme.ink : WNFTheme.surfaceSoft, in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }
}

private struct OnboardingTimePicker: View {
    var title: String
    @Binding var components: DateComponents

    private var date: Binding<Date> {
        Binding {
            DateComponents.calendar.date(from: components) ?? .now
        } set: { value in
            components = DateComponents.calendar.dateComponents([.hour, .minute], from: value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .black))
                .foregroundStyle(WNFTheme.muted)
            DatePicker("", selection: date, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(WNFTheme.yellow)
                .environment(\.locale, Locale(identifier: "zh_Hans"))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(WNFTheme.surfaceSoft.opacity(0.72), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct SummarySetupCard: View {
    @EnvironmentObject private var state: WageState

    private var day: WageDay { state.calculation }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("每个工作日目标")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(WNFTheme.muted)
                    Text(WNFFormat.money(day.targetToday, privacy: false))
                        .font(.system(size: 31, weight: .black, design: .rounded))
                        .foregroundStyle(WNFTheme.ink)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                }
                Spacer()
                YenBadge(size: 34)
            }
            .padding(.bottom, 10)

            Divider()
                .overlay(WNFTheme.hairline)

            SummaryLine(title: "每小时窝囊费", value: String(format: "¥%.0f", day.hourlyRate))
            SummaryLine(title: "计薪时长", value: WNFFormat.duration(day.workdayMinutes))
            SummaryLine(title: "午休状态", value: state.hasLunchBreak ? "有午休" : "没有午休")
        }
        .padding(16)
        .background(Color.white.opacity(0.92), in: RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(WNFTheme.hairline, lineWidth: 0.5))
    }
}

private struct SummaryLine: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(WNFTheme.inkSoft)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .black, design: .monospaced))
                .foregroundStyle(WNFTheme.ink)
        }
        .frame(height: 31)
    }
}

private struct OnboardingFooter: View {
    var page: Int
    var pageCount: Int
    var onBack: () -> Void
    var onNext: () -> Void
    var onSelect: (Int) -> Void

    var body: some View {
        VStack(spacing: 13) {
            HStack(spacing: 8) {
                ForEach(0..<pageCount, id: \.self) { index in
                    Button {
                        onSelect(index)
                    } label: {
                        Capsule()
                            .fill(index == page ? WNFTheme.ink : WNFTheme.ink.opacity(0.14))
                            .frame(width: index == page ? 24 : 8, height: 8)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("第 \(index + 1) 屏")
                }
            }

            HStack(spacing: 10) {
                if page > 0 {
                    Button {
                        onBack()
                    } label: {
                        Text("返回")
                            .font(.system(size: 15, weight: .black))
                            .foregroundStyle(WNFTheme.ink)
                            .frame(width: 92, height: 54)
                            .background(Color.white, in: Capsule())
                            .overlay(Capsule().stroke(WNFTheme.hairline, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    onNext()
                } label: {
                    Text(page == pageCount - 1 ? "开始使用" : "下一步")
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .background(WNFTheme.ink, in: Capsule())
                        .overlay(alignment: .trailing) {
                            Image(systemName: page == pageCount - 1 ? "checkmark" : "arrow.right")
                                .font(.system(size: 15, weight: .black))
                                .foregroundStyle(WNFTheme.yellow)
                                .padding(.trailing, 22)
                        }
                }
                .buttonStyle(.plain)
            }
            .shadow(color: .black.opacity(0.10), radius: 16, y: 8)
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
        .environmentObject(WageState())
}
