import FluidAudio
import Foundation
import SegmentTextKit

@available(iOS 16.0, *)
class KokoroStreamingSynthesizer {
    private static let sampleRate = 24_000
    private static let crossfadeMs = 8

    static func synthesizeStreaming(
        text: String,
        voice: String = "af_heart",
        ttsManager: TtSManager,
        onInitComplete: ((TimeInterval) -> Void)? = nil,
        onChunkGenerated: @escaping (Data) async -> Void
    ) async throws {
        try await streamChunks(
            text: text,
            voice: voice,
            ttsManager: ttsManager,
            onInitComplete: onInitComplete,
            emitSamples: { samples in
                let data = samplesToWAV(samples)
                if !data.isEmpty {
                    await onChunkGenerated(data)
                }
            },
            emitSilence: { duration in
                let data = generateSilence(duration: duration)
                if !data.isEmpty {
                    await onChunkGenerated(data)
                }
            }
        )
    }

    static func synthesizeStreamingToFile(
        text: String,
        voice: String = "af_heart",
        ttsManager: TtSManager,
        outputURL: URL,
        onInitComplete: ((TimeInterval) -> Void)? = nil
    ) async throws {
        let writer = try WavStreamWriter(outputURL: outputURL, sampleRate: Double(sampleRate))
        var didFinish = false
        defer {
            if !didFinish {
                try? writer.finish()
            }
        }

        do {
            try await streamChunks(
                text: text,
                voice: voice,
                ttsManager: ttsManager,
                onInitComplete: onInitComplete,
                emitSamples: { samples in
                    try samples.withUnsafeBufferPointer { buffer in
                        try writer.append(samples: buffer)
                    }
                },
                emitSilence: { duration in
                    let sampleCount = max(0, Int(Double(sampleRate) * duration))
                    try writer.appendSilence(sampleCount: sampleCount)
                }
            )
            try writer.finish()
            didFinish = true
        } catch {
            throw error
        }
    }

    private static func streamChunks(
        text: String,
        voice: String,
        ttsManager: TtSManager,
        onInitComplete: ((TimeInterval) -> Void)?,
        emitSamples: @escaping ([Float]) async throws -> Void,
        emitSilence: @escaping (Double) async throws -> Void
    ) async throws {
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

        let samplesPerMillisecond = Double(sampleRate) / 1_000.0
        let crossfadeSamples = max(
            0,
            Int(Double(crossfadeMs) * samplesPerMillisecond)
        )

        var previousSamples: [Float]? = nil
        var previousPauseMs = 0

        for chunk in chunks {
            if previousSamples == nil && previousPauseMs > 0 {
                let silenceDuration = Double(previousPauseMs) / 1_000.0
                try await emitSilence(silenceDuration)
                previousPauseMs = 0
            }

            var currentSamples = chunk.samples

            if var prevSamples = previousSamples {
                if previousPauseMs > 0 {
                    try await emitSamples(prevSamples)
                    let silenceDuration = Double(previousPauseMs) / 1_000.0
                    try await emitSilence(silenceDuration)
                } else {
                    let fadeCount = min(crossfadeSamples, prevSamples.count, currentSamples.count)
                    if fadeCount > 0 {
                        for index in 0 ..< fadeCount {
                            let sampleIndex = prevSamples.count - fadeCount + index
                            let t =
                                fadeCount == 1
                                ? Float(1.0)
                                : Float(index) / Float(fadeCount - 1)
                            prevSamples[sampleIndex] =
                                prevSamples[sampleIndex] * (1.0 - t) + currentSamples[index] * t
                        }
                        currentSamples.removeFirst(fadeCount)
                    }

                    try await emitSamples(prevSamples)
                }
            }

            previousSamples = currentSamples.isEmpty ? nil : currentSamples
            previousPauseMs = chunk.pauseAfterMs

            if previousSamples == nil && previousPauseMs > 0 {
                let silenceDuration = Double(previousPauseMs) / 1_000.0
                try await emitSilence(silenceDuration)
                previousPauseMs = 0
            }
        }

        if let tailSamples = previousSamples {
            try await emitSamples(tailSamples)

            if previousPauseMs > 0 {
                let silenceDuration = Double(previousPauseMs) / 1_000.0
                try await emitSilence(silenceDuration)
            }
        } else if previousPauseMs > 0 {
            let silenceDuration = Double(previousPauseMs) / 1_000.0
            try await emitSilence(silenceDuration)
        }
    }

    private static func generateSilence(duration: Double) -> Data {
        let sampleCount = max(0, Int(Double(sampleRate) * duration))
        guard sampleCount > 0 else { return Data() }
        let samples = [Float](repeating: 0, count: sampleCount)
        return samplesToWAV(samples)
    }

    private static func samplesToWAV(_ samples: [Float]) -> Data {
        guard !samples.isEmpty else { return Data() }

        var data = Data()

        data.append("RIFF".data(using: .ascii)!)
        let fileSize = UInt32(36 + samples.count * 2)
        data.append(contentsOf: withUnsafeBytes(of: fileSize.littleEndian) { Array($0) })
        data.append("WAVE".data(using: .ascii)!)

        data.append("fmt ".data(using: .ascii)!)
        data.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt32(sampleRate).littleEndian) { Array($0) })
        data.append(
            contentsOf: withUnsafeBytes(of: UInt32(sampleRate * 2).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(2).littleEndian) { Array($0) })
        data.append(contentsOf: withUnsafeBytes(of: UInt16(16).littleEndian) { Array($0) })

        data.append("data".data(using: .ascii)!)
        data.append(
            contentsOf: withUnsafeBytes(of: UInt32(samples.count * 2).littleEndian) { Array($0) })

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let scaled = Int16(clamped * 32767)
            data.append(contentsOf: withUnsafeBytes(of: scaled.littleEndian) { Array($0) })
        }

        return data
    }
}
