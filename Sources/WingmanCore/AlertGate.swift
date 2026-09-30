import Foundation

public struct AlertGate: Sendable {
    public var cooldown: TimeInterval = 0
    public var maximumPerTenMinutes = Int.max
    public var mutedUntil: Date?
    private var shownEvents: [UUID: Date] = [:]
    private var shownDates: [Date] = []
    public init() {}
    public mutating func resetSession() { shownEvents.removeAll(); shownDates.removeAll() }
    public mutating func admit(_ result: VoiceResult, eventID: UUID, isFinal: Bool, now: Date) -> Bool {
        guard result.decision == .alert, isFinal,
              shownEvents[eventID] == nil, mutedUntil.map({ now >= $0 }) ?? true else { return false }
        shownDates.removeAll { now.timeIntervalSince($0) >= 600 }
        guard shownDates.count < maximumPerTenMinutes,
              shownDates.last.map({ now.timeIntervalSince($0) >= cooldown }) ?? true else { return false }
        shownEvents = shownEvents.filter { now.timeIntervalSince($0.value) < 600 }
        shownEvents[eventID] = now; shownDates.append(now)
        return true
    }
}
