//
//  ContainerTests.swift
//

import XCTest
@testable import FocusHum

final class ContainerTests: XCTestCase {
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
