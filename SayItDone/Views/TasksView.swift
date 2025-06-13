//
//  TasksView.swift
//  SayItDone
//
//  Created by Bairineni Nidhish rao on 6/2/25.
//

import SwiftUI
import Speech
import AVFAudio
import Combine

@MainActor
struct TasksView: View {
    @StateObject private var taskManager = TaskManager()
    @StateObject private var speechService = SpeechRecognitionService()
    @StateObject private var whisperService = WhisperService()
    @StateObject private var openAIService = OpenAIService()
    
    @State private var isRecording = false
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    @State private var showingRecordingIndicator = false
    @State private var listenPulse = false
    @State private var feedbackMessage = ""
    @State private var showingFeedback = false
    @State private var showingUndoButton = false
    @State private var showingVerificationDialog = false
    
    // Voice Activity Detection
    @AppStorage("isVADEnabled") private var isVADEnabled = true
    
    // Elderly-friendly features
    @AppStorage("elderlyModeEnabled") private var elderlyModeEnabled = false
    @AppStorage("useWhisperSTT") private var useWhisperSTT = false
    
    // User preferences
    @AppStorage("isHapticsEnabled") private var isHapticsEnabled = true
    
    // Color for our app
    let pastelBlueDarker = Color(red: 150/255, green: 190/255, blue: 255/255)
    
    // Add this property at the top of the struct, near other state variables
    @State private var processingTask = false
    @State private var processingTimeout: DispatchWorkItem?
    
    // EMERGENCY FIX: Create a force updater
    @State private var forceUpdateTasks: Bool = false
    
    // OpenAI Integration Toggle
    private let enableOpenAI = true // Set to false to disable AI processing
    
    // MARK: - Computed Properties
    
    /// Returns the current speech service based on user preference
    private var currentSpeechService: SpeechRecognitionService {
        // For now, always return the main speech service since WhisperService has different interface
        // In a full implementation, you'd create a protocol that both services conform to
        return speechService
    }
    
    /// Returns the current transcription text from the active service
    private var currentTranscriptionText: String {
        if useWhisperSTT && elderlyModeEnabled {
            if whisperService.isProcessing {
                return "Processing with Whisper AI..."
            } else if !whisperService.transcribedText.isEmpty {
                return whisperService.transcribedText
            } else if whisperService.isRecording {
                return "🎤"
            } else {
                return ""
            }
        } else {
            return speechService.transcribedText.isEmpty ? 
                   "" : 
                   speechService.transcribedText
        }
    }
    
    /// Returns whether any service is currently recording
    private var isAnyServiceRecording: Bool {
        return speechService.isRecording || whisperService.isRecording
    }
    
    var body: some View {
        ZStack {
            mainContentView
            voiceStreamingOverlay
        }
        .onAppear {
            setupView()
        }
        .onChange(of: speechService.isListening) { _, newValue in
            handleListeningStateChange(newValue)
        }
        .onChange(of: speechService.transcribedText) { _, newValue in
            handleTranscriptionChange(newValue)
        }
        .onChange(of: isVADEnabled) { _, newValue in
            handleVADToggle(newValue)
        }
        .alert(isPresented: $showingPermissionAlert) {
            Alert(
                title: Text("Permission Required"),
                message: Text(permissionAlertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .overlay(undoButtonOverlay)
        .overlay(feedbackOverlay)
        .alert(isPresented: $showingVerificationDialog) {
            Alert(
                title: Text("Confirm Action"),
                message: Text("Are you sure you want to proceed with this action? This cannot be undone."),
                primaryButton: .destructive(Text("Proceed")) {
                    taskManager.executePendingOperation()
                },
                secondaryButton: .cancel {
                    taskManager.cancelPendingOperation()
                }
            )
        }
        .onChange(of: taskManager.isVerificationRequired) { _, newValue in
            if newValue {
                showingVerificationDialog = true
            }
        }
        .onDisappear {
            cleanupView()
        }
    }
    
    // MARK: - View Components
    
    private var mainContentView: some View {
        VStack(spacing: 0) {
            // Tasks section
            ScrollView {
                if taskManager.tasks.isEmpty {
                    // Empty state - completely blank
                    Spacer()
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: UIScreen.main.bounds.height - 200)
                } else {
                    // Task list - MODIFIED: Support multiple tasks
                    LazyVStack(spacing: 12) {
                        ForEach(taskManager.tasks) { task in
                            TaskRowView(task: task) { task in
                                // Delete task action
                                provideHapticFeedback(.medium)
                                taskManager.removeTask(task)
                                
                                // Show undo button
                                showUndoOption()
                            }
                            .id(task.id)
                            .background(Color.clear)
                            .cornerRadius(8)
                            .scaleEffect(1.0)
                        }
                    }
                    .id(forceUpdateTasks) // Force view to rebuild when this changes
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
            }
            
            // Add space at the bottom to make room for the floating recording indicator
            Spacer()
                .frame(height: 35)
        }
    }
    
    private var voiceStreamingOverlay: some View {
        VStack {
            Spacer()
            
            // Single Voice Streaming Box - Positioned just above microphone button
            if showingRecordingIndicator || speechService.isListening || !speechService.transcribedText.isEmpty {
                voiceStreamingBox
                    .padding(.bottom, 30) // Just above microphone button area
            }
            
            // Hide SubtitleBarView completely when main streaming box is active
            // Only show SubtitleBarView for elderly mode features when main box is not active
            if !(showingRecordingIndicator || speechService.isListening || !speechService.transcribedText.isEmpty) {
                SubtitleBarView(speechService: currentSpeechService)
                    .padding(.bottom, 90)
            }
        }
    }
    
    private var voiceStreamingBox: some View {
        // Ultra-compact streaming box for user commands
        HStack {
            // Microphone icon
            Image(systemName: "mic.fill")
                .font(.system(size: 12))
                .foregroundColor(.blue)
            
            // Command text - very compact
            if !speechService.transcribedText.isEmpty {
                Text(speechService.transcribedText)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .animation(.easeInOut(duration: 0.2), value: speechService.transcribedText)
            } else {
                Text("Listening...")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(Color(UIColor.systemBackground))
                .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                .shadow(color: Color.black.opacity(0.08), radius: 3, x: 0, y: 1)
        )
        .frame(maxWidth: 280) // Reasonable max width
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showingRecordingIndicator)
    }
    
    private var undoButtonOverlay: some View {
        VStack {
            Spacer()
            
            if showingUndoButton {
                Button(action: {
                    // Undo the last deletion
                    if taskManager.undoLastDeletion() {
                        // Show feedback
                        showFeedback(message: "Task restored")
                        
                        // Hide the undo button
                        withAnimation {
                            showingUndoButton = false
                        }
                        
                        // Provide haptic feedback
                        provideHapticFeedback(.medium)
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 14))
                        Text("Undo")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color(UIColor.systemBackground))
                            .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 2)
                    )
                }
                .padding(.bottom, 90)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }
    
    private var feedbackOverlay: some View {
        Group {
            if showingFeedback {
                VStack {
                    Spacer()
                    Text(feedbackMessage)
                        .font(.subheadline)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemBackground))
                                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                        )
                        .padding(.bottom, 100)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: showingFeedback)
                }
            }
        }
    }
    
    // MARK: - View Lifecycle Methods
    
    private func setupView() {
        print("TasksView: Loaded with \(taskManager.tasks.count) tasks")
        
        if speechService.isListening {
            listenPulse = true
        }
        
        // Set up speech recognition completion handler based on service preference
        setupSpeechServices()
        
        // Start VAD
        initializeVAD()
        
        // Set up notification observers
        setupNotificationObservers()
    }
    
    private func handleListeningStateChange(_ newValue: Bool) {
        listenPulse = newValue
        
        // Always show recording indicator when listening
        withAnimation(.easeIn(duration: 0.2)) {
            showingRecordingIndicator = newValue
        }
        
        // If we stop listening, ensure the recording indicator remains visible until processing completes
        if !newValue && showingRecordingIndicator {
            // Let the recording indicator stay visible for final transcription display
            // It will be hidden by onRecognitionComplete
        }
    }
    
    private func handleTranscriptionChange(_ newValue: String) {
        // Skip UI updates if we're processing a task
        guard !processingTask else { return }
        
        // Only show recording indicator when there's text and not already shown
        if !newValue.isEmpty && !showingRecordingIndicator {
            // Fast animation for better performance
            withAnimation(.easeIn(duration: 0.1)) {
                showingRecordingIndicator = true
            }
        }
        
        // Auto-hide recording indicator if transcription is empty for too long
        if newValue.isEmpty && showingRecordingIndicator {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if self.speechService.transcribedText.isEmpty && !self.processingTask {
                    withAnimation(.easeOut(duration: 0.3)) {
                        self.showingRecordingIndicator = false
                    }
                }
            }
        }
    }
    
    private func handleVADToggle(_ newValue: Bool) {
        // Handle changes to VAD toggle
        if newValue {
            startVADService()
        } else {
            stopVADService()
        }
    }
    
    private func cleanupView() {
        // Clean up observers when view disappears
        removeNotificationObservers()
        
        // Stop VAD if active
        if speechService.isVADActive {
            speechService.stopVoiceActivityDetection()
        }
    }
    
    // MARK: - Voice Activity Detection Methods
    
    private func initializeVAD() {
        print("🎤 INIT VAD: Starting VAD initialization")
        
        // Check microphone permission first
        checkMicrophonePermission { granted in
            print("🎤 INIT VAD: Microphone permission granted: \(granted)")
            
            if granted {
                // For Apple Speech, also check speech recognition permission
                if !self.useWhisperSTT || !self.enableOpenAI {
                    self.checkSpeechRecognitionPermission { granted in
                        print("🎤 INIT VAD: Speech recognition permission granted: \(granted)")
                        
                        if granted {
                            self.startVADService()
                        } else {
                            // Show permission error
                            self.permissionAlertMessage = "Speech recognition permission is required for auto-listening."
                            self.showingPermissionAlert = true
                            
                            // Revert the toggle
                            Task { @MainActor in
                                self.isVADEnabled = false
                            }
                        }
                    }
                } else {
                    // For Whisper, we only need microphone permission
                    print("🎤 INIT VAD: Using Whisper mode, starting VAD service")
                    self.startVADService()
                }
            } else {
                // Show permission error
                self.permissionAlertMessage = "Microphone permission is required for auto-listening."
                self.showingPermissionAlert = true
                
                // Revert the toggle
                Task { @MainActor in
                    self.isVADEnabled = false
                }
            }
        }
    }
    
    private func startVADService() {
        print("🎤 START VAD: Starting VAD service")
        
        // Reset processing state
        Task { @MainActor in
            self.processingTask = false
        }
        
        if useWhisperSTT && enableOpenAI {
            print("🎤 START VAD: Using Whisper STT mode")
            // For Whisper, we might implement a different VAD approach
            // For now, we'll use Apple's VAD but trigger Whisper for transcription
            speechService.isVADEnabled = true
            Task {
                await speechService.startVoiceActivityDetection()
                
                // CRITICAL FIX: Monitor VAD status and restart if needed
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self.monitorVADStatus()
                }
            }
        } else {
            print("🎤 START VAD: Using Apple Speech mode")
            // Start Apple Speech VAD service
            speechService.isVADEnabled = true
            Task {
                await speechService.startVoiceActivityDetection()
                
                // CRITICAL FIX: Monitor VAD status and restart if needed
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    self.monitorVADStatus()
                }
            }
        }
        
        // Show feedback that the app is ready
        showFeedback(message: "🎤 Ready to listen", duration: 2.0)
        print("🎤 START VAD: VAD service started successfully")
    }
    
    // CRITICAL FIX: Add VAD monitoring to prevent "paused" state
    private func monitorVADStatus() {
        print("🎤 MONITOR: === VAD STATUS CHECK ===")
        print("🎤 MONITOR: isVADEnabled (UI): \(isVADEnabled)")
        print("🎤 MONITOR: speechService.isVADEnabled: \(speechService.isVADEnabled)")
        print("🎤 MONITOR: speechService.isVADActive: \(speechService.isVADActive)")
        print("🎤 MONITOR: speechService.vadAudioEngine?.isRunning: \(speechService.isVADAudioEngineRunning)")
        print("🎤 MONITOR: speechService.isRecording: \(speechService.isRecording)")
        print("🎤 MONITOR: speechService.isProcessingRecognition: \(speechService.isProcessingRecognition)")
        print("🎤 MONITOR: processingTask: \(processingTask)")
        
        // If VAD should be enabled but isn't active, restart it
        if isVADEnabled && speechService.isVADEnabled && !speechService.isVADActive {
            print("🎤 MONITOR: ❌ VAD should be active but isn't - restarting!")
            
            Task {
                await speechService.startVoiceActivityDetection()
                
                // Check again after restart attempt
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    print("🎤 MONITOR: POST-RESTART CHECK - isVADActive: \(self.speechService.isVADActive)")
                }
            }
            
            // Show user feedback
            showFeedback(message: "🔄 Restarting listener", duration: 1.5)
        } else if isVADEnabled && speechService.isVADEnabled && speechService.isVADActive {
            print("🎤 MONITOR: ✅ VAD is active and working properly")
        } else if !isVADEnabled {
            print("🎤 MONITOR: ⏸️ VAD is disabled by user")
        } else {
            print("🎤 MONITOR: ⚠️ Unexpected VAD state - investigating...")
            print("🎤 MONITOR: Attempting to restart VAD service...")
            
            // Force restart the entire VAD service
            Task {
                await speechService.startVoiceActivityDetection()
            }
            
            showFeedback(message: "🔄 Restarting listener", duration: 1.5)
        }
        
        // Schedule next check
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            if self.isVADEnabled {
                self.monitorVADStatus()
            }
        }
    }
    
    private func stopVADService() {
        // Stop VAD service for Apple Speech (we use it for both services currently)
        speechService.isVADEnabled = false
        speechService.stopVoiceActivityDetection()
        
        // Reset the active service
        if useWhisperSTT && enableOpenAI {
            // Reset Whisper service
            whisperService.transcribedText = ""
            whisperService.errorMessage = nil
        } else {
            // Reset Apple Speech service
            speechService.resetRecording()
            speechService.resetTranscription()
        }
        
        // Ensure recording indicator is hidden
        withAnimation(.easeOut(duration: 0.3)) {
            showingRecordingIndicator = false
            isRecording = false
        }
        
        // Restart VAD with the new service if it's currently active
        if self.isVADEnabled {
            self.stopVADService()
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000)
                self.initializeVAD()
            }
        }
    }
    
    // MARK: - Haptic Feedback
    
    // Function to provide haptic feedback when enabled
    private func provideHapticFeedback(_ feedbackType: HapticFeedbackType) {
        guard isHapticsEnabled else { return }
        
        switch feedbackType {
        case .light:
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
        case .medium:
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        case .heavy:
            let generator = UIImpactFeedbackGenerator(style: .heavy)
            generator.impactOccurred()
        case .success:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        case .warning:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        case .error:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        }
    }
    
    // MARK: - Permission Checking
    
    // Check microphone permission
    private func checkMicrophonePermission(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            Task {
                let granted = await AVAudioApplication.requestRecordPermission()
                Task { @MainActor in
                    completion(granted)
                }
            }
        } else {
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                completion(true)
            case .denied:
                completion(false)
            case .undetermined:
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    Task { @MainActor in
                        completion(granted)
                    }
                }
            @unknown default:
                completion(false)
            }
        }
    }
    
    // Check speech recognition permission
    private func checkSpeechRecognitionPermission(completion: @escaping (Bool) -> Void) {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    completion(status == .authorized)
                }
            }
        @unknown default:
            completion(false)
        }
    }
    
    // MARK: - Speech Recognition Handling
    
    // Handle speech recognition completion from any service
    private func handleSpeechRecognitionComplete(finalText: String, dueDate: Date?, source: String) {
        print("🎤 RECOGNITION COMPLETE (\(source)): '\(finalText)'")
        
        // Cancel any existing timeout
        processingTimeout?.cancel()
        
        // Set processing state to prevent UI updates during processing
        processingTask = true
        
        // Set up a timeout to prevent hanging (5 seconds max)
        processingTimeout = DispatchWorkItem {
            print("⚠️ TIMEOUT: Processing took too long, resetting state")
            
            Task { @MainActor in
                self.processingTask = false
                self.showingRecordingIndicator = false
                self.showFeedback(message: "Processing timeout - try again", duration: 2.0)
                self.resetTranscriptionForSource(source)
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0, execute: processingTimeout!)
        
        // Hide recording indicator with animation
        withAnimation(.easeOut(duration: 0.3)) {
            showingRecordingIndicator = false
        }
        
        // Process the transcribed text
        if !finalText.isEmpty {
            // Check if this should be sent to GPT-4 for general questions
            if shouldSendToGPT4(text: finalText) {
                print("🤖 SENDING TO GPT-4: '\(finalText)'")
                
                // Send to OpenAI for general question answering - ASYNC to prevent blocking
                Task {
                    do {
                        // Use async/await pattern to prevent blocking
                        await MainActor.run {
                            self.showFeedback(message: "🤔 Thinking...", duration: 1.0)
                        }
                        
                        // Perform OpenAI call on background thread
                        let result = await withCheckedContinuation { continuation in
                            openAIService.processTaskQuery(transcribedText: finalText) { result in
                                continuation.resume(returning: result)
                            }
                        }
                        
                        // Handle result on main thread
                        await MainActor.run {
                            // Cancel timeout since we're processing successfully
                            self.processingTimeout?.cancel()
                            
                            switch result {
                            case .success(let response):
                                // Show the AI response as feedback
                                self.showFeedback(message: response, duration: 8.0)
                            case .failure(_):
                                // Show error message
                                self.showFeedback(message: "AI service temporarily unavailable", duration: 3.0)
                            }
                            
                            // Reset processing state immediately
                            self.processingTask = false
                            
                            // Reset transcription for next input
                            self.resetTranscriptionForSource(source)
                            
                            // CRITICAL FIX: Immediate VAD restart for continuous listening
                            // Remove all delays to ensure immediate readiness for next command
                            if self.isVADEnabled {
                                print("🎤 IMMEDIATE RESTART: Restarting VAD immediately for next command")
                                
                                // Re-establish callbacks before restarting VAD
                                self.setupVADCallbacks()
                                
                                self.speechService.forceRestartVAD()
                            }
                        }
                    } catch {
                        // Handle any errors
                        await MainActor.run {
                            // Cancel timeout since we're handling the error
                            self.processingTimeout?.cancel()
                            
                            self.showFeedback(message: "AI service error", duration: 3.0)
                            self.processingTask = false
                            self.resetTranscriptionForSource(source)
                            
                            // CRITICAL FIX: Immediate VAD restart for continuous listening
                            // Remove all delays to ensure immediate readiness for next command
                            if self.isVADEnabled {
                                print("🎤 IMMEDIATE RESTART: Restarting VAD immediately for next command")
                                
                                // Re-establish callbacks before restarting VAD
                                self.setupVADCallbacks()
                                
                                self.speechService.forceRestartVAD()
                            }
                        }
                    }
                }
            } else {
                // Process as a task - Keep this synchronous for immediate response
                processTaskDirectly(finalText: finalText, dueDate: dueDate, source: source)
            }
        } else {
            // Reset processing state if no text
            processingTask = false
        }
    }
    
    // MARK: - Helper Methods for Task Processing
    
    private func processTaskDirectly(finalText: String, dueDate: Date?, source: String) {
        // Cancel timeout since we're processing successfully
        processingTimeout?.cancel()
        
        // Process as a task on main thread for immediate response
        let (taskTitle, extractedDueDate) = speechService.processTaskText(finalText)
        let finalDueDate = dueDate ?? extractedDueDate
        
        if !taskTitle.isEmpty {
            // Add the task with animation - Use lightweight animation
            withAnimation(.easeInOut(duration: 0.2)) {
                taskManager.addTask(title: taskTitle, dueDate: finalDueDate)
            }
            
            // Provide haptic feedback on task creation
            provideHapticFeedback(.success)
            
            // Show feedback
            let dueDateText = finalDueDate != nil ? " for \(DateFormatter.localizedString(from: finalDueDate!, dateStyle: .medium, timeStyle: .none))" : ""
            showFeedback(message: "Task added\(dueDateText)")
            
            // Force update tasks view
            forceUpdateTasks.toggle()
        } else {
            // Show feedback for unrecognized command
            showFeedback(message: "Couldn't understand the task. Try again.")
            provideHapticFeedback(.warning)
        }
        
        // Reset processing state immediately
        processingTask = false
        
        // Reset transcription for next input
        resetTranscriptionForSource(source)
        
        // CRITICAL FIX: Immediate VAD restart for continuous listening
        // Remove all delays to ensure immediate readiness for next command
        if isVADEnabled {
            print("🎤 IMMEDIATE RESTART: Restarting VAD immediately for next command")
            
            // Re-establish callbacks before restarting VAD
            self.setupVADCallbacks()
            
            self.speechService.forceRestartVAD()
        }
    }
    
    private func resetTranscriptionForSource(_ source: String) {
        if source == "Apple Speech" {
            speechService.resetTranscription()
        } else if source == "Whisper" {
            whisperService.transcribedText = ""
        }
        
        // CRITICAL FIX: Ensure VAD is always active for continuous listening
        // Remove conditional checks that might prevent restart
        if isVADEnabled {
            print("🎤 ENSURE VAD: Making sure VAD is active for continuous listening")
            
            // Re-establish callbacks before restarting VAD
            setupVADCallbacks()
            
            // Force restart regardless of current state
            speechService.forceRestartVAD()
        }
    }
    
    // CRITICAL: Method to re-establish VAD callbacks
    private func setupVADCallbacks() {
        print("🎤 CALLBACK SETUP: Re-establishing VAD callbacks")
        
        if useWhisperSTT && enableOpenAI {
            // Set up VAD callback to trigger Whisper recording
            speechService.onVADVoiceDetected = {
                Task { @MainActor in
                    print("🎤 VAD CALLBACK: Voice detected - starting Whisper recording")
                    print("🎤 VAD STATE: isRecording=\(self.whisperService.isRecording), processingTask=\(self.processingTask)")
                    
                    if !self.whisperService.isRecording && !self.processingTask {
                        print("🎤 VAD ACTION: Starting Whisper recording now")
                        self.whisperService.startRecording()
                    } else {
                        print("🎤 VAD SKIP: Whisper already recording or processing task")
                    }
                }
            }
        } else {
            print("🎤 SETUP: Configuring Apple Speech mode")
            // Only set up Apple Speech service completion handler
            speechService.onRecognitionComplete = { finalText, dueDate in
                self.handleSpeechRecognitionComplete(finalText: finalText, dueDate: dueDate, source: "Apple Speech")
            }
            
            // Clear Whisper handler to prevent double processing
            whisperService.onTranscriptionComplete = nil
            
            // Set up VAD callback to trigger Apple Speech recording
            speechService.onVADVoiceDetected = {
                Task { @MainActor in
                    print("🎤 VAD CALLBACK: Voice detected - starting Apple Speech recording")
                    print("🎤 VAD STATE: isRecording=\(self.speechService.isRecording), processingTask=\(self.processingTask), isProcessingRecognition=\(self.speechService.isProcessingRecognition)")
                    
                    if !self.speechService.isRecording && !self.processingTask && !self.speechService.isProcessingRecognition {
                        print("🎤 VAD ACTION: Starting Apple Speech recording now")
                        self.speechService.startRecording()
                    } else {
                        print("🎤 VAD SKIP: Apple Speech already recording or processing")
                    }
                }
            }
        }
        
        print("🎤 CALLBACK SETUP: VAD callbacks re-established successfully")
    }
    
    // MARK: - Feedback methods
    
    // Shows a temporary feedback message
    private func showFeedback(message: String, duration: TimeInterval = 3.0) {
        feedbackMessage = message
        showingFeedback = true
        
        // Hide after the specified duration
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            withAnimation {
                self.showingFeedback = false
            }
        }
    }
    
    // MARK: - Notification Observers
    
    private func setupNotificationObservers() {
        // Observe VAD sensitivity changes from SettingsView
        NotificationCenter.default.addObserver(
            forName: Notification.Name("VADSensitivityChanged"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let sensitivity = userInfo["sensitivity"] as? Double {
                // Update the sensitivity in the speech service
                self.speechService.updateVADSensitivity(sensitivity)
                
                // Show feedback about the change
                self.showFeedback(message: "Auto-listening sensitivity updated")
            }
        }
        
        // Observe speech service changes (Apple Speech vs Whisper)
        NotificationCenter.default.addObserver(
            forName: Notification.Name("SpeechServiceChanged"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let useWhisper = userInfo["useWhisper"] as? Bool {
                self.useWhisperSTT = useWhisper
                
                // Restart VAD with the new service if it's currently active
                if self.isVADEnabled {
                    self.stopVADService()
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        self.initializeVAD()
                    }
                }
                
                // Show feedback about the change
                let serviceName = useWhisper ? "Whisper AI" : "Apple Speech"
                self.showFeedback(message: "Switched to \(serviceName)")
            }
        }
        
        // Observe permission check requests when VAD is enabled
        NotificationCenter.default.addObserver(
            forName: Notification.Name("CheckVADPermissions"),
            object: nil,
            queue: .main
        ) { _ in
            // Check permissions for VAD
            self.initializeVAD()
        }
        
        // Observe toggle VAD requests from MainView microphone button
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ToggleVAD"),
            object: nil,
            queue: .main
        ) { _ in
            // Toggle VAD state
            self.toggleVAD()
        }
        
        // Observe elderly mode changes
        NotificationCenter.default.addObserver(
            forName: Notification.Name("ElderlyModeChanged"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
               let enabled = userInfo["enabled"] as? Bool {
                self.elderlyModeEnabled = enabled
                
                // Update speech service settings for elderly mode
                if !self.useWhisperSTT {
                    self.speechService.updateElderlyModeSettings(enabled: enabled)
                }
                
                // Show feedback about the change
                self.showFeedback(message: enabled ? "Elderly mode enabled" : "Elderly mode disabled")
            }
        }
    }
    
    // Remove notification observers when the view disappears
    private func removeNotificationObservers() {
        NotificationCenter.default.removeObserver(
            self,
            name: Notification.Name("VADSensitivityChanged"),
            object: nil
        )
        
        NotificationCenter.default.removeObserver(
            self,
            name: Notification.Name("SpeechServiceChanged"),
            object: nil
        )
        
        NotificationCenter.default.removeObserver(
            self,
            name: Notification.Name("CheckVADPermissions"),
            object: nil
        )
        
        NotificationCenter.default.removeObserver(
            self,
            name: Notification.Name("ToggleVAD"),
            object: nil
        )
        
        NotificationCenter.default.removeObserver(
            self,
            name: Notification.Name("ElderlyModeChanged"),
            object: nil
        )
    }
    
    // MARK: - Helper methods
    
    // Shows a temporary undo option
    private func showUndoOption() {
        withAnimation(.spring()) {
            showingUndoButton = true
        }
        
        // Auto-hide after 5 seconds
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            withAnimation {
                self.showingUndoButton = false
            }
        }
    }
    
    // Helper to check if date is within current week
    private func isDateInCurrentWeek(_ date: Date) -> Bool {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let sevenDaysLater = calendar.date(byAdding: .day, value: 7, to: today)!
        return date <= sevenDaysLater && date >= today
    }
    
    // MARK: - Helper Methods
    
    /// Determines if the transcribed text should be sent to GPT-4 instead of creating a task
    private func shouldSendToGPT4(text: String) -> Bool {
        // If OpenAI is disabled, never send to GPT-4
        guard enableOpenAI else { return false }
        
        let lowercaseText = text.lowercased()
        
        // Question indicators
        let questionWords = ["what", "how", "why", "when", "where", "who", "which", "can you", "could you", "would you", "do you", "are you", "is there", "tell me", "explain", "help me"]
        
        // Check if it starts with a question word or contains question patterns
        for questionWord in questionWords {
            if lowercaseText.hasPrefix(questionWord) || lowercaseText.contains(questionWord) {
                return true
            }
        }
        
        // Check for question marks
        if text.contains("?") {
            return true
        }
        
        // Check for conversational patterns
        let conversationalPatterns = ["hello", "hi", "good morning", "good afternoon", "good evening", "thank you", "thanks"]
        for pattern in conversationalPatterns {
            if lowercaseText.contains(pattern) {
                return true
            }
        }
        
        return false
    }
    
    // Toggle VAD state
    private func toggleVAD() {
        isVADEnabled.toggle()
    }
    
    private func setupSpeechServices() {
        print("🎤 SETUP: Setting up speech services")
        
        if useWhisperSTT && enableOpenAI {
            print("🎤 SETUP: Configuring Whisper mode")
            // Only set up Whisper service completion handler
            whisperService.onTranscriptionComplete = { finalText, confidence in
                self.handleSpeechRecognitionComplete(finalText: finalText, dueDate: nil, source: "Whisper")
            }
            
            // Clear Apple Speech handler to prevent double processing
            speechService.onRecognitionComplete = nil
            
            // Set up VAD callback to trigger Whisper recording
            speechService.onVADVoiceDetected = {
                Task { @MainActor in
                    print("🎤 VAD CALLBACK: Voice detected - starting Whisper recording")
                    print("🎤 VAD STATE: isRecording=\(self.whisperService.isRecording), processingTask=\(self.processingTask)")
                    
                    if !self.whisperService.isRecording && !self.processingTask {
                        print("🎤 VAD ACTION: Starting Whisper recording now")
                        self.whisperService.startRecording()
                    } else {
                        print("🎤 VAD SKIP: Whisper already recording or processing task")
                    }
                }
            }
        } else {
            print("🎤 SETUP: Configuring Apple Speech mode")
            // Only set up Apple Speech service completion handler
            speechService.onRecognitionComplete = { finalText, dueDate in
                self.handleSpeechRecognitionComplete(finalText: finalText, dueDate: dueDate, source: "Apple Speech")
            }
            
            // Clear Whisper handler to prevent double processing
            whisperService.onTranscriptionComplete = nil
            
            // Set up VAD callback to trigger Apple Speech recording
            speechService.onVADVoiceDetected = {
                Task { @MainActor in
                    print("🎤 VAD CALLBACK: Voice detected - starting Apple Speech recording")
                    print("🎤 VAD STATE: isRecording=\(self.speechService.isRecording), processingTask=\(self.processingTask), isProcessingRecognition=\(self.speechService.isProcessingRecognition)")
                    
                    if !self.speechService.isRecording && !self.processingTask && !self.speechService.isProcessingRecognition {
                        print("🎤 VAD ACTION: Starting Apple Speech recording now")
                        self.speechService.startRecording()
                    } else {
                        print("🎤 VAD SKIP: Apple Speech already recording or processing")
                    }
                }
            }
        }
        
        // CRITICAL FIX: Always ensure VAD is enabled for continuous listening
        print("🎤 SETUP: Ensuring VAD is enabled for continuous listening")
        isVADEnabled = true
        
        // CRITICAL FIX: Start VAD after a small delay to ensure proper audio session setup
        print("🎤 SETUP: Scheduling VAD initialization with delay for proper audio session setup")
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            print("🎤 SETUP: Starting delayed VAD initialization")
            self.initializeVAD()
        }
        
        // Set up notification observers
        setupNotificationObservers()
    }
}

// MARK: - Supporting Types

enum HapticFeedbackType {
    case light
    case medium
    case heavy
    case success
    case warning
    case error
}

#Preview {
    TasksView()
} 