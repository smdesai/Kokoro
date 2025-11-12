import FluidAudio
import Foundation

/// Example usage of true incremental streaming for TTS.
///
/// This file demonstrates how to use the new streaming APIs added via extension
/// to TtSManager, which enables true low-latency audio generation as text arrives.
///
/// ## Scenarios Covered:
/// 1. Streaming from an async text source (e.g., LLM output)
/// 2. Streaming pre-segmented sentences
/// 3. Streaming to file with incremental writing
///
@available(iOS 16.0, *)
enum TrueStreamingExample {

    // MARK: - Example 1: Stream from LLM-style text generation

    /// Simulates streaming text from an LLM and generating audio in real-time.
    ///
    /// This example shows how to create an AsyncStream and feed text incrementally,
    /// which is ideal for LLM voice output where text arrives token-by-token or
    /// sentence-by-sentence.
    static func streamFromLLM() async throws {
        let ttsManager = TtSManager()
        try await ttsManager.initialize()

        // Create a text stream (producer-consumer pattern)
        let (textStream, continuation) = AsyncStream<String>.makeStream()

        // Start audio generation in background
        Task {
            let audioStream = try await ttsManager.synthesizeIncremental(
                textStream: textStream,
                voice: "af_heart"
            )

            for await audioChunk in audioStream {
                print("Received audio chunk: \(audioChunk.count) bytes")
                // Here you would send to your audio player
                // player.enqueueAudioData(audioChunk)
            }
        }

        // Simulate LLM producing text incrementally
        let sentences = [
            "Hello, I am a text-to-speech system.",
            "I can generate audio as text arrives.",
            "This enables low-latency voice output.",
            "Perfect for conversational AI applications!",
        ]

        for sentence in sentences {
            print("Sending: \(sentence)")
            continuation.yield(sentence)
            // Simulate delay between sentences (like LLM streaming)
            try await Task.sleep(nanoseconds: 500_000_000)  // 500ms
        }

        continuation.finish()
        print("Streaming complete!")
    }

    // MARK: - Example 2: Stream from pre-segmented text

    /// Demonstrates streaming from an array of pre-split sentences.
    ///
    /// This is useful when you have text that's already been segmented into
    /// sentences or phrases, and you want true incremental synthesis.
    static func streamFromArray() async throws {
        let ttsManager = TtSManager()
        try await ttsManager.initialize()

        let sentences = [
            "The quick brown fox jumps over the lazy dog.",
            "This is the second sentence.",
            "And here is the third one.",
            "Finally, we conclude with this sentence.",
        ]

        let audioStream = try await ttsManager.synthesizeIncrementalFromArray(
            textChunks: sentences,
            voice: "af_heart"
        )

        var chunkCount = 0
        for await audioChunk in audioStream {
            chunkCount += 1
            print("Chunk \(chunkCount): \(audioChunk.count) bytes")
            // Send to player immediately
            // player.enqueueAudioData(audioChunk)
        }

        print("Generated \(chunkCount) audio chunks")
    }

    // MARK: - Example 3: Stream to file with detailed results

    /// Demonstrates streaming synthesis with detailed chunk information
    /// and writing incrementally to a file.
    static func streamToFileWithDetails() async throws {
        let ttsManager = TtSManager()
        try await ttsManager.initialize()

        let sentences = [
            "This is sentence one.",
            "Here comes sentence two.",
            "And finally, sentence three.",
        ]

        // Create text stream
        let textStream = AsyncStream<String> { continuation in
            for sentence in sentences {
                continuation.yield(sentence)
            }
            continuation.finish()
        }

        // Get detailed synthesis results
        let audioStream = try await ttsManager.synthesizeIncrementalDetailed(
            textStream: textStream,
            voice: "af_heart"
        )

        var totalSamples = 0
        var totalChunks = 0

        for await result in audioStream {
            totalChunks += result.chunks.count
            let sampleCount = result.chunks.reduce(0) { $0 + $1.samples.count }
            totalSamples += sampleCount

            print("Result chunk: \(result.chunks.count) sub-chunks, \(sampleCount) samples")

            // Write to file incrementally here
            // writer.append(samples: ...)
        }

        print("Total: \(totalChunks) chunks, \(totalSamples) samples")
    }

    // MARK: - Example 4: Using with TTSViewModel

    /// Shows how to use true streaming with the TTSViewModel.
    ///
    /// This demonstrates integration with the existing view model for UI applications.
    static func streamWithViewModel(viewModel: TTSViewModel, sentences: [String]) async {
        // Option 1: Stream from array
        await viewModel.streamAudioTrueStreamingFromArray(
            textChunks: sentences,
            voice: "af_heart"
        )

        // Option 2: Stream from AsyncStream (e.g., LLM output)
        let (textStream, continuation) = AsyncStream<String>.makeStream()

        Task {
            await viewModel.streamAudioTrueStreaming(
                textStream: textStream,
                voice: "af_heart"
            )
        }

        // Feed text incrementally
        for sentence in sentences {
            continuation.yield(sentence)
            try? await Task.sleep(nanoseconds: 300_000_000)  // 300ms between sentences
        }
        continuation.finish()
    }

    // MARK: - Example 5: Using KokoroChunkedSynthesizer directly

    /// Demonstrates using the synthesizer directly for maximum control.
    static func streamWithSynthesizerDirect() async throws {
        let ttsManager = TtSManager()
        try await ttsManager.initialize()

        let sentences = ["First sentence.", "Second sentence.", "Third sentence."]
        let textStream = AsyncStream<String> { continuation in
            for sentence in sentences {
                continuation.yield(sentence)
            }
            continuation.finish()
        }

        try await KokoroChunkedSynthesizer.synthesizeTrueStreaming(
            textStream: textStream,
            voice: "af_heart",
            ttsManager: ttsManager,
            onInitComplete: { duration in
                print("Model initialized in \(duration)s")
            },
            onChunkGenerated: { audioData in
                print("Generated \(audioData.count) bytes")
                // Process audio immediately
            }
        )

        print("True streaming complete!")
    }

    // MARK: - Performance Comparison

    /// Compares batch vs true streaming performance.
    static func comparePerformance() async throws {
        let ttsManager = TtSManager()
        try await ttsManager.initialize()

        let text = """
            This is a longer text that will be used to compare performance.
            It contains multiple sentences to demonstrate the difference.
            With true streaming, the first sentence plays immediately.
            With batch processing, we wait for everything to generate first.
            """

        let sentences = text.components(separatedBy: ". ").filter { !$0.isEmpty }

        // Batch approach
        print("\n=== BATCH APPROACH ===")
        let batchStart = Date()
        var batchFirstAudioTime: TimeInterval?

        try await KokoroChunkedSynthesizer.synthesizeBatchedWithChunkedPlayback(
            text: text,
            voice: "af_heart",
            ttsManager: ttsManager,
            onInitComplete: nil
        ) { audioData in
            if batchFirstAudioTime == nil {
                batchFirstAudioTime = Date().timeIntervalSince(batchStart)
                print("First audio (batch): \(batchFirstAudioTime!)s")
            }
        }
        let batchTotal = Date().timeIntervalSince(batchStart)
        print("Total time (batch): \(batchTotal)s")

        // True streaming approach
        print("\n=== TRUE STREAMING APPROACH ===")
        let streamStart = Date()
        var streamFirstAudioTime: TimeInterval?

        let textStream = AsyncStream<String> { continuation in
            for sentence in sentences {
                continuation.yield(sentence + ".")
            }
            continuation.finish()
        }

        try await KokoroChunkedSynthesizer.synthesizeTrueStreaming(
            textStream: textStream,
            voice: "af_heart",
            ttsManager: ttsManager,
            onInitComplete: nil
        ) { audioData in
            if streamFirstAudioTime == nil {
                streamFirstAudioTime = Date().timeIntervalSince(streamStart)
                print("First audio (stream): \(streamFirstAudioTime!)s")
            }
        }
        let streamTotal = Date().timeIntervalSince(streamStart)
        print("Total time (stream): \(streamTotal)s")

        // Compare
        print("\n=== COMPARISON ===")
        if let batchFirst = batchFirstAudioTime, let streamFirst = streamFirstAudioTime {
            let improvement = ((batchFirst - streamFirst) / batchFirst) * 100
            print("Time to first audio improvement: \(String(format: "%.1f", improvement))%")
        }
    }
}
