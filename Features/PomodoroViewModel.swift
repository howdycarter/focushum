import Foundation
import SwiftUI
import SwiftData

enum PomodoroPhase {
    case idle, work, shortBreak, longBreak

    var sessionKind: SessionKind {
        switch self {
        case .idle, .work: return .work
        case .shortBreak:  return .shortBreak
        case .longBreak:   return .longBreak
        }
    }

    var label: String {
        switch self {
        case .idle:       return "Ready"
        case .work:       return "Focus"
        case .shortBreak: return "Break"
        case .longBreak:  return "Long Break"
        }
    }

    var isBreak: Bool { self == .shortBreak || self == .longBreak }
}

@Observable
final class PomodoroViewModel {
    var workMinutes: Int {
        didSet { UserDefaults.standard.set(workMinutes, forKey: "workMinutes") }
    }
    var shortBreakMinutes: Int {
        didSet { UserDefaults.standard.set(shortBreakMinutes, forKey: "shortBreakMinutes") }
    }
    var longBreakMinutes: Int {
        didSet { UserDefaults.standard.set(longBreakMinutes, forKey: "longBreakMinutes") }
    }
    var sessionsBeforeLongBreak: Int {
        didSet { UserDefaults.standard.set(sessionsBeforeLongBreak, forKey: "sessionsBeforeLongBreak") }
    }
    var autoStartBreaks: Bool {
        didSet { UserDefaults.standard.set(autoStartBreaks, forKey: "autoStartBreaks") }
    }
    var hapticsEnabled: Bool {
        didSet { UserDefaults.standard.set(hapticsEnabled, forKey: "hapticsEnabled") }
    }

    private(set) var phase: PomodoroPhase = .idle
    private(set) var secondsRemaining: Int = 0
    private(set) var completedSessions: Int = 0
    private(set) var isRunning: Bool = false

    var progress: Double {
        let total = totalSeconds(for: phase)
        guard total > 0 else { return 0 }
        return 1.0 - Double(secondsRemaining) / Double(total)
    }

    var timeString: String {
        let m = secondsRemaining / 60
        let s = secondsRemaining % 60
        return String(format: "%02d:%02d", m, s)
    }

    var onPhaseChanged: ((PomodoroPhase) -> Void)?

    private var timerTask: Task<Void, Never>?
    private var modelContext: ModelContext?
    private var currentSession: TimerSession?
    private var currentNoiseType: NoiseType = .brown

    init() {
        let defaults = UserDefaults.standard
        workMinutes             = defaults.integer(forKey: "workMinutes").nonZero(default: 25)
        shortBreakMinutes       = defaults.integer(forKey: "shortBreakMinutes").nonZero(default: 5)
        longBreakMinutes        = defaults.integer(forKey: "longBreakMinutes").nonZero(default: 15)
        sessionsBeforeLongBreak = defaults.integer(forKey: "sessionsBeforeLongBreak").nonZero(default: 4)
        autoStartBreaks         = defaults.bool(forKey: "autoStartBreaks")
        hapticsEnabled          = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
        secondsRemaining = workMinutes * 60
    }

    func setModelContext(_ ctx: ModelContext) { modelContext = ctx }

    func startOrResume(noiseType: NoiseType = .brown) {
        guard !isRunning else { return }
        currentNoiseType = noiseType
        if phase == .idle {
            phase = .work
            secondsRemaining = workMinutes * 60
            onPhaseChanged?(.work)
        }
        isRunning = true
        saveSessionStart()
        if hapticsEnabled { HapticManager.shared.sessionStart() }
        runTick()
    }

    func pause() {
        guard isRunning else { return }
        timerTask?.cancel()
        timerTask = nil
        isRunning = false
    }

    func skip() { pause(); advancePhase(completed: false) }

    func reset() {
        pause()
        phase = .idle
        secondsRemaining = workMinutes * 60
        completedSessions = 0
        onPhaseChanged?(.idle)
    }

    private func runTick() {
        timerTask = Task { @MainActor in
            while !Task.isCancelled && secondsRemaining > 0 {
                if phase == .work && secondsRemaining <= 5 && hapticsEnabled {
                    HapticManager.shared.countdownTick()
                }
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { break }
                secondsRemaining -= 1
                currentSession?.elapsedSeconds += 1
            }
            if !Task.isCancelled && secondsRemaining == 0 {
                advancePhase(completed: true)
            }
        }
    }

    private func advancePhase(completed: Bool) {
        if hapticsEnabled { HapticManager.shared.sessionEnd() }
        finalizeSession(completed: completed)
        if phase == .work {
            completedSessions += 1
            if completedSessions % sessionsBeforeLongBreak == 0 {
                phase = .longBreak
                secondsRemaining = longBreakMinutes * 60
            } else {
                phase = .shortBreak
                secondsRemaining = shortBreakMinutes * 60
            }
        } else {
            phase = .work
            secondsRemaining = workMinutes * 60
        }
        onPhaseChanged?(phase)
        if autoStartBreaks || phase == .work {
            isRunning = false
            startOrResume(noiseType: currentNoiseType)
        } else {
            isRunning = false
        }
    }

    private func totalSeconds(for phase: PomodoroPhase) -> Int {
        switch phase {
        case .idle, .work: return workMinutes * 60
        case .shortBreak:  return shortBreakMinutes * 60
        case .longBreak:   return longBreakMinutes * 60
        }
    }

    private func saveSessionStart() {
        guard let ctx = modelContext else { return }
        let session = TimerSession(
            plannedDuration: TimeInterval(totalSeconds(for: phase)),
            sessionKind: phase.sessionKind,
            noiseType: currentNoiseType
        )
        ctx.insert(session)
        currentSession = session
    }

    private func finalizeSession(completed: Bool) {
        currentSession?.completed = completed
        currentSession?.endDate = .now
        try? modelContext?.save()
        currentSession = nil
    }
}

private extension Int {
    func nonZero(default d: Int) -> Int { self == 0 ? d : self }
}
