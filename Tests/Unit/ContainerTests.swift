//
//  ContainerTests.swift
//

import XCTest
@testable import FocusHum

final class ContainerTests: XCTestCase {
    func testUnknownEntitlementRefreshPreservesPaidAccess() {
        let failedRefresh = Notification(name: .subscriptionDidChange)
        XCTAssertTrue(PremiumAccess.resolve(current: true, notification: failedRefresh, paywallEnabled: true))
        XCTAssertFalse(PremiumAccess.resolve(current: false, notification: failedRefresh, paywallEnabled: true))
    }

    func testVerifiedRevocationRemovesAccessUnlessPaywallIsDisabled() {
        let revoked = Notification(name: .subscriptionDidChange, userInfo: ["hasActiveEntitlement": false])
        XCTAssertFalse(PremiumAccess.resolve(current: true, notification: revoked, paywallEnabled: true))
        XCTAssertTrue(PremiumAccess.resolve(current: false, notification: revoked, paywallEnabled: false))
    }

    func testUnconfiguredPurchasesDoNotExposeDemoProducts() async {
        let options = await NoopPurchasesService().loadOfferings(includeAll: true)
        XCTAssertTrue(options.isEmpty)
    }

    func testUnconfiguredPurchaseCannotSucceed() async {
        do {
            try await NoopPurchasesService().purchase(packageIdentifier: "unconfigured")
            XCTFail("An unconfigured purchase must not report success")
        } catch {
            XCTAssertEqual(error as? PurchaseFriendlyError, .unavailable)
        }
    }

    func testUnconfiguredRestoreCannotSucceed() async {
        do {
            try await NoopPurchasesService().restorePurchases()
            XCTFail("An unconfigured restore must not report success")
        } catch {
            XCTAssertEqual(error as? PurchaseFriendlyError, .unavailable)
        }
    }

    func testContainerBuilds() throws {
        let container = DIContainer.makeDefault()
        XCTAssertNotNil(container.userRepository as Any)
        XCTAssertNotNil(container.authRepository as Any)
        XCTAssertEqual(container.config.appName.isEmpty, false)
    }
}

import SwiftData

@MainActor
final class PomodoroTests: XCTestCase {
    private final class TestClock {
        var date = Date(timeIntervalSince1970: 1_700_000_000)
    }

    private func makeTimer(_ clock: TestClock) -> (PomodoroViewModel, UserDefaults) {
        let defaults = UserDefaults(suiteName: "FocusHumTests.\(UUID().uuidString)")!
        defaults.set(false, forKey: "hapticsEnabled")
        let timer = PomodoroViewModel(defaults: defaults, now: { clock.date }, automaticTicks: false)
        timer.hasPremiumAccess = true
        return (timer, defaults)
    }

    func testCountdownFeedbackOnlyOnRemainingSecondChanges() {
        let clock = TestClock()
        let defaults = UserDefaults(suiteName: "FocusHumCountdownTests.\(UUID().uuidString)")!
        var pulses = 0
        let timer = PomodoroViewModel(defaults: defaults, now: { clock.date }, automaticTicks: false,
                                      countdownFeedback: { pulses += 1 })
        timer.startOrResume()
        clock.date.addTimeInterval(1_495)
        timer.refresh()
        timer.refresh()
        XCTAssertEqual(pulses, 1)
        clock.date.addTimeInterval(1)
        timer.refresh()
        XCTAssertEqual(pulses, 2)
        timer.hapticsEnabled = false
        clock.date.addTimeInterval(1)
        timer.refresh()
        XCTAssertEqual(pulses, 2)
        timer.reset()
    }

    func testDeadlineRecoversElapsedTimeAfterSuspension() {
        let clock = TestClock()
        let (timer, _) = makeTimer(clock)
        timer.startOrResume()
        clock.date.addTimeInterval(90)
        timer.refresh()
        XCTAssertEqual(timer.secondsRemaining, 1_410)
        XCTAssertEqual(timer.progress, 0.06, accuracy: 0.001)
        timer.reset()
    }

    func testPauseDoesNotCountTimeWhilePaused() {
        let clock = TestClock()
        let (timer, _) = makeTimer(clock)
        timer.startOrResume()
        clock.date.addTimeInterval(30)
        timer.pause()
        clock.date.addTimeInterval(120)
        timer.startOrResume()
        clock.date.addTimeInterval(10)
        timer.refresh()
        XCTAssertEqual(timer.secondsRemaining, 1_460)
        timer.reset()
    }

    func testResumeKeepsOneHistoryRecordAndResetFinalizesIt() throws {
        let clock = TestClock()
        let (timer, _) = makeTimer(clock)
        let container = try ModelContainer(for: TimerSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        timer.setModelContext(container.mainContext)
        timer.startOrResume()
        clock.date.addTimeInterval(30)
        timer.pause()
        timer.startOrResume()
        clock.date.addTimeInterval(20)
        timer.reset()
        let sessions = try container.mainContext.fetch(FetchDescriptor<TimerSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.elapsedSeconds, 50)
        XCTAssertNotNil(sessions.first?.endDate)
        XCTAssertEqual(sessions.first?.completed, false)
    }

    func testSkippedWorkDoesNotCountAsCompleted() {
        let clock = TestClock()
        let (timer, _) = makeTimer(clock)
        timer.startOrResume()
        timer.skip()
        XCTAssertEqual(timer.completedSessions, 0)
        XCTAssertEqual(timer.phase, .shortBreak)
        XCTAssertFalse(timer.isRunning)
    }

    func testCompletedWorkStartsBreakWithoutCountingExtraBackgroundSessions() {
        let clock = TestClock()
        let (timer, _) = makeTimer(clock)
        timer.startOrResume()
        clock.date.addTimeInterval(3_600)
        timer.refresh()
        XCTAssertEqual(timer.completedSessions, 1)
        XCTAssertEqual(timer.phase, .shortBreak)
        XCTAssertEqual(timer.secondsRemaining, 300)
        XCTAssertFalse(timer.isRunning)
    }

    func testLongBreakFollowsConfiguredCompletedSessions() {
        let clock = TestClock()
        let (timer, _) = makeTimer(clock)
        timer.sessionsBeforeLongBreak = 2
        timer.startOrResume()
        clock.date.addTimeInterval(1_500)
        timer.refresh()
        timer.skip()
        clock.date.addTimeInterval(1_500)
        timer.refresh()
        XCTAssertEqual(timer.completedSessions, 2)
        XCTAssertEqual(timer.phase, .longBreak)
        XCTAssertEqual(timer.secondsRemaining, 900)
    }

    func testChangingDurationUpdatesIdleTimerButNotActiveSession() {
        let clock = TestClock()
        let (timer, _) = makeTimer(clock)
        timer.workMinutes = 30
        XCTAssertEqual(timer.secondsRemaining, 1_800)
        timer.startOrResume()
        timer.workMinutes = 60
        clock.date.addTimeInterval(900)
        timer.refresh()
        XCTAssertEqual(timer.secondsRemaining, 900)
        XCTAssertEqual(timer.progress, 0.5, accuracy: 0.001)
        timer.reset()
        XCTAssertEqual(timer.secondsRemaining, 3_600)
    }

    func testFreeTimerUsesStandardDurationsEvenWhenCustomValuesAreSaved() {
        let clock = TestClock()
        let (timer, _) = makeTimer(clock)
        timer.workMinutes = 60
        timer.hasPremiumAccess = false
        timer.startOrResume()
        XCTAssertEqual(timer.secondsRemaining, 1500)
        XCTAssertEqual(timer.sessionGoal, 4)
        timer.reset()
    }

    func testInvalidSavedSettingsFallBackToSafeDurations() {
        let defaults = UserDefaults(suiteName: "FocusHumTests.\(UUID().uuidString)")!
        defaults.set(-10, forKey: "workMinutes")
        defaults.set(-2, forKey: "sessionsBeforeLongBreak")
        let timer = PomodoroViewModel(defaults: defaults, automaticTicks: false)
        XCTAssertEqual(timer.workMinutes, 25)
        XCTAssertEqual(timer.sessionsBeforeLongBreak, 4)
    }
}

import StoreKitTest

@MainActor
final class StoreKitPurchaseTests: XCTestCase {
    private func session() throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "FocusHum", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        return session
    }

    func testStoreKitLoadsLocalizedPlans() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let service = StoreKitPurchasesService(productIdentifiers: Secrets.storeProductIdentifiers)
        let plans = await service.loadOfferings(includeAll: false)
        XCTAssertEqual(Set(plans.map(\.id)), Set(Secrets.storeProductIdentifiers))
        XCTAssertTrue(plans.allSatisfy { !$0.price.isEmpty })
    }

    func testVerifiedPurchaseAndRestoreUnlockPro() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let service = StoreKitPurchasesService(productIdentifiers: Secrets.storeProductIdentifiers)
        try await service.purchase(packageIdentifier: Secrets.storeProductIdentifiers[0])
        XCTAssertTrue(service.hasActiveEntitlement)
        let restoredService = StoreKitPurchasesService(productIdentifiers: Secrets.storeProductIdentifiers)
        try await restoredService.restorePurchases()
        XCTAssertTrue(restoredService.hasActiveEntitlement)
    }

    func testRefundRevokesPro() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let service = StoreKitPurchasesService(productIdentifiers: Secrets.storeProductIdentifiers)
        service.configure()
        defer { service.stopMonitoring() }
        try await service.purchase(packageIdentifier: Secrets.storeProductIdentifiers[0])
        XCTAssertTrue(service.hasActiveEntitlement)
        let transaction = try XCTUnwrap(session.allTransactions().last)
        try session.refundTransaction(identifier: transaction.identifier)
        // StoreKit delivers revocations asynchronously through Transaction.updates.
        for _ in 0..<50 where service.hasActiveEntitlement {
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertFalse(service.hasActiveEntitlement, "The StoreKit transaction listener must revoke Pro after a refund")
    }

    func testUnknownProductCannotUnlockPro() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let service = StoreKitPurchasesService(productIdentifiers: Secrets.storeProductIdentifiers)
        do {
            try await service.purchase(packageIdentifier: "not.an.app.product")
            XCTFail("Unknown products must be rejected")
        } catch {
            XCTAssertEqual(error as? PurchaseFriendlyError, .unavailable)
            XCTAssertFalse(service.hasActiveEntitlement)
        }
    }
}


@MainActor
final class AudioLifecycleTests: XCTestCase {
    private final class Playback: AudioPlayback {
        var isPlaying = false
        var startCount = 0
        var volume: Float = 0
        var failStart = false
        func start(type: NoiseType, volume: Float) throws {
            startCount += 1
            if failStart { throw NSError(domain: "AudioTest", code: 1) }
            self.volume = volume
            isPlaying = true
        }
        func stop() { isPlaying = false }
        func setVolume(_ volume: Float) { self.volume = volume }
    }

    func testInterruptionResumesOnlyWhenSystemAllowsIt() {
        let playback = Playback()
        let model = AudioViewModel(generator: playback, observeNotifications: false)
        model.play()
        model.interruptionBegan()
        model.interruptionBegan() // Repeated begin notifications preserve prior playback intent.
        XCTAssertFalse(model.isPlaying)
        model.interruptionEnded(shouldResume: true)
        XCTAssertTrue(model.isPlaying)
        XCTAssertEqual(playback.startCount, 2)
        model.interruptionBegan()
        model.interruptionEnded(shouldResume: false)
        XCTAssertFalse(model.isPlaying)
        XCTAssertNotNil(model.errorMessage)
    }

    func testManualStopDuringInterruptionPreventsUnexpectedResume() {
        let playback = Playback()
        let model = AudioViewModel(generator: playback, observeNotifications: false)
        model.play()
        model.interruptionBegan()
        model.stop()
        model.interruptionEnded(shouldResume: true)
        XCTAssertFalse(model.isPlaying)
        XCTAssertEqual(playback.startCount, 1)
    }

    func testHeadphoneDisconnectDoesNotSwitchToSpeakerAutomatically() {
        let playback = Playback()
        let model = AudioViewModel(generator: playback, observeNotifications: false)
        model.play()
        model.routeDisconnected()
        XCTAssertFalse(model.isPlaying)
        XCTAssertNotNil(model.errorMessage)
        model.interruptionEnded(shouldResume: true)
        XCTAssertEqual(playback.startCount, 1)
        model.play()
        XCTAssertTrue(model.isPlaying)
        XCTAssertNil(model.errorMessage)
    }

    func testAudioFailureCanBeRetriedAndBreakVolumeIsApplied() {
        let playback = Playback()
        playback.failStart = true
        let model = AudioViewModel(generator: playback, observeNotifications: false)
        model.play()
        XCTAssertFalse(model.isPlaying)
        XCTAssertNotNil(model.errorMessage)
        playback.failStart = false
        model.isBreakPhase = true
        model.volume = 0.8
        model.play()
        XCTAssertTrue(model.isPlaying)
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(playback.volume, 0.44, accuracy: 0.001)
    }

    func testMediaResetAndStoppedEngineExposeRecovery() {
        let playback = Playback()
        let model = AudioViewModel(generator: playback, observeNotifications: false)
        model.play()
        model.audioConfigurationChanged()
        XCTAssertTrue(model.isPlaying, "A notification from a still-running engine must not stop playback")
        playback.isPlaying = false
        model.audioConfigurationChanged()
        XCTAssertFalse(model.isPlaying)
        XCTAssertNotNil(model.errorMessage)
        model.play()
        model.audioSystemReset()
        XCTAssertFalse(model.isPlaying)
        XCTAssertNotNil(model.errorMessage)
    }
}

@MainActor
final class TimerRecoveryTests: XCTestCase {
    private final class Clock { var date = Date(timeIntervalSince1970: 1_700_000_000) }
    private func defaults() -> UserDefaults {
        let value = UserDefaults(suiteName: "FocusHumRecovery.\(UUID().uuidString)")!
        value.set(false, forKey: "hapticsEnabled")
        return value
    }
    private func context() throws -> ModelContainer {
        try ModelContainer(for: TimerSession.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
    private func timer(_ defaults: UserDefaults, _ clock: Clock, _ context: ModelContext) -> PomodoroViewModel {
        let timer = PomodoroViewModel(defaults: defaults, now: { clock.date }, automaticTicks: false)
        timer.setModelContext(context)
        return timer
    }

    func testRunningSessionRecoversPausedWithoutDuplicateHistory() throws {
        let clock = Clock(), settings = defaults(), store = try context()
        let original = timer(settings, clock, store.mainContext)
        original.startOrResume()
        clock.date.addTimeInterval(90)
        let recovered = timer(settings, clock, ModelContext(store))
        XCTAssertFalse(recovered.isRunning)
        XCTAssertEqual(recovered.secondsRemaining, 1_410)
        XCTAssertNotNil(recovered.recoveryMessage)
        recovered.startOrResume()
        clock.date.addTimeInterval(10)
        recovered.reset()
        let sessions = try ModelContext(store).fetch(FetchDescriptor<TimerSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions[0].elapsedSeconds, 100)
        XCTAssertNotNil(sessions[0].endDate)
    }

    func testPausedSessionDoesNotAccumulateClosedTime() throws {
        let clock = Clock(), settings = defaults(), store = try context()
        let original = timer(settings, clock, store.mainContext)
        original.startOrResume()
        clock.date.addTimeInterval(30)
        original.pause()
        clock.date.addTimeInterval(3_600)
        let recovered = timer(settings, clock, ModelContext(store))
        XCTAssertEqual(recovered.secondsRemaining, 1_470)
        XCTAssertFalse(recovered.isRunning)
    }

    func testExpiredSessionCompletesOnceWithoutStartingNewSession() throws {
        let clock = Clock(), settings = defaults(), store = try context()
        settings.set(true, forKey: "autoStartBreaks")
        let original = timer(settings, clock, store.mainContext)
        original.startOrResume()
        clock.date.addTimeInterval(3_600)
        let recovered = timer(settings, clock, ModelContext(store))
        XCTAssertEqual(recovered.completedSessions, 1)
        XCTAssertEqual(recovered.phase, .shortBreak)
        XCTAssertFalse(recovered.isRunning)
        let again = timer(settings, clock, ModelContext(store))
        XCTAssertEqual(again.phase, .shortBreak)
        XCTAssertEqual(again.completedSessions, 1)
        let sessions = try ModelContext(store).fetch(FetchDescriptor<TimerSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertTrue(sessions[0].completed)
    }

    func testLegacyUnfinishedSessionIsReconciled() throws {
        let clock = Clock(), settings = defaults(), store = try context()
        let session = TimerSession(startDate: clock.date, plannedDuration: 1_500, sessionKind: .work, noiseType: .brown)
        session.elapsedSeconds = 60
        store.mainContext.insert(session)
        try store.mainContext.save()
        let recovered = timer(settings, clock, ModelContext(store))
        XCTAssertEqual(recovered.phase, .idle)
        let saved = try XCTUnwrap(ModelContext(store).fetch(FetchDescriptor<TimerSession>()).first)
        XCTAssertFalse(saved.completed)
        XCTAssertNotNil(saved.endDate)
        XCTAssertEqual(saved.elapsedSeconds, 60)
        XCTAssertNotNil(recovered.recoveryMessage)
    }

    func testHistorySaveFailureIsVisibleAndRetryClearsIt() throws {
        let clock = Clock(), settings = defaults(), store = try context()
        var fail = true
        let timer = PomodoroViewModel(defaults: settings, now: { clock.date }, automaticTicks: false, saveContext: { context in
            if fail { throw NSError(domain: "SaveTest", code: 1) }
            try context.save()
        })
        timer.setModelContext(store.mainContext)
        timer.startOrResume()
        XCTAssertNotNil(timer.errorMessage)
        fail = false
        timer.retryHistorySave()
        XCTAssertNil(timer.errorMessage)
        XCTAssertEqual(try ModelContext(store).fetch(FetchDescriptor<TimerSession>()).count, 1)
    }


    func testFailedRecoveryFetchRetriesRecoveryRatherThanOnlySaving() throws {
        let clock = Clock(), settings = defaults(), store = try context()
        let original = timer(settings, clock, store.mainContext)
        original.startOrResume()
        clock.date.addTimeInterval(60)
        var failFetch = true
        let recovered = PomodoroViewModel(defaults: settings, now: { clock.date }, automaticTicks: false, fetchSessions: { context in
            if failFetch { throw NSError(domain: "FetchTest", code: 1) }
            return try context.fetch(FetchDescriptor<TimerSession>())
        })
        recovered.setModelContext(ModelContext(store))
        XCTAssertNotNil(recovered.errorMessage)
        failFetch = false
        recovered.retryHistorySave()
        XCTAssertNil(recovered.errorMessage)
        XCTAssertEqual(recovered.phase, .work)
        XCTAssertEqual(recovered.secondsRemaining, 1_440)
        XCTAssertFalse(recovered.isRunning)
    }

    func testResetRemovesRecoveryState() throws {
        let clock = Clock(), settings = defaults(), store = try context()
        let original = timer(settings, clock, store.mainContext)
        original.startOrResume()
        original.reset()
        let recovered = timer(settings, clock, ModelContext(store))
        XCTAssertEqual(recovered.phase, .idle)
        XCTAssertNil(recovered.recoveryMessage)
    }
}
