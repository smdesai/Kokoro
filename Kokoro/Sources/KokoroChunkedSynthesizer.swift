import FluidAudio
import Foundation
import SegmentTextKit

/// Synthesizes audio from text using a batch-then-stream approach.
///
/// **Important:** This is NOT true incremental streaming. The full text is processed
/// upfront by the TTS model, generating all audio chunks in memory before any playback begins.
/// However, the generated chunks are then emitted progressively, allowing:
/// - Playback to start while later chunks are being emitted
/// - Incremental file writing to reduce peak memory usage
/// - Crossfading between chunks for smooth transitions
///
/// **For true incremental streaming** where text arrives over time (e.g., from an LLM),
/// use the sentence-by-sentence approach in `TTSViewModel.streamTextChunks()`.
///
/// ## Execution Flow:
/// 1. Receives complete text upfront
/// 2. Calls `ttsManager.synthesizeDetailed()` which generates ALL audio chunks
/// 3. Iterates through pre-generated chunks
/// 4. Applies crossfading between adjacent chunks
/// 5. Emits chunks progressively via callback
///
/// ## Use Cases:
/// - **File Generation:** Write large audio files incrementally to disk
/// - **Progressive Playback:** Start playing audio before entire file is assembled
/// - **Memory Optimization:** Process chunks one at a time rather than holding entire WAV
///
@available(iOS 16.0, *)
class KokoroChunkedSynthesizer {
    private static let sampleRate = 24_000
    private static let crossfadeMs = 8

    /// Synthesizes audio from complete text, emitting WAV chunks progressively for playback.
    ///
    /// - Note: The entire text is synthesized upfront before any chunks are emitted.
    ///   This is batch-then-stream, not true incremental streaming.
    ///
    /// - Parameters:
    ///   - text: The complete text to synthesize (must be provided entirely upfront)
    ///   - voice: Voice identifier for synthesis
    ///   - ttsManager: Initialized TTS manager
    ///   - onInitComplete: Called after model initialization with duration
    ///   - onChunkGenerated: Called for each audio chunk (WAV data) as it's emitted
    static func synthesizeBatchedWithChunkedPlayback(
        text: String,
        voice: String = "af_heart",
        ttsManager: TtSManager,
        onInitComplete: ((TimeInterval) -> Void)? = nil,
        onChunkGenerated: @escaping (Data) async -> Void
    ) async throws {
        try await processChunks(
            text: text,
            voice: voice,
            ttsManager: ttsManager,
            onInitComplete: onInitComplete,
            emitSamples: { samples in
                let data = try AudioWAV.data(from: samples, sampleRate: Double(sampleRate))
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

    /// Synthesizes audio from complete text, writing chunks incrementally to a WAV file.
    ///
    /// - Note: The entire text is synthesized upfront before any file writing begins.
    ///   Chunks are written incrementally to reduce peak memory usage, but synthesis
    ///   itself is not incremental.
    ///
    /// - Parameters:
    ///   - text: The complete text to synthesize (must be provided entirely upfront)
    ///   - voice: Voice identifier for synthesis
    ///   - ttsManager: Initialized TTS manager
    ///   - outputURL: File URL where the WAV file will be written
    ///   - onInitComplete: Called after model initialization with duration
    static func synthesizeBatchedToFile(
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
            try await processChunks(
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

    /// Core implementation: batch-synthesizes all audio, then emits chunks progressively.
    ///
    /// This method orchestrates the batch-then-stream process:
    /// 1. Initializes TTS manager if needed
    /// 2. **Blocks while synthesizing entire text** (via `synthesizeDetailed`)
    /// 3. Receives all pre-generated chunks
    /// 4. Iterates through chunks, applying crossfades
    /// 5. Emits chunks via callbacks
    private static func processChunks(
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

        // BATCH SYNTHESIS: All audio is generated here before any emission
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
        return (try? AudioWAV.data(from: samples, sampleRate: Double(sampleRate))) ?? Data()
    }

    // MARK: - True Incremental Streaming

    /// Synthesizes audio incrementally from a text stream with true streaming behavior.
    ///
    /// **This IS true incremental streaming.** Text is processed as it arrives, and audio
    /// is generated and emitted immediately without waiting for complete input.
    ///
    /// ## Difference from Batch Methods:
    /// - **Batch methods:** Wait for complete text → generate all audio → emit chunks
    /// - **This method:** Receive text chunk → generate audio → emit immediately → repeat
    ///
    /// ## Use Cases:
    /// - **LLM Voice Output:** Generate audio as the LLM produces text
    /// - **Real-Time Transcription:** Convert speech-to-text output to audio
    /// - **Low-Latency Applications:** Start playback as soon as first sentence is ready
    ///
    /// - Parameters:
    ///   - textStream: Async stream of text chunks (typically sentences or phrases)
    ///   - voice: Voice identifier for synthesis
    ///   - ttsManager: Initialized TTS manager
    ///   - onInitComplete: Called after first chunk initialization
    ///   - onChunkGenerated: Called for each audio chunk as it's generated
    ///
    /// - Note: For best results, send complete sentences or phrases rather than
    ///   individual words to maintain natural prosody.
    static func synthesizeTrueStreaming(
        textStream: AsyncStream<String>,
        voice: String = "af_heart",
        ttsManager: TtSManager,
        onInitComplete: ((TimeInterval) -> Void)? = nil,
        onChunkGenerated: @escaping (Data) async -> Void
    ) async throws {
        var hasReportedInit = false
        var initDuration: TimeInterval = 0

        if !ttsManager.isAvailable {
            let initStart = Date()
            try await ttsManager.initialize()
            initDuration = Date().timeIntervalSince(initStart)
        }

        let audioStream = try await ttsManager.synthesizeIncremental(
            textStream: textStream,
            voice: voice
        )

        for await audioData in audioStream {
            // Report initialization time on first chunk
            if !hasReportedInit {
                hasReportedInit = true
                onInitComplete?(initDuration)
            }

            // Emit audio chunk immediately
            await onChunkGenerated(audioData)
        }
    }

    /// Synthesizes audio incrementally from a text stream, writing directly to a file.
    ///
    /// **This IS true incremental streaming.** Text is processed as it arrives, and audio
    /// is written to the file incrementally without buffering all audio in memory.
    ///
    /// - Parameters:
    ///   - textStream: Async stream of text chunks (typically sentences or phrases)
    ///   - voice: Voice identifier for synthesis
    ///   - ttsManager: Initialized TTS manager
    ///   - outputURL: File URL where the WAV file will be written
    ///   - onInitComplete: Called after first chunk initialization
    ///
    /// - Note: The file is written incrementally as audio is generated. If the
    ///   process is interrupted, the file will be incomplete but valid up to the
    ///   last written chunk.
    static func synthesizeTrueStreamingToFile(
        textStream: AsyncStream<String>,
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

        var hasReportedInit = false
        var initDuration: TimeInterval = 0

        if !ttsManager.isAvailable {
            let initStart = Date()
            try await ttsManager.initialize()
            initDuration = Date().timeIntervalSince(initStart)
        }

        do {
            let audioStream = try await ttsManager.synthesizeIncrementalDetailed(
                textStream: textStream,
                voice: voice
            )

            for await result in audioStream {
                // Report initialization time on first chunk
                if !hasReportedInit {
                    hasReportedInit = true
                    onInitComplete?(initDuration)
                }

                // Write audio chunks directly to file
                for chunk in result.chunks {
                    try chunk.samples.withUnsafeBufferPointer { buffer in
                        try writer.append(samples: buffer)
                    }
                }
            }

            try writer.finish()
            didFinish = true
        } catch {
            throw error
        }
    }
}
