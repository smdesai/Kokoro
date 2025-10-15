import AVFoundation
import Foundation

@MainActor
class StreamingAudioPlayer: NSObject {
    private var audioEngine: AVAudioEngine
    private var playerNode: AVAudioPlayerNode
    private var playbackFormat: AVAudioFormat
    private var inputFormat: AVAudioFormat  // Input format from TTS (24 kHz mono)
    // Buffers are queued until the engine is ready to schedule them
    private var audioBufferQueue: [AVAudioPCMBuffer] = []
    private var isPlaying = false
    private var bufferSemaphore = DispatchSemaphore(value: 1)
    private var totalDurationScheduled: TimeInterval = 0
    private var onPlaybackComplete: (() -> Void)?
    private var pendingBufferCount = 0
    private var isFinishing = false

    override init() {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()

        // Kokoro TTS outputs 24 kHz mono WAV; match that here
        inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 24000,
            channels: 1,
            interleaved: false
        )!

        playbackFormat = inputFormat

        super.init()
        setupAudioEngine()
    }

    private func setupAudioEngine() {
        audioEngine.attach(playerNode)

        // Connect player to main mixer with matching format
        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: playbackFormat)

        do {
            let session = AVAudioSession.sharedInstance()
            if session.category != .playback || session.mode != .default {
                try session.setCategory(.playback, mode: .default)
            }
            try session.setActive(true)

            try audioEngine.start()

            print("Audio engine started with playback format: \(playbackFormat)")
            print("Main mixer format: \(audioEngine.mainMixerNode.outputFormat(forBus: 0))")
        } catch {
            print("Failed to setup audio engine: \(error)")
        }
    }

    func startPlayback(onComplete: @escaping () -> Void) {
        onPlaybackComplete = onComplete
        isPlaying = true
        isFinishing = false
        pendingBufferCount = 0
        totalDurationScheduled = 0

        // Ensure audio engine is running
        if !audioEngine.isRunning {
            do {
                try audioEngine.start()
                print("Started audio engine")
            } catch {
                print("Failed to start audio engine: \(error)")
            }
        }

        playerNode.play()
        print("Started playback")
    }

    func stopPlayback() {
        isPlaying = false
        isFinishing = false
        pendingBufferCount = 0
        playerNode.stop()

        bufferSemaphore.wait()
        audioBufferQueue.removeAll()
        bufferSemaphore.signal()

        onPlaybackComplete?()
        onPlaybackComplete = nil
    }

    func enqueueAudioData(_ audioData: Data) {
        guard isPlaying else {
            print("Not playing, skipping audio data")
            return
        }

        print("Enqueuing audio data of size: \(audioData.count) bytes")

        // Convert Data to PCM buffer
        guard let buffer = dataToPCMBuffer(audioData) else {
            print("Failed to convert data to PCM buffer")
            return
        }

        print("Created buffer with \(buffer.frameLength) frames")

        bufferSemaphore.wait()
        audioBufferQueue.append(buffer)
        bufferSemaphore.signal()

        scheduleBuffers()
    }

    private func dataToPCMBuffer(_ data: Data) -> AVAudioPCMBuffer? {
        // Detect WAV and parse header for sample rate (and channels if needed)
        let isWAV = data.count >= 44 && data.prefix(4) == "RIFF".data(using: .ascii)

        var srcSampleRate = inputFormat.sampleRate  // default to configured input rate
        var payload = data

        if isWAV {
            // Minimal WAV header parse: mono, 16-bit PCM, read sampleRate at byte offset 24
            let header = data.prefix(44)
            srcSampleRate = header[24 ..< 28].withUnsafeBytes { raw in
                return Double(UInt32(littleEndian: raw.load(fromByteOffset: 0, as: UInt32.self)))
            }
            // Extract payload after 44-byte header
            payload = data.subdata(in: 44 ..< data.count)
        }

        // Convert 16-bit PCM to Float32 mono buffer in source sample rate
        let int16Count = payload.count / MemoryLayout<Int16>.size
        guard int16Count > 0 else { return nil }

        // We assume mono sources; if channels > 1 we could downmix, but our generator is mono
        let srcFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: srcSampleRate,
            channels: 1,
            interleaved: false
        )!

        guard
            let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: srcFormat,
                frameCapacity: AVAudioFrameCount(int16Count)
            )
        else { return nil }

        inputBuffer.frameLength = AVAudioFrameCount(int16Count)

        payload.withUnsafeBytes { bytes in
            let int16Pointer = bytes.bindMemory(to: Int16.self)
            if let channelData = inputBuffer.floatChannelData?[0] {
                for i in 0 ..< int16Count {
                    let sample = Int16(littleEndian: int16Pointer[i])
                    channelData[i] = Float(sample) / 32768.0
                }
            }
        }

        if abs(srcSampleRate - playbackFormat.sampleRate) > 0.1 {
            print(
                "Sample rate mismatch: src=\(srcSampleRate), playback=\(playbackFormat.sampleRate)")

            guard let converter = AVAudioConverter(from: srcFormat, to: playbackFormat) else {
                print("Failed to create converter for sample rate mismatch")
                return nil
            }

            let ratio = playbackFormat.sampleRate / srcSampleRate
            let expectedFrames = AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio))

            guard
                let converted = AVAudioPCMBuffer(
                    pcmFormat: playbackFormat,
                    frameCapacity: expectedFrames
                )
            else {
                print("Failed to allocate conversion buffer")
                return nil
            }

            do {
                try converter.convert(to: converted, from: inputBuffer)
                let expected = AVAudioFrameCount(ceil(Double(inputBuffer.frameLength) * ratio))
                converted.frameLength = min(expected, converted.frameCapacity)
                return converted
            } catch {
                print("Conversion error: \(error.localizedDescription)")
                return nil
            }
        }

        return inputBuffer
    }

    private func scheduleBuffers() {
        bufferSemaphore.wait()
        let buffersToSchedule = audioBufferQueue
        audioBufferQueue.removeAll(keepingCapacity: true)
        bufferSemaphore.signal()

        guard !buffersToSchedule.isEmpty else { return }

        for buffer in buffersToSchedule {
            schedule(buffer: buffer)
        }
    }

    private func schedule(buffer: AVAudioPCMBuffer) {
        pendingBufferCount += 1
        let durationIncrement = Double(buffer.frameLength) / buffer.format.sampleRate
        totalDurationScheduled += durationIncrement

        print(
            "Scheduling buffer, length: \(buffer.frameLength) frames @ \(buffer.format.sampleRate) Hz, pending: \(pendingBufferCount)"
        )
        if let channelData = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            let headCount = min(3, Int(buffer.frameLength))
            let tailCount = min(5, Int(buffer.frameLength))
            let headSamples = (0 ..< headCount).map { channelData[$0] }
            let tailSamples = (0 ..< tailCount).map {
                channelData[Int(buffer.frameLength) - tailCount + $0]
            }
            let headString = headSamples.map { String(format: "%.4f", $0) }.joined(separator: ", ")
            let tailString = tailSamples.map { String(format: "%.4f", $0) }.joined(separator: ", ")
            print("Buffer head samples: [\(headString)]")
            print("Buffer tail samples: [\(tailString)]")
        }

        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) {
            [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                if self.pendingBufferCount > 0 {
                    self.pendingBufferCount -= 1
                }

                let time = self.formattedPlaybackTime()
                print(
                    "Buffer rendered, remaining pending: \(self.pendingBufferCount), playback time: \(time)"
                )

                if self.isFinishing && self.pendingBufferCount == 0 {
                    self.completePlayback()
                }
            }
        }

        // Debug logging
        print("Scheduled buffer with \(buffer.frameLength) frames")
        let formattedDuration = String(format: "%.3f", totalDurationScheduled)
        print("Total scheduled duration: \(formattedDuration)s")
    }

    func finishStreaming() {
        // Mark that no more buffers will be added
        print("Finishing streaming, scheduling remaining buffers")

        isFinishing = true

        // Schedule any remaining buffers
        scheduleBuffers()

        print("finishStreaming pending buffers: \(pendingBufferCount)")

        // Add a small trailing silence so the device has time to render the final phoneme
        if let silenceBuffer = makeSilenceBuffer(duration: 0.25) {
            schedule(buffer: silenceBuffer)
            print("Scheduled trailing silence buffer")
        }

        // If nothing was scheduled, finish immediately
        if pendingBufferCount == 0 {
            completePlayback()
        }
    }

    private func completePlayback() {
        guard let completion = onPlaybackComplete else { return }

        isPlaying = false
        isFinishing = false
        pendingBufferCount = 0

        let finalTime = formattedPlaybackTime()
        print("Playback completed at \(finalTime)")
        completion()
        onPlaybackComplete = nil
    }

    var currentTime: TimeInterval {
        guard let nodeTime = playerNode.lastRenderTime,
            let playerTime = playerNode.playerTime(forNodeTime: nodeTime)
        else {
            return 0
        }
        return Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    var totalDuration: TimeInterval {
        return totalDurationScheduled
    }

    private func formattedPlaybackTime() -> String {
        let time = currentTime
        return String(format: "%.3fs", time)
    }

    private func makeSilenceBuffer(duration: TimeInterval) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(duration * playbackFormat.sampleRate)
        guard frameCount > 0,
            let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount)
        else { return nil }

        buffer.frameLength = frameCount
        if let channelData = buffer.floatChannelData?[0] {
            channelData.initialize(repeating: 0, count: Int(frameCount))
        }
        return buffer
    }
}
