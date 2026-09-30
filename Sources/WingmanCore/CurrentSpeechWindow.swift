import Foundation

/// A small FIFO lets in-flight work finish without building an unbounded backlog.
public struct CurrentSpeechWindow: Sendable {
    public static let maximumAge: TimeInterval = 30
    public static let maximumCharacters = 1500
    public static let maximumPending = 4
    private var waiting: [TranscriptEntry] = []
    private var inFlightID: UUID?
    public var latest: TranscriptEntry? { waiting.last }
    public init() {}

    /// Returns evicted input so callers can distinguish skipped work from a model decision.
    @discardableResult public mutating func append(_ entry: TranscriptEntry) -> [TranscriptEntry] {
        guard entry.isFinal else { return [] }
        // Never truncate: that could remove an explanation or exclusion.
        guard entry.text.count <= Self.maximumCharacters else { return [entry] }
        waiting.append(entry)
        return waiting.count > Self.maximumPending ? [waiting.removeFirst()] : []
    }
    public mutating func removeExpired(now: Date) -> [TranscriptEntry] {
        let expired = waiting.filter { !Self.isFresh($0, now: now) }
        waiting.removeAll { !Self.isFresh($0, now: now) }
        return expired
    }
    public mutating func take(now: Date) -> TranscriptEntry? {
        _ = removeExpired(now: now)
        let entry = waiting.isEmpty ? nil : waiting.removeFirst()
        inFlightID = entry?.id
        return entry
    }
    public func canPresent(_ entry: TranscriptEntry, now: Date) -> Bool {
        inFlightID == entry.id && Self.isFresh(entry, now: now)
    }
    public static func isFresh(_ entry: TranscriptEntry, now: Date) -> Bool {
        (0...maximumAge).contains(now.timeIntervalSince(entry.date))
    }
    public mutating func reset() { waiting.removeAll(); inFlightID = nil }
}

/// VAD endpoints are pauses, not semantic sentence boundaries. Collect nearby finals
/// before evaluating, without attaching older conversation history to a new statement.
public struct SpeechStatementBuffer: Sendable {
    public static let settlingSeconds: TimeInterval = 1.5
    public static let maximumDuration: TimeInterval = 12
    private var segments: [TranscriptEntry] = []
    public var startedAt: Date? { segments.first?.date }
    public init() {}

    /// A configuration change or size bound closes the previous statement.
    /// The caller flushes after silence; a long ASR continuation may span several seconds.
    public mutating func append(_ entry: TranscriptEntry) -> [TranscriptEntry]? {
        guard entry.isFinal else { return nil }
        var completed: [TranscriptEntry]?
        if let last = segments.last, let first = segments.first,
           entry.configurationVersion != last.configurationVersion ||
            entry.date.timeIntervalSince(first.date) >= Self.maximumDuration ||
            segments.map(\.text).joined(separator: "\n").count + entry.text.count + 1 > CurrentSpeechWindow.maximumCharacters {
            completed = flush()
        }
        segments.append(entry)
        return completed
    }
    public mutating func flush() -> [TranscriptEntry] {
        defer { segments.removeAll() }
        return segments
    }
    public mutating func reset() { segments.removeAll() }
}

/// Only an explicit model `defer` can carry into the immediately following
/// statement. No topic keywords, alert history, or unbounded context is retained.
public struct DeferredSpeechContinuation: Sendable {
    public static let maximumGap = SpeechStatementBuffer.maximumDuration * 2
    private var previous: TranscriptEntry?
    public init() {}
    public mutating func input(for entry: TranscriptEntry) -> (text: String, continuedFrom: UUID?) {
        defer { previous = nil }
        guard let previous, previous.configurationVersion == entry.configurationVersion,
              (0...Self.maximumGap).contains(entry.date.timeIntervalSince(previous.date)) else { return (entry.text, nil) }
        let joined = previous.text + "\n" + entry.text
        guard joined.count <= CurrentSpeechWindow.maximumCharacters else { return (entry.text, nil) }
        return (joined, previous.id)
    }
    public mutating func remember(_ originalEntry: TranscriptEntry, decision: Decision) {
        // Remember only the current original input, never the accumulated input.
        previous = decision == .deferDecision ? originalEntry : nil
    }
    public mutating func reset() { previous = nil }
}
