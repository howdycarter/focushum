import Foundation
import SwiftUI
import SwiftData

enum PomodoroPhase: String, Codable {
    case idle, work, shortBreak, longBreak

    var sessionKind: SessionKind {
        switch self {
        case .idle, .work: return .work
        case .shortBreak: return .shortBreak
        case .longBreak: return .longBreak
        }
    }

    var label: String {
        switch self {
        case .idle: return "Ready"
        case .work: return "Focus"
        case .shortBreak: return "Break"
        case .longBreak: return "Long Break"
        }
    }

    var isBreak: Bool { self == .shortBreak || self == .longBreak }
}

@MainActor
@Observable
final class PomodoroViewModel {
    var hasPremiumAccess = false {
        didSet {
            if phase == .idle {
                phaseDuration = (hasPremiumAccess ? workMinutes : 25) * 60
                secondsRemaining = phaseDuration
            }
        }
    }
    var sessionGoal: Int { hasPremiumAccess ? sessionsBeforeLongBreak : 4 }

    var workMinutes: Int {
        didSet {
            defaults.set(workMinutes, forKey: "workMinutes")
            if phase == .idle {
                phaseDuration = (hasPremiumAccess ? workMinutes : 25) * 60
                secondsRemaining = phaseDuration
            }
        }
    }
    var shortBreakMinutes: Int {
        didSet { defaults.set(shortBreakMinutes, forKey: "shortBreakMinutes") }
    }
    var longBreakMinutes: Int {
        didSet { defaults.set(longBreakMinutes, forKey: "longBreakMinutes") }
    }
    var sessionsBeforeLongBreak: Int {
        didSet { defaults.set(sessionsBeforeLongBreak, forKey: "sessionsBeforeLongBreak") }
    }
    var autoStartBreaks: Bool {
        didSet { defaults.set(autoStartBreaks, forKey: "autoStartBreaks") }
    }
    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: "hapticsEnabled") }
    }

    var errorMessage: String?
    private(set) var recoveryMessage: String?
    private(set) var phase: PomodoroPhase = .idle
    private(set) var secondsRemaining: Int = 0
    private(set) var completedSessions = 0
    private(set) var isRunning = false

    var progress: Double {
        guard phaseDuration > 0 else { return 0 }
        return min(1, max(0, 1 - Double(secondsRemaining) / Double(phaseDuration)))
    }

    var timeString: String {
        String(format: "%02d:%02d", secondsRemaining / 60, secondsRemaining % 60)
    }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let automaticTicks: Bool
    private let countdownFeedback: () -> Void
    private var timerTask: Task<Void, Never>?
    private var deadline: Date?
    private var phaseDuration = 0
    private var modelContext: ModelContext?
    private var currentSession: TimerSession?
    private var currentNoiseType: NoiseType = .brown
    private let saveContext: (ModelContext) throws -> Void
    private let fetchSessions: (ModelContext) throws -> [TimerSession]
    private var didRestoreSession = false
    private static let recoveryKey = "FocusHum.activeSession.v1"

    private struct RecoverySnapshot: Codable {
        let sessionID: UUID?
        let phase: PomodoroPhase
        let phaseDuration: Int
        let secondsRemaining: Int
        let deadline: Date?
        let completedSessions: Int
    }

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init, automaticTicks: Bool = true, countdownFeedback: @escaping () -> Void = { HapticManager.shared.countdownTick() }, saveContext: @escaping (ModelContext) throws -> Void = { try $0.save() }, fetchSessions: @escaping (ModelContext) throws -> [TimerSession] = { try $0.fetch(FetchDescriptor<TimerSession>()) }) {
        self.defaults = defaults
        self.now = now
        self.automaticTicks = automaticTicks
        self.countdownFeedback = countdownFeedback
        self.saveContext = saveContext
        self.fetchSessions = fetchSessions
        workMinutes = Self.setting(defaults, "workMinutes", fallback: 25, range: 5...90)
        shortBreakMinutes = Self.setting(defaults, "shortBreakMinutes", fallback: 5, range: 1...30)
        longBreakMinutes = Self.setting(defaults, "longBreakMinutes", fallback: 15, range: 5...60)
        sessionsBeforeLongBreak = Self.setting(defaults, "sessionsBeforeLongBreak", fallback: 4, range: 2...8)
        autoStartBreaks = defaults.bool(forKey: "autoStartBreaks")
        hapticsEnabled = defaults.object(forKey: "hapticsEnabled") as? Bool ?? true
        phaseDuration = (hasPremiumAccess ? workMinutes : 25) * 60
        secondsRemaining = phaseDuration
    }

    func setModelContext(_ context: ModelContext) {
        modelContext = context
        guard !didRestoreSession else { return }
        didRestoreSession = true
        restoreSession()
    }

    /// Save at lifecycle boundaries as well as user-driven transitions.
    func checkpoint() {
        refresh()
        persistRecovery()
        saveHistory()
    }

    func retryHistorySave() {
        if !didRestoreSession {
            didRestoreSession = true
            restoreSession()
        } else { saveHistory() }
    }

    func startOrResume(noiseType: NoiseType = .brown) {
        guard !isRunning else { return }
        recoveryMessage = nil
        currentNoiseType = noiseType
        if phase == .idle { setPhase(.work) }
        if currentSession == nil { saveSessionStart() }
        deadline = now().addingTimeInterval(TimeInterval(secondsRemaining))
        isRunning = true
        persistRecovery()
        if hapticsEnabled { HapticManager.shared.sessionStart() }
        runTick()
    }

    func pause() {
        guard isRunning else { return }
        refresh()
        stopTicking()
        persistRecovery()
        saveHistory()
    }

    func skip() {
        guard phase != .idle else { return }
        if let deadline, isRunning { updateElapsed(until: deadline, at: now()) }
        stopTicking()
        advancePhase(completed: false)
    }

    func reset() {
        if let deadline, isRunning { updateElapsed(until: deadline, at: now()) }
        stopTicking()
        finalizeSession(completed: false)
        completedSessions = 0
        setPhase(.idle)
        recoveryMessage = nil
        defaults.removeObject(forKey: Self.recoveryKey)
    }

    /// A deadline keeps the timer accurate after a delayed tick or suspension.
    func refresh() {
        guard isRunning, let deadline else { return }
        let previous = secondsRemaining
        updateElapsed(until: deadline, at: now())
        if hapticsEnabled, phase == .work, (1...5).contains(secondsRemaining), secondsRemaining < previous {
            countdownFeedback()
        }
        if secondsRemaining == 0 {
            stopTicking()
            advancePhase(completed: true)
        }
        persistRecovery()
    }

    private func updateElapsed(until deadline: Date, at date: Date) {
        secondsRemaining = max(0, min(phaseDuration, Int(ceil(deadline.timeIntervalSince(date)))))
        currentSession?.elapsedSeconds = TimeInterval(phaseDuration - secondsRemaining)
    }

    private func runTick() {
        guard automaticTicks else { return }
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) }
                catch { return }
                guard !Task.isCancelled else { return }
                self?.refresh()
                guard self?.isRunning == true else { return }
            }
        }
    }

    private func stopTicking() {
        timerTask?.cancel()
        timerTask = nil
        deadline = nil
        isRunning = false
    }

    private func advancePhase(completed: Bool, automaticallyStartNext: Bool = true) {
        if completed && hapticsEnabled { HapticManager.shared.sessionEnd() }
        finalizeSession(completed: completed)
        if phase == .work {
            if completed { completedSessions += 1 }
            let longBreak = completed && completedSessions.isMultiple(of: max(1, sessionGoal))
            setPhase(longBreak ? .longBreak : .shortBreak)
        } else {
            setPhase(.work)
        }
        if automaticallyStartNext && (autoStartBreaks || phase == .work) { startOrResume(noiseType: currentNoiseType) }
        persistRecovery()
    }

    private func setPhase(_ phase: PomodoroPhase) {
        self.phase = phase
        switch phase {
        case .idle, .work: phaseDuration = (hasPremiumAccess ? workMinutes : 25) * 60
        case .shortBreak: phaseDuration = (hasPremiumAccess ? shortBreakMinutes : 5) * 60
        case .longBreak: phaseDuration = (hasPremiumAccess ? longBreakMinutes : 15) * 60
        }
        secondsRemaining = phaseDuration
    }

    private func saveSessionStart() {
        guard let modelContext else { return }
        let session = TimerSession(startDate: now(), plannedDuration: TimeInterval(phaseDuration), sessionKind: phase.sessionKind, noiseType: currentNoiseType)
        modelContext.insert(session)
        currentSession = session
        saveHistory()
    }

    private func finalizeSession(completed: Bool) {
        currentSession?.completed = completed
        currentSession?.endDate = now()
        saveHistory()
        currentSession = nil
        defaults.removeObject(forKey: Self.recoveryKey)
    }

    private func saveHistory() {
        guard let modelContext else { return }
        do {
            try saveContext(modelContext)
            errorMessage = nil
        } catch {
            errorMessage = "Your session history could not be saved. Free up device storage and tap Retry Save. Keep the app open until it saves."
        }
    }

    private func persistRecovery() {
        guard phase != .idle else { return }
        let snapshot = RecoverySnapshot(sessionID: currentSession?.id, phase: phase,
            phaseDuration: phaseDuration, secondsRemaining: secondsRemaining,
            deadline: isRunning ? deadline : nil, completedSessions: completedSessions)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: Self.recoveryKey)
        }
    }

    private func restoreSession() {
        guard let modelContext else { return }
        do {
            let sessions = try fetchSessions(modelContext)
            if let data = defaults.data(forKey: Self.recoveryKey),
               let snapshot = try? JSONDecoder().decode(RecoverySnapshot.self, from: data),
               snapshot.phase != .idle, (1...5_400).contains(snapshot.phaseDuration),
               (0...snapshot.phaseDuration).contains(snapshot.secondsRemaining),
               (0...1_000_000).contains(snapshot.completedSessions),
               snapshot.sessionID == nil || sessions.contains(where: { $0.id == snapshot.sessionID && $0.endDate == nil }) {
                let session = sessions.first(where: { $0.id == snapshot.sessionID && $0.endDate == nil })
                currentSession = session
                currentNoiseType = session?.noiseType ?? .brown
                phase = snapshot.phase
                phaseDuration = snapshot.phaseDuration
                completedSessions = snapshot.completedSessions
                secondsRemaining = snapshot.secondsRemaining
                if let deadline = snapshot.deadline { updateElapsed(until: deadline, at: now()) }
                // Relaunch never silently starts audio or another phase.
                isRunning = false
                deadline = nil
                if secondsRemaining == 0 {
                    advancePhase(completed: true, automaticallyStartNext: false)
                    recoveryMessage = "Your previous session finished while the app was closed. Start the next session when you are ready."
                } else {
                    session?.elapsedSeconds = TimeInterval(phaseDuration - secondsRemaining)
                    recoveryMessage = "Your previous session was recovered and paused. Tap Start to continue."
                    persistRecovery()
                }
            } else {
                defaults.removeObject(forKey: Self.recoveryKey)
            }
            // Reconcile legacy or incomplete records rather than leaving them running forever.
            let abandoned = sessions.filter { $0.endDate == nil && $0.id != currentSession?.id }
            for session in abandoned {
                session.endDate = now()
                session.completed = false
            }
            if !abandoned.isEmpty && recoveryMessage == nil {
                recoveryMessage = "An interrupted session was saved to history. Start a new session when you are ready."
            }
            saveHistory()
        } catch {
            errorMessage = "Your previous session could not be restored. Tap Retry to try again."
            didRestoreSession = false
        }
    }

    private static func setting(_ defaults: UserDefaults, _ key: String, fallback: Int, range: ClosedRange<Int>) -> Int {
        guard let value = defaults.object(forKey: key) as? Int, range.contains(value) else { return fallback }
        return value
    }
}
