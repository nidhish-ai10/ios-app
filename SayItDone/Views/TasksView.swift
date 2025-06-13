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

struct TasksView: View {
    @StateObject private var taskManager = TaskManager()
    @StateObject private var speechService = SpeechRecognitionService()
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
    @AppStorage("isVADEnabled") private var isVADEnabled = false
    
    // User preferences
    @AppStorage("isHapticsEnabled") private var isHapticsEnabled = true
    
    // Color for our app
    let pastelBlueDarker = Color(red: 150/255, green: 190/255, blue: 255/255)
    
    // Add this property at the top of the struct, near other state variables
    @State private var processingTask = false
    
    // EMERGENCY FIX: Create a force updater
    @State private var forceUpdateTasks: Bool = false
    
    // OpenAI Integration Toggle
    private let enableOpenAI = true // Set to false to disable AI processing
    
    var body: some View {
        ZStack {
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
            
            // Position the recording indicator near the bottom above where the mic button would be
            VStack {
                Spacer()
                
                // Recording indicator with live transcription - enhanced for better visibility
                if showingRecordingIndicator {
                    VStack(spacing: 10) {
                        // Status label - show whether using VAD or manual recording
                        if speechService.isVADActive && isVADEnabled {
                            Text("Auto-listening active")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                        
                        // Waveform animation (audio visualization) - more active when listening
                        HStack(spacing: 3) {
                            ForEach(0..<5) { index in
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(pastelBlueDarker)
                                    .frame(width: 3, height: speechService.isListening ? 20 : 10)
                                    .modifier(WaveformAnimationModifier(
                                        isActive: speechService.isListening,
                                        delay: Double(index) * 0.15
                                    ))
                            }
                        }
                        .padding(.vertical, 8)
                        
                        // Transcription text with improved visibility and status indicator
                        Text(speechService.transcribedText.isEmpty ? 
                             (speechService.isListening ? "Listening..." : "Say something...") : 
                             speechService.transcribedText)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(3)
                            .multilineTextAlignment(.center)
                            .frame(minHeight: 60)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal)
                            .animation(.easeInOut(duration: 0.2), value: speechService.transcribedText)
                            .animation(.easeInOut(duration: 0.2), value: speechService.isListening)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor.secondarySystemBackground))
                            .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                    )
                    .padding(.horizontal, 20)
                    .padding(.bottom, 90) // Position it above where the mic button will be
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .onAppear {
            print("TasksView: Loaded with \(taskManager.tasks.count) tasks")
            
            if speechService.isListening {
                listenPulse = true
            }
            
            // Set up the speech service with improved feedback
            speechService.onRecognitionComplete = { finalText, dueDate in
                print("RECOGNITION: Complete with text: '\(finalText)'")
                
                // Only process non-empty tasks and prevent rapid duplicates
                if !finalText.isEmpty && !processingTask {
                    // Set processing flag to prevent rapid duplicates
                    processingTask = true
                    
                    // IMPORTANT: Force UI updates to happen on main thread
                    DispatchQueue.main.async {
                        showingRecordingIndicator = false
                        
                        // Check if the text looks like a question or request for GPT-4
                        if self.shouldSendToGPT4(text: finalText) {
                            // Use the new combined GPT-4 processing function
                            self.openAIService.processTranscribedTextComplete(
                                finalText,
                                showFeedback: { message, duration in
                                    self.showFeedback(message: message, duration: duration)
                                },
                                provideHaptic: {
                                    self.provideHapticFeedback(.success)
                                },
                                completion: { result in
                                    // Ensure VAD restart happens on main thread with proper timing
                                    DispatchQueue.main.async {
                                        // Reset processing state regardless of success/failure
                                        self.processingTask = false
                                        
                                        // Add a longer delay to ensure all UI updates and speech synthesis complete
                                        // This is critical for allowing multiple GPT-4 questions
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                            print("🎤 Restarting VAD after GPT-4 interaction (with extended delay)")
                                            self.speechService.forceRestartVAD()
                                        }
                                    }
                                }
                            )
                            
                            // Analyze the conversation snippet
                            Task {
                                do {
                                    try await FirebaseUserService.shared.analyzeSnippet(
                                        assistantMessage: result ?? "",
                                        userMessage: finalText
                                    )
                                } catch {
                                    print("Error analyzing conversation: \(error)")
                                }
                            }
                        } else {
                            // Process as a regular task using the duplicate-prevention method
                            let result = taskManager.addTaskIfNotDuplicate(title: finalText, dueDate: dueDate)
                            print("TASK: Addition result: success=\(result.success)")
                            
                            if result.success {
                                // Success feedback - task was added
                                showFeedback(message: "Task added!")
                                provideHapticFeedback(.success)
                            } else {
                                // Duplicate task feedback
                                showFeedback(message: "Similar task already exists")
                                provideHapticFeedback(.warning)
                            }
                            
                            // CRITICAL FIX: Restart VAD immediately after processing to allow continuous task addition
                            processingTask = false
                            
                            // Force restart VAD to ensure it works for multiple tasks
                            speechService.forceRestartVAD()
                            
                            // Force UI refresh by toggling the force updater
                            forceUpdateTasks.toggle()
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        showingRecordingIndicator = false
                        
                        // CRITICAL FIX: Also restart VAD for empty text case
                        processingTask = false
                        
                        // Force restart VAD to ensure it works for multiple tasks
                        speechService.forceRestartVAD()
                    }
                }
            }
            
            // Always enable VAD since we removed the microphone button
            if !isVADEnabled {
                isVADEnabled = true
            }
            
            // Start VAD
            initializeVAD()
            
            // Set up notification observers
            setupNotificationObservers()
        }
        .onChange(of: speechService.isListening) { _, newValue in
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
        .onChange(of: speechService.transcribedText) { _, newValue in
            // Skip UI updates if we're processing a task
            guard !processingTask else { return }
            
            // Only show recording indicator when there's text and not already shown
            if !newValue.isEmpty && !showingRecordingIndicator {
                // Fast animation for better performance
                withAnimation(.easeIn(duration: 0.1)) {
                    showingRecordingIndicator = true
                }
            }
        }
        .onChange(of: isVADEnabled) { _, newValue in
            // Handle changes to VAD toggle
            if newValue {
                startVAD()
            } else {
                stopVAD()
            }
        }
        .alert(isPresented: $showingPermissionAlert) {
            Alert(
                title: Text("Permission Required"),
                message: Text(permissionAlertMessage),
                dismissButton: .default(Text("OK"))
            )
        }
        .overlay(
            // Undo button overlay
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
        )
        .overlay(
            // Feedback message overlay
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
        )
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
            // Clean up observers when view disappears
            removeNotificationObservers()
            
            // Stop VAD if active
            if speechService.isVADActive {
                speechService.stopVoiceActivityDetection()
            }
        }
    }
    
    // MARK: - Voice Activity Detection Methods
    
    private func initializeVAD() {
        // Check if VAD is enabled and initialize it
        if isVADEnabled {
            startVAD()
        } else {
            stopVAD()
        }
    }
    
    private func toggleVAD() {
        // Toggle the VAD setting
        isVADEnabled.toggle()
        
        // Provide haptic feedback
        provideHapticFeedback(.medium)
        
        // Show feedback message
        showFeedback(message: isVADEnabled ? "Auto-listening turned on" : "Auto-listening turned off")
        
        // Start or stop VAD based on new state
        if isVADEnabled {
            // Ensure any in-progress recognition is stopped before starting VAD
            speechService.resetRecording()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.startVAD()
            }
        } else {
            stopVAD()
        }
    }
    
    private func startVAD() {
        // First check permissions
        checkMicrophonePermission { micGranted in
            if micGranted {
                checkSpeechRecognitionPermission { speechGranted in
                    if speechGranted {
                        // Reset service state first (moved outside of async to start reset immediately)
                        self.speechService.resetRecording()
                        self.speechService.resetTranscription()
                        
                        // Reset UI state
                        DispatchQueue.main.async {
                            self.showingRecordingIndicator = false
                            self.processingTask = false
                        }
                        
                        // Start VAD service immediately for faster response
                        // Start VAD service
                        self.speechService.isVADEnabled = true
                        self.speechService.startVoiceActivityDetection()
                        
                        // Show feedback
                        self.showFeedback(message: "Auto-listening active")
                    } else {
                        // Show permission error
                        self.permissionAlertMessage = "Speech recognition permission is required for auto-listening."
                        self.showingPermissionAlert = true
                        
                        // Revert the toggle
                        DispatchQueue.main.async {
                            self.isVADEnabled = false
                        }
                    }
                }
            } else {
                // Show permission error
                self.permissionAlertMessage = "Microphone permission is required for auto-listening."
                self.showingPermissionAlert = true
                
                // Revert the toggle
                DispatchQueue.main.async {
                    self.isVADEnabled = false
                }
            }
        }
    }
    
    private func stopVAD() {
        // Stop VAD service
        speechService.isVADEnabled = false
        speechService.stopVoiceActivityDetection()
        
        // Reset the speech service
        speechService.resetRecording()
        // Reset transcription to ensure a clean slate
        speechService.resetTranscription()
        
        // Ensure recording indicator is hidden
        withAnimation(.easeOut(duration: 0.3)) {
            showingRecordingIndicator = false
            isRecording = false
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
        case .error:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.error)
        case .warning:
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.warning)
        }
    }
    
    // Enum to define haptic feedback types
    private enum HapticFeedbackType {
        case light, medium, heavy
        case success, warning, error
    }
    
    // Handle microphone button tap
    private func handleMicrophoneTap() {
        // Provide haptic feedback when tapping microphone
        provideHapticFeedback(.medium)
        
        if isRecording {
            // Stop recording
            speechService.stopRecording()
            
            // Update UI state - but don't hide recording indicator yet
            // Let the onRecognitionComplete callback handle hiding it
            withAnimation {
                isRecording = false
            }
        } else {
            // Check microphone permission
            checkMicrophonePermission { granted in
                if granted {
                    // Check speech recognition permission
                    checkSpeechRecognitionPermission { granted in
                        if granted {
                            // If VAD is active, stop it to avoid conflicts
                            if self.speechService.isVADActive {
                                self.speechService.stopVoiceActivityDetection()
                            }
                            
                            // Reset any previous state
                            self.speechService.resetRecording()
                            self.speechService.resetTranscription()
                            
                            // Start recording
                            withAnimation {
                                isRecording = true
                                showingRecordingIndicator = true
                            }
                            speechService.startRecording()
                        } else {
                            // Show permission alert
                            provideHapticFeedback(.error)
                            permissionAlertMessage = "Please allow speech recognition in Settings to use this feature."
                            showingPermissionAlert = true
                        }
                    }
                } else {
                    // Show permission alert
                    provideHapticFeedback(.error)
                    permissionAlertMessage = "Please allow microphone access in Settings to use this feature."
                    showingPermissionAlert = true
                }
            }
        }
    }
    
    // Check microphone permission
    private func checkMicrophonePermission(completion: @escaping (Bool) -> Void) {
        if #available(iOS 17.0, *) {
            // Use the new iOS 17+ API
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                completion(true)
            case .denied:
                completion(false)
            case .undetermined:
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        completion(granted)
                    }
                }
            @unknown default:
                completion(false)
            }
        } else {
            // Fallback for older iOS versions
            switch AVAudioSession.sharedInstance().recordPermission {
            case .granted:
                completion(true)
            case .denied:
                completion(false)
            case .undetermined:
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
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
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }
    
    // Update the processTranscription method to be more robust
    private func processTranscription(_ text: String) {
        // Only process if we have text and it hasn't been processed already
        if !text.isEmpty {
            // Use the speech service to process the text
            let (taskTitle, dueDate) = speechService.processTaskText(text)
            
            if !taskTitle.isEmpty {
                // Add the task with animation
                withAnimation {
                    taskManager.addTask(title: taskTitle, dueDate: dueDate)
                }
                
                // Provide haptic feedback on task creation
                provideHapticFeedback(.success)
                
                // Reset transcription to allow for new tasks
                speechService.resetTranscription()
            }
        }
    }
    
    // MARK: - Feedback methods
    
    // Shows a temporary feedback message
    private func showFeedback(message: String, duration: TimeInterval = 3.0) {
        feedbackMessage = message
        showingFeedback = true
        
        // Hide after the specified duration
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
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
        
        // Observe permission check requests when VAD is enabled
        NotificationCenter.default.addObserver(
            forName: Notification.Name("CheckVADPermissions"),
            object: nil,
            queue: .main
        ) { _ in
            // Check permissions for VAD
            self.startVAD()
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
            name: Notification.Name("CheckVADPermissions"),
            object: nil
        )
        
        NotificationCenter.default.removeObserver(
            self,
            name: Notification.Name("ToggleVAD"),
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
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
        let conversationalPatterns = ["hello", "hi", "hey", "good morning", "good afternoon", "good evening", "thank you", "thanks", "please", "sorry"]
        
        for pattern in conversationalPatterns {
            if lowercaseText.contains(pattern) {
                return true
            }
        }
        
        return false
    }
    
    private func getErrorMessage(from error: Error) -> String {
        if let openAIError = error as? OpenAIError {
            switch openAIError {
            case .httpError(429, _):
                return "🚫 OpenAI usage limit reached"
            case .httpError(401, _):
                return "🔑 Invalid OpenAI API key"
            case .networkError(_):
                return "🌐 Network connection issue"
            case .invalidAPIKey:
                return "⚙️ OpenAI API key not configured"
            case .emptyPrompt:
                return "📝 No text to process"
            case .noResponse:
                return "🤖 No response from AI"
            default:
                return "⚠️ AI service temporarily unavailable"
            }
        }
        return "❌ Something went wrong"
    }
    
    // MARK: - Combined GPT-4 Processing Helper
    
    /// Example usage of the combined GPT-4 processing function
    /// This shows how to use processTranscribedTextComplete in any SwiftUI view
    private func handleUserSpeech(_ transcribedText: String) {
        // Simple one-line call that handles everything:
        // 1. Sends to GPT-4
        // 2. Displays response in UI
        // 3. Speaks response aloud
        openAIService.processTranscribedTextComplete(
            transcribedText,
            showFeedback: { message, duration in
                // Display message in your UI
                self.showFeedback(message: message, duration: duration)
            },
            provideHaptic: {
                // Provide haptic feedback for success
                self.provideHapticFeedback(.success)
            },
            completion: { result in
                // Handle completion (success or failure)
                switch result {
                case .success(let response):
                    print("✅ GPT-4 pipeline completed: \(response)")
                case .failure(let error):
                    print("❌ GPT-4 pipeline failed: \(error)")
                }
                
                // Reset any processing states
                self.processingTask = false
                self.speechService.forceRestartVAD()
            }
        )
    }
}

// Waveform animation modifier
struct WaveformAnimationModifier: ViewModifier {
    @State private var isAnimating = false
    let isActive: Bool
    let delay: Double
    
    init(isActive: Bool = true, delay: Double = 0.0) {
        self.isActive = isActive
        self.delay = delay
    }
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(x: 1, y: isAnimating ? 
                        (isActive ? 0.5 + CGFloat.random(in: 0.5...1.0) : 0.7) : 
                        0.3)
            .animation(
                Animation.easeInOut(duration: isActive ? 0.5 : 1.0)
                    .repeatForever(autoreverses: true)
                    .delay(delay),
                value: isAnimating
            )
            .onAppear {
                isAnimating = true
            }
    }
}

#Preview {
    TasksView()
} 