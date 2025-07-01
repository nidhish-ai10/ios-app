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

// MARK: - OpenAI TTS Service
class OpenAITTSService {
    static func generateVoice(from text: String, voice: String = "nova", completion: @escaping @Sendable (URL?) -> Void) {
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] else {
            print("❌ API key not found in environment.")
            completion(nil)
            return
        }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/speech")!)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "model": "tts-1",
            "input": text,
            "voice": voice
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        URLSession.shared.dataTask(with: request) { data, _, error in
            guard let data = data, error == nil else {
                print("❌ TTS API failed:", error?.localizedDescription ?? "Unknown")
                completion(nil)
                return
            }

            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("openai_voice.mp3")

            do {
                try data.write(to: tempURL)
                completion(tempURL)
            } catch {
                print("❌ Error saving audio:", error.localizedDescription)
                completion(nil)
            }
        }.resume()
    }
}

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
            authManager.checkAuthenticationStatus()
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
    @State private var isAnimating: Bool = false
    
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
                        // If recording is not active (red mic), allow manual restart
                        if !speechRecognizer.isRecording && !speechRecognizer.isProcessing && !speechRecognizer.isSpeaking && !speechRecognizer.isCanceled {
                            print("🎤 Manual recording restart triggered by user tap")
                            Task {
                                do {
                                    try await speechRecognizer.configureAudioSessionForRecording()
                                    speechRecognizer.startRecording()
                                } catch {
                                    print("❌ Manual recording restart failed: \(error)")
                                }
                            }
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
                    .disabled(speechRecognizer.isProcessing || speechRecognizer.isCanceled) // Disable when processing or canceled
                    
                    // Status Text
                    Text(microphoneStatusText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    // Control Buttons
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
        .onChange(of: speechRecognizer.isProcessing) { _, processing in
            isAnimating = processing
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
        if speechRecognizer.isCanceled {
            return .orange
        } else if speechRecognizer.isSpeaking || speechRecognizer.isRecording {
            return .green
        } else {
            return .red
        }
    }
    
    private var microphoneBackgroundColor: Color {
        microphoneColor.opacity(0.15)
    }
    
    private var microphoneIcon: String {
        if speechRecognizer.isCanceled {
            return "mic.slash"
        } else if speechRecognizer.isSpeaking {
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
        if speechRecognizer.isCanceled {
            return speechRecognizer.cancelMessage
        } else if speechRecognizer.isSpeaking {
            return "Responding..."
        } else if speechRecognizer.isProcessing {
            return "Processing..."
        } else if speechRecognizer.isRecording {
            return "Listening..."
        } else if speechRecognizer.isAuthorized {
            return "Ready"
        } else {
            return "Permissions needed"
        }
    }
    
    private var conversationBorderColor: Color {
        if speechRecognizer.isCanceled {
            return .orange
        } else if speechRecognizer.isSpeaking || speechRecognizer.isRecording {
            return .green
        } else if speechRecognizer.isProcessing {
            return .blue
        } else {
            return Color(.systemGray4)
        }
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
    var id = UUID()
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
    @Published var isCanceled = false
    @Published var cancelMessage = ""
    private var cancellationDetectedForCurrentSession = false
    
    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let recognizer: SFSpeechRecognizer?
    
    // Silence detection properties
    private var lastSpeechTime = Date()
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 2.5 // 2.5 seconds for faster response
    private var lastTranscriptLength = 0
    
    // LLM Integration
    private var llmManager: LLMManager?
    
    // TTS Integration - Using OpenAI TTS for more natural voices
    @Published var isSpeaking = false
    
    // Voice settings
    @AppStorage("voiceSpeed") private var voiceSpeed: Double = 1.0
    @AppStorage("selectedVoice") private var selectedVoice: String = "nova"
    
    // Memory Integration
    private var memory = MemoryService.shared
    
    // NEW: Additional protection against recording AI voice
    private var shouldPreventRecording = false
    private var ttsCompletionTimer: Timer?
    
    init() {
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        llmManager = LLMManager.shared
        
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
            print("❌ Cannot start recording - currently processing")
            return 
        }
        
        // NEW: Prevent recording during TTS to avoid feedback loops
        guard !isSpeaking && !shouldPreventRecording else {
            print("❌ Cannot start recording - AI is speaking or TTS protection is active")
            return
        }
        
        guard isAuthorized else {
            print("❌ Cannot start recording - not authorized")
            return
        }
        
        // Stop any existing recording first
        if isRecording {
            print("⚠️ Stopping existing recording before starting new one")
            stopRecording()
        }
        
        print("🎤 Starting new recording session")
        Task {
            await record()
        }
    }
    
    func stopRecording() {
        print("🛑 Stopping recording - cleaning up resources")
        
        // Stop audio engine first
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        
        // End recognition request
        request?.endAudio()
        request = nil
        
        // Cancel recognition task
        task?.cancel()
        task = nil
        
        // Clear audio engine reference
        audioEngine = nil
        
        // Update state
        isRecording = false
        isDetectingSilence = false
        stopSilenceTimer()
        
        print("✅ Recording stopped and cleaned up")
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
    
    // Test TTS functionality using OpenAI TTS
    func testTTS() async {
        print("🧪 TESTING OpenAI TTS: Starting test...")
        print("🔧 Test using voice: \(selectedVoice)")
        
        // Stop any current recording
        stopRecording()
        
        isSpeaking = true
        shouldPreventRecording = true
        
        // Cancel any existing TTS completion timer
        ttsCompletionTimer?.invalidate()
        ttsCompletionTimer = nil
        
        let testText = "Hello! This is a test of the OpenAI text to speech system. If you can hear this clearly, the new voice system is working correctly."
        
        await withCheckedContinuation { continuation in
            OpenAITTSService.generateVoice(from: testText, voice: selectedVoice) { [weak self] audioURL in
                guard let audioURL = audioURL else {
                    print("❌ OpenAI TTS Test failed: Could not generate audio")
                    Task { @MainActor in
                        self?.isSpeaking = false
                        self?.shouldPreventRecording = false
                    }
                    continuation.resume()
                    return
                }
                
                guard let strongSelf = self else {
                    continuation.resume()
                    return
                }
                
                Task { @MainActor in
                    let success = await strongSelf.playAudioFile(from: audioURL)
                    
                    if success {
                        print("✅ OpenAI TTS Test completed successfully")
                    } else {
                        print("❌ OpenAI TTS Test failed during playback")
                    }
                    
                    strongSelf.isSpeaking = false
                    
                    // Use a timer to delay re-enabling recording after TTS test
                    print("🔄 TTS test completed, starting protection timer")
                    strongSelf.ttsCompletionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                        Task { @MainActor in
                            self?.shouldPreventRecording = false
                            print("🔄 TTS test protection timer completed, recording is now allowed")
                            if self?.isAuthorized == true {
                                self?.startRecording()
                            }
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - LLM Processing
    
    private func processTranscriptWithLLM() async {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("No transcript to process")
            restartRecording()
            return
        }
        
        isProcessing = true
        let userMessage = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        
        //Memory processing
        Task {
            do {
                guard let results = try await memory.analyzeSnippet(userMessage: userMessage) else{
                    return
                }
                for result in results {
                    let event = MemoryService.MemoryEvent.init(
                        id: UUID().uuidString,
                        type: result["type"] as! String,
                        content: result["content"] as! String,
                        source: result["source"] as? String ?? "conversation",
                        timestamp: result["timestamp"] as? String ?? ISO8601DateFormatter().string(from: Date()),
                        tags: result["tags"] as? [String] ?? [],
                        confidence: result["confidence"] as? Double ?? 1.0
                    )
                    try await memory.saveMemories(memories: [event])
                }
            } catch {
                print("Memory analysis failed: \(error)")
            }
        }
        // Add user message to conversation history
        let userChatMessage = ConversationMessage(
            content: userMessage,
            isFromUser: true,
            timestamp: Date()
        )
        conversationHistory.append(userChatMessage)
        print("Added user message to conversation: \(userMessage)")
        
        Task {
            do {
                guard let llmManager = llmManager else {
                    print("LLM Manager not initialized")
                    restartRecording()
                    return
                }
                
                print("Processing transcript with LLM: \(userMessage)")
                
                // Process the transcript with AI
                let response = try await llmManager.processTranscription(
                    userMessage,
                    systemPrompt: "You are a helpful AI assistant engaged in a voice conversation. Respond naturally and conversationally to the user's input. Keep responses concise but friendly."
                )
                
                print("LLM Response: \(response)")
                
                // Add AI response to conversation history and start TTS simultaneously
                let aiChatMessage = ConversationMessage(
                    content: response,
                    isFromUser: false,
                    timestamp: Date()
                )
                
                // Start both text display and voice response simultaneously
                conversationHistory.append(aiChatMessage)
                print("Added AI response to conversation: \(response)")
                
                // Start TTS simultaneously (recording restart handled by TTS completion)
                Task {
                    await speakResponseSimultaneous(response)
                }
                
                // Reset processing state immediately
                restartRecording()
                
            } catch {
                print("LLM Processing error: \(error)")
                
                // Add error message to conversation
                let errorMessage = ConversationMessage(
                    content: "Sorry, I encountered an error processing your request. Please try again.",
                    isFromUser: false,
                    timestamp: Date()
                )
                conversationHistory.append(errorMessage)
                print("Added error message to conversation")
                
                // Restart recording after error immediately (since no TTS)
                restartRecording()
                
                // Start recording immediately since there's no TTS to wait for
                if isAuthorized {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.startRecording()
                    }
                }
            }
        }
    }
    
    // MARK: - TTS Processing using OpenAI TTS
    
    private func speakResponse(_ text: String) async {
        print("🔊 STARTING OpenAI TTS: About to speak response: '\(text)'")
        print("🔧 Using voice: \(selectedVoice)")
        
        isSpeaking = true
        shouldPreventRecording = true
        
        // Cancel any existing TTS completion timer
        ttsCompletionTimer?.invalidate()
        ttsCompletionTimer = nil
        
        print("🔊 Converting AI response to speech with OpenAI...")
        print("📝 TTS Text Length: \(text.count) characters")
        
        // Make sure we stop any recording before speaking
        stopRecording()
        
        await withCheckedContinuation { continuation in
            OpenAITTSService.generateVoice(from: text, voice: selectedVoice) { [weak self] audioURL in
                guard let audioURL = audioURL else {
                    print("❌ OpenAI TTS Error: Could not generate audio")
                    Task { @MainActor in
                        self?.isSpeaking = false
                        if let strongSelf = self {
                            strongSelf.restartRecording()
                        }
                    }
                    continuation.resume()
                    return
                }
                
                guard let strongSelf = self else {
                    continuation.resume()
                    return
                }
                
                Task { @MainActor in
                    let success = await strongSelf.playAudioFile(from: audioURL)
                    
                    if success {
                        print("✅ OpenAI TTS playback completed successfully")
                    } else {
                        print("❌ OpenAI TTS playback failed")
                    }
                    
                    strongSelf.isSpeaking = false
                    
                    // Use a timer to delay re-enabling recording to ensure AI voice doesn't get picked up
                    print("🔄 TTS completed, starting protection timer before allowing recording")
                    strongSelf.ttsCompletionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                        Task { @MainActor in
                            self?.shouldPreventRecording = false
                            print("🔄 TTS protection timer completed, recording is now allowed")
                            if let strongInnerSelf = self {
                                strongInnerSelf.restartRecording()
                            }
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    private func speakResponseSimultaneous(_ text: String) async {
        print("🔊 STARTING SIMULTANEOUS OpenAI TTS: About to speak response: '\(text)'")
        print("🔧 Using voice: \(selectedVoice)")
        
        isSpeaking = true
        shouldPreventRecording = true
        
        // Cancel any existing TTS completion timer
        ttsCompletionTimer?.invalidate()
        ttsCompletionTimer = nil
        
        print("🔊 Converting AI response to speech with OpenAI (simultaneous mode)...")
        print("📝 TTS Text Length: \(text.count) characters")
        
        await withCheckedContinuation { continuation in
            OpenAITTSService.generateVoice(from: text, voice: selectedVoice) { [weak self] audioURL in
                guard let audioURL = audioURL else {
                    print("❌ OpenAI TTS Error (simultaneous mode): Could not generate audio")
                    Task { @MainActor in
                        self?.isSpeaking = false
                        self?.shouldPreventRecording = false
                    }
                    continuation.resume()
                    return
                }
                
                guard let strongSelf = self else {
                    continuation.resume()
                    return
                }
                
                Task { @MainActor in
                    let success = await strongSelf.playAudioFile(from: audioURL)
                    
                    if success {
                        print("✅ OpenAI TTS playback completed successfully (simultaneous mode)")
                    } else {
                        print("❌ OpenAI TTS playback failed (simultaneous mode)")
                    }
                    
                    strongSelf.isSpeaking = false
                    
                    // Use a timer to delay re-enabling recording to ensure AI voice doesn't get picked up
                    print("🔄 TTS completed (simultaneous mode), automatically restarting recording")
                    strongSelf.ttsCompletionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in
                        Task { @MainActor in
                            guard let strongSelf = self else { return }
                            
                            strongSelf.shouldPreventRecording = false
                            print("🔄 TTS protection cleared, automatically starting recording")
                            
                            // Automatically restart recording without showing "Ready" state
                            if strongSelf.isAuthorized && !strongSelf.isProcessing && !strongSelf.isCanceled {
                                do {
                                    try await strongSelf.configureAudioSessionForRecording()
                                    // Small delay to ensure audio session is ready
                                    try await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                                    strongSelf.startRecording()
                                    print("✅ Recording automatically restarted after AI response")
                                } catch {
                                    print("❌ Failed to auto-restart recording: \(error)")
                                    // Fallback: Allow manual restart by showing Ready state
                                }
                            } else {
                                print("⚠️ Cannot auto-restart recording - conditions not met")
                                print("  - isAuthorized: \(strongSelf.isAuthorized)")
                                print("  - isProcessing: \(strongSelf.isProcessing)")
                                print("  - isCanceled: \(strongSelf.isCanceled)")
                            }
                        }
                    }
                    continuation.resume()
                }
            }
        }
    }
    
    // MARK: - Audio Playback Helper
    
    @MainActor
    private func playAudioFile(from url: URL) async -> Bool {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.defaultToSpeaker])
            try audioSession.setActive(true)
            
            let player = try AVAudioPlayer(contentsOf: url)
            player.play()
            
            // Wait for playback to complete using proper async handling
            return await withCheckedContinuation { continuation in
                Task.detached {
                    while player.isPlaying {
                        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    }
                    continuation.resume(returning: true)
                }
            }
        } catch {
            print("❌ Failed to play audio: \(error.localizedDescription)")
            return false
        }
    }

    
    func configureAudioSessionForRecording() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let audioSession = AVAudioSession.sharedInstance()
                
                // Configure for recording input
                try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
                try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
                
                print("✅ Audio session configured for recording")
                continuation.resume()
            } catch {
                print("❌ Failed to configure audio session for recording: \(error)")
                continuation.resume(throwing: error)
            }
        }
    }
    

    
    private func restartRecording() {
        print("🔄 Restarting recording after processing")
        
        // Reset processing state immediately
        isProcessing = false
        isDetectingSilence = false
        
        // Clear current transcript for next input
        transcript = ""
        lastTranscriptLength = 0
        
        print("✅ Processing state reset, transcript cleared")
    }
    

    
    // MARK: - Silence Detection Methods
    
    private func startSilenceTimer() {
        stopSilenceTimer()
        lastSpeechTime = Date()
        
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkForSilence()
            }
        }
    }
    
    private func stopSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
    
    @MainActor
    private func checkForSilence() {
        guard isRecording && !isProcessing && !isCanceled else { return }
        
        let timeSinceLastSpeech = Date().timeIntervalSince(lastSpeechTime)
        
        if timeSinceLastSpeech >= silenceThreshold {
            // Only process if we have actual content and haven't already started processing
            if !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isRecording && !isCanceled {
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
            
            // Check for cancellation intent in real-time
            checkForCancellationIntent()
        }
    }
    
    // MARK: - Cancellation Detection
    // Sophisticated confidence-based cancellation detection to avoid false positives
    // Only triggers when confidence > 0.8, requires phrase-level context, not just keywords
    
    private func checkForCancellationIntent() {
        // Skip if cancellation already detected for this session
        guard !cancellationDetectedForCurrentSession else { return }
        
        let currentTranscript = transcript.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Skip if transcript is too short or empty
        guard currentTranscript.count > 5 else { return }
        
        let confidenceScore = calculateCancellationConfidence(for: currentTranscript)
        
        // Only trigger cancellation if confidence is above threshold
        if confidenceScore > 0.8 {
            print("🚫 Cancellation intent detected with confidence \(String(format: "%.2f", confidenceScore)): '\(currentTranscript)'")
            cancellationDetectedForCurrentSession = true
            handleCancellation()
        } else if confidenceScore > 0.3 {
            print("🤔 Possible cancellation intent (confidence: \(String(format: "%.2f", confidenceScore))): '\(currentTranscript)' - continuing to listen")
        }
    }
    
    private func calculateCancellationConfidence(for text: String) -> Double {
        var confidence: Double = 0.0
        let words = text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        
        // HIGH CONFIDENCE: Clear cancellation phrases (require complete phrases, not just single words)
        let highConfidencePatterns = [
            "never mind", "nevermind", "forget it", "forget that",
            "oh never mind", "actually never mind",
            "sorry never mind", "no never mind",
            "i don't want to", "i don't want that",
            "actually forget it", "actually forget that",
            "oh sorry never mind", "wait never mind",
            "no no never mind", "uh never mind"
        ]
        
        for pattern in highConfidencePatterns {
            if text.contains(pattern) {
                confidence += 0.9
                break // Only count once per category
            }
        }
        
        // MEDIUM-HIGH CONFIDENCE: Apologetic cancellation (must include context)
        let apologeticCancellationPatterns = [
            "oh sorry", "sorry i", "my mistake",
            "oops sorry", "whoops sorry"
        ]
        
        var hasApologeticPhrase = false
        for pattern in apologeticCancellationPatterns {
            if text.contains(pattern) {
                hasApologeticPhrase = true
                break
            }
        }
        
        // Only add confidence if apology is combined with other indicators
        if hasApologeticPhrase {
            if text.contains("i don't") || text.contains("not what") || text.contains("didn't mean") {
                confidence += 0.7
            } else if words.count <= 6 { // Short apologetic phrase likely to be cancellation
                confidence += 0.5
            } else {
                confidence += 0.2 // Just politeness, probably not cancellation
            }
        }
        
        // MEDIUM CONFIDENCE: Self-correction with context
        let selfCorrectionPatterns = [
            "i didn't mean", "that's not what", "not what i meant",
            "actually i", "wait i", "hold on i"
        ]
        
        for pattern in selfCorrectionPatterns {
            if text.contains(pattern) {
                confidence += 0.6
                break
            }
        }
        
        // MEDIUM CONFIDENCE: Hesitation with negative context
        let hesitationWords = ["uh", "um", "er", "ah"]
        let negativeContext = ["no", "not", "don't", "won't", "can't"]
        
        let hesitationCount = words.filter { hesitationWords.contains($0) }.count
        let negativeCount = words.filter { negativeContext.contains($0) }.count
        
        // Only consider hesitation with negatives as potential cancellation
        if hesitationCount >= 2 && negativeCount >= 1 && words.count <= 8 {
            confidence += 0.5
        }
        
        // LOW-MEDIUM CONFIDENCE: Fragmented speech (be very careful here)
        let fillerWords = ["uh", "um", "er", "ah", "oh", "well"]
        let fillerCount = words.filter { fillerWords.contains($0) }.count
        
        // Only consider fragmented if it's very fragmented AND short
        if words.count >= 6 && words.count <= 12 {
            let fillerRatio = Double(fillerCount) / Double(words.count)
            if fillerRatio > 0.5 && negativeCount >= 1 {
                confidence += 0.4
            }
        }
        
        // LOW CONFIDENCE: Multiple negatives (be very conservative)
        if negativeCount >= 3 && words.count <= 8 {
            confidence += 0.3
        }
        
        // REDUCTION FACTORS: Reduce confidence if text seems like normal speech
        
        // If text contains question words, likely not cancellation
        let questionWords = ["what", "how", "when", "where", "why", "who", "which"]
        let hasQuestionWord = words.contains { questionWords.contains($0) }
        if hasQuestionWord {
            confidence *= 0.5
        }
        
        // If text is too long, probably not cancellation
        if words.count > 15 {
            confidence *= 0.6
        }
        
                 // If text contains positive words, less likely to be cancellation
         let positiveWords = ["yes", "okay", "sure", "good", "great", "please", "thank"]
         let hasPositiveWord = words.contains { positiveWords.contains($0) }
         if hasPositiveWord {
             confidence *= 0.4
         }
         
         // If text seems to be building toward a complete thought, reduce confidence
         let buildingWords = ["and", "but", "so", "then", "because", "since", "while", "if"]
         let hasBuildingWord = words.contains { buildingWords.contains($0) }
         if hasBuildingWord && words.count > 8 {
             confidence *= 0.6
         }
         
         // If text ends with incomplete thought indicators, might be building to something
         let lastWord = words.last ?? ""
         let incompleteEndings = ["and", "but", "so", "or", "with", "to", "for"]
         if incompleteEndings.contains(lastWord) {
             confidence *= 0.7
         }
         
         // Cap confidence at 1.0
         return min(confidence, 1.0)
    }
    
    private func handleCancellation() {
        // Stop recording immediately
        stopRecording()
        
        // Set cancellation state
        isCanceled = true
        cancelMessage = "Listening canceled"
        
        // Add a gentle cancellation message to conversation history
        let cancelChatMessage = ConversationMessage(
            content: "No worries! I'm ready to listen whenever you're ready to speak. 😊",
            isFromUser: false,
            timestamp: Date()
        )
        conversationHistory.append(cancelChatMessage)
        
        // Clear transcript
        transcript = ""
        lastTranscriptLength = 0
        
        print("✅ Input canceled, clearing transcript")
        
        // Auto-restart listening after a brief pause
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.isCanceled = false
            self.cancelMessage = ""
            self.cancellationDetectedForCurrentSession = false // Reset for next session
            
            // Restart recording if authorized
            if self.isAuthorized && !self.isProcessing && !self.isSpeaking {
                Task {
                    do {
                        try await self.configureAudioSessionForRecording()
                        self.startRecording()
                        print("🔄 Recording restarted after cancellation")
                    } catch {
                        print("❌ Failed to restart recording after cancellation: \(error)")
                    }
                }
            }
        }
    }
    
    // MARK: - Recording Logic
    
    private func record() async {
        do {
            // Reset states before starting new recording
            isDetectingSilence = false
            lastSpeechTime = Date()
            cancellationDetectedForCurrentSession = false // Reset cancellation detection for new session
            
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

// MARK: - Account View
struct AccountView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var authManager: FirebaseAuthManager
    @AppStorage("notificationsEnabled") private var notificationsEnabled: Bool = true
    @AppStorage("voiceSpeed") private var voiceSpeed: Double = 1.0
    @AppStorage("selectedVoice") private var selectedVoice: String = "nova"
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
                    // Voice Selection
                    HStack {
                        Image(systemName: "person.wave.2")
                            .foregroundColor(.blue)
                            .frame(width: 24)
                        
                        Text("AI Voice")
                        
                        Spacer()
                        
                        Picker("Voice", selection: $selectedVoice) {
                            Text("Nova").tag("nova")
                            Text("Shimmer").tag("shimmer")
                            Text("Echo").tag("echo")
                            Text("Fable").tag("fable")
                            Text("Onyx").tag("onyx")
                            Text("Alloy").tag("alloy")
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                    
                    // Legacy voice speed control (kept for compatibility)
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

