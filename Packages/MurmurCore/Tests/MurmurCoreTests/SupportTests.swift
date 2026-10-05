import XCTest
@testable import MurmurCore

final class GlobeKeyActionTests: XCTestCase {
    func testStoredValues() {
        XCTAssertEqual(GlobeKeyAction.from(storedValue: 0), .doNothing)
        XCTAssertEqual(GlobeKeyAction.from(storedValue: 3), .startDictation)
        XCTAssertFalse(GlobeKeyAction.doNothing.conflictsWithDictation)
        XCTAssertTrue(GlobeKeyAction.showEmoji.conflictsWithDictation)
    }

    func testMissingOrUnknownValueIsNotSafe() {
        XCTAssertTrue(GlobeKeyAction.from(storedValue: nil).conflictsWithDictation)
        XCTAssertTrue(GlobeKeyAction.from(storedValue: 42).conflictsWithDictation)
    }
}

final class LevelMeterTests: XCTestCase {
    func testRMS() {
        XCTAssertEqual(LevelMeter.rms([Float]()), 0)
        XCTAssertEqual(LevelMeter.rms([0.5, -0.5, 0.5, -0.5]), 0.5, accuracy: 1e-6)
    }

    func testDecibelsClamp() {
        XCTAssertEqual(LevelMeter.decibels(rms: 0), -160)
        XCTAssertEqual(LevelMeter.decibels(rms: 1), 0, accuracy: 1e-6)
        XCTAssertEqual(LevelMeter.decibels(rms: 0.1), -20, accuracy: 1e-4)
    }

    func testDisplayLevelRange() {
        XCTAssertEqual(LevelMeter.displayLevel(decibels: -160), 0)
        XCTAssertEqual(LevelMeter.displayLevel(decibels: -55), 0)
        XCTAssertEqual(LevelMeter.displayLevel(decibels: 0), 1, accuracy: 1e-6)
        let quiet = LevelMeter.displayLevel(decibels: -40)
        let loud = LevelMeter.displayLevel(decibels: -10)
        XCTAssertGreaterThan(quiet, 0)
        XCTAssertGreaterThan(loud, quiet)
    }
}

final class AudioSamplesTests: XCTestCase {
    func testPadding() {
        XCTAssertEqual(AudioSamples.padded([1, 2], toAtLeast: 4), [1, 2, 0, 0])
        XCTAssertEqual(AudioSamples.padded([1, 2, 3], toAtLeast: 2), [1, 2, 3])
    }

    func testDuration() {
        XCTAssertEqual(AudioSamples.duration(sampleCount: 24_000), 1.5, accuracy: 1e-9)
        XCTAssertEqual(AudioSamples.duration(sampleCount: 10, sampleRate: 0), 0)
    }

    func testFloat32RoundTrip() {
        let samples: [Float] = [0, 0.25, -1, 1, 0.123456]
        XCTAssertEqual(AudioSamples.fromFloat32Data(AudioSamples.float32Data(samples)), samples)
    }
}

final class TranscriptTidyTests: XCTestCase {
    func testCollapsesWhitespaceAndFixesPunctuationSpacing() {
        XCTAssertEqual(TranscriptTidy.basic("  Hello   world , how are you ?  "), "Hello world, how are you?")
    }

    func testKeepsInteriorLineBreaks() {
        XCTAssertEqual(TranscriptTidy.basic("\nFirst line.\n\nSecond line.\n"), "First line.\n\nSecond line.")
    }

    func testEmpty() {
        XCTAssertEqual(TranscriptTidy.basic("   "), "")
    }
}

final class DictationTimelineTests: XCTestCase {
    func testLatencies() {
        var timeline = DictationTimeline(mode: .hold, engine: "parakeet-ultra", pressedAt: 10)
        timeline.captureStartedAt = 10.08
        timeline.releasedAt = 13.0
        timeline.audioReadyAt = 13.16
        timeline.transcribedAt = 13.30
        timeline.deliveredAt = 13.31
        timeline.audioSeconds = 3.2
        XCTAssertEqual(timeline.postReleaseLatency!, 0.31, accuracy: 1e-9)
        XCTAssertEqual(timeline.transcriptionTime!, 0.14, accuracy: 1e-9)
        XCTAssertEqual(timeline.captureStartDelay!, 0.08, accuracy: 1e-9)
        XCTAssertEqual(
            timeline.summary(),
            "hold · 3.2 s audio · mic start 80 ms · transcribe 140 ms · release→clipboard 310 ms · parakeet-ultra"
        )
    }

    func testMissingMarks() {
        let timeline = DictationTimeline(mode: .handsFree, engine: "x", pressedAt: 0)
        XCTAssertNil(timeline.postReleaseLatency)
        XCTAssertEqual(timeline.summary(), "handsFree · 0.0 s audio · x")
    }
}
