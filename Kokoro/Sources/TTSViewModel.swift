import Foundation
import AVFoundation
import FluidAudio
import Combine
#if canImport(UIKit)
import UIKit
#endif
#if canImport(UserNotifications)
import UserNotifications
#endif

@MainActor
class TTSViewModel: ObservableObject {
    @Published var isGenerating = false
    @Published var isStreaming = false
    @Published var isPlaying = false
    @Published var hasGeneratedAudio = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?
    @Published var audioDuration: Double = 0.0
    @Published var generationTime: Double = 0.0
    @Published var modelInitTime: Double = 0.0
    @Published var rtf: Double = 0.0
    @Published var timeToFirstAudio: Double = 0.0
    @Published var chunksGenerated: Int = 0
    @Published var totalChunks: Int = 0
    @Published var generationMode: GenerationMode = .none
    @Published var isPreWarming = false
    @Published var lastPreWarmDuration: Double?

    enum GenerationMode {
        case none
        case file
        case stream
    }

    private var streamingPlayer: StreamingAudioPlayer?
    private var audioPlayer: AVAudioPlayer?
    private var audioPlayerDelegate: AudioPlayerDelegate?
    private var generatedAudioURL: URL?
//    private let voice = "af_heart"
    private var generationStartTime: Date?
    private var generationEndTime: Date?
    private var firstChunkTime: Date?
    private let ttsManager = TtSManager()
#if canImport(UIKit)
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid
#endif

    init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to setup audio session: \(error)")
        }
    }

    private func beginBackgroundTask(named name: String) {
#if canImport(UIKit)
        endBackgroundTask()
        backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.handleBackgroundTaskExpiration()
            }
        }
#endif
    }

    private func endBackgroundTask() {
#if canImport(UIKit)
        guard backgroundTaskIdentifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
        backgroundTaskIdentifier = .invalid
#endif
    }

#if canImport(UIKit)
    private func handleBackgroundTaskExpiration() {
        if generationMode == .stream {
            streamingPlayer?.stopPlayback()
        } else {
            audioPlayer?.stop()
        }
        statusMessage = nil
        errorMessage = "Background execution time expired."
        isGenerating = false
        isStreaming = false
        isPlaying = false
        generationMode = .none
        endBackgroundTask()
    }
#endif

#if canImport(UserNotifications)
    private func requestNotificationAuthorizationIfNeeded() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, error in
                if let error {
                    print("Notification authorization request failed: \(error)")
                }
            }
        }
    }
#endif

#if canImport(UIKit) && canImport(UserNotifications)
    private func notifyCompletionIfBackground(for mode: GenerationMode) {
        guard UIApplication.shared.applicationState != .active else { return }

        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Kokoro Audio Ready"
        switch mode {
        case .file:
            content.body = "Your generated audio file is ready to play."
        case .stream:
            content.body = "Audio generation finished. Playback continues."
        case .none:
            content.body = "Audio generation has finished."
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "kokoro.tts.complete.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error {
                print("Failed to schedule completion notification: \(error)")
            }
        }
    }
#endif

    func clearDisplayedResults() {
        statusMessage = nil
        errorMessage = nil
        hasGeneratedAudio = false
        audioDuration = 0.0
        generationTime = 0.0
        modelInitTime = 0.0
        rtf = 0.0
        timeToFirstAudio = 0.0
        chunksGenerated = 0
        totalChunks = 0
        generationMode = .none
    }

    func preWarm(variant: ModelNames.TTS.Variant? = nil) async {
        if isPreWarming { return }

        await MainActor.run {
            self.errorMessage = nil
            self.statusMessage = "Pre-warming Kokoro engine..."
            self.isPreWarming = true
        }

        do {
            let warmStart = Date()

            if !ttsManager.isAvailable {
                try await ttsManager.initialize()
            }

//            try await ttsManager.preWarm(variant: variant)

            let duration = Date().timeIntervalSince(warmStart)

            await MainActor.run {
                self.lastPreWarmDuration = duration
                self.statusMessage = String(format: "Engine ready in %.2f seconds", duration)
                self.isPreWarming = false
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self else { return }
                if !self.isGenerating && !self.isStreaming {
                    self.statusMessage = nil
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Failed to pre-warm models: \(error.localizedDescription)"
                self.statusMessage = nil
                self.isPreWarming = false
            }
        }
    }

    func generateFile(from text: String, voice: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                self.errorMessage = "Please enter some text to synthesize"
            }
            return
        }

        await MainActor.run {
            self.isGenerating = true
            self.errorMessage = nil
            self.statusMessage = "Initializing TTS model..."
            self.audioDuration = 0.0
            self.generationTime = 0.0
            self.modelInitTime = 0.0
            self.rtf = 0.0
            self.generationMode = .file
        }

#if canImport(UserNotifications)
        requestNotificationAuthorizationIfNeeded()
#endif

        beginBackgroundTask(named: "TTSFileGeneration")
        defer { endBackgroundTask() }

        let startTime = Date()

        do {
            await MainActor.run {
                self.statusMessage = "Loading Kokoro model and resources..."
            }

            var initDuration: TimeInterval = 0
            if !ttsManager.isAvailable {
                let initStart = Date()
                try await ttsManager.initialize()
                initDuration = Date().timeIntervalSince(initStart)
            }

            await MainActor.run {
                self.modelInitTime = initDuration
                self.statusMessage = "Generating speech..."
            }

            let audioData = try await ttsManager.synthesize(text: text, voice: voice)

            let generationEndTime = Date()
            let totalGenerationTime = generationEndTime.timeIntervalSince(startTime)

            let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let audioURL = documentsPath.appendingPathComponent("generated_audio.wav")

            try audioData.write(to: audioURL)

            // Calculate audio duration
            let audioAsset = AVURLAsset(url: audioURL)
            let duration = try await audioAsset.load(.duration)
            let durationInSeconds = CMTimeGetSeconds(duration)

            // Calculate RTF
            let rtfValue = totalGenerationTime > 0 ? durationInSeconds / totalGenerationTime : 0.0

            await MainActor.run {
                self.generatedAudioURL = audioURL
                self.hasGeneratedAudio = true
                self.isGenerating = false
                self.audioDuration = durationInSeconds
                self.generationTime = totalGenerationTime
                self.rtf = rtfValue
                self.statusMessage = "Audio file generated successfully!"
#if canImport(UIKit) && canImport(UserNotifications)
                self.notifyCompletionIfBackground(for: .file)
#endif
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                self?.statusMessage = nil
            }

        } catch {
            await MainActor.run {
                self.isGenerating = false
                self.errorMessage = "Failed to generate audio: \(error.localizedDescription)"
                self.statusMessage = nil
            }
        }
    }

    func streamAudio(from text: String, voice: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            await MainActor.run {
                self.errorMessage = "Please enter some text to synthesize"
            }
            return
        }

        await MainActor.run {
            self.isStreaming = true
            self.isPlaying = true
            self.errorMessage = nil
            self.statusMessage = "Initializing TTS model..."
            self.audioDuration = 0.0
            self.generationTime = 0.0
            self.modelInitTime = 0.0
            self.timeToFirstAudio = 0.0
            self.chunksGenerated = 0
            self.totalChunks = 0
            self.generationMode = .stream
        }

#if canImport(UserNotifications)
        requestNotificationAuthorizationIfNeeded()
#endif

        beginBackgroundTask(named: "TTSStreaming")
        defer { endBackgroundTask() }

        generationStartTime = nil
        generationEndTime = nil
        firstChunkTime = nil
        streamingPlayer = StreamingAudioPlayer()

        do {
            await MainActor.run {
                self.statusMessage = "Loading Kokoro model and resources..."
            }

            var isFirstChunk = true

            // Start streaming synthesis (measure generation time only for synthesis span)
            generationStartTime = Date()
            try await KokoroStreamingSynthesizer.synthesizeStreaming(
                text: text,
                voice: voice,
                ttsManager: ttsManager,
                onInitComplete: { [weak self] initDuration in
                    guard let self = self else { return }
                    Task { @MainActor in
                        self.modelInitTime = initDuration
                        self.updateMetrics()
                    }
                }
            ) { [weak self] chunkData in
                guard let self = self else { return }

                await MainActor.run {
                    self.chunksGenerated += 1
                    self.statusMessage = "Generating chunk \(self.chunksGenerated)..."

                    // Start playback after first chunk is ready
                    if isFirstChunk {
                        isFirstChunk = false
                        self.firstChunkTime = Date()
                        if let startTime = self.generationStartTime {
                            self.timeToFirstAudio = self.firstChunkTime!.timeIntervalSince(startTime)
                        }
                        self.streamingPlayer?.startPlayback { [weak self] in
                            DispatchQueue.main.async {
                                self?.isPlaying = false
                                self?.updateMetrics()
                            }
                        }
                    }

                    // Enqueue audio data for immediate playback
                    self.streamingPlayer?.enqueueAudioData(chunkData)
                    self.hasGeneratedAudio = true
                }
            }

            // Signal end of streaming and finalize generation timing
            await MainActor.run {
                self.generationEndTime = Date()
                self.streamingPlayer?.finishStreaming()
                self.isStreaming = false
                self.statusMessage = "Audio streaming complete"
                self.updateMetrics()
#if canImport(UIKit) && canImport(UserNotifications)
                self.notifyCompletionIfBackground(for: .stream)
#endif
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                if self?.statusMessage == "Audio generation complete" {
                    self?.statusMessage = nil
                }
            }

        } catch {
            await MainActor.run {
                self.isStreaming = false
                self.isPlaying = false
                self.errorMessage = "Failed to stream audio: \(error.localizedDescription)"
                self.statusMessage = nil
            }
        }
    }

    private func updateMetrics() {
        guard let startTime = generationStartTime else { return }

        let totalElapsed: TimeInterval
        if let endTime = generationEndTime {
            totalElapsed = endTime.timeIntervalSince(startTime)
        } else {
            totalElapsed = Date().timeIntervalSince(startTime)
        }

        // Synthesis time excludes model init
        let synthesisOnly = max(0.0, totalElapsed - modelInitTime)
        generationTime = synthesisOnly

        audioDuration = streamingPlayer?.totalDuration ?? 0.0
        rtf = synthesisOnly > 0 ? (audioDuration / synthesisOnly) : 0.0
    }

    func playAudio() {
        guard let audioURL = generatedAudioURL else {
            errorMessage = "No audio file available to play"
            return
        }

        if isPlaying {
            audioPlayer?.stop()
            isPlaying = false
        } else {
            do {
                audioPlayer = try AVAudioPlayer(contentsOf: audioURL)
                audioPlayerDelegate = AudioPlayerDelegate(viewModel: self)
                audioPlayer?.delegate = audioPlayerDelegate
                audioPlayer?.prepareToPlay()
                audioPlayer?.play()
                isPlaying = true
                errorMessage = nil
            } catch {
                errorMessage = "Failed to play audio: \(error.localizedDescription)"
            }
        }
    }

    func stopPlayback() {
        if generationMode == .stream {
            streamingPlayer?.stopPlayback()
        } else {
            audioPlayer?.stop()
        }
        isPlaying = false
        isStreaming = false
        statusMessage = "Playback stopped"

        endBackgroundTask()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            if self?.statusMessage == "Playback stopped" {
                self?.statusMessage = nil
            }
        }
    }

    private final class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate, Sendable {
        private let viewModel: TTSViewModel

        init(viewModel: TTSViewModel) {
            self.viewModel = viewModel
        }

        func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
            Task { @MainActor in
                self.viewModel.isPlaying = false
            }
        }
    }
}
