import SwiftUI
import AVFoundation

struct ContentView: View {
    @StateObject private var viewModel = TTSViewModel()
    @State private var inputText: String = "Hello! Welcome to FluidAudio TTS. This is a sample text to demonstrate the Kokoro text-to-speech synthesis capabilities."
    @FocusState private var isTextFieldFocused: Bool
    @State private var keyboardHeight: CGFloat = 0

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.1, green: 0.2, blue: 0.45),
                        Color(red: 0.05, green: 0.1, blue: 0.25)
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack {
                                Label("Text Input", systemImage: "text.quote")
                                    .font(.headline)
                                    .foregroundColor(.white.opacity(0.9))
                                
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
                                        .foregroundColor(.white.opacity(0.7))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.2))
                                        .cornerRadius(6)
                                    }
                                    .transition(.scale.combined(with: .opacity))
                                }
                            }
                            
                            TextEditor(text: $inputText)
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .scrollContentBackground(.hidden)
                                .padding(12)
                                .background(Color.black.opacity(0.7))
                                .cornerRadius(12)
                                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
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

                        Button(action: {
                            if !viewModel.isPreWarming {
                                Task {
                                    await viewModel.preWarm()
                                }
                            }
                        }) {
                            HStack(spacing: 16) {
                                ZStack {
                                    Circle()
                                        .fill(
                                            LinearGradient(
                                                gradient: Gradient(colors: [
                                                    Color(red: 0.95, green: 0.6, blue: 0.2).opacity(0.3),
                                                    Color(red: 0.9, green: 0.35, blue: 0.25).opacity(0.15)
                                                ]),
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            )
                                        )
                                        .frame(width: 44, height: 44)

                                    if viewModel.isPreWarming {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "flame.fill")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundColor(.white)
                                    }
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(viewModel.isPreWarming ? "Pre-warming..." : "Pre-warm Engine")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(.white.opacity(0.95))

                                    if let warmDuration = viewModel.lastPreWarmDuration {
                                        Text(String(format: "Last ready in %.2f seconds", warmDuration))
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.75))
                                    } else {
                                        Text("Prepare models for instant playback")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.75))
                                    }
                                }

                                Spacer()

//                                Image(systemName: "sparkles")
//                                    .font(.system(size: 18, weight: .medium))
//                                    .foregroundColor(.white.opacity(0.9))
//                                    .opacity(viewModel.isPreWarming ? 0.0 : 1.0)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 20)
                            .background(
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color(red: 1.0, green: 0.55, blue: 0.2).opacity(0.5),
                                                Color(red: 0.8, green: 0.3, blue: 0.4).opacity(0.45)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 18)
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [
                                                Color.white.opacity(0.35),
                                                Color.white.opacity(0.15)
                                            ]),
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                            .shadow(color: Color.orange.opacity(0.35), radius: 10, x: 0, y: 6)
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal)
                        .disabled(viewModel.isPreWarming || viewModel.isGenerating || viewModel.isStreaming)
                        .opacity(viewModel.isPreWarming ? 0.85 : 1.0)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.isPreWarming)

                        VStack(spacing: 16) {
                            HStack(spacing: 12) {
                                // Generate File button
                                Button(action: {
                                    Task {
                                        await viewModel.generateFile(from: inputText)
                                    }
                                }) {
                                    VStack(spacing: 8) {
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        gradient: Gradient(colors: [
                                                            Color(red: 0.3, green: 0.6, blue: 1.0).opacity(0.3),
                                                            Color(red: 0.2, green: 0.5, blue: 0.9).opacity(0.1)
                                                        ]),
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 44, height: 44)
                                            
                                            Image(systemName: "waveform.badge.plus")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                        Text("Generate")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.white.opacity(0.95))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 80)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        Color(red: 0.2, green: 0.5, blue: 0.9),
                                                        Color(red: 0.15, green: 0.4, blue: 0.85)
                                                    ]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        Color.white.opacity(0.3),
                                                        Color.white.opacity(0.1)
                                                    ]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                                    .shadow(color: Color(red: 0.2, green: 0.5, blue: 0.9).opacity(0.4), radius: 8, x: 0, y: 4)
                                }
                                .disabled(viewModel.isPreWarming || viewModel.isGenerating || viewModel.isStreaming || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .opacity((viewModel.isPreWarming || viewModel.isGenerating || viewModel.isStreaming || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.5 : 1.0)
                                .scaleEffect((viewModel.isPreWarming || viewModel.isGenerating || viewModel.isStreaming || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.95 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: viewModel.isGenerating)
                                
                                // Stream button
                                Button(action: {
                                    if viewModel.isStreaming || (viewModel.isPlaying && viewModel.generationMode == .stream) {
                                        viewModel.stopPlayback()
                                    } else {
                                        Task {
                                            await viewModel.streamAudio(from: inputText)
                                        }
                                    }
                                }) {
                                    VStack(spacing: 8) {
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        gradient: Gradient(colors: [
                                                            Color(red: 0.7, green: 0.4, blue: 1.0).opacity(0.3),
                                                            Color(red: 0.6, green: 0.3, blue: 0.9).opacity(0.1)
                                                        ]),
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 44, height: 44)
                                            
                                            if viewModel.isStreaming {
                                                ProgressView()
                                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                                    .scaleEffect(0.8)
                                            } else if viewModel.isPlaying && viewModel.generationMode == .stream {
                                                Image(systemName: "stop.fill")
                                                    .font(.system(size: 20, weight: .semibold))
                                                    .foregroundColor(.white)
                                            } else {
                                                Image(systemName: "antenna.radiowaves.left.and.right")
                                                    .font(.system(size: 20, weight: .semibold))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        Text(viewModel.isStreaming ? "Streaming" : (viewModel.isPlaying && viewModel.generationMode == .stream ? "Stop" : "Stream"))
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.white.opacity(0.95))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 80)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(
                                                LinearGradient(
                                                    gradient: Gradient(colors: (viewModel.isPlaying && viewModel.generationMode == .stream) ? [
                                                        Color(red: 0.9, green: 0.3, blue: 0.3),
                                                        Color(red: 0.8, green: 0.2, blue: 0.25)
                                                    ] : [
                                                        Color(red: 0.6, green: 0.3, blue: 0.9),
                                                        Color(red: 0.5, green: 0.25, blue: 0.85)
                                                    ]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        Color.white.opacity(0.3),
                                                        Color.white.opacity(0.1)
                                                    ]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                                    .shadow(color: (viewModel.isPlaying && viewModel.generationMode == .stream) ? Color.red.opacity(0.4) : Color(red: 0.6, green: 0.3, blue: 0.9).opacity(0.4), radius: 8, x: 0, y: 4)
                                }
                                .disabled(viewModel.isPreWarming || viewModel.isGenerating || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .opacity((viewModel.isPreWarming || viewModel.isGenerating || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.5 : 1.0)
                                .scaleEffect((viewModel.isPreWarming || viewModel.isGenerating || inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? 0.95 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: viewModel.isStreaming)
                                
                                // Play button
                                Button(action: {
                                    viewModel.playAudio()
                                }) {
                                    VStack(spacing: 8) {
                                        ZStack {
                                            Circle()
                                                .fill(
                                                    LinearGradient(
                                                        gradient: Gradient(colors: [
                                                            Color(red: 0.3, green: 0.9, blue: 0.6).opacity(0.3),
                                                            Color(red: 0.2, green: 0.8, blue: 0.5).opacity(0.1)
                                                        ]),
                                                        startPoint: .topLeading,
                                                        endPoint: .bottomTrailing
                                                    )
                                                )
                                                .frame(width: 44, height: 44)
                                            
                                            Image(systemName: viewModel.isPlaying && viewModel.generationMode == .file ? "stop.fill" : "play.fill")
                                                .font(.system(size: 20, weight: .semibold))
                                                .foregroundColor(.white)
                                        }
                                        Text(viewModel.isPlaying && viewModel.generationMode == .file ? "Stop" : "Play")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(.white.opacity(0.95))
                                    }
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 80)
                                    .background(
                                        RoundedRectangle(cornerRadius: 16)
                                            .fill(
                                                LinearGradient(
                                                    gradient: Gradient(colors: (viewModel.isPlaying && viewModel.generationMode == .file) ? [
                                                        Color(red: 0.9, green: 0.3, blue: 0.3),
                                                        Color(red: 0.8, green: 0.2, blue: 0.25)
                                                    ] : [
                                                        Color(red: 0.3, green: 0.8, blue: 0.5),
                                                        Color(red: 0.25, green: 0.75, blue: 0.45)
                                                    ]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                )
                                            )
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16)
                                            .stroke(
                                                LinearGradient(
                                                    gradient: Gradient(colors: [
                                                        Color.white.opacity(0.3),
                                                        Color.white.opacity(0.1)
                                                    ]),
                                                    startPoint: .topLeading,
                                                    endPoint: .bottomTrailing
                                                ),
                                                lineWidth: 1
                                            )
                                    )
                                    .shadow(color: (viewModel.isPlaying && viewModel.generationMode == .file) ? Color.red.opacity(0.4) : Color.green.opacity(0.4), radius: 8, x: 0, y: 4)
                                }
                                .disabled(!viewModel.hasGeneratedAudio || viewModel.isPreWarming || viewModel.isGenerating || viewModel.isStreaming || viewModel.generationMode != .file)
                                .opacity((!viewModel.hasGeneratedAudio || viewModel.isPreWarming || viewModel.isGenerating || viewModel.isStreaming || viewModel.generationMode != .file) ? 0.5 : 1.0)
                                .scaleEffect((!viewModel.hasGeneratedAudio || viewModel.isPreWarming || viewModel.isGenerating || viewModel.isStreaming || viewModel.generationMode != .file) ? 0.95 : 1.0)
                                .animation(.easeInOut(duration: 0.2), value: viewModel.isPlaying)
                            }
                            .padding(.horizontal)
                            
                            if let errorMessage = viewModel.errorMessage {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.yellow)
                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                }
                                .padding(12)
                                .background(Color.red.opacity(0.8))
                                .cornerRadius(8)
                                .padding(.horizontal)
                            }
                            
                            if viewModel.statusMessage != nil {
                                VStack(spacing: 8) {
                                    HStack {
                                        Image(systemName: "info.circle.fill")
                                            .foregroundColor(.white.opacity(0.8))
                                        Text(viewModel.statusMessage ?? "")
                                            .font(.caption)
                                            .foregroundColor(.white.opacity(0.9))
                                    }
                                    
                                    if viewModel.chunksGenerated > 0 {
                                        HStack(spacing: 4) {
                                            Image(systemName: "square.stack.3d.down.forward.fill")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.7))
                                            Text("Chunk \(viewModel.chunksGenerated)")
                                                .font(.caption.monospacedDigit())
                                                .foregroundColor(.white.opacity(0.8))
                                        }
                                    }
                                }
                                .padding(12)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(8)
                                .padding(.horizontal)
                            }
                            
                            if viewModel.hasGeneratedAudio && viewModel.audioDuration > 0 {
                                VStack(spacing: 8) {
                                    HStack {
                                        Label("Metrics", systemImage: "chart.bar.fill")
                                            .font(.headline)
                                            .foregroundColor(.white.opacity(0.9))
                                        Spacer()
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack {
                                            Image(systemName: "music.note")
                                                .foregroundColor(.white.opacity(0.7))
                                                .frame(width: 20)
                                            Text("Audio Duration:")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                            Spacer()
                                            Text(String(format: "%.2f seconds", viewModel.audioDuration))
                                                .font(.caption.monospacedDigit())
                                                .foregroundColor(.white)
                                        }
                                        
                                        HStack {
                                            Image(systemName: "bolt.badge.clock")
                                                .foregroundColor(.white.opacity(0.7))
                                                .frame(width: 20)
                                            Text("Model Init Time:")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                            Spacer()
                                            Text(String(format: "%.2f seconds", viewModel.modelInitTime))
                                                .font(.caption.monospacedDigit())
                                                .foregroundColor(.white)
                                        }

                                        if let warmDuration = viewModel.lastPreWarmDuration {
                                            HStack {
                                                Image(systemName: "flame")
                                                    .foregroundColor(.white.opacity(0.7))
                                                    .frame(width: 20)
                                                Text("Last Pre-Warm:")
                                                    .font(.caption)
                                                    .foregroundColor(.white.opacity(0.8))
                                                Spacer()
                                                Text(String(format: "%.2f seconds", warmDuration))
                                                    .font(.caption.monospacedDigit())
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        
                                        HStack {
                                            Image(systemName: "timer")
                                                .foregroundColor(.white.opacity(0.7))
                                                .frame(width: 20)
                                            Text("Synthesis Time:")
                                                .font(.caption)
                                                .foregroundColor(.white.opacity(0.8))
                                            Spacer()
                                            Text(String(format: "%.2f seconds", viewModel.generationTime))
                                                .font(.caption.monospacedDigit())
                                                .foregroundColor(.white)
                                        }
                                        
                                        if viewModel.generationMode == .file {
                                            HStack {
                                                Image(systemName: "speedometer")
                                                    .foregroundColor(.white.opacity(0.7))
                                                    .frame(width: 20)
                                                Text("RTF (Real-Time Factor):")
                                                    .font(.caption)
                                                    .foregroundColor(.white.opacity(0.8))
                                                Spacer()
                                                Text(String(format: "%.2fx", viewModel.rtf))
                                                    .font(.caption.monospacedDigit().bold())
                                                    .foregroundColor(viewModel.rtf > 10.0 ? .green : (viewModel.rtf > 1.0 ? .yellow : .orange))
                                            }
                                        } else if viewModel.generationMode == .stream {
                                            HStack {
                                                Image(systemName: "timer.circle.fill")
                                                    .foregroundColor(.white.opacity(0.7))
                                                    .frame(width: 20)
                                                Text("Time to First Audio:")
                                                    .font(.caption)
                                                    .foregroundColor(.white.opacity(0.8))
                                                Spacer()
                                                Text(String(format: "%.2f seconds", viewModel.timeToFirstAudio))
                                                    .font(.caption.monospacedDigit().bold())
                                                    .foregroundColor(viewModel.timeToFirstAudio < 1.0 ? .green : (viewModel.timeToFirstAudio < 2.0 ? .yellow : .orange))
                                            }
                                        }
                                    }
                                    .padding(12)
                                    .background(Color.black.opacity(0.3))
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
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}
