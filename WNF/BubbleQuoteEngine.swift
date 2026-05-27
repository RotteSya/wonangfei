import Foundation
import SwiftUI

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Drives the home page mascot's speech bubble: rotates a quote every ~5s
/// from a curated static pool, optionally enriched with on-device Apple
/// Intelligence-generated lines (iOS 26+ on supported hardware).
@MainActor
final class BubbleQuoteEngine: ObservableObject {
    @Published private(set) var currentQuote: String

    private var status: WorkStatus
    private var staticPool: [String]
    private var aiPool: [String] = []
    private var rotationTask: Task<Void, Never>?
    private var generationTask: Task<Void, Never>?

    private static let rotationSeconds: UInt64 = 5
    private static let aiBatchSize = 5
    private static let aiPoolCeiling = 8

    init(initialStatus: WorkStatus) {
        let presentation = WorkStatusPresentation(status: initialStatus)
        self.status = initialStatus
        self.staticPool = presentation.quotes
        self.currentQuote = presentation.quotes.first ?? ""
        startRotation()
        prefetchAIQuotes()
    }

    deinit {
        rotationTask?.cancel()
        generationTask?.cancel()
    }

    func setStatus(_ newStatus: WorkStatus) {
        guard newStatus != status else { return }
        status = newStatus
        staticPool = WorkStatusPresentation(status: newStatus).quotes
        aiPool.removeAll()
        generationTask?.cancel()
        let next = staticPool.first(where: { $0 != currentQuote }) ?? staticPool.first ?? currentQuote
        withAnimation(.easeInOut(duration: 0.25)) {
            currentQuote = next
        }
        prefetchAIQuotes()
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
        let next = pickNext()
        withAnimation(.easeInOut(duration: 0.25)) {
            currentQuote = next
        }
    }

    private func pickNext() -> String {
        if !aiPool.isEmpty {
            let aiNext = aiPool.removeFirst()
            if aiPool.count < 2 { prefetchAIQuotes() }
            if aiNext != currentQuote { return aiNext }
        }
        let candidates = staticPool.filter { $0 != currentQuote }
        return candidates.randomElement() ?? staticPool.first ?? currentQuote
    }

    private func prefetchAIQuotes() {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return }
        guard generationTask == nil || generationTask?.isCancelled == true else { return }
        let capturedStatus = status
        // Top up toward the ceiling, but cap per-batch generation cost at aiBatchSize.
        let needed = min(Self.aiBatchSize, max(0, Self.aiPoolCeiling - aiPool.count))
        guard needed > 0 else { return }
        generationTask = Task { [weak self] in
            await BubbleQuoteEngine.generateBatch(for: capturedStatus, count: needed) { [weak self] line in
                guard let self else { return }
                guard self.status == capturedStatus else { return }
                guard !self.aiPool.contains(line) else { return }
                guard line != self.currentQuote else { return }
                self.aiPool.append(line)
            }
            await MainActor.run { [weak self] in
                self?.generationTask = nil
            }
        }
        #endif
    }

    #if canImport(FoundationModels)
    @available(iOS 26.0, *)
    @Generable
    struct AIQuote {
        @Guide(description: "10 到 16 个汉字的中文吐槽")
        var line: String
    }

    @available(iOS 26.0, *)
    private static func generateBatch(
        for status: WorkStatus,
        count: Int,
        append: @MainActor @escaping (String) -> Void
    ) async {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return }

        let instructions = Instructions {
            """
            你是窝囊费 app 里那只摸鱼的窝囊牛在工位上的内心独白。
            每次只回一句中文吐槽，要求：
            - 自嘲、温和、带 deadpan-warm 的丧
            - 优先用打工人词汇：搬砖、工位、回血、打工、房租、咖啡钱、外卖、奶茶、邮件、会议、PPT
            - 严禁出现：emoji、unicode 图标、"提升效率"、"智能洞察"、"数据驱动"、"用户"、"您"
            - 长度 10 到 16 个汉字，句末标点可有可无
            - 每次换个角度，不要复读上一句
            """
        }

        let contextLine = statusContext(for: status)
        let session = LanguageModelSession(instructions: instructions)

        for _ in 0..<count {
            if Task.isCancelled { return }
            do {
                let response = try await session.respond(
                    to: "场景：\(contextLine)。再来一句新的，不要重复。",
                    generating: AIQuote.self
                )
                let cleaned = sanitize(response.content.line)
                if !cleaned.isEmpty {
                    await MainActor.run { append(cleaned) }
                }
            } catch {
                continue
            }
        }
    }

    @available(iOS 26.0, *)
    private static func statusContext(for status: WorkStatus) -> String {
        switch status {
        case .before:    return "还没到上班时间，窝囊牛在通勤或刚起床，时薪是零"
        case .morning:   return "上午在工位搬砖，状态半死不活"
        case .lunch:     return "午休回血，正在吃饭或趴桌小睡，吃饭这段不发工资"
        case .afternoon: return "下午挺挺，离下班还有一段，钱在慢慢涨"
        case .done:      return "今日通关下班了，可以回家"
        }
    }

    private static let bannedSubstrings: [String] = [
        "您", "用户", "智能洞察", "提升效率", "数据驱动"
    ]

    @available(iOS 26.0, *)
    private static func sanitize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip emoji-like scalars: default-emoji presentation, modifiers,
        // ZWJ (used to glue emoji sequences), and variation selectors.
        s = String(s.unicodeScalars.filter { scalar in
            if scalar.value == 0x200D { return false }
            if scalar.value == 0xFE0E || scalar.value == 0xFE0F { return false }
            if scalar.properties.isEmojiPresentation { return false }
            if scalar.properties.isEmojiModifier { return false }
            if scalar.properties.isEmojiModifierBase { return false }
            return true
        })
        s = s.replacingOccurrences(of: "/", with: " · ")
        s = s.replacingOccurrences(of: "|", with: " · ")
        if s.count > 18 { s = String(s.prefix(18)) }
        // Hard reject if a banned voice-rule substring slipped through the
        // model's instructions — the empty return causes the caller to drop it.
        if bannedSubstrings.contains(where: { s.contains($0) }) {
            return ""
        }
        return s
    }
    #endif
}
