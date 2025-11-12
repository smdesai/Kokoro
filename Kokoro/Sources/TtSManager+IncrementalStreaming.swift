import FluidAudio
import Foundation

/// Extension to TtSManager providing true incremental streaming capabilities.
///
/// This extension adds support for processing text as it arrives incrementally,
/// generating audio chunks on-demand without waiting for complete text input.
///
/// ## True Incremental Streaming
///
/// Unlike the batch-then-stream approach in `KokoroChunkedSynthesizer`, this
/// implementation generates audio **as text arrives**, enabling:
/// - Lower Time To First Audio (TTFA)
/// - Real-time voice output for LLM responses
/// - Progressive audio generation without blocking
///
/// ## Usage Example
///
/// ```swift
/// let ttsManager = TtSManager()
/// try await ttsManager.initialize()
///
/// // Create text stream
/// let (textStream, continuation) = AsyncStream<String>.makeStream()
///
/// // Start audio generation
/// Task {
///     let audioStream = try await ttsManager.synthesizeIncremental(
///         textStream: textStream,
///         voice: "af_heart"
///     )
///
///     for await audioChunk in audioStream {
///         // Play audio as it's generated
///         player.enqueueAudioData(audioChunk)
///     }
/// }
///
/// // Feed text incrementally (e.g., from LLM)
/// continuation.yield("Hello, ")
/// continuation.yield("this is ")
/// continuation.yield("incremental streaming!")
/// continuation.finish()
/// ```
@available(iOS 16.0, *)
extension TtSManager {

    /// Synthesizes audio incrementally from a stream of text chunks.
    ///
    /// This method processes text as it arrives, generating and yielding audio chunks
    /// without waiting for the complete text. Each text chunk is synthesized independently,
    /// and the resulting audio is immediately available for playback.
    ///
    /// - Parameters:
    ///   - textStream: An async stream of text chunks to synthesize
    ///   - voice: Voice identifier for synthesis (defaults to manager's default voice)
    ///   - voiceSpeed: Speech rate multiplier (1.0 = normal speed)
    ///   - speakerId: Speaker ID for voice selection
    ///   - variantPreference: Model variant preference (5s or 15s)
    ///
    /// - Returns: An async stream of audio data (WAV format) generated incrementally
    ///
    /// - Note: Each text chunk is synthesized independently. For best results:
    ///   - Send complete sentences or phrases (not word-by-word)
    ///   - Ensure proper punctuation for natural prosody
    ///   - Consider sentence segmentation for optimal chunking
    ///
    /// - Throws: TTSError if synthesis fails for any text chunk
    func synthesizeIncremental(
        textStream: AsyncStream<String>,
        voice: String? = nil,
        voiceSpeed: Float = 1.0,
        speakerId: Int = 0,
        variantPreference: ModelNames.TTS.Variant? = nil
    ) async throws -> AsyncStream<Data> {
        return AsyncStream { continuation in
            Task {
                do {
                    for await textChunk in textStream {
                        let trimmed = textChunk.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }

                        // Generate audio for this text chunk
                        let audioData = try await self.synthesize(
                            text: trimmed,
                            voice: voice,
                            voiceSpeed: voiceSpeed,
                            speakerId: speakerId,
                            variantPreference: variantPreference
                        )

                        // Yield audio immediately
                        continuation.yield(audioData)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish()
                    throw error
                }
            }
        }
    }

    /// Synthesizes audio incrementally with detailed chunk information.
    ///
    /// Similar to `synthesizeIncremental()`, but returns detailed synthesis results
    /// including chunk metadata (words, tokens, samples, etc.) for each text chunk.
    ///
    /// - Parameters:
    ///   - textStream: An async stream of text chunks to synthesize
    ///   - voice: Voice identifier for synthesis
    ///   - voiceSpeed: Speech rate multiplier
    ///   - speakerId: Speaker ID for voice selection
    ///   - variantPreference: Model variant preference
    ///
    /// - Returns: An async stream of detailed synthesis results
    ///
    /// - Throws: TTSError if synthesis fails for any text chunk
    func synthesizeIncrementalDetailed(
        textStream: AsyncStream<String>,
        voice: String? = nil,
        voiceSpeed: Float = 1.0,
        speakerId: Int = 0,
        variantPreference: ModelNames.TTS.Variant? = nil
    ) async throws -> AsyncStream<KokoroSynthesizer.SynthesisResult> {
        return AsyncStream { continuation in
            Task {
                do {
                    for await textChunk in textStream {
                        let trimmed = textChunk.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }

                        // Generate detailed audio for this text chunk
                        let result = try await self.synthesizeDetailed(
                            text: trimmed,
                            voice: voice,
                            voiceSpeed: voiceSpeed,
                            speakerId: speakerId,
                            variantPreference: variantPreference
                        )

                        // Yield result immediately
                        continuation.yield(result)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish()
                    throw error
                }
            }
        }
    }

    /// Convenience method to synthesize from an array of text chunks.
    ///
    /// Converts an array of strings into an AsyncStream and synthesizes incrementally.
    /// Useful for pre-segmented text (e.g., sentences from a sentence splitter).
    ///
    /// - Parameters:
    ///   - textChunks: Array of text chunks to synthesize
    ///   - voice: Voice identifier for synthesis
    ///   - voiceSpeed: Speech rate multiplier
    ///   - speakerId: Speaker ID for voice selection
    ///   - variantPreference: Model variant preference
    ///
    /// - Returns: An async stream of audio data (WAV format)
    ///
    /// - Throws: TTSError if synthesis fails
    func synthesizeIncrementalFromArray(
        textChunks: [String],
        voice: String? = nil,
        voiceSpeed: Float = 1.0,
        speakerId: Int = 0,
        variantPreference: ModelNames.TTS.Variant? = nil
    ) async throws -> AsyncStream<Data> {
        let textStream = AsyncStream<String> { continuation in
            for chunk in textChunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }

        return try await synthesizeIncremental(
            textStream: textStream,
            voice: voice,
            voiceSpeed: voiceSpeed,
            speakerId: speakerId,
            variantPreference: variantPreference
        )
    }
}
