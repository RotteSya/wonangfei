import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case records
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .records: "记录"
        case .settings: "我的"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .records: "chart.bar"
        case .settings: "person"
        }
    }
}

struct RootView: View {
    @State private var selectedTab: AppTab = .home
    @State private var entryAnimating = false
    @State private var entryExpanded = false
    @AppStorage("wnf.onboarding.completed") private var onboardingCompleted = false

    var body: some View {
        ZStack {
            if onboardingCompleted || entryAnimating {
                appShell
                    .scaleEffect(entryAnimating && !entryExpanded ? 0.88 : 1)
                    .opacity(entryAnimating && !entryExpanded ? 0.18 : 1)
                    .blur(radius: entryAnimating && !entryExpanded ? 12 : 0)
                    .allowsHitTesting(onboardingCompleted && !entryAnimating)
                    .animation(.spring(response: 0.82, dampingFraction: 0.82), value: entryExpanded)
            }

            if !onboardingCompleted {
                OnboardingView {
                    startHomeEntrance()
                }
                .scaleEffect(entryAnimating ? 1.08 : 1)
                .opacity(entryAnimating ? 0 : 1)
                .blur(radius: entryAnimating ? 16 : 0)
                .transition(.opacity)
                .animation(.easeInOut(duration: 0.46), value: entryAnimating)
            }

            if entryAnimating {
                HomeEntranceOverlay(expanded: entryExpanded)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .preferredColorScheme(.light)
    }

    private func startHomeEntrance() {
        guard !entryAnimating else { return }
        selectedTab = .home
        entryAnimating = true
        entryExpanded = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            withAnimation(.spring(response: 0.9, dampingFraction: 0.74)) {
                entryExpanded = true
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.68) {
            onboardingCompleted = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.28) {
            withAnimation(.easeOut(duration: 0.22)) {
                entryAnimating = false
            }
            entryExpanded = false
        }
    }

    private var appShell: some View {
        ZStack(alignment: .bottom) {
            WNFTheme.bg.ignoresSafeArea()

            Group {
                switch selectedTab {
                case .home:
                    HomeView()
                case .records:
                    RecordsView()
                case .settings:
                    SettingsView {
                        onboardingCompleted = false
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            AppTabBar(selectedTab: $selectedTab)
                .padding(.bottom, 10)
        }
    }
}

struct AppTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.25)) {
                        selectedTab = tab
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol)
                            .font(.system(size: 15, weight: .bold))
                        if selectedTab == tab {
                            Text(tab.title)
                                .font(.system(size: 13, weight: .heavy))
                        }
                    }
                    .foregroundStyle(selectedTab == tab ? Color.white : WNFTheme.inkSoft)
                    .padding(.horizontal, selectedTab == tab ? 17 : 13)
                    .frame(height: 44)
                    .background {
                        if selectedTab == tab {
                            Capsule().fill(WNFTheme.ink)
                        }
                    }
                    .overlay {
                        if selectedTab == tab {
                            Image(systemName: tab.symbol)
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(WNFTheme.yellow)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 17)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tab.title)
            }
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
    }
}

private struct HomeEntranceOverlay: View {
    var expanded: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = min(proxy.size.width, proxy.size.height)

            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(expanded ? 0.0 : 0.96),
                                WNFTheme.yellow.opacity(expanded ? 0.0 : 0.72),
                                WNFTheme.gold.opacity(0)
                            ],
                            center: .center,
                            startRadius: 1,
                            endRadius: size * 0.62
                        )
                    )
                    .frame(width: expanded ? size * 2.6 : 42, height: expanded ? size * 2.6 : 42)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                    .opacity(expanded ? 0 : 1)

                ForEach(0..<18, id: \.self) { index in
                    EntranceCoin(index: index, expanded: expanded)
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }

                Text("¥")
                    .font(.system(size: expanded ? 86 : 34, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.yellow)
                    .shadow(color: .black.opacity(0.18), radius: 10, y: 5)
                    .scaleEffect(expanded ? 1.25 : 0.4)
                    .opacity(expanded ? 0 : 1)
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(WNFTheme.bg.opacity(expanded ? 0 : 0.22))
        }
    }
}

private struct EntranceCoin: View {
    var index: Int
    var expanded: Bool

    private var angle: Double {
        Double(index) / 18 * .pi * 2
    }

    private var distance: CGFloat {
        expanded ? CGFloat(132 + (index % 5) * 28) : 0
    }

    private var fontSize: CGFloat {
        CGFloat(15 + (index % 4) * 3)
    }

    private var coinSize: CGFloat {
        CGFloat(28 + (index % 3) * 5)
    }

    private var xOffset: CGFloat {
        CGFloat(cos(angle)) * distance
    }

    private var yOffset: CGFloat {
        CGFloat(sin(angle)) * distance
    }

    private var confettiColor: Color {
        index % 2 == 0 ? WNFTheme.coral : Color(red: 0.49, green: 0.78, blue: 0.38)
    }

    private var isCoin: Bool {
        index % 3 != 0
    }

    var body: some View {
        content
        .offset(x: xOffset, y: yOffset)
        .scaleEffect(expanded ? 1 : 0.22)
        .rotationEffect(.degrees(expanded ? Double(index * 31 + 90) : 0))
        .opacity(expanded ? 0 : 1)
        .animation(.spring(response: 0.72, dampingFraction: 0.78).delay(Double(index % 5) * 0.018), value: expanded)
    }

    @ViewBuilder
    private var content: some View {
        if isCoin {
            Text("¥")
                .font(.system(size: fontSize, weight: .black, design: .rounded))
                .foregroundStyle(Color.white)
                .frame(width: coinSize, height: coinSize)
                .background(WNFTheme.yellow, in: Circle())
                .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
        } else {
            RoundedRectangle(cornerRadius: 5)
                .fill(confettiColor)
                .frame(width: 16, height: 11)
                .rotationEffect(.degrees(Double(index * 17)))
        }
    }
}

#Preview {
    RootView()
        .environmentObject(WageState())
}
