import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var state: WageState

    private var day: WageDay { state.calculation }

    var body: some View {
        ZStack {
            WNFTheme.bg.ignoresSafeArea()

            HeroHomePage(day: day)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}

private struct HeroHomePage: View {
    @EnvironmentObject private var state: WageState
    var day: WageDay

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TopBar()
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 14) {
                StatusChip(label: day.status.label)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 5) {
                    Text("今 日 窝 囊 费")
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(5)
                        .foregroundStyle(WNFTheme.inkSoft)

                    BigMoneyText(value: day.earnedToday, privacy: state.privacyMode)
                }

                HStack(spacing: 18) {
                    Text("已忍 \(WNFFormat.duration(day.elapsedPaidMinutes))")
                    Circle().fill(WNFTheme.muted).frame(width: 4, height: 4)
                    Text("离下班 \(WNFFormat.duration(day.wallToEndMinutes))")
                }
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(WNFTheme.inkSoft)

                ProgressTrack(day: day, startText: state.workStart.clockText, endText: state.workEnd.clockText)
            }
            .padding(.horizontal, 22)

            Spacer(minLength: 16)

            ZStack(alignment: .topLeading) {
                Image(day.status.mascotAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 285)
                    .frame(maxWidth: .infinity)

                Text(day.status.quote)
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(WNFTheme.ink)
                    .padding(.horizontal, 15)
                    .padding(.vertical, 11)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 17))
                    .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                    .offset(x: 42, y: 18)

                YenCoin(size: 25)
                    .offset(x: UIScreen.main.bounds.width - 84, y: 72)
                YenCoin(size: 22)
                    .offset(x: 48, y: 220)
            }
            .frame(maxWidth: .infinity)
            .padding(.bottom, 145)
        }
    }
}

private struct BigMoneyText: View {
    var value: Double
    var privacy: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("¥")
                .foregroundStyle(WNFTheme.yellow)
            if privacy {
                Text("•••")
                    .tracking(4)
                Text(".••")
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.muted)
            } else {
                let totalCents = max(0, Int((value * 100).rounded(.down)))
                let integer = totalCents / 100
                let cents = totalCents % 100
                Text(integer.formatted(.number.grouping(.automatic)))
                Text(String(format: ".%02d", cents))
                    .font(.system(size: 46, weight: .black, design: .rounded))
                    .foregroundStyle(WNFTheme.muted)
            }
        }
        .font(.system(size: 86, weight: .black, design: .rounded))
        .minimumScaleFactor(0.58)
        .lineLimit(1)
        .contentTransition(.numericText(value: value))
        .animation(.linear(duration: 0.2), value: value)
    }
}

private struct ProgressTrack: View {
    var day: WageDay
    var startText: String
    var endText: String

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(red: 0.95, green: 0.90, blue: 0.75))
                    Capsule()
                        .fill(LinearGradient(colors: [WNFTheme.gold, WNFTheme.yellow], startPoint: .leading, endPoint: .trailing))
                        .frame(width: proxy.size.width * day.progress)
                    if day.progress > 0 && day.progress < 1 {
                        Circle()
                            .fill(Color.white)
                            .overlay(Circle().stroke(WNFTheme.ink, lineWidth: 3))
                            .frame(width: 15, height: 15)
                            .offset(x: max(0, proxy.size.width * day.progress - 7))
                    }
                }
            }
            .frame(height: 13)

            HStack {
                Text(startText)
                Spacer()
                Text("\(Int(day.progress * 100))%")
                Spacer()
                Text(endText)
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundStyle(WNFTheme.muted)
        }
    }
}

private struct YenCoin: View {
    var size: CGFloat

    var body: some View {
        Text("¥")
            .font(.system(size: size * 0.58, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RadialGradient(colors: [Color(red: 1, green: 0.92, blue: 0.62), WNFTheme.gold], center: .topLeading, startRadius: 2, endRadius: size),
                in: Circle()
            )
            .shadow(color: WNFTheme.gold.opacity(0.45), radius: 8, y: 4)
    }
}

#Preview {
    HomeView()
        .environmentObject(WageState())
}
