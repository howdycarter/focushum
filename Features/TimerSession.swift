import Foundation
import SwiftData

enum SessionKind: String, Codable {
    case work       = "work"
    case shortBreak = "shortBreak"
    case longBreak  = "longBreak"

    var label: String {
        switch self {
        case .work:       return "Focus"
        case .shortBreak: return "Short Break"
        case .longBreak:  return "Long Break"
        }
    }
}

@Model
final class TimerSession {
    var id: UUID
    var startDate: Date
    var endDate: Date?
    var plannedDuration: TimeInterval
    var elapsedSeconds: TimeInterval
    var sessionKindRaw: String
    var noiseTypeRaw: String
    var completed: Bool

    init(
        startDate: Date = .now,
        plannedDuration: TimeInterval,
        sessionKind: SessionKind,
        noiseType: NoiseType
    ) {
        self.id               = UUID()
        self.startDate        = startDate
        self.plannedDuration  = plannedDuration
        self.elapsedSeconds   = 0
        self.sessionKindRaw   = sessionKind.rawValue
        self.noiseTypeRaw     = noiseType.rawValue
        self.completed        = false
    }

    var sessionKind: SessionKind {
        SessionKind(rawValue: sessionKindRaw) ?? .work
    }

    var noiseType: NoiseType {
        NoiseType(rawValue: noiseTypeRaw) ?? .brown
    }

    var dayString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: startDate)
    }
}
