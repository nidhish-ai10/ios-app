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
            
            // Microphone button with improved visual feedback
            Button(action: {
                handleMicrophoneTap()
            }) {
                ZStack {
                    // Pulsing background for active listening
                    if speechService.isListening {
                        Circle()
                            .fill(pastelBlueDarker.opacity(0.3))
                            .frame(width: listenPulse ? 90 : 68, height: listenPulse ? 90 : 68)
                            .animation(
                                Animation.easeInOut(duration: 1.0)
                                    .repeatForever(autoreverses: true),
                                value: listenPulse
                            )
                    }
                    
                    Circle()
                        .fill(pastelBlueDarker)
                        .frame(width: 68, height: 68)
                        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                    
                    if isRecording {
                        // Stop icon when recording
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 20, height: 20)
                    } else {
                        // Mic icon when not recording
                        Image(systemName: "mic.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 28)
                            .foregroundColor(.white)
                    }
                }
                // Add pulsing animation when recording
                .scaleEffect(isRecording ? 1.05 : 1.0)
                .animation(
                    isRecording ? 
                        Animation.easeInOut(duration: 0.5).repeatForever(autoreverses: true) : 
                        .default, 
                    value: isRecording
                )
            }
            .padding(.bottom, 35)
            .onAppear {
                if speechService.isListening {
                    listenPulse = true
                }
            }
            .onChange(of: speechService.isListening) { _, newValue in
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
                // Add the recognized task with animation
                if !taskTitle.isEmpty {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                        taskManager.addTask(title: taskTitle, dueDate: dueDate)
                        // Keep the streaming box visible when task is added
                        isRecording = false
                    }
                    
                    // Provide haptic feedback on task creation
                    provideHapticFeedback(.success)
                } else {
                    // If no task was created, hide UI elements
                    withAnimation(.easeOut(duration: 0.3)) {
                        showingRecordingIndicator = false
                        isRecording = false
                    }
                }
            }
        }
        .onChange(of: speechService.transcribedText) { oldValue, newValue in
            // Handle transcription text changes more efficiently
            if newValue.isEmpty && oldValue.isEmpty {
                // Both empty - no change needed
                return
            }
            
            if !newValue.isEmpty {
                // Show recording indicator whenever we have text
                if !showingRecordingIndicator {
                    withAnimation(.easeIn(duration: 0.2)) {
                        showingRecordingIndicator = true
                    }
                }
            }
        }
        .alert(isPresented: $showingPermissionAlert) {
            Alert(
                title: Text("Permission Required"),
                message: Text(permissionAlertMessage),
                dismissButton: .default(Text("OK"))
            )
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