import Foundation

public struct AlertGate: Sendable {
    public var cooldown: TimeInterval = 30
    public var maximumPerTenMinutes = 3
    public var mutedUntil: Date?
    private var shownEvents: Set<UUID> = []
    private var shownDates: [Date] = []
    public init() {}
    public mutating func resetSession() { shownEvents.removeAll(); shownDates.removeAll() }
    public mutating func admit(_ result: VoiceResult, eventID: UUID, isFinal: Bool, now: Date) -> Bool {
        guard result.decision == .alert, isFinal,
              !shownEvents.contains(eventID), mutedUntil.map({ now >= $0 }) ?? true else { return false }
        shownDates.removeAll { now.timeIntervalSince($0) >= 600 }
        guard shownDates.count < maximumPerTenMinutes,
              shownDates.last.map({ now.timeIntervalSince($0) >= cooldown }) ?? true else { return false }
        shownEvents.insert(eventID); shownDates.append(now)
        return true
    }
}
