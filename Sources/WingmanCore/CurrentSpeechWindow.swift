import Foundation

/// At most one waiting segment. Slow inference must not turn into a queue of old alerts.
public struct CurrentSpeechWindow: Sendable {
    public static let maximumAge: TimeInterval = 20
    public static let maximumCharacters = 1500
    public private(set) var latest: TranscriptEntry?
    private var newestID: UUID?
    public init() {}

    public mutating func append(_ entry: TranscriptEntry) {
        guard entry.isFinal else { return }
        newestID = entry.id
        // Never cut a sentence: truncation can remove an exclusion or a negation.
        latest = entry.text.count <= Self.maximumCharacters ? entry : nil
    }
    public mutating func take(now: Date) -> TranscriptEntry? {
        defer { latest = nil }
        guard let latest, Self.isFresh(latest, now: now) else { return nil }
        return latest
    }
    public func canPresent(_ entry: TranscriptEntry, now: Date) -> Bool {
        newestID == entry.id && latest == nil && Self.isFresh(entry, now: now)
    }
    public static func isFresh(_ entry: TranscriptEntry, now: Date) -> Bool {
        (0...maximumAge).contains(now.timeIntervalSince(entry.date))
    }
    public mutating func reset() { latest = nil; newestID = nil }
}
