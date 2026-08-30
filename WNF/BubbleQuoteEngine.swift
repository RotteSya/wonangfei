import Foundation
import SwiftUI

/// Rotates the mascot's own short, curated coworker lines every ~8 seconds.
@MainActor
final class BubbleQuoteEngine: ObservableObject {
    @Published private(set) var currentQuote: String
    @Published private(set) var bubbleOffset: CGSize

    private var status: WorkStatus
    private var staticPool: [String]
    private var currentBase: String
    private var rotationTask: Task<Void, Never>?

    private static let rotationSeconds: UInt64 = 8
    // Bubble position drifts within a small band relative to the mascot
    // stage's topLeading corner. The mascot stage sits below the 今日结算
    // card so any value here keeps the bubble strictly below that card.
    private static let offsetXRange: ClosedRange<CGFloat> = 30...75
    private static let offsetYRange: ClosedRange<CGFloat> = 8...30

    init(initialStatus: WorkStatus) {
        let presentation = WorkStatusPresentation(status: initialStatus)
        let base = presentation.quotes.first ?? ""
        self.status = initialStatus
        self.staticPool = presentation.quotes
        self.currentBase = base
        self.currentQuote = base
        self.bubbleOffset = Self.randomOffset()
        startRotation()
    }

    deinit {
        rotationTask?.cancel()
    }

    func setStatus(_ newStatus: WorkStatus) {
        guard newStatus != status else { return }
        status = newStatus
        staticPool = WorkStatusPresentation(status: newStatus).quotes
        let nextBase = staticPool.first(where: { $0 != currentBase }) ?? staticPool.first ?? currentBase
        currentBase = nextBase
        let newOffset = Self.randomOffset()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.66)) {
            currentQuote = nextBase
            bubbleOffset = newOffset
        }
    }

    private func startRotation() {
        rotationTask?.cancel()
        rotationTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.rotationSeconds * 1_000_000_000)
                if Task.isCancelled { return }
                self?.advance()
            }
        }
    }

    private func advance() {
        let nextBase = pickNext()
        currentBase = nextBase
        let newOffset = Self.randomOffset()
        withAnimation(.spring(response: 0.45, dampingFraction: 0.66)) {
            currentQuote = nextBase
            bubbleOffset = newOffset
        }
    }

    private func pickNext() -> String {
        let candidates = staticPool.filter { $0 != currentBase }
        return candidates.randomElement() ?? staticPool.first ?? currentBase
    }

    private static func randomOffset() -> CGSize {
        CGSize(
            width: CGFloat.random(in: offsetXRange),
            height: CGFloat.random(in: offsetYRange)
        )
    }

}
