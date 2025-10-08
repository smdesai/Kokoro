import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var viewModel = TTSViewModel()
    @State private var inputText: String = "This is the [Kokoro](/kˈOkəɹO/) TTS model. It supports the [Misaki](/misˈɑki/) [G2P](G to P) engine for better currency, time and number support. Here are some examples. The item costs $5.23. The current time is 2:30 and the value of pi is 3.14 to 2 decimal places. It also supports alias replacement so things like [Dr.](Doctor) sound better and direct phonetic replacement as in, you say [tomato](/təmˈɑːtQ/), I say [tomato](/təmˈAɾO/)."

    @FocusState private var isTextFieldFocused: Bool
    @State private var keyboardHeight: CGFloat = 0
    @StateObject private var speakerModel = SpeakerViewModel()

    var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 16) {
                            speakerCard
                            HStack {
                                Label("Text Input", systemImage: "text.quote")
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                Spacer()

                                if !inputText.isEmpty {
                                    Button(action: {
                                        inputText = ""
                                    }) {
                                        HStack(spacing: 4) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.system(size: 14))
                                            Text("Clear")
                                                .font(.caption)
                                        }
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(.tertiarySystemBackground))
                                        .cornerRadius(6)
                                    }
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }

                            TextEditor(text: $inputText)
                                .font(.system(size: 16))
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                                .frame(minHeight: 250, maxHeight: 450)
                                .focused($isTextFieldFocused)
                                .toolbar {
                                    ToolbarItemGroup(placement: .keyboard) {
                                        Spacer()
                                        Button("Done") {
                                            isTextFieldFocused = false
                                        }
                                        .foregroundColor(.blue)
                                    }
                                }
                        }
                        .padding(.horizontal)

//                        Button(action: {
//                            if !viewModel.isPreWarming {
//                                Task {
//                                    await viewModel.preWarm()
//                                }
//                            }
//                        }) {
//                            HStack(spacing: 16) {
//                                ZStack {
//                                    Circle()
//                                        .fill(Color(.tertiarySystemBackground))
//                                        .frame(width: 44, height: 44)
//
//                                    if viewModel.isPreWarming {
//                                        ProgressView()
//                                            .scaleEffect(0.8)
//                                    } else {
//                                        Image(systemName: "flame.fill")
//                                            .font(.system(size: 20, weight: .semibold))
//                                            .foregroundColor(.orange)
//                                    }
//                                }
//
//                                VStack(alignment: .leading, spacing: 4) {
//                                    Text(viewModel.isPreWarming ? "Pre-warming..." : "Pre-warm Engine")
//                                        .font(.system(size: 16, weight: .semibold))
//                                        .foregroundStyle(.primary)
//
//                                    if let warmDuration = viewModel.lastPreWarmDuration {
//                                        Text(String(format: "Last ready in %.2f seconds", warmDuration))
//                                            .font(.caption)
//                                            .foregroundStyle(.secondary)
//                                    } else {
//                                        Text("Prepare models for instant playback")
//                                            .font(.caption)
//                                            .foregroundStyle(.secondary)
//                                    }
//                                }
//
//                                Spacer()
//                            }
//                            .padding(.vertical, 14)
//                            .padding(.horizontal, 20)
//                            .background(
//                                RoundedRectangle(cornerRadius: 12)
//                                    .fill(Color(.secondarySystemBackground))
//                            )
//                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                        .disabled(viewModel.isPreWarming || viewModel.isGenerating || viewModel.isStreaming)
                        .opacity(viewModel.isPreWarming ? 0.6 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.isPreWarming)

                        VStack(spacing: 16) {
                            HStack(spacing: 12) {
                                // Generate File button
                                Button(action: {
                                    Task {
                                        let speaker = speakerModel.getSpeaker().first!
                                        await viewModel.generateFile(from: inputText, voice: speaker.name)
                                    }
                                }) {
                                    VStack(spacing: 8) {
                                        Image(systemName: "waveform.badge.plus")
                                            .font(.system(size: 24))
                                            .foregroundColor(.blue)

                                        Text("Generate")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 80)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.secondarySystemBackground))
                                    )
                                }
                                .disabled(viewModel.isPreWarming || viewModel.isGenerating || viewModel.isStreaming || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .opacity((viewModel.isPreWarming || viewModel.isGenerating || viewModel.isStreaming || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.5 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: viewModel.isGenerating)
                                
                                // Stream button
                                Button(action: {
                                    if viewModel.isStreaming || (viewModel.isPlaying && viewModel.generationMode == .stream) {
                                        viewModel.stopPlayback()
                                    } else {
                                        Task {
                                            let speaker = speakerModel.getSpeaker().first!
                                            await viewModel.streamAudio(from: inputText, voice: speaker.name)
                                        }
                                    }
                                }) {
                                    VStack(spacing: 8) {
                                        if viewModel.isStreaming {
                                            ProgressView()
                                                .scaleEffect(1.2)
                                        } else if viewModel.isPlaying && viewModel.generationMode == .stream {
                                            Image(systemName: "stop.fill")
                                                .font(.system(size: 24))
                                                .foregroundColor(.red)
                                        } else {
                                            Image(systemName: "antenna.radiowaves.left.and.right")
                                                .font(.system(size: 24))
                                                .foregroundColor(.purple)
                                        }

                                        Text(viewModel.isStreaming ? "Streaming" : (viewModel.isPlaying && viewModel.generationMode == .stream ? "Stop" : "Stream"))
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 80)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.secondarySystemBackground))
                                    )
                                }
                                .disabled(viewModel.isPreWarming || viewModel.isGenerating || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .opacity((viewModel.isPreWarming || viewModel.isGenerating || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.5 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: viewModel.isStreaming)
                                .animation(.easeInOut(duration: 0.2), value: viewModel.isPlaying)
                                
                                // Play button
                                Button(action: {
                                    viewModel.playAudio()
                                }) {
                                    VStack(spacing: 8) {
                                        Image(systemName: viewModel.isPlaying && viewModel.generationMode == .file ? "stop.fill" : "play.fill")
                                            .font(.system(size: 24))
                                            .foregroundColor(viewModel.isPlaying && viewModel.generationMode == .file ? .red : .green)

                                        Text(viewModel.isPlaying && viewModel.generationMode == .file ? "Stop" : "Play")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.primary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 80)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12)
                                            .fill(Color(.secondarySystemBackground))
                                    )
                                }
                                .disabled(!viewModel.hasGeneratedAudio || viewModel.isPreWarming || viewModel.isGenerating || viewModel.isStreaming || viewModel.generationMode != .file)
                                .opacity((!viewModel.hasGeneratedAudio || viewModel.isPreWarming || viewModel.isGenerating || viewModel.isStreaming || viewModel.generationMode != .file) ? 0.5 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: viewModel.isPlaying)
                            }
                            .padding(.horizontal)
                            
                            if let errorMessage = viewModel.errorMessage {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                }
                                .padding(12)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                                .padding(.horizontal)
                            }

                            if viewModel.statusMessage != nil {
                                VStack(spacing: 8) {
                                    HStack {
                                        Image(systemName: "info.circle.fill")
                                            .foregroundColor(.blue)
                                        Text(viewModel.statusMessage ?? "")
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                    }

                                    if viewModel.chunksGenerated > 0 {
                                        HStack(spacing: 4) {
                                            Image(systemName: "square.stack.3d.down.forward.fill")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("Chunk \(viewModel.chunksGenerated)")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .padding(12)
                                .background(Color(.tertiarySystemBackground))
                                .cornerRadius(8)
                                .padding(.horizontal)
                            }
                            
                            if viewModel.hasGeneratedAudio && viewModel.audioDuration > 0 {
                                VStack(spacing: 8) {
                                    HStack {
                                        Label("Metrics", systemImage: "chart.bar.fill")
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                    }

                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Image(systemName: "music.note")
                                                .foregroundStyle(.secondary)
                                                .frame(width: 20)
                                            Text("Audio Duration:")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text(String(format: "%.2f seconds", viewModel.audioDuration))
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.primary)
                                        }

                                        HStack {
                                            Image(systemName: "bolt.badge.clock")
                                                .foregroundStyle(.secondary)
                                                .frame(width: 20)
                                            Text("Model Init Time:")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text(String(format: "%.2f seconds", viewModel.modelInitTime))
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.primary)
                                        }

                                        if let warmDuration = viewModel.lastPreWarmDuration {
                                            HStack {
                                                Image(systemName: "flame")
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 20)
                                                Text("Last Pre-Warm:")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                                Text(String(format: "%.2f seconds", warmDuration))
                                                    .font(.caption.monospacedDigit())
                                                    .foregroundStyle(.primary)
                                            }
                                        }

                                        HStack {
                                            Image(systemName: "timer")
                                                .foregroundStyle(.secondary)
                                                .frame(width: 20)
                                            Text("Synthesis Time:")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Spacer()
                                            Text(String(format: "%.2f seconds", viewModel.generationTime))
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.primary)
                                        }

                                        if viewModel.generationMode == .file {
                                            HStack {
                                                Image(systemName: "speedometer")
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 20)
                                                Text("RTF (Real-Time Factor):")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                                Text(String(format: "%.2fx", viewModel.rtf))
                                                    .font(.caption.monospacedDigit().bold())
                                                    .foregroundColor(viewModel.rtf > 10.0 ? .green : (viewModel.rtf > 1.0 ? .yellow : .orange))
                                            }
                                        } else if viewModel.generationMode == .stream {
                                            HStack {
                                                Image(systemName: "timer.circle.fill")
                                                    .foregroundStyle(.secondary)
                                                    .frame(width: 20)
                                                Text("Time to First Audio:")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                                Spacer()
                                                Text(String(format: "%.2f seconds", viewModel.timeToFirstAudio))
                                                    .font(.caption.monospacedDigit().bold())
                                                    .foregroundColor(viewModel.timeToFirstAudio < 1.0 ? .green : (viewModel.timeToFirstAudio < 2.0 ? .yellow : .orange))
                                            }
                                        }
                                    }
                                    .padding(12)
                                    .background(Color(.tertiarySystemBackground))
                                    .cornerRadius(8)
                                }
                                .padding(.horizontal)
                                .transition(.opacity.combined(with: .scale))
                            }
                        }
                        
                        Spacer(minLength: 20)
                    }
                    .padding(.vertical)
                    .padding(.bottom, keyboardHeight)
                }
                .animation(.easeOut(duration: 0.3), value: keyboardHeight)
            }
            .navigationTitle("Kokoro TTS")
            .navigationBarTitleDisplayMode(.large)
            .onTapGesture {
                isTextFieldFocused = false
            }
            .onAppear {
                NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { notification in
                    if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                        keyboardHeight = keyboardFrame.height
                    }
                }
                
                NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: .main) { _ in
                    keyboardHeight = 0
                }
            }
            .onChange(of: viewModel.isGenerating) { _, newValue in
                speakerModel.isGenerating = newValue
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
    
    // MARK: - Speaker Card

     private var speakerCard: some View {
         VStack(alignment: .leading, spacing: 16) {
             Label("Voice Selection", systemImage: "person.wave.2")
                 .font(.headline)

             Menu {
                 ForEach(speakerModel.speakers) { speaker in
                     Button(action: {
                         withAnimation(.spring(response: 0.3)) {
                             speakerModel.selectedSpeakerId = speaker.id
                             speakerModel.selectedSpeakerName = speaker.name

                         }
                     }) {
                         HStack {
                             Text("\(speaker.flag) \(speaker.displayName)")
                             if speakerModel.selectedSpeakerId == speaker.id {
                                 Image(systemName: "checkmark")
                             }
                         }
                     }
                 }
             } label: {
                 HStack {
                     if let speaker = speakerModel.getSpeaker(id: speakerModel.selectedSpeakerId) {
                         // Voice icon with flag
                         ZStack {
                             Circle()
                                 .fill(Color(.tertiarySystemBackground))
                                 .frame(width: 40, height: 40)
                             Text(speaker.flag)
                                 .font(.title2)
                         }

                         VStack(alignment: .leading, spacing: 4) {
                             Text(speaker.displayName)
                                 .font(.headline)
                                 .foregroundStyle(.primary)
                             Text("Tap to change")
                                 .font(.caption)
                                 .foregroundStyle(.secondary)
                         }
                     }

                     Spacer()

                     Image(systemName: "chevron.down.circle.fill")
                         .font(.title2)
                         .foregroundStyle(.secondary)
                 }
                 .padding()
                 .background(
                     RoundedRectangle(cornerRadius: 16)
                         .fill(Color(.secondarySystemBackground))
                 )
                 .overlay(
                     RoundedRectangle(cornerRadius: 16)
                         .stroke(Color(.separator), lineWidth: 0.5)
                 )
             }
         }
         .padding()
         .background(
             RoundedRectangle(cornerRadius: 20)
                 .fill(Color(.systemBackground))
                 .shadow(color: Color.black.opacity(0.05), radius: 10, y: 5)
         )
     }
}

// MARK: - Speaker Model

struct Speaker: Identifiable {
    let id: Int
    let name: String

    var flag: String {
        if name.lowercased() == "none" {
            return "⚪️"
        }

        guard name.count >= 2 else { return "🏳️" }
        let country = name.prefix(1)

        let countryFlag: String
        switch country {
        case "a": countryFlag = "🇺🇸" // USA
        case "b": countryFlag = "🇬🇧" // British
        case "e": countryFlag = "🇪🇸" // Spain
        case "f": countryFlag = "🇫🇷" // French
        case "h": countryFlag = "🇮🇳" // Hindi
        case "i": countryFlag = "🇮🇹" // Italian
        case "j": countryFlag = "🇯🇵" // Japanese
        case "p": countryFlag = "🇧🇷" // Brazil
        case "z": countryFlag = "🇨🇳" // Chinese
        default: countryFlag = "🏳️"
        }

        return countryFlag
    }

    var displayName: String {
        if name.lowercased() == "none" {
            return "None"
        }

        guard name.count >= 2 else { return name }
        let cleanName = name.dropFirst(3).capitalized
        return "\(cleanName)"
    }

    var isFemale: Bool {
        guard name.count >= 2 else { return false }
        return name.prefix(2).hasSuffix("f")
    }

    var genderIcon: String {
        isFemale ? "person.fill" : "person.fill"
    }

    var accentColor: Color {
        isFemale ? .pink : .blue
    }

    var languageName: String {
        guard name.count >= 1 else { return "Other" }
        let prefix = String(name.prefix(1))

        switch prefix {
        case "a": return "American"
        case "b": return "British"
        case "e": return "Spanish"
        case "f": return "French"
        case "h": return "Hindi"
        case "i": return "Italian"
        case "j": return "Japanese"
        case "p": return "Portuguese"
        case "z": return "Chinese"
        default: return "Other"
        }
    }
}

class SpeakerViewModel: ObservableObject {
    @Published var selectedSpeakerId: Int = 3 // Default to af_heart
    @Published var selectedSpeakerName: String = "af_heart" // Default to af_heart
    @Published var isGenerating: Bool = false

    let speakers: [Speaker] = [
        Speaker(id: 0, name: "af_alloy"),
        Speaker(id: 1, name: "af_aoede"),
        Speaker(id: 2, name: "af_bella"),
        Speaker(id: 3, name: "af_heart"),
        Speaker(id: 4, name: "af_jessica"),
        Speaker(id: 5, name: "af_kore"),
        Speaker(id: 6, name: "af_nicole"),
        Speaker(id: 7, name: "af_nova"),
        Speaker(id: 8, name: "af_river"),
        Speaker(id: 9, name: "af_sarah"),
        Speaker(id: 10, name: "af_sky"),
        Speaker(id: 11, name: "am_adam"),
        Speaker(id: 12, name: "am_echo"),
        Speaker(id: 13, name: "am_eric"),
        Speaker(id: 14, name: "am_fenrir"),
        Speaker(id: 15, name: "am_liam"),
        Speaker(id: 16, name: "am_michael"),
        Speaker(id: 17, name: "am_onyx"),
        Speaker(id: 18, name: "am_puck"),
        Speaker(id: 19, name: "am_santa"),
        Speaker(id: 20, name: "bf_alice"),
        Speaker(id: 21, name: "bf_emma"),
        Speaker(id: 22, name: "bf_isabella"),
        Speaker(id: 23, name: "bf_lily"),
        Speaker(id: 24, name: "bm_daniel"),
        Speaker(id: 25, name: "bm_fable"),
        Speaker(id: 26, name: "bm_george"),
        Speaker(id: 27, name: "bm_lewis"),
        Speaker(id: 28, name: "ef_dora"),
        Speaker(id: 29, name: "em_alex"),
        Speaker(id: 30, name: "ff_siwis"),
        Speaker(id: 31, name: "hf_alpha"),
        Speaker(id: 32, name: "hf_beta"),
        Speaker(id: 33, name: "hm_omega"),
        Speaker(id: 34, name: "hm_psi"),
        Speaker(id: 35, name: "if_sara"),
        Speaker(id: 36, name: "im_nicola"),
        Speaker(id: 37, name: "jf_alpha"),
        Speaker(id: 38, name: "jf_gongitsune"),
        Speaker(id: 39, name: "jf_nezumi"),
        Speaker(id: 40, name: "jf_tebukuro"),
        Speaker(id: 41, name: "jm_kumo"),
        Speaker(id: 42, name: "pf_dora"),
        Speaker(id: 43, name: "pm_alex"),
        Speaker(id: 44, name: "pm_santa"),
        Speaker(id: 45, name: "zf_xiaobei"),
        Speaker(id: 46, name: "zf_xiaoni"),
        Speaker(id: 47, name: "zf_xiaoxiao"),
        Speaker(id: 48, name: "zf_xiaoyi"),
        Speaker(id: 49, name: "zm_yunjian"),
        Speaker(id: 50, name: "zm_yunxi"),
        Speaker(id: 51, name: "zm_yunxia"),
        Speaker(id: 52, name: "zm_yunyang"),
    ]

   func getSpeaker() -> [Speaker] {
        speakers.filter { $0.id == selectedSpeakerId }
    }

    func getSpeaker(id: Int) -> Speaker? {
        speakers.first { $0.id == id }
    }
}
