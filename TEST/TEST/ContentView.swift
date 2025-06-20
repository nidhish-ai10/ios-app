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

// MARK: - Main Tab View
struct MainTabView: View {
    @EnvironmentObject var authManager: FirebaseAuthManager
    @AppStorage("selectedTab") private var selectedTab = 1
    
    var body: some View {
        // Authentication guard - ensure user is still authenticated
        Group {
            if authManager.isAuthenticated {
                TabView(selection: $selectedTab) {
                    RemindersView()
                        .tabItem {
                            Image(systemName: "bell.fill")
                            Text("Reminders")
                        }
                        .tag(0)
                    
                    ContentView()
                        .tabItem {
                            Image(systemName: "house.fill")
                            Text("Home")
                        }
                        .tag(1)
                    
                    ReportsView()
                        .tabItem {
                            Image(systemName: "chart.bar.fill")
                            Text("Reports")
                        }
                        .tag(2)
                }
                .accentColor(.blue)
            } else {
                // If authentication is lost, show a loading or redirect message
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    
                    Text("Checking authentication...")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemBackground))
            }
        }
        .onAppear {
            // Verify authentication when the main view appears
            _ = authManager.verifyAuthenticationStatus()
        }
    }
}

// MARK: - Home Screen (Main Content View)
struct ContentView: View {
    @EnvironmentObject var authManager: FirebaseAuthManager
    @StateObject private var speechRecognizer = SpeechRecognizer()
    @State private var isListening: Bool = false
    @State private var showingPermissionAlert = false
    @State private var permissionStatus: String = "Checking permissions..."
    @State private var showingAccountView = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Spacer for top padding
                Spacer()
                    .frame(height: 20)
                
                // Conversation Display
                VStack(spacing: 12) {
                    HStack {
                        Text("🎧 Your Companion is Listening...")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    
                    ChatScrollView(
                        speechRecognizer: speechRecognizer,
                        permissionStatus: permissionStatus
                    )
                    .frame(maxHeight: 300)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(conversationBorderColor, lineWidth: 1.5)
                            )
                    )
                    .padding(.horizontal, 20)
                }
                
                Spacer()
                
                // Microphone Section
                VStack(spacing: 16) {
                    // Microphone Button
                    Button(action: {
                        // Trigger recording when microphone is tapped
                        if !speechRecognizer.isRecording && speechRecognizer.isAuthorized {
                            print("🎤 UI: Microphone button tapped - starting recording")
                            speechRecognizer.forceRestartRecording()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(microphoneBackgroundColor)
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Circle()
                                        .stroke(microphoneColor, lineWidth: 2)
                                        .frame(width: 80, height: 80)
                                )
                            
                            Image(systemName: microphoneIcon)
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(microphoneColor)
                        }
                    }
                    .scaleEffect(isAnimating ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: isAnimating)
                    .disabled(false)
                    
                    // Status Text
                    Text(microphoneStatusText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    // Control Buttons
                    HStack(spacing: 12) {
                        if !speechRecognizer.conversationHistory.isEmpty && !speechRecognizer.isProcessing {
                            Button("Clear") {
                                speechRecognizer.clearTranscript()
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(8)
                        }
                        
                        // Debug: Force restart recording button
                        if !speechRecognizer.isRecording {
                            Button("Start Listening") {
                                speechRecognizer.forceRestartRecording()
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.blue.opacity(0.1))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                        }
                    }
                }
                .padding(.bottom, 100) // Space for tab bar
            }
            .navigationBarHidden(false)
            .navigationBarBackButtonHidden(true)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAccountView = true
                    }) {
                        Image(systemName: "person.circle")
                            .font(.title2)
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            speechRecognizer.requestPermissions()
            updatePermissionStatus()
        }
        .onChange(of: speechRecognizer.isAuthorized) { _, authorized in
            updatePermissionStatus()
            if authorized {
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
        .sheet(isPresented: $showingAccountView) {
            AccountView()
        }
    }
    
    // MARK: - Computed Properties for UI State
    
    private var statusText: String {
        if speechRecognizer.isSpeaking {
            return "AI is speaking"
        } else if speechRecognizer.isProcessing {
            return "Processing"
        } else if speechRecognizer.isRecording {
            return speechRecognizer.isDetectingSilence ? "Waiting" : "Listening"
        } else if speechRecognizer.isAuthorized {
            return "Ready"
        } else {
            return "Microphone access needed"
        }
    }
    
    private var statusIcon: String {
        if speechRecognizer.isSpeaking || speechRecognizer.isRecording {
            return speechRecognizer.isSpeaking ? "speaker.wave.2.fill" : "mic.fill"
        } else if speechRecognizer.isProcessing {
            return "brain.head.profile"
        } else if speechRecognizer.isAuthorized {
            return "checkmark.circle.fill"
        } else {
            return "exclamationmark.triangle.fill"
        }
    }
    
    private var statusColor: Color {
        if speechRecognizer.isSpeaking || speechRecognizer.isRecording {
            return .green
        } else if speechRecognizer.isProcessing {
            return .blue
        } else if speechRecognizer.isAuthorized {
            return .blue
        } else {
            return .red
        }
    }
    
    private var microphoneColor: Color {
        if speechRecognizer.isSpeaking || speechRecognizer.isRecording {
            return .green
        } else {
            return .red
        }
    }
    
    private var microphoneBackgroundColor: Color {
        microphoneColor.opacity(0.15)
    }
    
    private var microphoneIcon: String {
        if speechRecognizer.isSpeaking {
            return "speaker.wave.2.fill"
        } else if speechRecognizer.isProcessing {
            return "brain.head.profile"
        } else if speechRecognizer.isRecording {
            return "mic.fill"
        } else {
            return "mic"
        }
    }
    
    private var microphoneStatusText: String {
        if speechRecognizer.isSpeaking {
            return "AI is speaking"
        } else if speechRecognizer.isProcessing {
            return "Processing your request"
        } else if speechRecognizer.isRecording {
            return speechRecognizer.isDetectingSilence ? "Listening..." : "Recording"
        } else if speechRecognizer.isAuthorized {
            return "Tap to interact"
        } else {
            return "Permissions needed"
        }
    }
    
    private var conversationBorderColor: Color {
        if speechRecognizer.isSpeaking || speechRecognizer.isRecording {
            return .green
        } else if speechRecognizer.isProcessing {
            return .blue
        } else {
            return Color(.systemGray4)
        }
    }
    
    private var isAnimating: Bool {
        speechRecognizer.isRecording || speechRecognizer.isProcessing || speechRecognizer.isSpeaking
    }
    
    private func updatePermissionStatus() {
        if speechRecognizer.isAuthorized {
            permissionStatus = "Ready to start conversation. Speak naturally and I'll respond!"
        } else {
            permissionStatus = "Please allow microphone and speech recognition access to use this voice assistant."
        }
    }
}

// MARK: - Reminders View
struct RemindersView: View {
    @EnvironmentObject var authManager: FirebaseAuthManager
    @AppStorage("reminders") private var remindersData: Data = Data()
    @State private var reminders: [ReminderItem] = []
    @State private var showingAddReminder = false
    
    var body: some View {
        NavigationView {
            List {
                ForEach(reminders) { reminder in
                    ReminderRow(reminder: reminder)
                }
                .onDelete(perform: deleteReminders)
            }
            .navigationTitle("Reminders")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddReminder = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            loadReminders()
        }
        .sheet(isPresented: $showingAddReminder) {
            AddReminderView { reminder in
                reminders.append(reminder)
                saveReminders()
            }
        }
    }
    
    private func deleteReminders(offsets: IndexSet) {
        reminders.remove(atOffsets: offsets)
        saveReminders()
    }
    
    private func loadReminders() {
        if let decoded = try? JSONDecoder().decode([ReminderItem].self, from: remindersData) {
            reminders = decoded
        }
    }
    
    private func saveReminders() {
        if let encoded = try? JSONEncoder().encode(reminders) {
            remindersData = encoded
        }
    }
}

// MARK: - Reports View
struct ReportsView: View {
    @EnvironmentObject var authManager: FirebaseAuthManager
    
    var body: some View {
        NavigationView {
            List {
                // Empty list for now - future reports will go here
            }
            .navigationTitle("Reports")
            .navigationBarTitleDisplayMode(.large)
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// MARK: - Supporting Views and Models
struct ReminderItem: Identifiable, Codable {
    let id = UUID()
    let title: String
    let time: String
    let isDaily: Bool
    let medication: Bool
}

struct ReminderRow: View {
    let reminder: ReminderItem
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: reminder.medication ? "pills.circle.fill" : "bell.circle.fill")
                .foregroundColor(reminder.medication ? .green : .blue)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(reminder.title)
                    .font(.body)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Text(reminder.time)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    if reminder.isDaily {
                        Text("Daily")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

struct AddReminderView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var time = Date()
    @State private var isDaily = true
    @State private var medication = false
    
    let onSave: (ReminderItem) -> Void
    
    var body: some View {
        NavigationView {
            Form {
                Section("Reminder Details") {
                    TextField("Title", text: $title)
                    
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                }
                
                Section("Options") {
                    Toggle("Daily Reminder", isOn: $isDaily)
                    Toggle("Medication Reminder", isOn: $medication)
                }
            }
            .navigationTitle("New Reminder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let formatter = DateFormatter()
                        formatter.timeStyle = .short
                        
                        let reminder = ReminderItem(
                            title: title,
                            time: formatter.string(from: time),
                            isDaily: isDaily,
                            medication: medication
                        )
                        
                        onSave(reminder)
                        dismiss()
                    }
                    .disabled(title.isEmpty)
                }
            }
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
    
    // Voice settings
    @AppStorage("voiceSpeed") private var voiceSpeed: Double = 1.0
    
    // NEW: Additional protection against recording AI voice
    private var shouldPreventRecording = false
    private var ttsCompletionTimer: Timer?
    
    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        
        // Initialize LLM Manager with API key and TTS Service
        // TODO: Replace with your actual OpenAI API key
        let apiKey = "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"
        llmManager = LLMManager(apiKey: apiKey)
        ttsService = TTSService()
        
        // Set up TTS completion callbacks
        ttsService?.onSpeechCompleted = { [weak self] in
            Task { @MainActor in
                print("🎉 TTS CALLBACK: Speech completed - resetting flags")
                self?.isSpeaking = false
                self?.shouldPreventRecording = false
                self?.isProcessing = false
            }
        }
        
        ttsService?.onSpeechFailed = { [weak self] error in
            Task { @MainActor in
                print("❌ TTS CALLBACK: Speech failed - \(error)")
                self?.isSpeaking = false
                self?.shouldPreventRecording = false
                await self?.restartRecording()
            }
        }
        
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
        print("🎤 START RECORDING: Checking conditions...")
        print("🔧 Processing: \(isProcessing), Speaking: \(isSpeaking), PreventRecording: \(shouldPreventRecording)")
        print("🔧 Authorized: \(isAuthorized), Recognizer Available: \(recognizer?.isAvailable ?? false)")
        
        guard !isProcessing else { 
            print("❌ Cannot start recording - currently processing")
            return 
        }
        
        // NEW: Prevent recording during TTS to avoid feedback loops
        guard !isSpeaking && !shouldPreventRecording else {
            print("❌ Cannot start recording - AI is speaking or TTS protection is active (speaking: \(isSpeaking), preventRecording: \(shouldPreventRecording))")
            return
        }
        
        guard isAuthorized else {
            print("❌ Cannot start recording - not authorized")
            return
        }
        
        guard recognizer?.isAvailable == true else {
            print("❌ Cannot start recording - speech recognizer not available")
            return
        }
        
        print("✅ Starting recording session - all conditions met")
        Task {
            await record()
        }
    }
    
    func stopRecording() {
        print("🛑 Stopping recording session")
        
        // Stop the audio engine
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        
        // End the speech recognition request
        request?.endAudio()
        
        // Cancel the current recognition task
        task?.cancel()
        task = nil
        
        // Clean up audio engine and request
        audioEngine = nil
        request = nil
        
        // Update state
        isRecording = false
        isDetectingSilence = false
        stopSilenceTimer()
        
        print("✅ Recording session stopped and cleaned up")
    }
    
    func clearTranscript() {
        transcript = ""
        lastTranscriptLength = 0
        conversationHistory.removeAll()
    }
    
    // NEW: Cleanup method to handle timers properly
    deinit {
        ttsCompletionTimer?.invalidate()
        ttsCompletionTimer = nil
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
    
    // Test TTS functionality
    func testTTS() async {
        guard let ttsService = ttsService else {
            print("❌ TTS Service not available for testing")
            return
        }
        
        print("🧪 TESTING TTS: Starting test...")
        print("🔧 Test using voice speed: \(voiceSpeed)")
        
        // Stop any current recording
        stopRecording()
        
        await MainActor.run {
            isSpeaking = true
            shouldPreventRecording = true // NEW: Prevent recording during TTS test
            
            // Cancel any existing TTS completion timer
            ttsCompletionTimer?.invalidate()
            ttsCompletionTimer = nil
        }
        
        do {
            // Configure audio session for speech output
            try await configureAudioSessionForSpeech()
            
            // Create TTS configuration with user's voice speed
            let ttsConfiguration = TTSService.TTSConfiguration(
                voice: getBestVoice(),
                rate: Float(voiceSpeed * 0.5),
                pitchMultiplier: 1.0,
                volume: 1.0
            )
            
            try await ttsService.speakText("Hello! This is a test of the text to speech system. If you can hear this clearly, TTS is working correctly with your preferred voice speed.", configuration: ttsConfiguration)
            print("✅ TTS Test completed successfully")
        } catch {
            print("❌ TTS Test failed: \(error)")
        }
        
        await MainActor.run {
            isSpeaking = false
            
            // NEW: Use a timer to delay re-enabling recording after TTS test
            print("🔄 TTS test completed, starting protection timer")
            ttsCompletionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.shouldPreventRecording = false
                    print("🔄 TTS test protection timer completed, recording is now allowed")
                    if self?.isAuthorized == true && self?.isSpeaking == false {
                        print("🎤 Automatically restarting recording after TTS test")
                        self?.startRecording()
                    } else {
                        print("⏸️ Not restarting recording - conditions not met (authorized: \(self?.isAuthorized ?? false), speaking: \(self?.isSpeaking ?? false))")
                    }
                }
            }
        }
    }
    
    // MARK: - LLM Processing
    
    private func processTranscriptWithLLM() async {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("No transcript to process")
            await restartRecording()
            return
        }
        
        let userMessage = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        print("🚀 FAST PROCESSING: Starting LLM processing for: '\(userMessage)'")
        
        // Add user message to conversation history immediately
        let userChatMessage = ConversationMessage(
            content: userMessage,
            isFromUser: true,
            timestamp: Date()
        )
        await MainActor.run {
            conversationHistory.append(userChatMessage)
            isProcessing = true
            print("✅ Added user message to conversation: \(userMessage)")
        }
        
        // Start processing in parallel - don't block the UI
        Task {
            do {
                guard let llmManager = llmManager else {
                    print("❌ LLM Manager not initialized")
                    await restartRecording()
                    return
                }
                
                print("🤖 Processing with LLM...")
                
                // Process the transcript with AI
                let response = try await llmManager.processTranscription(
                    userMessage,
                    systemPrompt: "You are a helpful AI assistant engaged in a voice conversation. Respond naturally and conversationally to the user's input. Keep responses concise but friendly."
                )
                
                print("✅ LLM Response received: \(response)")
                
                // Add AI response to conversation history
                let aiChatMessage = ConversationMessage(
                    content: response,
                    isFromUser: false,
                    timestamp: Date()
                )
                
                await MainActor.run {
                    conversationHistory.append(aiChatMessage)
                    print("✅ Added AI response to conversation")
                }
                
                // Start TTS first, then restart recording after it completes
                print("🎯 Starting TTS response: '\(response)'")
                await speakResponseSimultaneous(response)
                print("🎯 TTS completed, now restarting recording")
                
                // No need for additional restart here - speakResponseSimultaneous handles it
                
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
            print("❌ TTS Service not initialized")
            await restartRecording()
            return
        }
        
        print("🔊 STARTING TTS: About to speak response: '\(text)'")
        print("🔧 Using voice speed: \(voiceSpeed)")
        
        await MainActor.run {
            isSpeaking = true
            shouldPreventRecording = true // NEW: Prevent recording during TTS
            
            // Cancel any existing TTS completion timer
            ttsCompletionTimer?.invalidate()
            ttsCompletionTimer = nil
        }
        
        do {
            print("🔊 Converting AI response to speech...")
            print("📝 TTS Text Length: \(text.count) characters")
            
            // Make sure we stop any recording before speaking
            stopRecording()
            
            // Configure audio session for speech output
            try await configureAudioSessionForSpeech()
            
            // Add a small delay to ensure audio session switch
            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            
            // Create TTS configuration with user's voice speed
            let ttsConfiguration = TTSService.TTSConfiguration(
                voice: getBestVoice(),
                rate: Float(voiceSpeed * 0.5), // Convert to TTS rate (0.5-1.0 range)
                pitchMultiplier: 1.0,
                volume: 1.0
            )
            
            try await ttsService.speakText(text, configuration: ttsConfiguration)
            print("✅ Speech playback completed successfully")
        } catch {
            print("❌ TTS Error: \(error)")
            if let localizedError = error as? LocalizedError {
                print("❌ TTS Error Description: \(localizedError.errorDescription ?? "Unknown error")")
            }
        }
        
        await MainActor.run {
            isSpeaking = false
            shouldPreventRecording = false
            
            // Immediate restart for better responsiveness
            print("🔄 TTS completed, immediately attempting restart")
            Task {
                // Brief delay to ensure audio session switch
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                await restartRecording()
            }
        }
    }
    
    private func speakResponseSimultaneous(_ text: String) async {
        guard let ttsService = ttsService else {
            print("❌ TTS Service not initialized")
            return
        }
        
        print("🔊 STARTING SIMULTANEOUS TTS: About to speak response: '\(text)'")
        print("🔧 Using voice speed: \(voiceSpeed)")
        
        await MainActor.run {
            isSpeaking = true
            shouldPreventRecording = true // NEW: Prevent recording during TTS
            
            // Cancel any existing TTS completion timer
            ttsCompletionTimer?.invalidate()
            ttsCompletionTimer = nil
        }
        
        do {
            print("🔊 Converting AI response to speech (simultaneous mode)...")
            print("📝 TTS Text Length: \(text.count) characters")
            
            // Configure audio session for speech output
            try await configureAudioSessionForSpeech()
            
            // Create TTS configuration with user's voice speed
            let ttsConfiguration = TTSService.TTSConfiguration(
                voice: getBestVoice(),
                rate: Float(voiceSpeed * 0.5), // Convert to TTS rate (0.5-1.0 range)
                pitchMultiplier: 1.0,
                volume: 1.0
            )
            
            try await ttsService.speakText(text, configuration: ttsConfiguration)
            print("✅ Speech playback completed successfully (simultaneous mode)")
        } catch {
            print("❌ TTS Error: \(error)")
            if let localizedError = error as? LocalizedError {
                print("❌ TTS Error Description: \(localizedError.errorDescription ?? "Unknown error")")
            }
        }
        
        // BACKUP: Ensure restart happens even if callback fails
        print("🔄 TTS: Backup restart mechanism triggered")
        
        await MainActor.run {
            isSpeaking = false
            shouldPreventRecording = false
            print("🔄 TTS completed (simultaneous mode), flags reset")
        }
        
        // Brief delay to ensure audio session switch, then restart
        try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
        
        print("🔄 TTS: Starting automatic restart after completion")
        
        // Force reset all blocking flags before restart
        await MainActor.run {
            isProcessing = false
            isSpeaking = false
            shouldPreventRecording = false
            print("🔧 TTS: All flags forcibly reset before restart")
        }
        
        await restartRecording()
        print("✅ TTS: Automatic restart completed")
    }
    
    private func configureAudioSessionForSpeech() async throws {
        // Simplified - no complex session switching to avoid deadlocks
        print("✅ Audio session ready for speech (using shared session)")
    }
    
    private func configureAudioSessionForRecording() async throws {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            
            // Simple configuration without deactivation to avoid deadlocks
            try audioSession.setCategory(.playAndRecord, 
                                       mode: .measurement, 
                                       options: [.defaultToSpeaker, .allowBluetooth])
            
            try audioSession.setActive(true)
            
            print("✅ Audio session configured for recording")
        } catch {
            print("❌ Failed to configure audio session for recording: \(error)")
            throw error
        }
    }
    
    private func getBestVoice() -> AVSpeechSynthesisVoice? {
        // Try to get a high-quality English voice
        let voices = AVSpeechSynthesisVoice.speechVoices()
        
        // Prefer enhanced quality voices
        if let enhancedVoice = voices.first(where: { $0.language.hasPrefix("en") && $0.quality == .enhanced }) {
            print("🎤 Using enhanced quality voice: \(enhancedVoice.name)")
            return enhancedVoice
        }
        
        // Fallback to default quality English voice
        if let defaultVoice = voices.first(where: { $0.language.hasPrefix("en") && $0.quality == .default }) {
            print("🎤 Using default quality voice: \(defaultVoice.name)")
            return defaultVoice
        }
        
        // Last resort - system default
        print("🎤 Using system default voice")
        return nil
    }
    
    private func restartRecording() async {
        await MainActor.run {
            print("🔄 RESTART: Restarting recording after processing")
            isProcessing = false
            isDetectingSilence = false
            
            // Clear current transcript for next input
            transcript = ""
            lastTranscriptLength = 0
        }
        
        // Short delay for audio session switch
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        await MainActor.run {
            print("🔧 RESTART: Final state check - authorized: \(isAuthorized), speaking: \(isSpeaking), preventRecording: \(shouldPreventRecording)")
            
            // Force start recording regardless of flags (since TTS should be done)
            if isAuthorized {
                print("✅ RESTART: Force starting recording session")
                
                // Reset all blocking flags
                isProcessing = false
                isSpeaking = false
                shouldPreventRecording = false
                
                // Start recording immediately
                startRecording()
            } else {
                print("❌ RESTART: Cannot start - not authorized")
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
        let currentTranscript = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Process faster for short responses or if we have substantial content
        let adaptiveThreshold = currentTranscript.count > 20 ? max(silenceThreshold * 0.7, 1.0) : silenceThreshold
        
        if timeSinceLastSpeech >= adaptiveThreshold {
            // Only process if we have actual content and haven't already started processing
            if !currentTranscript.isEmpty && isRecording {
                print("🚀 FAST: Silence threshold reached (adaptive: \(adaptiveThreshold)s) - processing transcript")
                isDetectingSilence = true
                stopRecording()
                Task {
                    await processTranscriptWithLLM()
                }
            }
        } else if timeSinceLastSpeech >= (adaptiveThreshold * 0.5) {
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
            print("🎤 FAST: Starting new recording session")
            
            // Ensure we're properly cleaned up first
            stopRecording()
            
            // Much shorter delay for faster startup
            try await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
            
            // Reset states before starting new recording
            isDetectingSilence = false
            lastSpeechTime = Date()
            
            // Configure audio session for recording
            try await configureAudioSessionForRecording()
            
            let (audioEngine, request) = try Self.prepareEngine()
            self.audioEngine = audioEngine
            self.request = request
            
            self.task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
                Task { @MainActor in
                    if let result = result {
                        self?.transcript = result.bestTranscription.formattedString
                        self?.updateSpeechActivity()
                    }
                    if let error = error {
                        print("❌ Recognition error: \(error)")
                        self?.stopRecording()
                    } else if result?.isFinal == true {
                        print("✅ Recognition completed successfully")
                        self?.stopRecording()
                    }
                }
            }
            
            // Faster engine startup
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
            print("✅ FAST: Recording started successfully")
            
            // Start silence detection immediately
            startSilenceTimer()
            
        } catch {
            print("❌ Recording error: \(error)")
            stopRecording()
        }
    }
    
    private static func prepareEngine() throws -> (AVAudioEngine, SFSpeechAudioBufferRecognitionRequest) {
        let audioEngine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        
        // Don't configure audio session here - it's handled separately in configureAudioSessionForRecording
        // This prevents conflicts between recording and TTS sessions
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        // Remove any existing tap first
        inputNode.removeTap(onBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }
        
        return (audioEngine, request)
    }
    
    // Force restart recording method for debugging
    func forceRestartRecording() {
        print("🚨 FORCE RESTART: Manually restarting recording")
        print("🔧 FORCE: Current state - authorized: \(isAuthorized), speaking: \(isSpeaking), preventRecording: \(shouldPreventRecording), processing: \(isProcessing)")
        
        // Stop any current recording first
        stopRecording()
        
        // Reset all blocking flags
        isProcessing = false
        isSpeaking = false
        shouldPreventRecording = false
        isDetectingSilence = false
        
        // Clear transcript for new input
        transcript = ""
        lastTranscriptLength = 0
        
        // Cancel any existing timers
        ttsCompletionTimer?.invalidate()
        ttsCompletionTimer = nil
        
        // Force start recording
        if isAuthorized {
            print("✅ FORCE: Starting recording session")
            startRecording()
        } else {
            print("❌ FORCE: Cannot restart - not authorized")
        }
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

// MARK: - Account View
struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: FirebaseAuthManager
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("voiceSpeed") private var voiceSpeed: Double = 1.0
    @AppStorage("autoRecord") private var autoRecord: Bool = true
    @State private var showingSignOutAlert = false
    
    var body: some View {
        NavigationView {
            List {
                // User Profile Section
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 50))
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(authManager.currentUser?.displayName ?? "User")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Text(authManager.currentUser?.email ?? "user@example.com")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 8)
                }
                
                // Voice Settings Section
                Section("Voice Settings") {
                    HStack {
                        Image(systemName: "speaker.wave.2")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        
                        Text("Voice Speed")
                        
                        Spacer()
                        
                        Text("\(Int(voiceSpeed * 100))%")
                            .foregroundColor(.secondary)
                    }
                    
                    Slider(value: $voiceSpeed, in: 0.5...2.0, step: 0.1)
                        .padding(.leading, 40)
                    
                    Toggle(isOn: $autoRecord) {
                        HStack {
                            Image(systemName: "mic.circle")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            Text("Auto Record")
                        }
                    }
                }
                
                // App Settings Section
                Section("App Settings") {
                    Toggle(isOn: $notificationsEnabled) {
                        HStack {
                            Image(systemName: "bell")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            Text("Notifications")
                        }
                    }
                    
                    NavigationLink(destination: PrivacySettingsView()) {
                        HStack {
                            Image(systemName: "lock.shield")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            Text("Privacy & Security")
                        }
                    }
                    
                    NavigationLink(destination: AboutView()) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            
                            Text("About")
                        }
                    }
                    
                    NavigationLink(destination: FirebaseTestView()) {
                        HStack {
                            Image(systemName: "flame")
                                .foregroundColor(.orange)
                                .frame(width: 24)
                            
                            Text("Firebase Test")
                        }
                    }
                }
                
                // Account Actions Section
                Section {
                    Button(action: {
                        showingSignOutAlert = true
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                                .foregroundColor(.red)
                                .frame(width: 24)
                            
                            Text("Sign Out")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) {
                authManager.signOut()
                dismiss()
            }
        } message: {
            Text("Are you sure you want to sign out?")
        }
    }
}

// MARK: - Privacy Settings View
struct PrivacySettingsView: View {
    @AppStorage("dataSharing") private var dataSharing: Bool = false
    @AppStorage("analyticsEnabled") private var analyticsEnabled: Bool = false
    
    var body: some View {
        List {
            Section("Data Privacy") {
                Toggle("Share Usage Data", isOn: $dataSharing)
                Toggle("Analytics", isOn: $analyticsEnabled)
            }
            
            Section("Data Management") {
                Button("Export My Data") {
                    // Handle data export
                }
                .foregroundColor(.blue)
                
                Button("Delete All Data") {
                    // Handle data deletion
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Privacy & Security")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - About View
struct AboutView: View {
    var body: some View {
        List {
            Section("App Information") {
                HStack {
                    Text("Version")
                    Spacer()
                    Text("1.0.0")
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text("Build")
                    Spacer()
                    Text("2024.06.19")
                        .foregroundColor(.secondary)
                }
            }
            
            Section("Support") {
                Link("Contact Support", destination: URL(string: "mailto:support@voiceassistant.com")!)
                    .foregroundColor(.blue)
                
                Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                    .foregroundColor(.blue)
                
                Link("Terms of Service", destination: URL(string: "https://example.com/terms")!)
                    .foregroundColor(.blue)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    ContentView()
}


