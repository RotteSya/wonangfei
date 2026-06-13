import SwiftUI

// MARK: - Horizontal gesture arbitration
//
// The pager's swipe and the records chart's scrub are both horizontal drags
// living on the same screen. Whoever's gesture sees its first event claims
// the axis for the duration of that touch; the other backs off. The chart
// attaches a `minimumDistance: 0` drag so it always wins on its own pixels.
@MainActor
final class HorizontalGestureArbiter: ObservableObject {
    enum Owner {
        case pager
        case chartScrub
    }

    private(set) var owner: Owner?

    /// Returns true when `candidate` may drive this touch.
    func claim(_ candidate: Owner) -> Bool {
        if owner == nil || owner == candidate {
            owner = candidate
            return true
        }
        return false
    }

    func release(_ candidate: Owner) {
        if owner == candidate {
            owner = nil
        }
    }
}

// MARK: - Jelly stretch environment
//
// RootView owns the pager's jelly amount; pages that can't take a full-layer
// distortion (the home page hosts an AVPlayerLayer, which SwiftUI shader
// effects cannot rasterize) read this to apply tailored squish to their
// SwiftUI-native subtrees instead.
private struct PagerJellyStretchKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    var pagerJellyStretch: CGFloat {
        get { self[PagerJellyStretchKey.self] }
        set { self[PagerJellyStretchKey.self] = newValue }
    }
}

// MARK: - Per-page depth treatment

/// Parallax + dim + scale for pages as they enter/leave the viewport.
/// `rel` is the page's signed distance from the viewport center in page
/// widths (0 = front and center, ±1 = fully off).
struct PageDepthFX: ViewModifier {
    var rel: CGFloat

    func body(content: Content) -> some View {
        let r = max(-1, min(1, rel))
        content
            .offset(x: r * 16)
            .scaleEffect(1 - 0.022 * abs(r))
            .brightness(-0.035 * abs(r))
    }
}

// MARK: - Continuous tab bar

/// The bottom capsule bar, rebuilt around a continuous `progress` (0…2)
/// instead of a discrete selection: the ink pill glides and stretches between
/// items in lock-step with the pager drag, and squishes against the wall when
/// the pager rubber-bands past the first/last page.
struct AppTabBar: View {
    var progress: CGFloat
    var onSelect: (AppTab) -> Void

    private static let baseWidth: CGFloat = 47
    private static let extraWidth: CGFloat = 35
    private static let spacing: CGFloat = 4
    private static let itemHeight: CGFloat = 44

    private func selection(_ index: Int) -> CGFloat {
        max(0, 1 - abs(min(max(progress, 0), 2) - CGFloat(index)))
    }

    private func itemWidth(_ index: Int) -> CGFloat {
        Self.baseWidth + Self.extraWidth * selection(index)
    }

    private func itemLeft(_ index: Int) -> CGFloat {
        (0..<index).reduce(0) { $0 + itemWidth($1) + Self.spacing }
    }

    private var pill: (x: CGFloat, width: CGFloat) {
        let clamped = min(max(progress, 0), 2)
        let lower = Int(clamped.rounded(.down))
        let upper = min(lower + 1, 2)
        let t = clamped - CGFloat(lower)
        let x = lerp(itemLeft(lower), itemLeft(upper), t)
        let width = lerp(itemWidth(lower), itemWidth(upper), t)
        // Squish against the wall while rubber-banding past either end; the
        // pill compresses toward whichever wall is being pressed.
        let overscroll = max(0, -progress) + max(0, progress - 2)
        let squishedWidth = width * (1 - min(0.24, overscroll * 0.5))
        let anchoredX = progress > 2 ? x + (width - squishedWidth) : x
        return (anchoredX, squishedWidth)
    }

    var body: some View {
        HStack(spacing: Self.spacing) {
            ForEach(AppTab.allCases) { tab in
                item(for: tab)
            }
        }
        .background(alignment: .leading) {
            let p = pill
            Capsule()
                .fill(WNFTheme.ink)
                .frame(width: p.width, height: Self.itemHeight)
                .offset(x: p.x)
        }
        .padding(6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.8), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.16), radius: 18, y: 10)
    }

    private func item(for tab: AppTab) -> some View {
        let index = tab.order
        let sel = selection(index)

        return Button {
            onSelect(tab)
        } label: {
            ZStack {
                // Resting face: centered mono icon.
                Image(systemName: tab.symbol)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(WNFTheme.inkSoft)
                    .opacity(Double(1 - sel))

                // Active face: yellow icon + label, pinned leading.
                HStack(spacing: 6) {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(WNFTheme.yellow)
                    Text(tab.title)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .fixedSize()
                        .opacity(Double(max(0, sel * 1.6 - 0.6)))
                }
                .opacity(Double(sel))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 16)
            }
            .frame(width: itemWidth(index), height: Self.itemHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(.squish(0.9))
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("tab.\(tab.rawValue)")
        .accessibilityAddTraits(sel > 0.5 ? [.isSelected] : [])
    }
}

private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
    a + (b - a) * t
}

#Preview("Tab bar sweep") {
    struct BarPreview: View {
        @State private var progress: CGFloat = 0

        var body: some View {
            VStack(spacing: 40) {
                AppTabBar(progress: progress, onSelect: { _ in })
                Slider(value: $progress, in: -0.4...2.4)
                    .padding(.horizontal, 40)
            }
            .padding(40)
            .background(WNFTheme.bg)
        }
    }
    return BarPreview()
}
