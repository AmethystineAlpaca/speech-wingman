import Foundation

public enum Decision: String, Codable, Sendable {
    case alert, noAlert = "no_alert", deferDecision = "defer", inconclusive
}

public struct VoiceResult: Codable, Sendable, Equatable {
    public let transcript: String
    public let decision: Decision
    public let quote: String
    public let suggestion: String
}

public enum Sensitivity: String, Codable, Sendable, CaseIterable {
    case low, medium, high
    /// Stable inference profiles. UI levels select a profile through
    /// SessionConfiguration.evaluationSensitivity; prompt wording is kept intact.
    public var instruction: String {
        switch self {
        case .low:
            "低敏感度：只在发言直接、明确、无歧义地满足规则时提醒。需要猜测的暗示、委婉表达和边界情况不提醒。"
        case .medium:
            "中敏感度：发言明确满足规则就提醒，包括清楚的同义表达和明确的隐含意思。模糊、有同样合理的中性解释时不提醒。"
        case .high:
            "高敏感度：优先减少漏报。发言中有具体证据支持的暗示、委婉表达、可能命中和边界情况都提醒，不要求完全确定或使用规则中的原词。完全无关或没有触发证据时不提醒。"
        }
    }
    public var titleKey: String {
        switch self { case .low: "低"; case .medium: "中"; case .high: "高" }
    }
    public var summaryKey: String {
        switch self { case .low: "仅明显命中"; case .medium: "明确语义匹配"; case .high: "包括边界情况" }
    }
    public var descriptionKey: String {
        switch self {
        case .low: "低：只在表达直接、证据明确时提醒，尽量减少打扰。"
        case .medium: "中：也识别清楚的同义表达和隐含意思；模糊情况保持安静。"
        case .high: "高：有相关证据的暗示和可能命中也提醒，优先减少漏报。"
        }
    }
}

public struct SessionConfiguration: Codable, Sendable {
    public static let routedRuleThreshold = 8
    public static let sensitivityMappingVersion = "routed-recall-v1"
    /// App sessions always set this. Nil preserves legacy evaluation fixtures and exports.
    public var responseLanguage: DisplayLanguage?
    public var prompt: String
    /// Each nonempty line is one independent rule, including its own exclusions.
    public var rules: [String] {
        prompt.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    public var sensitivity: Sensitivity
    /// Calibrated on a common positive set, not on level-specific denominators.
    /// Large-rule routing and independent small-rule checks have different recall
    /// rankings, so preserve the measured winner for each existing inference path.
    public var evaluationSensitivity: Sensitivity {
        guard rules.count >= Self.routedRuleThreshold else { return sensitivity }
        switch sensitivity {
        case .low: return .low
        case .medium: return .high
        case .high: return .medium
        }
    }
    public var evaluationProfileID: String { "legacy-" + evaluationSensitivity.rawValue }
    public var version: Int
    public init(prompt: String, sensitivity: Sensitivity = .medium, version: Int = 1, responseLanguage: DisplayLanguage? = nil) {
        self.responseLanguage = responseLanguage
        self.prompt = prompt; self.sensitivity = sensitivity; self.version = version
    }
}

public enum EvaluationStatus: String, Codable, Sendable {
    case pending, evaluating, evaluated, expired, overflow, cancelled, invalid
}

public struct StatementEvaluationRecord: Codable, Sendable {
    public let id: UUID
    public let segmentIDs: [UUID]
    public let text: String
    public let configurationVersion: Int
    public var status: EvaluationStatus
    public var decision: Decision?
    public var alertDisposition: String?
    public var startedAt: Date?
    public var completedAt: Date?
    public var errorMessage: String?
    public var inputText: String?
    public var continuedFromID: UUID?
    public var matchedRuleIndex: Int?
    public init(id: UUID, segmentIDs: [UUID], text: String, configurationVersion: Int) {
        self.id = id; self.segmentIDs = segmentIDs; self.text = text
        self.configurationVersion = configurationVersion; status = .pending
    }
}

public struct TranscriptEntry: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let text: String
    public let decision: Decision
    public let configurationVersion: Int
    public let isFinal: Bool
    public var evaluationStatus: EvaluationStatus?
    public init(id: UUID, date: Date, text: String, decision: Decision, configurationVersion: Int, isFinal: Bool = true, evaluationStatus: EvaluationStatus? = nil) {
        self.id = id; self.date = date; self.text = text
        self.decision = decision; self.configurationVersion = configurationVersion
        self.isFinal = isFinal; self.evaluationStatus = evaluationStatus
    }
}

public struct AlertEntry: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let quote: String
    public let suggestion: String
    public let configurationVersion: Int
    public init(id: UUID, date: Date, quote: String, suggestion: String, configurationVersion: Int) {
        self.id = id; self.date = date; self.quote = quote
        self.suggestion = suggestion; self.configurationVersion = configurationVersion
    }
}

public enum WingmanError: Error, LocalizedError, Sendable {
    case invalidResult(String), unavailable(String), worker(String), cancelled
    public var errorDescription: String? {
        switch self {
        case .invalidResult(let reason): "模型输出未通过校验：\(reason)"
        case .unavailable(let reason): reason
        case .worker(let reason): "本地模型错误：\(reason)"
        case .cancelled: "已取消"
        }
    }
}

public extension Error {
    var isContextCapacityExceeded: Bool {
        guard let error = self as? WingmanError, case .worker(let message) = error else { return false }
        return message == "context capacity exceeded" || message == "prompt too long"
    }

    var isWorkerBusy: Bool {
        guard let error = self as? WingmanError, case .worker(let message) = error else { return false }
        return message.localizedCaseInsensitiveContains("busy") || message.contains("worker 忙")
    }
}
