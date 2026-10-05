import XCTest
@testable import MurmurCore

final class HotkeyStateMachineTests: XCTestCase {
    private var machine = HotkeyStateMachine()

    override func setUp() {
        super.setUp()
        machine = HotkeyStateMachine()
    }

    private func send(_ input: HotkeyInput, at time: TimeInterval) -> [HotkeyEffect] {
        machine.handle(input, at: time)
    }

    // MARK: - Hold to talk

    func testHoldStartsCaptureOnPressAndFinishesOnRelease() {
        XCTAssertEqual(send(.triggerDown(held: []), at: 0), [.beginCapture(.hold)])
        XCTAssertTrue(machine.isCapturing)
        XCTAssertEqual(send(.tick, at: 0.2), [.commitHold])
        XCTAssertEqual(machine.state, .holding(since: 0))
        XCTAssertEqual(send(.triggerUp, at: 2.0), [.finish(.hold)])
        XCTAssertEqual(machine.state, .idle)
    }

    func testTickBeforeThresholdDoesNothing() {
        _ = send(.triggerDown(held: []), at: 0)
        XCTAssertEqual(send(.tick, at: 0.10), [])
        XCTAssertEqual(machine.state, .pending(since: 0))
    }

    func testLateTickStillCountsAsHoldOnRelease() {
        _ = send(.triggerDown(held: []), at: 0)
        // No tick arrived, but the press lasted past the threshold.
        XCTAssertEqual(send(.triggerUp, at: 0.4), [.commitHold, .finish(.hold)])
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: - Taps

    func testShortTapIsDiscarded() {
        _ = send(.triggerDown(held: []), at: 0)
        XCTAssertEqual(send(.triggerUp, at: 0.08), [.discard(.tap)])
        XCTAssertFalse(machine.isCapturing)
        XCTAssertEqual(machine.state, .tapWindow(releasedAt: 0.08))
    }

    func testTapWindowExpiresBackToIdle() {
        _ = send(.triggerDown(held: []), at: 0)
        _ = send(.triggerUp, at: 0.08)
        XCTAssertEqual(send(.tick, at: 0.30), [])
        XCTAssertEqual(machine.state, .tapWindow(releasedAt: 0.08))
        XCTAssertEqual(send(.tick, at: 0.08 + 0.36), [])
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: - Double-tap hands-free

    func testDoubleTapLatchesHandsFreeAndNextPressFinishes() {
        _ = send(.triggerDown(held: []), at: 0)
        _ = send(.triggerUp, at: 0.08)
        XCTAssertEqual(send(.triggerDown(held: []), at: 0.25), [.beginCapture(.handsFree)])
        // Releasing the second tap must not end the capture it started.
        XCTAssertEqual(send(.triggerUp, at: 0.33), [])
        XCTAssertTrue(machine.isCapturing)
        XCTAssertEqual(send(.tick, at: 10), [])
        XCTAssertEqual(send(.triggerDown(held: []), at: 30), [.finish(.handsFree)])
        XCTAssertEqual(machine.state, .idle)
        // The release that follows the finishing press is ignored.
        XCTAssertEqual(send(.triggerUp, at: 30.1), [])
    }

    func testSecondPressAfterWindowIsAFreshHold() {
        _ = send(.triggerDown(held: []), at: 0)
        _ = send(.triggerUp, at: 0.08)
        let secondPress: TimeInterval = 0.08 + 0.5
        XCTAssertEqual(send(.triggerDown(held: []), at: secondPress), [.beginCapture(.hold)])
        XCTAssertEqual(machine.state, .pending(since: secondPress))
    }

    func testHandsFreeIgnoresOtherKeys() {
        _ = send(.pillClick, at: 0)
        XCTAssertEqual(send(.otherKeyDown, at: 1), [])
        XCTAssertEqual(send(.controlDown, at: 1.5), [])
        XCTAssertTrue(machine.isCapturing)
    }

    func testHoldingTheSecondTapKeepsHandsFreeAfterRelease() {
        _ = send(.triggerDown(held: []), at: 0)
        _ = send(.triggerUp, at: 0.05)
        _ = send(.triggerDown(held: []), at: 0.2)
        XCTAssertEqual(send(.tick, at: 2), [])
        XCTAssertEqual(send(.triggerUp, at: 3), [])
        XCTAssertEqual(machine.state, .handsFree(since: 0.2, awaitingLatchRelease: false))
    }

    // MARK: - Pill

    func testPillClickTogglesHandsFree() {
        XCTAssertEqual(send(.pillClick, at: 0), [.beginCapture(.handsFree)])
        XCTAssertEqual(send(.pillClick, at: 5), [.finish(.handsFree)])
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: - Chords

    func testOtherKeyWhilePendingCancels() {
        _ = send(.triggerDown(held: []), at: 0)
        XCTAssertEqual(send(.otherKeyDown, at: 0.05), [.discard(.chord)])
        XCTAssertEqual(machine.state, .idle)
        // The release that follows is not a tap and starts nothing.
        XCTAssertEqual(send(.triggerUp, at: 0.1), [])
        XCTAssertEqual(machine.state, .idle)
    }

    func testOtherKeyWhileHoldingCancels() {
        _ = send(.triggerDown(held: []), at: 0)
        _ = send(.tick, at: 0.2)
        XCTAssertEqual(send(.otherKeyDown, at: 1), [.discard(.chord)])
        XCTAssertEqual(machine.state, .idle)
    }

    func testPressWithAnotherModifierAlreadyHeldStartsNothing() {
        XCTAssertEqual(send(.triggerDown(held: [.other]), at: 0), [])
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(send(.triggerUp, at: 1), [])
    }

    // MARK: - Command mode

    func testControlDuringHoldSwitchesToCommandMode() {
        _ = send(.triggerDown(held: []), at: 0)
        _ = send(.tick, at: 0.2)
        XCTAssertEqual(send(.controlDown, at: 0.5), [.switchMode(.command)])
        XCTAssertEqual(send(.triggerUp, at: 2), [.finish(.command)])
    }

    func testControlWhilePendingSwitchesToCommandMode() {
        _ = send(.triggerDown(held: []), at: 0)
        XCTAssertEqual(send(.controlDown, at: 0.05), [.switchMode(.command)])
        XCTAssertEqual(machine.state, .command(since: 0))
    }

    func testPressWithControlHeldStartsCommandMode() {
        XCTAssertEqual(send(.triggerDown(held: [.control]), at: 0), [.beginCapture(.command)])
        XCTAssertEqual(send(.triggerUp, at: 1.5), [.finish(.command)])
    }

    func testQuickCommandTapIsDiscarded() {
        _ = send(.triggerDown(held: [.control]), at: 0)
        XCTAssertEqual(send(.triggerUp, at: 0.05), [.discard(.tap)])
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: - Escape

    func testEscapeCancelsHoldHandsFreeAndCommand() {
        _ = send(.triggerDown(held: []), at: 0)
        XCTAssertEqual(send(.escape, at: 0.5), [.discard(.escape)])

        _ = send(.pillClick, at: 1)
        XCTAssertEqual(send(.escape, at: 2), [.discard(.escape)])

        _ = send(.triggerDown(held: [.control]), at: 3)
        XCTAssertEqual(send(.escape, at: 4), [.discard(.escape)])
        XCTAssertEqual(machine.state, .idle)
    }

    func testEscapeWhenIdleDoesNothing() {
        XCTAssertEqual(send(.escape, at: 0), [])
        _ = send(.triggerDown(held: []), at: 1)
        _ = send(.triggerUp, at: 1.05)
        XCTAssertEqual(send(.escape, at: 1.1), [])
        XCTAssertEqual(machine.state, .idle)
    }

    // MARK: - Missed release watchdog

    func testMissedReleaseFinishesAfterGrace() {
        _ = send(.triggerDown(held: []), at: 0)
        _ = send(.tick, at: 0.2)
        XCTAssertEqual(send(.triggerFlag(isDown: false), at: 3.0), [])
        XCTAssertEqual(machine.nextDeadline(now: 3.0), 3.5)
        XCTAssertEqual(send(.tick, at: 3.2), [])
        XCTAssertEqual(send(.tick, at: 3.5), [.finish(.hold)])
        XCTAssertEqual(machine.state, .idle)
    }

    func testFlagFlickerDoesNotFinish() {
        _ = send(.triggerDown(held: []), at: 0)
        _ = send(.tick, at: 0.2)
        _ = send(.triggerFlag(isDown: false), at: 1.0)
        XCTAssertEqual(send(.triggerFlag(isDown: true), at: 1.2), [])
        XCTAssertEqual(send(.tick, at: 2.0), [])
        XCTAssertTrue(machine.isCapturing)
    }

    func testMissedReleaseDuringPendingIsCaughtOnceHolding() {
        // Times are exact binary fractions so the grace comparison is not at the mercy of rounding.
        _ = send(.triggerDown(held: []), at: 0)
        _ = send(.triggerFlag(isDown: false), at: 0.125)
        XCTAssertEqual(send(.tick, at: 0.25), [.commitHold])
        XCTAssertEqual(send(.tick, at: 0.5), [])
        XCTAssertEqual(send(.tick, at: 0.625), [.finish(.hold)])
    }

    // MARK: - Deadlines

    func testNextDeadlines() {
        XCTAssertNil(machine.nextDeadline(now: 0))
        _ = send(.triggerDown(held: []), at: 1)
        XCTAssertEqual(machine.nextDeadline(now: 1)!, 1.15, accuracy: 1e-9)
        _ = send(.tick, at: 1.2)
        XCTAssertEqual(machine.state, .holding(since: 1))
        XCTAssertEqual(machine.nextDeadline(now: 1.2)!, 1.45, accuracy: 1e-9)
        _ = send(.triggerUp, at: 2)
        XCTAssertNil(machine.nextDeadline(now: 2))

        _ = send(.triggerDown(held: []), at: 3)
        _ = send(.triggerUp, at: 3.05)
        XCTAssertEqual(machine.nextDeadline(now: 3.05)!, 3.05 + 0.35 + 0.001, accuracy: 1e-9)

        _ = send(.tick, at: 4)
        _ = send(.pillClick, at: 5)
        XCTAssertNil(machine.nextDeadline(now: 5))
    }

    func testResetClearsEverything() {
        _ = send(.triggerDown(held: []), at: 0)
        machine.reset()
        XCTAssertEqual(machine.state, .idle)
        XCTAssertFalse(machine.isCapturing)
    }

    // MARK: - Pill buttons

    func testStopFinishesWhateverIsCapturing() {
        _ = send(.triggerDown(held: []), at: 0)
        _ = send(.tick, at: 0.2)
        XCTAssertEqual(send(.stop, at: 1), [.finish(.hold)])
        XCTAssertEqual(machine.state, .idle)

        _ = send(.pillClick, at: 2)
        XCTAssertEqual(send(.stop, at: 3), [.finish(.handsFree)])

        _ = send(.triggerDown(held: [.control]), at: 4)
        XCTAssertEqual(send(.stop, at: 5), [.finish(.command)])
        XCTAssertEqual(machine.state, .idle)
    }

    func testStopDuringPendingStillDelivers() {
        _ = send(.triggerDown(held: []), at: 0)
        XCTAssertEqual(send(.stop, at: 0.05), [.commitHold, .finish(.hold)])
        XCTAssertFalse(machine.isCapturing)
    }

    func testStopWhenIdleDoesNothing() {
        XCTAssertEqual(send(.stop, at: 0), [])
        XCTAssertEqual(machine.state, .idle)
    }

    func testTriggerReleaseAfterStopIsIgnored() {
        _ = send(.triggerDown(held: []), at: 0)
        _ = send(.tick, at: 0.2)
        _ = send(.stop, at: 1)
        XCTAssertEqual(send(.triggerUp, at: 1.5), [])
        XCTAssertEqual(machine.state, .idle)
    }

    func testCancelDiscardsWithItsOwnReason() {
        _ = send(.pillClick, at: 0)
        XCTAssertEqual(send(.cancel, at: 1), [.discard(.cancelled)])
        XCTAssertEqual(machine.state, .idle)
        XCTAssertEqual(send(.cancel, at: 2), [])
    }

    func testCustomTiming() {
        machine = HotkeyStateMachine(timing: HotkeyTiming(tapThreshold: 0.3, doubleTapWindow: 0.5))
        _ = send(.triggerDown(held: []), at: 0)
        XCTAssertEqual(send(.triggerUp, at: 0.25), [.discard(.tap)])
        XCTAssertEqual(send(.triggerDown(held: []), at: 0.7), [.beginCapture(.handsFree)])
    }
}
