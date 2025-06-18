//
//  ContentView.swift
//  VoicetoVoice
//
//  Created by Bairineni Nidhish rao on 6/16/25.
//

import SwiftUI
import Speech
import AVFoundation
import AVFAudio

struct ContentView: View {
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var isListening: Bool = false
    @State private var showingPermissionAlert = false
    @State private var permissionStatus: String = "Checking permissions..."
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 40) {
                Spacer()
                
                // Streaming text box
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "waveform")
                            .foregroundColor(speechRecognizer.isProcessing ? .purple : (isListening ? .red : .blue))
                            .font(.title2)
                        Text("Live Transcription")
                            .font(.title2)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        Spacer()
                        
                        // Status indicator
                        if speechRecognizer.isProcessing {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(Color.purple)
                                    .frame(width: 8, height: 8)
                                    .opacity(0.8)
                                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: speechRecognizer.isProcessing)
                                Text("Processing...")
                                    .font(.caption)
                                    .foregroundColor(.purple)
                            }
                        } else if speechRecognizer.isRecording {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(speechRecognizer.isDetectingSilence ? Color.orange : Color.red)
                                    .frame(width: 8, height: 8)
                                    .opacity(isListening ? 1.0 : 0.3)
                                    .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isListening)
                                Text(speechRecognizer.isDetectingSilence ? "Silence..." : "Recording")
                                    .font(.caption)
                                    .foregroundColor(speechRecognizer.isDetectingSilence ? .orange : .red)
                            }
                        }
                    }
                    
                    ChatScrollView(
                        speechRecognizer: speechRecognizer,
                        permissionStatus: permissionStatus
                    )
                    .frame(height: min(geometry.size.height * 0.4, 300))
                }
                .padding(24)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(.systemGray6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(speechRecognizer.isSpeaking ? Color.green.opacity(0.5) :
                                        (speechRecognizer.isProcessing ? Color.purple.opacity(0.5) :
                                        (speechRecognizer.isRecording ? 
                                        (speechRecognizer.isDetectingSilence ? Color.orange.opacity(0.5) : Color.red.opacity(0.5)) : 
                                        Color(.systemGray4))), 
                                        lineWidth: (speechRecognizer.isRecording || speechRecognizer.isProcessing || speechRecognizer.isSpeaking) ? 2 : 1)
                        )
                )
                .padding(.horizontal, 20)
                
                Spacer()
                
                // Microphone display
                VStack(spacing: 20) {
                    // Microphone icon
                    ZStack {
                        Circle()
                            .fill(speechRecognizer.isSpeaking ? Color.green.opacity(0.1) :
                                  (speechRecognizer.isProcessing ? Color.purple.opacity(0.1) :
                                  (isListening ? 
                                  (speechRecognizer.isDetectingSilence ? Color.orange.opacity(0.1) : Color.red.opacity(0.1)) : 
                                  Color.blue.opacity(0.1))))
                            .frame(width: 80, height: 80)
                        
                        Image(systemName: speechRecognizer.isSpeaking ? "speaker.wave.3.fill" :
                                         (speechRecognizer.isProcessing ? "brain.head.profile" : 
                                         (speechRecognizer.isRecording ? "mic.fill" : "mic")))
                            .font(.system(size: 32, weight: .medium))
                            .foregroundColor(speechRecognizer.isSpeaking ? .green :
                                            (speechRecognizer.isProcessing ? .purple :
                                            (speechRecognizer.isRecording ? 
                                            (speechRecognizer.isDetectingSilence ? .orange : .red) : 
                                            .blue)))
                    }
                    .scaleEffect((isListening || speechRecognizer.isProcessing || speechRecognizer.isSpeaking) ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: speechRecognizer.isSpeaking ? 0.4 : 0.6).repeatForever(autoreverses: (speechRecognizer.isRecording || speechRecognizer.isProcessing || speechRecognizer.isSpeaking)), 
                              value: (isListening || speechRecognizer.isProcessing || speechRecognizer.isSpeaking))
                    
                    Text(speechRecognizer.isSpeaking ? "AI is speaking..." :
                         (speechRecognizer.isProcessing ? "Processing with AI..." :
                         (speechRecognizer.isRecording ? 
                         (speechRecognizer.isDetectingSilence ? "Detecting silence..." : "Listening...") : 
                         (speechRecognizer.isAuthorized ? "Starting..." : "Permission required"))))
                        .font(.headline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    // Clear button
                    if !speechRecognizer.conversationHistory.isEmpty && !speechRecognizer.isProcessing {
                        Button("Clear Conversation") {
                            speechRecognizer.clearTranscript()
                        }
                        .font(.subheadline)
                        .foregroundColor(.blue)
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .background(Color(.systemBackground))
        .onAppear {
            speechRecognizer.requestPermissions()
            updatePermissionStatus()
        }
        .onChange(of: speechRecognizer.isAuthorized) { _, authorized in
            updatePermissionStatus()
            if authorized {
                // Automatically start recording when permissions are granted
                speechRecognizer.startRecording()
            }
        }
        .onChange(of: speechRecognizer.isRecording) { _, recording in
            isListening = recording
        }
        .alert("Permissions Required", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                if let settingsUrl = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsUrl)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This app needs microphone and speech recognition permissions to function. Please enable them in Settings.")
        }
    }
    

    
    private func updatePermissionStatus() {
        if speechRecognizer.isAuthorized {
            permissionStatus = "Ready to transcribe. Starting automatically..."
        } else {
            permissionStatus = "Microphone and speech recognition permissions are required for transcription."
        }
    }
}



// MARK: - Speech Recognizer Class
@MainActor
class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var isAuthorized = false
    @Published var isDetectingSilence = false
    @Published var isProcessing = false
    @Published var conversationHistory: [ConversationMessage] = []
    
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer: SFSpeechRecognizer?
    
    // Silence detection properties
    private var lastSpeechTime = Date()
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 10.0 // 10 seconds
    private var lastTranscriptLength = 0
    
    // LLM Integration
    private var llmManager: LLMManager?
    
    // TTS Integration
    private var ttsService: TTSService?
    @Published var isSpeaking = false
    
    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        
        // Initialize LLM Manager and TTS Service with API key
        // TODO: Replace with your actual OpenAI API key
        let apiKey = "YOUR_OPENAI_API_KEY_HERE"
        llmManager = LLMManager(apiKey: apiKey)
        ttsService = TTSService(apiKey: apiKey)
        
        Task {
            do {
                guard recognizer != nil else {
                    throw RecognizerError.nilRecognizer
                }
                guard await SFSpeechRecognizer.hasAuthorizationToRecognize() else {
                    throw RecognizerError.notAuthorizedToRecognize
                }
                guard AVAudioApplication.hasRecordPermission() else {
                    throw RecognizerError.notPermittedToRecord
                }
                
                isAuthorized = true
            } catch {
                print("Speech recognition setup error: \(error)")
                isAuthorized = false
            }
        }
    }
    
    func requestPermissions() {
        guard recognizer != nil else {
            print("Speech recognizer is nil")
            isAuthorized = false
            return
        }
        
        // Request speech recognition authorization first
        Task {
            let speechAuthStatus = await SFSpeechRecognizer.requestAuthorization()
            
            if speechAuthStatus == .authorized {
                // Then request microphone permission using completion handler
                AVAudioApplication.requestRecordPermissionWithCompletionHandler { [weak self] granted in
                    self?.isAuthorized = granted
                    if !granted {
                        print("Microphone permission denied")
                    }
                }
            } else {
                print("Speech recognition permission denied")
                isAuthorized = false
            }
        }
    }
    
    func startRecording() {
        guard !isProcessing else { 
            print("Cannot start recording - currently processing")
            return 
        }
        print("Starting recording session")
        Task {
            await record()
        }
    }
    
    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        isRecording = false
        isDetectingSilence = false
        stopSilenceTimer()
    }
    
    func clearTranscript() {
        transcript = ""
        lastTranscriptLength = 0
        conversationHistory.removeAll()
    }
    
    // MARK: - LLM Processing
    
    private func processTranscriptWithLLM() async {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("No transcript to process")
            await restartRecording()
            return
        }
        
        isProcessing = true
        let userMessage = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Add user message to conversation history
        let userChatMessage = ConversationMessage(
            content: userMessage,
            isFromUser: true,
            timestamp: Date()
        )
        await MainActor.run {
            conversationHistory.append(userChatMessage)
            print("Added user message to conversation: \(userMessage)")
        }
        
        Task {
            do {
                guard let llmManager = llmManager else {
                    print("LLM Manager not initialized")
                    await restartRecording()
                    return
                }
                
                print("Processing transcript with LLM: \(userMessage)")
                
                // Process the transcript with AI
                let response = try await llmManager.processTranscription(
                    userMessage,
                    systemPrompt: "You are a helpful AI assistant engaged in a voice conversation. Respond naturally and conversationally to the user's input. Keep responses concise but friendly."
                )
                
                print("LLM Response: \(response)")
                
                // Add AI response to conversation history
                let aiChatMessage = ConversationMessage(
                    content: response,
                    isFromUser: false,
                    timestamp: Date()
                )
                await MainActor.run {
                    conversationHistory.append(aiChatMessage)
                    print("Added AI response to conversation: \(response)")
                }
                
                // Convert AI response to speech
                await speakResponse(response)
                
            } catch {
                print("LLM Processing error: \(error)")
                
                // Add error message to conversation
                let errorMessage = ConversationMessage(
                    content: "Sorry, I encountered an error processing your request. Please try again.",
                    isFromUser: false,
                    timestamp: Date()
                )
                await MainActor.run {
                    conversationHistory.append(errorMessage)
                    print("Added error message to conversation")
                }
                
                await restartRecording()
            }
        }
    }
    
    // MARK: - TTS Processing
    
    private func speakResponse(_ text: String) async {
        guard let ttsService = ttsService else {
            print("TTS Service not initialized")
            await restartRecording()
            return
        }
        
        await MainActor.run {
            isSpeaking = true
        }
        
        do {
            print("🔊 Converting AI response to speech...")
            try await ttsService.speakText(text)
            print("✅ Speech playback completed")
        } catch {
            print("❌ TTS Error: \(error)")
        }
        
        await MainActor.run {
            isSpeaking = false
        }
        
        // Restart recording after speech is complete
        await restartRecording()
    }
    
    private func restartRecording() async {
        await MainActor.run {
            print("Restarting recording after processing")
            isProcessing = false
            isDetectingSilence = false
            
            // Clear current transcript for next input
            transcript = ""
            lastTranscriptLength = 0
            
            // Automatically restart recording after processing (but not if currently speaking)
            if isAuthorized && !isSpeaking {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    print("Starting new recording session")
                    self.startRecording()
                }
            }
        }
    }
    
    // MARK: - Silence Detection Methods
    
    private func startSilenceTimer() {
        stopSilenceTimer()
        lastSpeechTime = Date()
        
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForSilence()
        }
    }
    
    private func stopSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
    
    private func checkForSilence() {
        guard isRecording && !isProcessing else { return }
        
        let timeSinceLastSpeech = Date().timeIntervalSince(lastSpeechTime)
        
        if timeSinceLastSpeech >= silenceThreshold {
            // Only process if we have actual content and haven't already started processing
            if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isRecording {
                print("Silence threshold reached - processing transcript with LLM")
                isDetectingSilence = true
                stopRecording()
                Task {
                    await processTranscriptWithLLM()
                }
            }
        } else if timeSinceLastSpeech >= (silenceThreshold * 0.5) {
            // Show silence warning after half the threshold time
            isDetectingSilence = true
        } else {
            isDetectingSilence = false
        }
    }
    
    private func updateSpeechActivity() {
        if transcript.count > lastTranscriptLength {
            print("Speech activity detected - transcript length: \(transcript.count)")
            lastSpeechTime = Date()
            lastTranscriptLength = transcript.count
            isDetectingSilence = false
        }
    }
    
    // MARK: - Recording Logic
    
    private func record() async {
        do {
            // Reset states before starting new recording
            isDetectingSilence = false
            lastSpeechTime = Date()
            
            let (audioEngine, request) = try Self.prepareEngine()
            self.audioEngine = audioEngine
            self.request = request
            
            self.task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result = result {
                        self?.transcript = result.bestTranscription.formattedString
                        self?.updateSpeechActivity()
                    }
                    if error != nil || result?.isFinal == true {
                        print("Recognition completed or error occurred")
                        self?.stopRecording()
                    }
                }
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            print("Recording started successfully")
            
            // Start silence detection
            startSilenceTimer()
            
        } catch {
            print("Recording error: \(error)")
            stopRecording()
        }
    }
    
    private static func prepareEngine() throws -> (AVAudioEngine, SFSpeechAudioBufferRecognitionRequest) {
        let audioEngine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        
        return (audioEngine, request)
    }
}

// MARK: - Extensions for Permissions
extension SFSpeechRecognizer {
    static func hasAuthorizationToRecognize() async -> Bool {
        await withCheckedContinuation { continuation in
            requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
    static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}

extension AVAudioApplication {
    static func hasRecordPermission() -> Bool {
        return AVAudioApplication.shared.recordPermission == .granted
    }
    
    static func requestRecordPermissionWithCompletionHandler(_ completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                completion(granted)
            }
        }
    }
}

// MARK: - Error Handling
enum RecognizerError: Error {
    case nilRecognizer
    case notAuthorizedToRecognize
    case notPermittedToRecord
    case recognizerIsUnavailable
    
    var message: String {
        switch self {
        case .nilRecognizer: return "Can't initialize speech recognizer"
        case .notAuthorizedToRecognize: return "Not authorized to recognize speech"
        case .notPermittedToRecord: return "Not permitted to record audio"
        case .recognizerIsUnavailable: return "Recognizer is unavailable"
        }
    }
}

#Preview {
    ContentView()
}


