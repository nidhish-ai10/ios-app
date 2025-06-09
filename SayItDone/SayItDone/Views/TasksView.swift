//
//  TasksView.swift
//  SayItDone
//
//  Created by Bairineni Nidhish rao on 6/2/25.
//

import SwiftUI
import Speech
import AVFAudio

struct TasksView: View {
    @StateObject private var taskManager = TaskManager()
    @StateObject private var speechService = SpeechRecognitionService()
    
    @State private var isRecording = false
    @State private var showingPermissionAlert = false
    @State private var permissionAlertMessage = ""
    @State private var showingRecordingIndicator = false
    @State private var listenPulse = false
    @State private var feedbackMessage = ""
    @State private var showingFeedback = false
    
    // Voice Activity Detection
    @AppStorage("isVADEnabled") private var isVADEnabled = false
    
    // User preferences
    @AppStorage("isHapticsEnabled") private var isHapticsEnabled = true
    
    // Color for our app
    let pastelBlueDarker = Color(red: 150/255, green: 190/255, blue: 255/255)
    
    var body: some View {
        VStack(spacing: 0) {
            // Tasks section
            ScrollView {
                if taskManager.tasks.isEmpty {
                    // Empty space when no tasks
                    Spacer()
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: UIScreen.main.bounds.height - 200)
                } else {
                    // Task list
                    LazyVStack(spacing: 12) {
                        ForEach(taskManager.tasks) { task in
                            TaskRowView(task: task) {
                                // Delete task action
                                provideHapticFeedback(.medium)
                                taskManager.removeTask(with: task.id)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                }
            }
            
            // Recording indicator with live transcription
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
                    
                    // Transcription text with improved visibility and status indicator
                    Text(speechService.transcribedText.isEmpty ? 
                         (speechService.isListening ? "Listening..." : "Say something...") : 
                         speechService.transcribedText)
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
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
                .padding(.bottom, 10)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            
            // Bottom controls area with VAD toggle only
            HStack {
                Spacer()
                
                // Enhanced VAD toggle button (centered and larger)
                Button(action: {
                    toggleVAD()
                }) {
                    HStack(spacing: 10) {
                        Image(systemName: isVADEnabled ? "mic.fill" : "mic.slash.fill")
                            .font(.system(size: 22))
                            .foregroundColor(.white)
                        
                        Text(isVADEnabled ? "Auto-Listen On" : "Auto-Listen Off")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(isVADEnabled ? pastelBlueDarker : Color.gray)
                            .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
                    )
                }
                .accessibilityLabel(isVADEnabled ? "Turn off auto-listening" : "Turn on auto-listening")
                
                Spacer()
            }
            .padding(.bottom, 35)
            .onAppear {
                if speechService.isListening {
                    listenPulse = true
                }
            }
            .onChange(of: speechService.isListening) { newValue in
                listenPulse = newValue
                
                // If we stop listening, ensure the recording indicator remains visible until processing completes
                if !newValue && showingRecordingIndicator {
                    // Let the recording indicator stay visible for final transcription display
                    // It will be hidden by onRecognitionComplete
                }
            }
        }
        .onAppear {
            // Set up the speech service with improved feedback
            speechService.onRecognitionComplete = { taskTitle, dueDate in
                // Immediately hide the recording indicator regardless of task result
                withAnimation(.easeOut(duration: 0.1)) {
                    self.showingRecordingIndicator = false
                    self.isRecording = false
                }
                
                // Only process non-empty tasks
                if !taskTitle.isEmpty {
                    // Small delay to ensure UI update completes first
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        // Add the task
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            self.taskManager.addTask(title: taskTitle, dueDate: dueDate)
                            
                            // Show feedback with date if available
                            if let date = dueDate {
                                let formatter = DateFormatter()
                                formatter.dateFormat = "MMMM d, yyyy"
                                let dateString = formatter.string(from: date)
                                self.showFeedback(message: "Task scheduled for \(dateString)")
                            } else {
                                // Show confirmation for tasks without dates
                                self.showFeedback(message: "Task added")
                            }
                        }
                        
                        // Provide haptic feedback on task creation
                        self.provideHapticFeedback(.success)
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
        .onChange(of: speechService.transcribedText) { newValue in
            // Handle transcription text changes more efficiently
            let oldValue = speechService.transcribedText
            if newValue.isEmpty && oldValue.isEmpty {
                // Both empty - no change needed
                return
            }
            
            if !newValue.isEmpty && showingRecordingIndicator == false {
                // Show recording indicator when we have text
                withAnimation(.easeIn(duration: 0.2)) {
                    showingRecordingIndicator = true
                }
            }
        }
        .onChange(of: isVADEnabled) { newValue in
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
            startVAD()
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
    private func showFeedback(message: String) {
        feedbackMessage = message
        showingFeedback = true
        
        // Hide after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
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