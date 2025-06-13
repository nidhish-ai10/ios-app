//
//  SpeechRecognitionService.swift
//  SayItDone
//
//  Created by Bairineni Nidhish rao on 6/2/25.
//

import Foundation
import Speech
import AVFoundation
import NaturalLanguage
import SwiftUI

@MainActor
class SpeechRecognitionService: NSObject, ObservableObject {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var errorMessage: String?
    @Published var lastProcessedText = "" // Track last processed text to avoid duplicates
    @Published var isListening = false // Track active listening state
    
    // Elderly-friendly features
    @Published var subtitleText = "" // Real-time subtitle display
    @Published var correctedTranscript = "" // Post-processed corrected text
    @Published var isSlowSpeechMode = false // Detect and handle slow speech
    @Published var speechConfidence: Float = 0.0 // Confidence level of recognition
    
    // Voice Activity Detection (VAD) properties
    @Published var isVADEnabled = false
    @Published var isVADActive: Bool = false
    
    // Public computed property to check if VAD audio engine is running
    var isVADAudioEngineRunning: Bool {
        return vadAudioEngine?.isRunning ?? false
    }
    
    // Private properties
    private var vadAudioEngine: AVAudioEngine?
    private var vadInputNode: AVAudioInputNode?
    private var consecutiveVoiceFrames = 0
    private var vadSilenceFrames = 0 // Use a different name for VAD silence frames
    private let requiredVoiceFrames = 10 // Number of consecutive voice frames to trigger activation
    private let vadPowerThreshold: Float = 0.01 // Adjustable threshold for voice detection
    
    // Enhanced settings for elderly users
    private var elderlyModeEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "elderlyModeEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "elderlyModeEnabled") }
    }
    
    private var slowSpeechTolerance: Double {
        get { UserDefaults.standard.double(forKey: "slowSpeechTolerance") }
        set { UserDefaults.standard.set(newValue, forKey: "slowSpeechTolerance") }
    }
    
    private var stutterDetectionEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: "stutterDetectionEnabled") }
        set { UserDefaults.standard.set(newValue, forKey: "stutterDetectionEnabled") }
    }
    
    private var accentToleranceLevel: Double {
        get { UserDefaults.standard.double(forKey: "accentToleranceLevel") }
        set { UserDefaults.standard.set(newValue, forKey: "accentToleranceLevel") }
    }
    
    private var noiseSuppressionLevel: Double {
        get { UserDefaults.standard.double(forKey: "noiseSuppressionLevel") }
        set { UserDefaults.standard.set(newValue, forKey: "noiseSuppressionLevel") }
    }
    
    // User preferences from UserDefaults
    private var vadSensitivity: Double {
        get { UserDefaults.standard.double(forKey: "vadSensitivity") }
        set { UserDefaults.standard.set(newValue, forKey: "vadSensitivity") }
    }
    
    // Property for storing completion handler
    public var onRecognitionComplete: ((String, Date?) -> Void)?
    
    // Property for VAD voice detection callback - allows external control of what happens when voice is detected
    public var onVADVoiceDetected: (() -> Void)?
    
    // Add these properties to the class after the existing @Published variables
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.2 // Increased for elderly users
    private let powerThreshold: Float = 0.002 // Reduced threshold for better sensitivity
    private var consecutiveSilenceFrames = 0
    private let requiredSilenceFrames = 3 // Adjusted for elderly users
    
    // Enhanced timing for elderly users
    private var maxRecordingTimer: Timer?
    private let maxRecordingDuration: TimeInterval = 15.0 // Increased to 15 seconds for slower speech
    
    // Add debouncing timer to prevent duplicate task creation
    private var processingDebounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.5 // Increased debounce for elderly users
    
    // Add a property to track if we're currently processing a completion
    @Published var isProcessingRecognition = false
    
    // Stored transcribed text to use when processing is complete
    private var storedTranscribedText = ""
    
    // Stutter detection properties
    private var previousWords: [String] = []
    private var stutterPatterns: [String] = []
    
    // Noise suppression filter
    private var noiseFilter: AVAudioUnitEQ?
    
    // Elderly Mode Settings
    @Published var subtitleFontSize: CGFloat = 16.0
    @Published var highContrastMode: Bool = false
    @Published var showRecognitionQuality: Bool = false
    
    override init() {
        super.init()
        
        // Initialize elderly-friendly defaults
        if UserDefaults.standard.object(forKey: "elderlyModeEnabled") == nil {
            elderlyModeEnabled = false
        }
        if UserDefaults.standard.object(forKey: "slowSpeechTolerance") == nil {
            slowSpeechTolerance = 0.7 // Default tolerance level
        }
        if UserDefaults.standard.object(forKey: "stutterDetectionEnabled") == nil {
            stutterDetectionEnabled = true
        }
        if UserDefaults.standard.object(forKey: "accentToleranceLevel") == nil {
            accentToleranceLevel = 0.6 // Default accent tolerance
        }
        if UserDefaults.standard.object(forKey: "noiseSuppressionLevel") == nil {
            noiseSuppressionLevel = 0.5 // Default noise suppression
        }
        
        // Initialize VAD sensitivity with default if not set
        if UserDefaults.standard.double(forKey: "vadSensitivity") == 0 {
            vadSensitivity = 0.5 // Default sensitivity (0.0-1.0 range)
        }
        
        // Setup noise suppression filter
        setupNoiseSuppressionFilter()
        
        // Check if speech recognition is available
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                switch status {
                case .authorized:
                    self.errorMessage = nil
                case .denied:
                    self.errorMessage = "Speech recognition permission denied"
                case .restricted:
                    self.errorMessage = "Speech recognition is restricted on this device"
                case .notDetermined:
                    self.errorMessage = "Speech recognition permission not determined"
                @unknown default:
                    self.errorMessage = "Unknown speech recognition authorization status"
                }
            }
        }
    }
    
    // MARK: - Elderly-Friendly Features
    
    /// Setup noise suppression filter for better audio quality
    private func setupNoiseSuppressionFilter() {
        noiseFilter = AVAudioUnitEQ(numberOfBands: 10)
        
        // Configure EQ bands for noise suppression
        guard let filter = noiseFilter else { return }
        
        // Reduce low-frequency noise (air conditioning, traffic)
        filter.bands[0].frequency = 60
        filter.bands[0].gain = -6
        filter.bands[0].bypass = false
        
        // Reduce mid-low frequency noise
        filter.bands[1].frequency = 120
        filter.bands[1].gain = -3
        filter.bands[1].bypass = false
        
        // Enhance speech frequencies (300-3000 Hz)
        filter.bands[3].frequency = 1000
        filter.bands[3].gain = 2
        filter.bands[3].bypass = false
        
        filter.bands[4].frequency = 2000
        filter.bands[4].gain = 3
        filter.bands[4].bypass = false
        
        // Reduce high-frequency noise
        filter.bands[8].frequency = 8000
        filter.bands[8].gain = -4
        filter.bands[8].bypass = false
    }
    
    /// Detect if speech is slow and adjust recognition accordingly
    private func detectSlowSpeech(from text: String, timeInterval: TimeInterval) {
        let wordCount = text.split(separator: " ").count
        let wordsPerMinute = Double(wordCount) / (timeInterval / 60.0)
        
        // Average speaking rate is 150-160 WPM, slow speech is typically below 100 WPM
        let slowSpeechThreshold = 100.0 * (1.0 - slowSpeechTolerance)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isSlowSpeechMode = wordsPerMinute < slowSpeechThreshold
        }
    }
    
    /// Process text to remove stutters and repeated words
    private func removeStutters(from text: String) -> String {
        guard stutterDetectionEnabled else { return text }
        
        let words = text.split(separator: " ").map(String.init)
        var cleanedWords: [String] = []
        var i = 0
        
        while i < words.count {
            let currentWord = words[i].lowercased()
            
            // Check for immediate repetition (stutter)
            if i + 1 < words.count && currentWord == words[i + 1].lowercased() {
                // Skip repeated word
                cleanedWords.append(words[i])
                i += 2 // Skip the duplicate
            } else if i + 2 < words.count && currentWord == words[i + 2].lowercased() {
                // Check for pattern like "the the cat" -> "the cat"
                cleanedWords.append(words[i])
                cleanedWords.append(words[i + 1])
                i += 3 // Skip the duplicate
            } else {
                cleanedWords.append(words[i])
                i += 1
            }
        }
        
        return cleanedWords.joined(separator: " ")
    }
    
    /// Apply accent tolerance by using alternative recognition approaches
    private func enhanceAccentRecognition() {
        // Configure speech recognizer for better accent handling
        if speechRecognizer != nil {
            // Enhanced accent recognition is handled by the main recognizer
            // Multiple locale support would be implemented here in a full version
            print("Enhanced accent recognition configured")
        }
    }
    
    /// Update subtitle text in real-time
    private func updateSubtitles(with text: String, confidence: Float) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.subtitleText = text
            self.speechConfidence = confidence
            
            // Apply corrections if confidence is low
            if confidence < 0.7 && self.elderlyModeEnabled {
                self.correctedTranscript = self.removeStutters(from: text)
            } else {
                self.correctedTranscript = text
            }
        }
    }
    
    // MARK: - Voice Activity Detection (VAD)
    
    /// Start Voice Activity Detection with enhanced reliability for elderly users
    func startVoiceActivityDetection() async {
        print("🎤 VAD START: Starting Voice Activity Detection...")
        
        // CRITICAL FIX: Always reset state before starting
        isVADActive = false
        consecutiveVoiceFrames = 0
        vadSilenceFrames = 0
        
        guard !isVADActive else {
            print("🎤 VAD WARNING: VAD already active, skipping start")
            return
        }
        
        // CRITICAL FIX: Stop any existing VAD first and clean up thoroughly
        if vadAudioEngine?.isRunning == true {
            print("🎤 VAD CLEANUP: Stopping existing VAD engine")
            stopVoiceActivityDetection()
            
            // Wait a moment for cleanup
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }
        
        // CRITICAL FIX: Clean up any existing audio engine completely
        if let existingEngine = vadAudioEngine {
            print("🎤 VAD CLEANUP: Cleaning up existing audio engine")
            if existingEngine.isRunning {
                existingEngine.stop()
            }
            vadInputNode?.removeTap(onBus: 0)
            vadAudioEngine = nil
            vadInputNode = nil
            
            // Wait for complete cleanup
            try? await Task.sleep(nanoseconds: 200_000_000) // 0.2 seconds
        }
        
        // Configure audio session with enhanced error handling
        do {
            let audioSession = AVAudioSession.sharedInstance()
            print("🎤 VAD AUDIO: Configuring audio session...")
            
            // CRITICAL FIX: Deactivate session first to ensure clean state
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
            try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            
            if elderlyModeEnabled {
                // For elderly users, use more permissive settings
                try audioSession.setCategory(.record, mode: .spokenAudio, options: [.allowBluetooth, .mixWithOthers, .defaultToSpeaker])
                print("🎤 VAD AUDIO: Set elderly-friendly audio category (.record + .spokenAudio)")
            } else {
                // Standard configuration
                try audioSession.setCategory(.record, mode: .measurement, options: [.allowBluetooth, .mixWithOthers])
                print("🎤 VAD AUDIO: Set standard audio category (.record + .measurement)")
            }
            
            // CRITICAL: Request microphone permission explicitly
            if #available(iOS 17.0, *) {
                let recordPermission = await AVAudioApplication.requestRecordPermission()
                print("🎤 VAD PERMISSION: Microphone permission granted: \(recordPermission)")
                if !recordPermission {
                    Task { @MainActor in
                        self.errorMessage = "Microphone permission denied - please enable in Settings"
                    }
                    return
                }
            } else {
                let permissionGranted = await withCheckedContinuation { continuation in
                    audioSession.requestRecordPermission { granted in
                        continuation.resume(returning: granted)
                    }
                }
                print("🎤 VAD PERMISSION: Microphone permission granted: \(permissionGranted)")
                if !permissionGranted {
                    Task { @MainActor in
                        self.errorMessage = "Microphone permission denied - please enable in Settings"
                    }
                    return
                }
            }
            
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            print("🎤 VAD AUDIO: Audio session activated successfully")
            
            // Enhanced audio settings for better streaming
            if elderlyModeEnabled {
                try audioSession.setPreferredSampleRate(16000) // Optimal for speech
                try audioSession.setPreferredIOBufferDuration(0.005) // Very low latency
                print("🎤 VAD AUDIO: Set elderly-friendly audio parameters (16kHz, 5ms buffer)")
            } else {
                try audioSession.setPreferredSampleRate(44100) // Higher quality
                try audioSession.setPreferredIOBufferDuration(0.01) // Low latency
                print("🎤 VAD AUDIO: Set standard audio parameters (44.1kHz, 10ms buffer)")
            }
        } catch {
            let errorMsg = "Failed to set up audio session for VAD: \(error.localizedDescription)"
            Task { @MainActor in
                self.errorMessage = errorMsg
            }
            print("🎤 VAD ERROR: \(errorMsg)")
            return
        }
        
        // Create a separate audio engine for VAD
        vadAudioEngine = AVAudioEngine()
        vadInputNode = vadAudioEngine?.inputNode
        
        guard let vadEngine = vadAudioEngine, let inputNode = vadInputNode else {
            let errorMsg = "Failed to create VAD audio engine"
            Task { @MainActor in
                self.errorMessage = errorMsg
            }
            print("🎤 VAD ERROR: Failed to create audio engine or input node")
            return
        }
        
        // Get the recording format
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        print("🎤 VAD FORMAT: Recording format - Sample Rate: \(recordingFormat.sampleRate), Channels: \(recordingFormat.channelCount)")
        
        // CRITICAL FIX: Enhanced buffer configuration for better streaming
        let bufferSize: AVAudioFrameCount = elderlyModeEnabled ? 256 : 512 // Smaller buffers for better responsiveness
        print("🎤 VAD BUFFER: Using buffer size: \(bufferSize)")
        
        // Install tap on input node with optimized buffer for elderly users
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, self.isVADEnabled else { return }
            
            // Calculate audio power level with enhanced sensitivity for elderly users
            let audioBuffer = buffer.audioBufferList.pointee.mBuffers
            if let channelData = audioBuffer.mData {
                let channelDataSize = Int(audioBuffer.mDataByteSize)
                let samples = channelDataSize / MemoryLayout<Float>.size
                let floatData = channelData.bindMemory(to: Float.self, capacity: samples)
                
                var sum: Float = 0
                var peakPower: Float = 0
                
                // Calculate both average and peak power
                for i in 0..<samples {
                    let sample = abs(floatData[i])
                    sum += sample
                    peakPower = max(peakPower, sample)
                }
                
                let averagePower = sum / Float(samples)
                
                // CRITICAL FIX: Much more sensitive threshold calculation
                var adjustedThreshold = self.vadPowerThreshold * Float(1.0 - self.vadSensitivity * 0.95)
                if self.elderlyModeEnabled {
                    adjustedThreshold *= 0.3 // MUCH more sensitive for elderly users
                }
                
                // CRITICAL: Set minimum threshold to catch very quiet speech
                adjustedThreshold = max(adjustedThreshold, 0.0005) // Even lower minimum
                
                // Enhanced voice detection using both metrics
                let isVoiceDetected = averagePower > adjustedThreshold || peakPower > adjustedThreshold * 1.5
                
                if isVoiceDetected {
                    self.consecutiveVoiceFrames += 1
                    self.vadSilenceFrames = 0
                    
                    // Enhanced debug logging for voice detection
                    if self.consecutiveVoiceFrames % 2 == 0 { // Log every 2 frames
                        print("🎤 VAD VOICE: Detected - frames: \(self.consecutiveVoiceFrames), avgPower: \(String(format: "%.6f", averagePower)), peakPower: \(String(format: "%.6f", peakPower)), threshold: \(String(format: "%.6f", adjustedThreshold))")
                    }
                    
                    // CRITICAL FIX: Start recording much faster and ensure it always triggers
                    let requiredFrames = self.elderlyModeEnabled ? 2 : 3 // Very fast trigger
                    if self.consecutiveVoiceFrames >= requiredFrames && !self.isRecording && !self.isProcessingRecognition {
                        // CRITICAL: Reset consecutive frames to prevent multiple triggers
                        self.consecutiveVoiceFrames = 0
                        
                        // CRITICAL FIX: Ensure all UI updates happen on main thread
                        Task { @MainActor in
                            // Double-check we're not already recording or processing
                            guard !self.isRecording && !self.isProcessingRecognition else {
                                print("🎤 VAD SKIP: Already recording or processing, skipping trigger")
                                return
                            }
                            
                            print("🎤 VAD TRIGGER: Voice detected - triggering voice detection callback!")
                            print("🎤 VAD STATS: avgPower: \(String(format: "%.6f", averagePower)), peakPower: \(String(format: "%.6f", peakPower)), threshold: \(String(format: "%.6f", adjustedThreshold))")
                            
                            // Use callback if available, otherwise fall back to direct recording
                            if let callback = self.onVADVoiceDetected {
                                print("🎤 VAD CALLBACK: Executing VAD callback")
                                callback()
                            } else {
                                print("🎤 VAD DIRECT: No callback, starting recording directly")
                                self.startRecording()
                            }
                        }
                    }
                } else {
                    self.vadSilenceFrames += 1
                    self.consecutiveVoiceFrames = 0
                    
                    // Debug logging for silence (less frequent)
                    if self.vadSilenceFrames % 50 == 0 && self.isRecording {
                        print("🎤 VAD SILENCE: Detected for \(self.vadSilenceFrames) frames while recording")
                    }
                }
            }
        }
        
        // Start VAD audio engine with enhanced error handling
        do {
            print("🎤 VAD ENGINE: Preparing audio engine...")
            vadEngine.prepare()
            print("🎤 VAD ENGINE: Audio engine prepared, attempting to start...")
            try vadEngine.start()
            print("🎤 VAD ENGINE: Start command executed, checking if running...")
            
            // CRITICAL FIX: Verify engine actually started
            if vadEngine.isRunning {
                print("🎤 VAD ENGINE: ✅ Engine is running successfully!")
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.isVADActive = true
                    print("🎤 VAD STATE: isVADActive set to true")
                }
                print("🎤 VAD SUCCESS: Voice Activity Detection started successfully!")
                print("🎤 VAD CONFIG: Elderly mode: \(elderlyModeEnabled), Sensitivity: \(vadSensitivity)")
                
                // CRITICAL FIX: Schedule a health check
                DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                    print("🎤 VAD HEALTH: Scheduling first health check...")
                    self?.performVADHealthCheck()
                }
            } else {
                let errorMsg = "VAD audio engine failed to start properly - engine.isRunning = false"
                print("🎤 VAD ENGINE: ❌ \(errorMsg)")
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.errorMessage = errorMsg
                    self.isVADActive = false
                    print("🎤 VAD STATE: isVADActive set to false due to engine failure")
                }
                print("🎤 VAD ERROR: \(errorMsg)")
            }
        } catch {
            let errorMsg = "Failed to start VAD audio engine: \(error.localizedDescription)"
            print("🎤 VAD ENGINE: ❌ Exception caught: \(errorMsg)")
            print("🎤 VAD ENGINE: Error details: \(error)")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.errorMessage = errorMsg
                self.isVADActive = false
                print("🎤 VAD STATE: isVADActive set to false due to exception")
            }
            print("🎤 VAD ERROR: \(errorMsg)")
        }
    }
    
    // CRITICAL FIX: Add VAD health check to prevent silent failures
    private func performVADHealthCheck() {
        print("🎤 VAD HEALTH: Performing health check")
        
        guard isVADEnabled else {
            print("🎤 VAD HEALTH: VAD disabled, skipping health check")
            return
        }
        
        if let vadEngine = vadAudioEngine {
            if !vadEngine.isRunning {
                print("🎤 VAD HEALTH: Engine stopped running - attempting restart")
                
                Task {
                    await startVoiceActivityDetection()
                }
            } else {
                print("🎤 VAD HEALTH: Engine running normally")
                
                // Schedule next health check
                DispatchQueue.main.asyncAfter(deadline: .now() + 30.0) { [weak self] in
                    self?.performVADHealthCheck()
                }
            }
        } else {
            print("🎤 VAD HEALTH: No engine found - attempting restart")
            
            Task {
                await startVoiceActivityDetection()
            }
        }
    }
    
    /// Stop Voice Activity Detection
    func stopVoiceActivityDetection() {
        if vadAudioEngine?.isRunning == true {
            vadInputNode?.removeTap(onBus: 0)
            vadAudioEngine?.stop()
        }
        isVADActive = false
        
        // Also stop any ongoing recording
        if isRecording {
            stopRecording()
        }
        
        // Reset all state variables
        consecutiveVoiceFrames = 0
        vadSilenceFrames = 0
        print("VAD deactivated successfully")
    }
    
    /// Update VAD sensitivity (0.0-1.0 range, higher = more sensitive)
    func updateVADSensitivity(_ sensitivity: Double) {
        vadSensitivity = min(max(sensitivity, 0.0), 1.0)
    }
    
    // MARK: - Speech Recognition
    
    // Start recording and recognizing speech
    func startRecording() {
        print("🎤 RECORDING START: startRecording called")
        
        // Reset previous recording session
        resetRecording()
        
        // Reset processing state
        isProcessingRecognition = false
        
        // Reset last processed text to avoid duplicate tasks
        lastProcessedText = ""
        
        // Store empty string for transcribed text
        storedTranscribedText = ""
        
        // Clear subtitle text
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.subtitleText = ""
            self.correctedTranscript = ""
            self.speechConfidence = 0.0
        }
        
        // CRITICAL FIX: Enhanced audio session configuration for recording
        let audioSession = AVAudioSession.sharedInstance()
        do {
            print("🎤 RECORDING AUDIO: Configuring audio session for recording...")
            
            if elderlyModeEnabled {
                // Enhanced configuration for elderly users
                try audioSession.setCategory(.record, mode: .spokenAudio, options: [.allowBluetooth, .mixWithOthers, .defaultToSpeaker])
                try audioSession.setPreferredSampleRate(16000) // Optimal for speech recognition
                try audioSession.setPreferredIOBufferDuration(0.005) // Very low latency for better streaming
                print("🎤 RECORDING AUDIO: Set elderly-friendly recording parameters (16kHz, 5ms buffer)")
            } else {
                try audioSession.setCategory(.record, mode: .measurement, options: [.mixWithOthers])
                try audioSession.setPreferredSampleRate(44100) // Higher quality
                try audioSession.setPreferredIOBufferDuration(0.01) // Low latency
                print("🎤 RECORDING AUDIO: Set standard recording parameters (44.1kHz, 10ms buffer)")
            }
            
            // CRITICAL: Ensure audio session is active
            try audioSession.setActive(true)
            print("🎤 RECORDING AUDIO: Audio session activated for recording")
            
        } catch {
            let errorMsg = "Failed to set up audio session for recording: \(error.localizedDescription)"
            errorMessage = errorMsg
            print("🎤 RECORDING ERROR: \(errorMsg)")
            return
        }
        
        // CRITICAL: Check microphone permission before proceeding
        if #available(iOS 17.0, *) {
            Task {
                let granted = await AVAudioApplication.requestRecordPermission()
                print("🎤 RECORDING PERMISSION: Microphone permission granted: \(granted)")
                
                if !granted {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.errorMessage = "Microphone permission denied - please enable in Settings > Privacy & Security > Microphone"
                    }
                    return
                }
                
                // Continue with recording setup on main thread
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.continueRecordingSetup()
                }
            }
        } else {
            audioSession.requestRecordPermission { [weak self] granted in
                guard let self = self else { return }
                
                print("🎤 RECORDING PERMISSION: Microphone permission granted: \(granted)")
                
                if !granted {
                    DispatchQueue.main.async {
                        self.errorMessage = "Microphone permission denied - please enable in Settings > Privacy & Security > Microphone"
                    }
                    return
                }
                
                // Continue with recording setup on main thread
                DispatchQueue.main.async {
                    self.continueRecordingSetup()
                }
            }
        }
    }
    
    // CRITICAL: Separate method to continue recording setup after permission check
    private func continueRecordingSetup() {
        print("🎤 RECORDING SETUP: Continuing with recording setup...")
        
        // Create recognition request with enhanced configuration
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        // Get input node
        let inputNode = audioEngine.inputNode
        
        // Apply noise suppression filter if enabled
        if let filter = noiseFilter, noiseSuppressionLevel > 0 {
            print("🎤 RECORDING FILTER: Applying noise suppression filter")
            audioEngine.attach(filter)
            audioEngine.connect(inputNode, to: filter, format: inputNode.outputFormat(forBus: 0))
            audioEngine.connect(filter, to: audioEngine.mainMixerNode, format: inputNode.outputFormat(forBus: 0))
        }
        
        // Check microphone availability
        guard let recognitionRequest = recognitionRequest else {
            errorMessage = "Unable to create recognition request"
            print("🎤 RECORDING ERROR: Failed to create recognition request")
            return
        }
        
        // Configure request for enhanced recognition
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation // Optimize for continuous speech
        
        // Enhanced settings for elderly users
        if elderlyModeEnabled {
            recognitionRequest.requiresOnDeviceRecognition = false // Use server-based for better accuracy
            print("🎤 RECORDING CONFIG: Using server-based recognition for elderly mode")
        } else {
            print("🎤 RECORDING CONFIG: Using standard recognition settings")
        }
        
        // Apply accent tolerance settings
        enhanceAccentRecognition()
        
        // Track recording start time for slow speech detection
        let recordingStartTime = Date()
        print("🎤 RECORDING TIMING: Recording started at \(recordingStartTime)")
        
        // Start recognition task with enhanced processing
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            var isFinal = false
            
            if let result = result {
                let transcription = result.bestTranscription.formattedString
                let confidence = result.bestTranscription.segments.last?.confidence ?? 0.0
                
                // Enhanced logging for transcription
                if !transcription.isEmpty {
                    print("🎤 TRANSCRIPTION: '\(transcription)' (confidence: \(String(format: "%.2f", confidence)))")
                }
                
                // Detect slow speech
                let timeElapsed = Date().timeIntervalSince(recordingStartTime)
                self.detectSlowSpeech(from: transcription, timeInterval: timeElapsed)
                
                // Update subtitles in real-time
                self.updateSubtitles(with: transcription, confidence: confidence)
                
                DispatchQueue.main.async {
                    // Only update if the text has actually changed
                    if self.transcribedText != transcription {
                        withAnimation(.easeInOut(duration: 0.1)) {
                            self.transcribedText = transcription
                        }
                        
                        if self.isRecording {
                            self.isListening = true
                        }
                    }
                }
                
                isFinal = result.isFinal
                
                // Store the transcribed text for processing when finished
                if isFinal {
                    // Apply stutter removal and corrections
                    let cleanedText = self.removeStutters(from: transcription)
                    self.storedTranscribedText = cleanedText
                    
                    print("🎤 FINAL TRANSCRIPTION: '\(cleanedText)'")
                    
                    // Update final corrected transcript
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.correctedTranscript = cleanedText
                    }
                }
                
                // Reset silence timer when new text comes in
                self.resetSilenceTimer()
            }
            
            // Handle errors or completion
            if error != nil || isFinal {
                if let error = error {
                    print("🎤 RECOGNITION ERROR: \(error.localizedDescription)")
                }
                
                // Stop audio engine and clean up
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                // Update state on main thread
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.isListening = false
                    self.isRecording = false
                    
                    // Process final text if we have it
                    if !self.isProcessingRecognition {
                        self.isProcessingRecognition = true
                        
                        // Use corrected transcript if available, otherwise use stored text
                        let finalText = self.correctedTranscript.isEmpty ? 
                            (self.storedTranscribedText.isEmpty ? self.transcribedText : self.storedTranscribedText) : 
                            self.correctedTranscript
                        
                        print("🎤 PROCESSING: Final text for processing: '\(finalText)'")
                        
                        // Check if we have text to process and it hasn't been processed already
                        if !finalText.isEmpty && finalText != self.lastProcessedText {
                            self.lastProcessedText = finalText
                            
                            // Process the task text
                            let (title, dueDate) = self.processTaskText(finalText)
                            print("🎤 TASK EXTRACTED: Title: '\(title)', Due Date: \(String(describing: dueDate))")
                            
                            // Clear the transcribed text after processing
                            self.transcribedText = ""
                            
                            // Call completion handler
                            print("🎤 COMPLETION: Calling onRecognitionComplete")
                            self.onRecognitionComplete?(title, dueDate)
                            
                            // Reset processing state
                            self.isProcessingRecognition = false
                        } else {
                            // If there's no text to process, still notify completion
                            self.transcribedText = ""
                            self.onRecognitionComplete?("", nil)
                            self.isProcessingRecognition = false
                        }
                    }
                }
            }
        }
        
        // Configure audio recording with enhanced buffer settings for elderly users
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        let bufferSize: AVAudioFrameCount = elderlyModeEnabled ? 256 : 512 // Optimized buffer sizes for better streaming
        
        print("🎤 RECORDING FORMAT: Sample Rate: \(recordingFormat.sampleRate), Channels: \(recordingFormat.channelCount), Buffer Size: \(bufferSize)")
        
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            // Add incoming audio to the recognition request
            self.recognitionRequest?.append(buffer)
            
            // Enhanced silence detection with elderly-friendly thresholds
            let audioBuffer = buffer.audioBufferList.pointee.mBuffers
            if let channelData = audioBuffer.mData {
                let channelDataSize = Int(audioBuffer.mDataByteSize)
                let samples = channelDataSize / MemoryLayout<Float>.size
                let floatData = channelData.bindMemory(to: Float.self, capacity: samples)
                
                var sum: Float = 0
                var peakPower: Float = 0
                
                // Calculate both average and peak power
                for i in 0..<samples {
                    let sample = abs(floatData[i])
                    sum += sample
                    peakPower = max(peakPower, sample)
                }
                
                let averagePower = sum / Float(samples)
                
                // Adjust thresholds for elderly users
                let adjustedPowerThreshold = self.elderlyModeEnabled ? self.powerThreshold * 0.8 : self.powerThreshold
                let adjustedPeakThreshold = adjustedPowerThreshold * 2
                
                if averagePower < adjustedPowerThreshold && peakPower < adjustedPeakThreshold {
                    self.consecutiveSilenceFrames += 1
                    
                    // Adjust required silence frames for elderly users
                    let requiredFrames = self.elderlyModeEnabled ? self.requiredSilenceFrames * 2 : self.requiredSilenceFrames
                    
                    if self.consecutiveSilenceFrames >= requiredFrames {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.startSilenceTimer()
                        }
                    }
                } else {
                    self.consecutiveSilenceFrames = 0
                    
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        self.resetSilenceTimer()
                        
                        if self.isRecording && !self.isListening {
                            self.isListening = true
                        }
                    }
                }
            }
        }
        
        // Start audio engine with enhanced error handling
        do {
            try audioEngine.start()
            
            print("🎤 RECORDING SUCCESS: Audio engine started successfully!")
            
            // Update state on main thread
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isRecording = true
                self.isListening = true
                self.errorMessage = nil
                print("🎤 RECORDING STATE: Recording active - isRecording: true, isListening: true")
                
                // Start maximum recording timer with extended duration for elderly users
                let maxDuration = self.elderlyModeEnabled ? self.maxRecordingDuration * 1.5 : self.maxRecordingDuration
                self.maxRecordingTimer = Timer.scheduledTimer(withTimeInterval: maxDuration, repeats: false) { [weak self] _ in
                    guard let self = self, self.isRecording else { return }
                    print("🎤 RECORDING TIMEOUT: Maximum recording time reached - stopping")
                    self.stopRecording()
                }
            }
        } catch {
            let errorMsg = "Failed to start audio engine for recording: \(error.localizedDescription)"
            errorMessage = errorMsg
            print("🎤 RECORDING ERROR: \(errorMsg)")
        }
    }
    
    // Stop recording
    func stopRecording() {
        print("RECORDING DEBUG: stopRecording called")
        
        // Invalidate silence timer
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        // Invalidate maximum recording timer
        maxRecordingTimer?.invalidate()
        maxRecordingTimer = nil
        
        // Invalidate debounce timer
        processingDebounceTimer?.invalidate()
        processingDebounceTimer = nil
        
        // Immediately set UI state to not listening - this helps hide the streaming box faster
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.isListening = false
        }
        
        // Store current text before clearing it
        let currentText = transcribedText
        
        // Immediately clear transcribed text to ensure UI updates
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.transcribedText = ""
        }
        
        // Stop audio engine if running
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            recognitionRequest?.endAudio()
            
            // Use main thread for UI-related state changes
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.isRecording = false
                
                // Process any final transcription if we have text and it hasn't been processed
                if !currentText.isEmpty && currentText != self.lastProcessedText {
                    self.lastProcessedText = currentText
                    let (title, dueDate) = self.processTaskText(currentText)
                    
                    // Call completion handler with the extracted task - IMMEDIATELY
                    print("PROCESSING: Calling onRecognitionComplete with title: '\(title)'")
                    self.onRecognitionComplete?(title, dueDate)
                    
                    // Reset processing state immediately for faster response
                    self.isProcessingRecognition = false
                    print("PROCESSING: Reset isProcessingRecognition to false immediately")
                } else {
                    // If there's no text to process, still notify completion to hide UI
                    print("PROCESSING: Calling onRecognitionComplete with empty text")
                    self.onRecognitionComplete?("", nil)
                    
                    // Reset processing state immediately
                    self.isProcessingRecognition = false
                }
            }
        }
    }
    
    // Reset the recording session
    public func resetRecording() {
        // Cancel any ongoing recognition tasks
        recognitionTask?.cancel()
        recognitionTask = nil
        
        // Reset all state variables
        isListening = false
        isProcessingRecognition = false
        transcribedText = ""
        
        // Stop audio engine if running
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }
    
    // Reset transcription text
    func resetTranscription() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.transcribedText = ""
            self.lastProcessedText = ""
            self.storedTranscribedText = ""
            self.correctedTranscript = ""
            self.isProcessingRecognition = false
            
            // CRITICAL FIX: Reset VAD state for continuous listening
            self.consecutiveVoiceFrames = 0
            self.vadSilenceFrames = 0
            
            print("🎤 RESET: All transcription and processing state reset for next command")
        }
    }
    
    // CRITICAL FIX: Method to restart VAD after task processing
    func restartVADIfNeeded() {
        print("VAD RESTART: Checking if VAD needs restart")
        
        // Always restart VAD if it's not active, regardless of isVADEnabled flag
        if !isVADActive {
            print("VAD RESTART: VAD not active, restarting immediately")
            
            // Reset all state first
            resetRecording()
            resetTranscription()
            
            // Enable VAD and start it immediately for faster response
            isVADEnabled = true
            Task {
                await self.startVoiceActivityDetection()
            }
            print("VAD RESTART: VAD restarted immediately")
        } else {
            print("VAD RESTART: VAD already active, no restart needed")
        }
    }
    
    // FORCE restart VAD - ensures it always restarts for multiple tasks
    func forceRestartVAD() {
        print("🎤 FORCE RESTART: Starting force VAD restart for multiple commands")
        
        // CRITICAL: Stop everything immediately and synchronously first
        if isVADActive {
            print("🎤 FORCE RESTART: Stopping current VAD synchronously")
            stopVoiceActivityDetection()
        }
        
        if isRecording {
            print("🎤 FORCE RESTART: Stopping current recording synchronously")
            stopRecording()
        }
        
        // Reset all state variables synchronously
        print("🎤 FORCE RESTART: Resetting all state variables synchronously")
        resetRecording()
        resetTranscription()
        
        // Reset VAD-specific state
        consecutiveVoiceFrames = 0
        vadSilenceFrames = 0
        isProcessingRecognition = false
        lastProcessedText = ""
        
        // Clear any stored text
        storedTranscribedText = ""
        correctedTranscript = ""
        transcribedText = ""
        
        // CRITICAL FIX: Use a very short delay to ensure audio system is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            print("🎤 FORCE RESTART: Starting VAD after brief delay...")
            
            // Force enable VAD
            self.isVADEnabled = true
            
            // Start VAD immediately
            Task {
                await self.startVoiceActivityDetection()
            }
            
            print("🎤 FORCE RESTART: VAD force restart completed - ready for next command")
        }
    }
    
    // Process task text with natural language processing for better date extraction
    func processTaskText(_ text: String) -> (String, Date?) {
        guard !text.isEmpty else { 
            print("DEBUG: processTaskText received empty text")
            return ("", nil) 
        }
        
        print("DEBUG: processTaskText received: '\(text)'")
        
        var taskTitle = text
        var dueDate: Date?
        var timeSpecified = false
        
        // Common date patterns to search for - Fixed to use proper dictionary type
        let datePatterns: [String: Date?] = [
            // Relative dates - with explicit date references
            "today": Calendar.current.startOfDay(for: Date()),
            "tomorrow": Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: Date())),
            "next week": Calendar.current.date(byAdding: .weekOfYear, value: 1, to: Calendar.current.startOfDay(for: Date()))
        ]
        
        // Dictionary for day of week patterns
        let weekdayPatterns: [String: Int] = [
            "sunday": 1, "monday": 2, "tuesday": 3, "wednesday": 4, 
            "thursday": 5, "friday": 6, "saturday": 7
        ]
        
        // First check for common patterns
        let lowercasedText = text.lowercased()
        print("DEBUG: lowercased text: '\(lowercasedText)'")
        
        // ENHANCED: Check for "in X minutes" patterns first
        if let minutesFromNow = extractMinutesFromText(lowercasedText) {
            print("DEBUG: Found minutes from now: \(minutesFromNow)")
            // Calculate exact time from now
            dueDate = Calendar.current.date(byAdding: .minute, value: minutesFromNow, to: Date())
            
            // Remove the time reference from the task title
            taskTitle = removeTimeReferencesFromText(text, lowercasedText)
            timeSpecified = true
            print("DEBUG: Extracted task title after removing time: '\(taskTitle)'")
            print("DEBUG: Due date set to: \(String(describing: dueDate))")
        }
        
        // Time extraction - Look for time patterns
        var extractedHour: Int?
        var extractedMinute: Int?
        var isPM = false
        
        // First check for time patterns in the entire text (only if no minutes-from-now found)
        if dueDate == nil && extractTimeFromText(lowercasedText, &extractedHour, &extractedMinute, &isPM) {
            timeSpecified = true
        }
        
        // Enhanced weekday detection - handle "next", "coming", and "this" modifiers
        for (weekday, weekdayNumber) in weekdayPatterns {
            // Check for patterns like "next wednesday", "coming wednesday", or "this wednesday"
            let nextWeekdayPattern = "next \(weekday)"
            let comingWeekdayPattern = "coming \(weekday)"
            let thisWeekdayPattern = "this \(weekday)"
            
            if lowercasedText.contains(nextWeekdayPattern) {
                // For "next" weekday, always add 7 days to the next occurrence
                dueDate = nextWeekdayWithOffset(weekdayNumber, offset: 7)
                
                // Remove the date reference from the task title
                if let range = lowercasedText.range(of: nextWeekdayPattern) {
                    let originalRange = text.range(of: text[range])!
                    taskTitle = text.replacingCharacters(in: originalRange, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                break
            } else if lowercasedText.contains(comingWeekdayPattern) {
                // For "coming" weekday, behavior same as "next"
                dueDate = nextWeekdayWithOffset(weekdayNumber, offset: 7)
                
                // Remove the date reference from the task title
                if let range = lowercasedText.range(of: comingWeekdayPattern) {
                    let originalRange = text.range(of: text[range])!
                    taskTitle = text.replacingCharacters(in: originalRange, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                break
            } else if lowercasedText.contains(thisWeekdayPattern) {
                // For "this" weekday, use the current week's day
                dueDate = nextWeekdayWithOffset(weekdayNumber, offset: 0)
                
                // Remove the date reference from the task title
                if let range = lowercasedText.range(of: thisWeekdayPattern) {
                    let originalRange = text.range(of: text[range])!
                    taskTitle = text.replacingCharacters(in: originalRange, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
                break
            }
        }
        
        // Look for "due" or "by" followed by a date reference
        let dateKeywords = ["due", "by", "on", "for", "at"]
        
        for keyword in dateKeywords {
            if let range = lowercasedText.range(of: "\(keyword) ") {
                let afterKeyword = String(lowercasedText[range.upperBound...])
                
                // Check for direct matches like "tomorrow", "today", etc.
                for (pattern, patternDate) in datePatterns {
                    if afterKeyword.contains(pattern), let dateValue = patternDate {
                        dueDate = dateValue
                        
                        // Remove the date part from the title
                        if let fullRange = lowercasedText.range(of: "\(keyword) \(pattern)") {
                            let originalFullRange = text.range(of: text[fullRange])!
                            taskTitle = String(text[..<originalFullRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                        break
                    }
                }
                
                // Check for weekday names if no match found yet
                if dueDate == nil {
                    for (weekday, weekdayNumber) in weekdayPatterns {
                        if afterKeyword.contains(weekday) {
                            // Calculate the next occurrence of this weekday
                            dueDate = nextWeekday(weekdayNumber)
                            
                            // Remove the date part from the title
                            if let fullRange = lowercasedText.range(of: "\(keyword) \(weekday)") {
                                let originalFullRange = text.range(of: text[fullRange])!
                                taskTitle = String(text[..<originalFullRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                            break
                        }
                    }
                }
                
                // If still no match, try to parse a specific date
                if dueDate == nil {
                    // Try to extract more complex date patterns
                    let dateExtractor = DateExtractor()
                    if let extractedDate = dateExtractor.extractDate(from: afterKeyword) {
                        dueDate = extractedDate
                        
                        // For complex dates, we'll just use the first part of the string as the task
                        if let rangeOfKeyword = text.range(of: keyword) {
                            taskTitle = String(text[..<rangeOfKeyword.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                }
                
                // Break after finding the first date keyword
                if dueDate != nil {
                    break
                }
            }
        }
        
        // If no date was found with keywords, try looking for standalone date references
        if dueDate == nil {
            // Check for standalone relative dates like "today", "tomorrow", "next week"
            for (pattern, patternDate) in datePatterns {
                if lowercasedText.contains(pattern), let dateValue = patternDate {
                    dueDate = dateValue
                    
                    // Log the actual date detected for debugging
                    let formatter = DateFormatter()
                    formatter.dateFormat = "MMMM d, yyyy"
                    print("Date detected from '\(pattern)': \(formatter.string(from: dateValue))")
                    
                    // Try to remove the date part from title
                    if let range = lowercasedText.range(of: pattern) {
                        let originalRange = text.range(of: text[range])!
                        
                        // Check if the pattern is at the end of the string
                        if originalRange.upperBound == text.endIndex {
                            taskTitle = String(text[..<originalRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        } else if originalRange.lowerBound == text.startIndex {
                            taskTitle = String(text[originalRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        } else {
                            // If pattern is in the middle, replace it with a placeholder and then remove it
                            taskTitle = text.replacingCharacters(in: originalRange, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                        }
                    }
                    break
                }
            }
            
            // If still no date found, check for weekday names
            if dueDate == nil {
                for (weekday, weekdayNumber) in weekdayPatterns {
                    if lowercasedText.contains(weekday) {
                        // Calculate the next occurrence of this weekday
                        dueDate = nextWeekday(weekdayNumber)
                        
                        // Try to remove the weekday from the title
                        if let range = lowercasedText.range(of: weekday) {
                            let originalRange = text.range(of: text[range])!
                            
                            // Check if the weekday is at the end of the string
                            if originalRange.upperBound == text.endIndex {
                                taskTitle = String(text[..<originalRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                            } else if originalRange.lowerBound == text.startIndex {
                                taskTitle = String(text[originalRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                        break
                    }
                }
            }
        }
        
        // Final cleanup of task title
        taskTitle = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Clean up task title by removing common prefixes and filler words
        let commonPrefixes = ["I need to", "I want to", "I have to", "Remember to", "Don't forget to", "Please", "Can you", "Remind me to"]
        for prefix in commonPrefixes {
            if taskTitle.lowercased().hasPrefix(prefix.lowercased()) {
                taskTitle = String(taskTitle.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
                break
            }
        }
        
        // If we have a date and time was specified, set the time components
        if dueDate != nil && timeSpecified && extractedHour != nil {
            let calendar = Calendar.current
            var dateComponents = calendar.dateComponents([.year, .month, .day], from: dueDate!)
            
            // Set the hour and minute components
            dateComponents.hour = extractedHour!
            // Adjust for PM if needed
            if isPM && extractedHour! < 12 {
                dateComponents.hour! += 12
            }
            // Handle 12 AM edge case
            if !isPM && extractedHour! == 12 {
                dateComponents.hour! = 0
            }
            
            dateComponents.minute = extractedMinute ?? 0
            dateComponents.second = 0
            
            // Create the new date with time
            if let newDateWithTime = calendar.date(from: dateComponents) {
                dueDate = newDateWithTime
            }
        }
        
        // Capitalize first letter of task title
        if !taskTitle.isEmpty {
            let firstChar = taskTitle.prefix(1).capitalized
            let restOfTitle = taskTitle.dropFirst()
            taskTitle = firstChar + restOfTitle
        }
        
        print("DEBUG: Final task title: '\(taskTitle)'")
        print("DEBUG: Final due date: \(String(describing: dueDate))")
        
        return (taskTitle, dueDate)
    }
    
    // Helper method to find the next occurrence of a specific weekday with optional offset
    private func nextWeekdayWithOffset(_ weekday: Int, offset: Int) -> Date {
        let today = Calendar.current.startOfDay(for: Date())
        let todayWeekday = Calendar.current.component(.weekday, from: today)
        
        var daysToAdd = weekday - todayWeekday
        
        // If weekday has already occurred this week
        if daysToAdd <= 0 {
            // For "this weekday" when it's already passed, use next week
            daysToAdd += 7
        }
        
        // Add additional offset (for "next" we add 7 more days)
        daysToAdd += offset
        
        return Calendar.current.date(byAdding: .day, value: daysToAdd, to: today)!
    }
    
    // Keep the original nextWeekday method for backward compatibility
    private func nextWeekday(_ weekday: Int) -> Date {
        return nextWeekdayWithOffset(weekday, offset: 0)
    }
    
    private func startSilenceTimer() {
        // Only start timer if not already running
        if silenceTimer == nil {
            print("SILENCE DEBUG: Starting silence timer (\(silenceThreshold) seconds)")
            silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
                guard let self = self, self.isRecording else { return }
                
                print("SILENCE DEBUG: Silence timer triggered - stopping recording")
                // Stop recording after silence period
                self.stopRecording()
            }
        }
    }
    
    private func resetSilenceTimer() {
        if silenceTimer != nil {
            print("SILENCE DEBUG: Resetting silence timer")
        }
        silenceTimer?.invalidate()
        silenceTimer = nil
    }
    
    // Helper method to extract time from text
    private func extractTimeFromText(_ text: String, _ hour: inout Int?, _ minute: inout Int?, _ isPM: inout Bool) -> Bool {
        // Look for time patterns like "at 3 PM", "at 10:30 AM", etc.
        
        // Pattern 1: Simple time with AM/PM - "3 PM", "10 AM", etc.
        let simpleTimePattern = #"(\d{1,2})\s*(am|pm)"#
        if let timeRange = text.range(of: simpleTimePattern, options: .regularExpression) {
            let timeText = String(text[timeRange])
            let components = timeText.components(separatedBy: CharacterSet.letters.union(CharacterSet.whitespaces))
            let filteredComponents = components.filter { !$0.isEmpty }
            
            if let hourValue = Int(filteredComponents[0]) {
                hour = hourValue
                minute = 0
                isPM = timeText.lowercased().contains("pm")
                return true
            }
        }
        
        // Pattern 2: Time with colon and AM/PM - "3:30 PM", "10:15 AM", etc.
        let colonTimePattern = #"(\d{1,2}):(\d{2})\s*(am|pm)"#
        if let timeRange = text.range(of: colonTimePattern, options: .regularExpression) {
            let timeText = String(text[timeRange])
            let components = timeText.components(separatedBy: CharacterSet(charactersIn: ": "))
            let filteredComponents = components.filter { !$0.isEmpty }
            
            if filteredComponents.count >= 2,
               let hourValue = Int(filteredComponents[0]),
               let minuteValue = Int(filteredComponents[1]) {
                hour = hourValue
                minute = minuteValue
                isPM = timeText.lowercased().contains("pm")
                return true
            }
        }
        
        // Pattern 3: 24-hour format - "14:30", "09:15", etc.
        let twentyFourHourPattern = #"(\d{1,2}):(\d{2})"#
        if let timeRange = text.range(of: twentyFourHourPattern, options: .regularExpression) {
            let timeText = String(text[timeRange])
            let components = timeText.components(separatedBy: ":")
            
            if components.count == 2,
               let hourValue = Int(components[0]),
               let minuteValue = Int(components[1]),
               hourValue >= 0 && hourValue <= 23 &&
               minuteValue >= 0 && minuteValue <= 59 {
                hour = hourValue
                minute = minuteValue
                isPM = hourValue >= 12
                return true
            }
        }
        
        return false
    }
    
    // ENHANCED: Helper method to extract minutes from "in X minutes" patterns
    private func extractMinutesFromText(_ text: String) -> Int? {
        print("DEBUG: extractMinutesFromText called with: '\(text)'")
        
        // Patterns to match: "in 5 minutes", "in 10 min", "next 15 minutes", "in five minutes"
        let patterns = [
            #"in\s+(\d+)\s+minutes?"#,           // "in 5 minutes", "in 10 minute"
            #"in\s+(\d+)\s+mins?"#,              // "in 5 mins", "in 10 min"
            #"next\s+(\d+)\s+minutes?"#,         // "next 5 minutes"
            #"next\s+(\d+)\s+mins?"#,            // "next 5 mins"
            #"after\s+(\d+)\s+minutes?"#,        // "after 5 minutes"
            #"after\s+(\d+)\s+mins?"#            // "after 5 mins"
        ]
        
        // Also handle written numbers
        let writtenNumbers = [
            "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
            "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
            "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14, "fifteen": 15,
            "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60
        ]
        
        // Check numeric patterns first
        for (index, pattern) in patterns.enumerated() {
            print("DEBUG: Checking pattern \(index): \(pattern)")
            if let range = text.range(of: pattern, options: .regularExpression) {
                let matchText = String(text[range])
                print("DEBUG: Found match: '\(matchText)'")
                // Extract the number from the match
                let numberPattern = #"\d+"#
                if let numberRange = matchText.range(of: numberPattern, options: .regularExpression) {
                    let numberText = String(matchText[numberRange])
                    if let minutes = Int(numberText) {
                        print("DEBUG: Extracted minutes: \(minutes)")
                        return minutes
                    }
                }
            }
        }
        
        // Check written number patterns
        let writtenPatterns = [
            #"in\s+(\w+)\s+minutes?"#,           // "in five minutes"
            #"next\s+(\w+)\s+minutes?"#,         // "next ten minutes"
            #"after\s+(\w+)\s+minutes?"#         // "after fifteen minutes"
        ]
        
        for pattern in writtenPatterns {
            if let range = text.range(of: pattern, options: .regularExpression) {
                let matchText = String(text[range]).lowercased()
                for (word, number) in writtenNumbers {
                    if matchText.contains(word) {
                        return number
                    }
                }
            }
        }
        
        return nil
    }
    
    // ENHANCED: Helper method to remove time references from text
    private func removeTimeReferencesFromText(_ originalText: String, _ lowercaseText: String) -> String {
        print("DEBUG: removeTimeReferencesFromText called with original: '\(originalText)', lowercase: '\(lowercaseText)'")
        
        var cleanedText = originalText
        
        // Patterns to remove
        let patternsToRemove = [
            #"in\s+\d+\s+minutes?"#,
            #"in\s+\d+\s+mins?"#,
            #"next\s+\d+\s+minutes?"#,
            #"next\s+\d+\s+mins?"#,
            #"after\s+\d+\s+minutes?"#,
            #"after\s+\d+\s+mins?"#,
            #"in\s+\w+\s+minutes?"#,     // for written numbers
            #"next\s+\w+\s+minutes?"#,
            #"after\s+\w+\s+minutes?"#
        ]
        
        for (index, pattern) in patternsToRemove.enumerated() {
            print("DEBUG: Checking removal pattern \(index): \(pattern)")
            if let range = lowercaseText.range(of: pattern, options: .regularExpression) {
                print("DEBUG: Found pattern to remove: '\(String(lowercaseText[range]))'")
                // Find corresponding range in original text
                let startIndex = originalText.index(originalText.startIndex, offsetBy: lowercaseText.distance(from: lowercaseText.startIndex, to: range.lowerBound))
                let endIndex = originalText.index(originalText.startIndex, offsetBy: lowercaseText.distance(from: lowercaseText.startIndex, to: range.upperBound))
                let originalRange = startIndex..<endIndex
                
                cleanedText = cleanedText.replacingCharacters(in: originalRange, with: "")
                print("DEBUG: Text after removal: '\(cleanedText)'")
                break // Remove only the first match to avoid index issues
            }
        }
        
        let finalText = cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
        print("DEBUG: Final cleaned text: '\(finalText)'")
        return finalText
    }
    
    // MARK: - Elderly Mode Settings
    
    func updateElderlyModeSettings(enabled: Bool) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.elderlyModeEnabled = enabled
            
            // Update recognition parameters based on elderly mode
            if enabled {
                // Enable elderly-friendly features
                self.slowSpeechTolerance = 2.0
                self.stutterDetectionEnabled = true
                self.accentToleranceLevel = 0.8
                self.noiseSuppressionLevel = 0.8
                
                // Update subtitle settings
                self.subtitleFontSize = 20.0
                self.highContrastMode = true
                self.showRecognitionQuality = true
            } else {
                // Reset to default settings
                self.slowSpeechTolerance = 1.0
                self.stutterDetectionEnabled = false
                self.accentToleranceLevel = 0.5
                self.noiseSuppressionLevel = 0.0
                
                // Reset subtitle settings
                self.subtitleFontSize = 16.0
                self.highContrastMode = false
                self.showRecognitionQuality = false
            }
            
            print("🔧 Updated elderly mode settings: enabled=\(enabled)")
        }
    }
}

// Helper class for date extraction
class DateExtractor {
    private let dateFormatter = DateFormatter()
    
    init() {
        dateFormatter.dateFormat = "MMMM d, yyyy"
    }
    
    func extractDate(from text: String) -> Date? {
        // Try to match common date formats
        
        // Format: "June 15, 2025" or "June 15 2025"
        let monthDayYearPattern = #"(January|February|March|April|May|June|July|August|September|October|November|December)\s+(\d{1,2})(?:,|)\s+(\d{4})"#
        
        if let match = text.range(of: monthDayYearPattern, options: .regularExpression) {
            let matchedText = String(text[match])
            return dateFormatter.date(from: matchedText)
        }
        
        // Format: "mm/dd/yyyy" or "mm-dd-yyyy"
        let numericDatePattern = #"(\d{1,2})[/-](\d{1,2})[/-](\d{4})"#
        
        if let match = text.range(of: numericDatePattern, options: .regularExpression) {
            let matchedText = String(text[match])
            let components = matchedText.components(separatedBy: CharacterSet(charactersIn: "/-"))
            
            if components.count == 3,
               let month = Int(components[0]),
               let day = Int(components[1]),
               let year = Int(components[2]),
               month >= 1 && month <= 12,
               day >= 1 && day <= 31 {
                
                var dateComponents = DateComponents()
                dateComponents.year = year
                dateComponents.month = month
                dateComponents.day = day
                
                return Calendar.current.date(from: dateComponents)
            }
        }
        
        return nil
    }
} 