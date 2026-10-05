import XCTest
@testable import MurmurCore

final class ScoringNormalizerTests: XCTestCase {
    func testLowercasesAndStripsPunctuation() {
        XCTAssertEqual(ScoringNormalizer.normalize("Hello, World! How's it going?"), "hello world how's it going")
    }

    func testCurlyQuotesHyphensAndEdges() {
        XCTAssertEqual(ScoringNormalizer.normalize("It\u{2019}s a state-of-the-art 'demo'"), "it's a state of the art demo")
    }

    func testWhitespaceCollapses() {
        XCTAssertEqual(ScoringNormalizer.words("  one\n two\tthree  "), ["one", "two", "three"])
    }

    func testKeepsDigitsAndNonLatinLetters() {
        XCTAssertEqual(ScoringNormalizer.normalize("Meet at 4 — कल मिलते हैं"), "meet at 4 कल मिलते हैं")
    }
}

final class EditDistanceTests: XCTestCase {
    func testIdentical() {
        XCTAssertEqual(EditDistance.operations(reference: ["a", "b"], hypothesis: ["a", "b"]).total, 0)
    }

    func testEmptySides() {
        XCTAssertEqual(EditDistance.operations(reference: [String](), hypothesis: ["a"]), EditOperations(insertions: 1))
        XCTAssertEqual(EditDistance.operations(reference: ["a", "b"], hypothesis: [String]()), EditOperations(deletions: 2))
    }

    func testSubstitutionAndInsertion() {
        // Only one minimal alignment exists: b→x, then e inserted.
        let ops = EditDistance.operations(reference: ["a", "b", "c", "d"], hypothesis: ["a", "x", "c", "d", "e"])
        XCTAssertEqual(ops, EditOperations(substitutions: 1, deletions: 0, insertions: 1))
    }

    func testDeletion() {
        let ops = EditDistance.operations(reference: ["a", "b", "c", "d"], hypothesis: ["a", "c", "d"])
        XCTAssertEqual(ops, EditOperations(substitutions: 0, deletions: 1, insertions: 0))
    }

    func testTiesPreferSubstitution() {
        // Two minimal alignments of cost 2 exist (2 S, or D + I); the convention picks substitutions.
        let ops = EditDistance.operations(reference: ["the", "mat"], hypothesis: ["mat", "today"])
        XCTAssertEqual(ops.total, 2)
    }

    func testCharacterDistanceAndSimilarity() {
        XCTAssertEqual(EditDistance.characters("kitten", "sitting"), 3)
        XCTAssertEqual(EditDistance.similarity("", ""), 1)
        XCTAssertEqual(EditDistance.similarity("abcd", "abcd"), 1)
        XCTAssertEqual(EditDistance.similarity("abcd", "abce"), 0.75, accuracy: 1e-9)
    }
}

final class WordErrorRateTests: XCTestCase {
    func testPerfectAfterNormalisation() {
        let wer = WordErrorRate.compute(reference: "Hello world.", hypothesis: "hello, world")
        XCTAssertEqual(wer.rate, 0)
        XCTAssertEqual(wer.referenceWords, 2)
    }

    func testRate() {
        let wer = WordErrorRate.compute(reference: "one two three four", hypothesis: "one too three")
        XCTAssertEqual(wer.operations, EditOperations(substitutions: 1, deletions: 1, insertions: 0))
        XCTAssertEqual(wer.rate, 0.5, accuracy: 1e-9)
    }

    func testEmptyReference() {
        XCTAssertEqual(WordErrorRate.compute(reference: "", hypothesis: "").rate, 0)
        XCTAssertEqual(WordErrorRate.compute(reference: "", hypothesis: "noise").rate, 1)
    }

    func testAggregateWeightsByLength() {
        let short = WordErrorRate.compute(reference: "a", hypothesis: "b")            // 1/1
        let long = WordErrorRate.compute(reference: "a b c d e f g h i", hypothesis: "a b c d e f g h i") // 0/9
        XCTAssertEqual(WordErrorRate.aggregate([short, long]).rate, 0.1, accuracy: 1e-9)
    }
}

final class PercentilesTests: XCTestCase {
    func testValues() {
        XCTAssertNil(Percentiles.value(50, of: []))
        XCTAssertEqual(Percentiles.value(95, of: [7]), 7)
        XCTAssertEqual(Percentiles.median([3, 1, 2])!, 2, accuracy: 1e-9)
        XCTAssertEqual(Percentiles.value(50, of: [1, 2, 3, 4])!, 2.5, accuracy: 1e-9)
        XCTAssertEqual(Percentiles.value(100, of: [1, 2, 3, 4])!, 4, accuracy: 1e-9)
        XCTAssertEqual(Percentiles.value(95, of: [0, 10])!, 9.5, accuracy: 1e-9)
    }
}

final class EvalManifestTests: XCTestCase {
    func testDecodesExampleShape() throws {
        let json = """
        {
          "clips": [
            {"id": "001", "audio": "audio/001.m4a", "category": "casual",
             "reference": "so um i was thinking we could meet at three no wait four",
             "expected": "I was thinking we could meet at 4.",
             "app": "com.tinyspeck.slackmacgap"},
            {"id": "002", "audio": "audio/002.wav", "reference": "hello"}
          ]
        }
        """
        let manifest = try JSONDecoder().decode(EvalManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.clips.count, 2)
        XCTAssertEqual(manifest.clips[0].category, "casual")
        XCTAssertNil(manifest.clips[1].expected)
    }

    func testReportMarkdown() {
        let clip = EvalClipResult(
            id: "001", category: "casual", reference: "hello world", hypothesis: "hello | world",
            wer: WordErrorRate.compute(reference: "hello world", hypothesis: "hello world"),
            audioSeconds: 1.5, processingSeconds: 0.12
        )
        let report = EvalReport(createdAt: "2026-10-05T10:00:00Z", engine: "parakeet-ultra", clips: [clip], failures: ["003: file missing"])
        let markdown = report.markdown()
        XCTAssertTrue(markdown.contains("| Corpus WER (raw ASR) | 0.0% |"))
        XCTAssertTrue(markdown.contains("| Transcription latency p50 | 120 ms |"))
        XCTAssertTrue(markdown.contains("hello \\| world"))
        XCTAssertTrue(markdown.contains("- 003: file missing"))
        XCTAssertEqual(report.werByCategory.map(\.category), ["casual"])
    }
}
