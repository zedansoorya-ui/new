import XCTest
@testable import MurmurCore

final class ModifierGateTests: XCTestCase {
    func testGlobePressAndRelease() {
        var gate = ModifierGate(trigger: .globe)
        XCTAssertEqual(gate.update(flags: ModifierMask.function), .trigger(.pressed, held: []))
        XCTAssertTrue(gate.isDown)
        XCTAssertEqual(gate.update(flags: 0), .trigger(.released, held: []))
        XCTAssertFalse(gate.isDown)
    }

    func testRightOptionIgnoresLeftOption() {
        var gate = ModifierGate(trigger: .rightOption)
        // Left Option going down is not our trigger.
        XCTAssertEqual(gate.update(flags: ModifierMask.leftOption), .irrelevant)
        XCTAssertFalse(gate.isDown)
        // Right Option down while left is held.
        let both = ModifierMask.leftOption | ModifierMask.rightOption
        XCTAssertEqual(gate.update(flags: both), .trigger(.pressed, held: [.other]))
        // Right Option released while left is still held: the union bit would hide this.
        XCTAssertEqual(gate.update(flags: ModifierMask.leftOption), .trigger(.released, held: [.other]))
    }

    func testControlWhileHeldIsReportedSeparately() {
        var gate = ModifierGate(trigger: .globe)
        _ = gate.update(flags: ModifierMask.function)
        XCTAssertEqual(gate.update(flags: ModifierMask.function | ModifierMask.leftControl), .controlPressed)
        XCTAssertEqual(gate.update(flags: ModifierMask.function | ModifierMask.rightControl), .controlPressed)
    }

    func testOtherModifierWhileHeld() {
        var gate = ModifierGate(trigger: .globe)
        _ = gate.update(flags: ModifierMask.function)
        XCTAssertEqual(gate.update(flags: ModifierMask.function | ModifierMask.leftShift), .otherModifierPressed)
        // Releasing that modifier is irrelevant.
        XCTAssertEqual(gate.update(flags: ModifierMask.function), .irrelevant)
    }

    func testModifierChangesWhileTriggerUpAreIrrelevant() {
        var gate = ModifierGate(trigger: .globe)
        XCTAssertEqual(gate.update(flags: ModifierMask.leftCommand), .irrelevant)
        XCTAssertEqual(gate.update(flags: 0), .irrelevant)
    }

    func testTriggerPressWithControlAlreadyHeld() {
        var gate = ModifierGate(trigger: .globe)
        _ = gate.update(flags: ModifierMask.leftControl)
        XCTAssertEqual(
            gate.update(flags: ModifierMask.leftControl | ModifierMask.function),
            .trigger(.pressed, held: [.control])
        )
    }

    func testRightControlMaskIsNotLeftShift() {
        XCTAssertEqual(ModifierMask.rightControl, 0x2000)
        XCTAssertNotEqual(ModifierMask.rightControl, ModifierMask.leftShift)
    }

    func testResynchroniseReportsMissedEdges() {
        var gate = ModifierGate(trigger: .globe)
        _ = gate.update(flags: ModifierMask.function)
        XCTAssertEqual(gate.resynchronise(flags: 0), .released)
        XCTAssertNil(gate.resynchronise(flags: 0))
        XCTAssertEqual(gate.resynchronise(flags: ModifierMask.function), .pressed)
    }

    func testTriggerLookupAndTakeover() {
        XCTAssertEqual(HotkeyTrigger.with(id: "rightCommand"), .rightCommand)
        XCTAssertNil(HotkeyTrigger.with(id: "nope"))
        XCTAssertTrue(HotkeyTrigger.globe.canTakeOverSystemAction)
        XCTAssertFalse(HotkeyTrigger.rightOption.canTakeOverSystemAction)
    }

    func testHeldModifiersFromFlags() {
        XCTAssertEqual(HeldModifiers(flags: 0), [])
        XCTAssertEqual(HeldModifiers(flags: ModifierMask.rightControl), [.control])
        XCTAssertEqual(HeldModifiers(flags: ModifierMask.leftCommand), [.other])
        XCTAssertEqual(HeldModifiers(flags: ModifierMask.leftControl | ModifierMask.leftShift), [.control, .other])
    }
}
