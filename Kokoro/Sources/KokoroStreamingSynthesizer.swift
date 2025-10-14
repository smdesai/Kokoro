import Foundation
import FluidAudio
import SegmentTextKit

@available(iOS 16.0, *)
class KokoroStreamingSynthesizer {
    static func synthesizeStreaming(
        text: String,
        voice: String = "af_heart",
        ttsManager: TtSManager,
        onInitComplete: ((TimeInterval) -> Void)? = nil,
        onChunkGenerated: @escaping (Data) async -> Void
    ) async throws {
        // Measure model initialization (downloads + CoreML load)
        var initDuration: TimeInterval = 0
        if !ttsManager.isAvailable {
            let initStart = Date()
            try await ttsManager.initialize()
            initDuration = Date().timeIntervalSince(initStart)
        }
        onInitComplete?(initDuration)

        let synthesis = try await ttsManager.synthesizeDetailed(text: text, voice: voice)
        let chunks = synthesis.chunks

        guard !chunks.isEmpty else {
            throw TTSError.processingFailed("No valid chunks generated from text")
        }

        let sampleRate = 24_000
        let crossfadeMs = 8
        let crossfadeSamples = max(0, Int(Double(crossfadeMs) * 24.0))

        var previousSamples: [Float]? = nil
        var previousPauseMs = 0

        for chunk in chunks {
            if previousSamples == nil && previousPauseMs > 0 {
                let silence = generateSilence(duration: Double(previousPauseMs) / 1000.0, sampleRate: sampleRate)
                if !silence.isEmpty {
                    await onChunkGenerated(silence)
                }
                previousPauseMs = 0
            }

            var currentSamples = chunk.samples

            if var prevSamples = previousSamples {
                if previousPauseMs > 0 {
                    let data = samplesToWAV(prevSamples, sampleRate: sampleRate)
                    await onChunkGenerated(data)

                    let silence = generateSilence(duration: Double(previousPauseMs) / 1000.0, sampleRate: sampleRate)
                    if !silence.isEmpty {
                        await onChunkGenerated(silence)
                    }
                } else {
                    let fadeCount = min(crossfadeSamples, prevSamples.count, currentSamples.count)
                    if fadeCount > 0 {
                        for index in 0..<fadeCount {
                            let sampleIndex = prevSamples.count - fadeCount + index
                            let t = fadeCount == 1 ? Float(1.0) : Float(index) / Float(fadeCount - 1)
                            prevSamples[sampleIndex] = prevSamples[sampleIndex] * (1.0 - t) + currentSamples[index] * t
                        }
                        currentSamples.removeFirst(fadeCount)
                    }

                    let data = samplesToWAV(prevSamples, sampleRate: sampleRate)
                    await onChunkGenerated(data)
                }
            }

            previousSamples = currentSamples.isEmpty ? nil : currentSamples
            previousPauseMs = chunk.pauseAfterMs

            if previousSamples == nil && previousPauseMs > 0 {
                let silence = generateSilence(duration: Double(previousPauseMs) / 1000.0, sampleRate: sampleRate)
                if !silence.isEmpty {
                    await onChunkGenerated(silence)
                }
                previousPauseMs = 0
            }
        }

        if let tailSamples = previousSamples {
            let data = samplesToWAV(tailSamples, sampleRate: sampleRate)
            await onChunkGenerated(data)

            if previousPauseMs > 0 {
                let silence = generateSilence(duration: Double(previousPauseMs) / 1000.0, sampleRate: sampleRate)
                if !silence.isEmpty {
                    await onChunkGenerated(silence)
                }
            }
        } else if previousPauseMs > 0 {
            let silence = generateSilence(duration: Double(previousPauseMs) / 1000.0, sampleRate: sampleRate)
            if !silence.isEmpty {
                await onChunkGenerated(silence)
            }
        }
    }

    private static func generateSilence(duration: Double, sampleRate: Int) -> Data {
        let sampleCount = max(0, Int(Double(sampleRate) * duration))
        guard sampleCount > 0 else { return Data() }
        let samples = [Float](repeating: 0, count: sampleCount)
        return samplesToWAV(samples, sampleRate: sampleRate)
    }

    private static func samplesToWAV(_ samples: [Float], sampleRate: Int) -> Data {
        guard !samples.isEmpty else { return Data() }

        var data = Data()

        // WAV header
        data.append("RIFF".data(using: .ascii)!)
        let fileSize = UInt32(36 + samples.count * 2)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append("WAVE".data(using: .ascii)!)

        // fmt chunk
        data.append("fmt ".data(using: .ascii)!)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // PCM
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) }) // Mono
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })

        // data chunk
        data.append("data".data(using: .ascii)!)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(samples.count * 2).littleEndian) { Array($0) })

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let scaled = Int16(clamped * 32767)
            data.append(contentsOf: withUnsafeBytes(of: scaled.littleEndian) { Array($0) })
        }

        return data
    }
}
