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
    public var instruction: String {
        switch self {
        case .low: "Only alert for unambiguous matches to the configured policy."
        case .medium: "Alert when the policy is met and there is sufficient evidence."
        case .high: "Include borderline matches to the policy, but never invent evidence."
        }
    }
}

public struct SessionConfiguration: Codable, Sendable {
    public var prompt: String
    public var sensitivity: Sensitivity
    public var version: Int
    public init(prompt: String, sensitivity: Sensitivity = .medium, version: Int = 1) {
        self.prompt = prompt; self.sensitivity = sensitivity; self.version = version
    }
}

public struct TranscriptEntry: Identifiable, Codable, Sendable {
    public let id: UUID
    public let date: Date
    public let text: String
    public let decision: Decision
    public let configurationVersion: Int
    public let isFinal: Bool
    public init(id: UUID, date: Date, text: String, decision: Decision, configurationVersion: Int, isFinal: Bool = true) {
        self.id = id; self.date = date; self.text = text
        self.decision = decision; self.configurationVersion = configurationVersion
        self.isFinal = isFinal
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
