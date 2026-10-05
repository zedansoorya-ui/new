import Foundation

/// Converts audio blocks into levels for the recording waveform.
public enum LevelMeter {
    /// Root mean square of a block of samples; 0 for an empty block.
    public static func rms<C: Collection>(_ samples: C) -> Float where C.Element == Float {
        guard !samples.isEmpty else { return 0 }
        var sumOfSquares: Float = 0
        for sample in samples {
            sumOfSquares += sample * sample
        }
        return (sumOfSquares / Float(samples.count)).squareRoot()
    }

    /// RMS in dBFS, clamped to [-160, 0].
    public static func decibels(rms: Float) -> Float {
        guard rms > 0.000_001 else { return -160 }
        return min(0, max(-160, 20 * log10(rms)))
    }

    /// Maps dBFS to a 0...1 display level. Everything at or below `floor` reads as silence; the
    /// square-root curve lifts quiet speech so the waveform moves for normal voices.
    public static func displayLevel(decibels: Float, floor: Float = -55) -> Float {
        guard decibels > floor else { return 0 }
        let linear = (decibels - floor) / -floor
        return min(1, max(0, linear)).squareRoot()
    }

    /// Convenience: display level straight from samples.
    public static func displayLevel<C: Collection>(of samples: C) -> Float where C.Element == Float {
        displayLevel(decibels: decibels(rms: rms(samples)))
    }
}
