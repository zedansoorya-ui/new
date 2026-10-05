import Foundation

/// Helpers for 16 kHz mono Float32 audio, the format every Murmur engine consumes.
public enum AudioSamples {
    public static let sampleRate = 16_000

    /// Seconds of audio in `count` samples at `sampleRate`.
    public static func duration(sampleCount count: Int, sampleRate: Int = sampleRate) -> TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return TimeInterval(count) / TimeInterval(sampleRate)
    }

    /// Pads with trailing silence up to `minimumCount`. Parakeet rejects clips shorter than
    /// 0.3 s, and a very short press is still worth trying.
    public static func padded(_ samples: [Float], toAtLeast minimumCount: Int) -> [Float] {
        guard samples.count < minimumCount else { return samples }
        return samples + [Float](repeating: 0, count: minimumCount - samples.count)
    }

    /// Reinterprets little-endian Float32 bytes, the layout of Murmur's spool files.
    public static func fromFloat32Data(_ data: Data) -> [Float] {
        let count = data.count / MemoryLayout<Float>.size
        var samples = [Float](repeating: 0, count: count)
        _ = samples.withUnsafeMutableBytes { destination in
            data.copyBytes(to: destination, count: count * MemoryLayout<Float>.size)
        }
        return samples
    }

    /// Little-endian Float32 bytes for spooling.
    public static func float32Data(_ samples: [Float]) -> Data {
        samples.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
