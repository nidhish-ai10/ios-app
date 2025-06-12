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
    
    // Voice Activity Detection (VAD) properties
    @Published var isVADEnabled = false
    @Published var isVADActive = false
    private var vadAudioEngine: AVAudioEngine?
    private var vadInputNode: AVAudioInputNode?
    private var consecutiveVoiceFrames = 0
    private var vadSilenceFrames = 0 // Use a different name for VAD silence frames
    private let requiredVoiceFrames = 10 // Number of consecutive voice frames to trigger activation
    private let vadPowerThreshold: Float = 0.01 // Adjustable threshold for voice detection
    
    // User preferences from UserDefaults
    private var vadSensitivity: Double {
        get { UserDefaults.standard.double(forKey: "vadSensitivity") }
        set { UserDefaults.standard.set(newValue, forKey: "vadSensitivity") }
    }
    
    // Property for storing completion handler
    public var onRecognitionComplete: ((String, Date?) -> Void)?
    
    // Add these properties to the class after the existing @Published variables
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 0.5 // Reduced from 0.8 to 0.5 seconds for faster response
    private let powerThreshold: Float = 0.003 // Reduced threshold for better sensitivity
    private var consecutiveSilenceFrames = 0
    private let requiredSilenceFrames = 2 // Reduced from 4 to 2 for faster response
    
    // Add maximum recording timeout to prevent infinite recording
    private var maxRecordingTimer: Timer?
    private let maxRecordingDuration: TimeInterval = 10.0 // Maximum 10 seconds of recording
    
    // Add debouncing timer to prevent duplicate task creation
    private var processingDebounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.3
    
    // Add a property to track if we're currently processing a completion
    private var isProcessingRecognition = false
    
    // Stored transcribed text to use when processing is complete
    private var storedTranscribedText = ""
    
    override init() {
        super.init()
        
        // Initialize VAD sensitivity with default if not set
        if UserDefaults.standard.double(forKey: "vadSensitivity") == 0 {
            vadSensitivity = 0.5 // Default sensitivity (0.0-1.0 range)
        }
        
        // Check if speech recognition is available
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.errorMessage = nil
                case .denied:
                    self?.errorMessage = "Speech recognition permission denied"
                case .restricted:
                    self?.errorMessage = "Speech recognition is restricted on this device"
                case .notDetermined:
                    self?.errorMessage = "Speech recognition permission not determined"
                @unknown default:
                    self?.errorMessage = "Unknown speech recognition authorization status"
                }
            }
        }
    }
    
    // MARK: - Voice Activity Detection (VAD)
    
    /// Start Voice Activity Detection in the background
    func startVoiceActivityDetection() {
        guard !isVADActive else { return }
        
        // Configure audio session for background listening
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Failed to set up audio session for VAD: \(error.localizedDescription)"
            return
        }
        
        // Create a separate audio engine for VAD
        vadAudioEngine = AVAudioEngine()
        vadInputNode = vadAudioEngine?.inputNode
        
        // Get the recording format
        let recordingFormat = vadInputNode?.outputFormat(forBus: 0)
        
        // Install tap on input node with smaller buffer for real-time response
        vadInputNode?.installTap(onBus: 0, bufferSize: 512, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, self.isVADEnabled else { return }
            
            // Calculate audio power level
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
                
                // Calculate adjusted threshold based on user sensitivity setting
                let adjustedThreshold = self.vadPowerThreshold * Float(1.0 - self.vadSensitivity * 0.8)
                
                // Detect voice activity using both metrics
                if averagePower > adjustedThreshold || peakPower > adjustedThreshold * 3 {
                    self.consecutiveVoiceFrames += 1
                    self.vadSilenceFrames = 0
                    
                    // Add debug logging for voice detection
                    if self.consecutiveVoiceFrames % 5 == 0 {
                        print("VAD DEBUG: Voice detected - frames: \(self.consecutiveVoiceFrames), avgPower: \(averagePower), threshold: \(adjustedThreshold)")
                    }
                    
                    // Start recording if voice detected for enough consecutive frames
                    if self.consecutiveVoiceFrames >= self.requiredVoiceFrames && !self.isRecording && !self.isProcessingRecognition {
                        DispatchQueue.main.async {
                            print("VAD DEBUG: Voice detected - starting recording (avgPower: \(averagePower), threshold: \(adjustedThreshold))")
                            self.startRecording()
                        }
                    }
                } else {
                    self.vadSilenceFrames += 1
                    self.consecutiveVoiceFrames = 0
                    
                    // Add debug logging for silence detection
                    if self.vadSilenceFrames % 10 == 0 && self.isRecording {
                        print("VAD DEBUG: Silence detected for \(self.vadSilenceFrames) frames while recording")
                    }
                }
            }
        }
        
        // Start VAD audio engine
        do {
            vadAudioEngine?.prepare()
            try vadAudioEngine?.start()
            isVADActive = true
            print("VAD activated successfully")
        } catch {
            errorMessage = "Failed to start VAD audio engine: \(error.localizedDescription)"
            isVADActive = false
            print("Failed to start VAD: \(error.localizedDescription)")
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
        print("RECORDING DEBUG: startRecording called")
        
        // Reset previous recording session
        resetRecording()
        
        // Reset processing state
        isProcessingRecognition = false
        
        // Reset last processed text to avoid duplicate tasks
        lastProcessedText = ""
        
        // Store empty string for transcribed text
        storedTranscribedText = ""
        
        // Configure audio session with optimized settings for speed
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Use simpler configuration for faster startup
            try audioSession.setCategory(.record, mode: .measurement, options: [])
            try audioSession.setActive(true)
        } catch {
            errorMessage = "Failed to set up audio session: \(error.localizedDescription)"
            return
        }
        
        // Create recognition request with configuration for better performance
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        
        // Get input node
        let inputNode = audioEngine.inputNode
        
        // Check microphone availability
        guard let recognitionRequest = recognitionRequest else {
            errorMessage = "Unable to create recognition request"
            return
        }
        
        // Configure request for partial results with enhanced settings
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation // Optimize for continuous speech
        
        // Start recognition task
        recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            var isFinal = false
            
            if let result = result {
                // Update transcribed text on the main thread to ensure UI updates
                let transcription = result.bestTranscription.formattedString
                
                DispatchQueue.main.async {
                    // Only update if the text has actually changed to avoid unnecessary UI updates
                    if self.transcribedText != transcription {
                        // Use faster animation for better responsiveness
                        withAnimation(.easeInOut(duration: 0.1)) {
                            self.transcribedText = transcription
                        }
                        
                        // Only update isListening if we're truly listening (protects against false UI updates)
                        if self.isRecording {
                            self.isListening = true
                        }
                    }
                }
                
                isFinal = result.isFinal
                
                // Store the transcribed text for processing when finished
                if isFinal {
                    self.storedTranscribedText = transcription
                }
                
                // Reset silence timer when new text comes in
                self.resetSilenceTimer()
            }
            
            // Handle errors or completion
            if error != nil || isFinal {
                // Stop audio engine and clean up
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                // Update state on main thread
                DispatchQueue.main.async {
                    // Update listening status immediately for faster UI response
                    self.isListening = false
                    self.isRecording = false
                    
                    // Process final text if we have it
                    if !self.isProcessingRecognition {
                        self.isProcessingRecognition = true
                        
                        // Get the final text to process
                        let finalText = self.storedTranscribedText.isEmpty ? self.transcribedText : self.storedTranscribedText
                        
                        // CRITICAL DEBUG: Add logging for final text processing
                        print("CRITICAL DEBUG: Processing final text: '\(finalText)'")
                        
                        // Check if we have text to process and it hasn't been processed already
                        if !finalText.isEmpty && finalText != self.lastProcessedText {
                            self.lastProcessedText = finalText
                            
                            // Process the task text - moved outside of UI update to improve performance
                            let (title, dueDate) = self.processTaskText(finalText)
                            print("CRITICAL DEBUG: Extracted task title: '\(title)', dueDate: \(String(describing: dueDate))")
                            
                            // Clear the transcribed text after processing
                            self.transcribedText = ""
                            
                            // Call completion handler with the extracted task - IMMEDIATELY without any delay
                            print("CRITICAL DEBUG: About to call onRecognitionComplete with title: '\(title)', dueDate: \(String(describing: dueDate))")
                            print("CRITICAL DEBUG: onRecognitionComplete callback exists: \(self.onRecognitionComplete != nil)")
                            self.onRecognitionComplete?(title, dueDate)
                            print("CRITICAL DEBUG: onRecognitionComplete callback called successfully")
                            
                            // Reset processing state immediately for faster response
                            self.isProcessingRecognition = false
                        } else {
                            // If there's no text to process, still notify completion to hide UI
                            self.transcribedText = "" // Ensure text is cleared
                            self.onRecognitionComplete?("", nil)
                            
                            // Reset processing state immediately
                            self.isProcessingRecognition = false
                        }
                    }
                }
            }
        }
        
        // Configure audio recording with monitoring for silence - use smaller buffer size for better responsiveness
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 128, format: recordingFormat) { [weak self] buffer, _ in
            // Use even smaller buffer size (128 instead of 256) for improved responsiveness
            guard let self = self else { return }
            
            // Add incoming audio to the recognition request
            self.recognitionRequest?.append(buffer)
            
            // Enhanced silence detection using peak power and RMS
            let audioBuffer = buffer.audioBufferList.pointee.mBuffers
            if let channelData = audioBuffer.mData {
                let channelDataSize = Int(audioBuffer.mDataByteSize)
                let samples = channelDataSize / MemoryLayout<Float>.size
                let floatData = channelData.bindMemory(to: Float.self, capacity: samples)
                
                var sum: Float = 0
                var peakPower: Float = 0
                
                // Calculate both average and peak power for better silence detection
                for i in 0..<samples {
                    let sample = abs(floatData[i])
                    sum += sample
                    peakPower = max(peakPower, sample)
                }
                
                let averagePower = sum / Float(samples)
                
                // Use both metrics for more accurate silence detection - more aggressive thresholds
                if averagePower < self.powerThreshold && peakPower < self.powerThreshold * 2 {
                    self.consecutiveSilenceFrames += 1
                    
                    // Start silence timer if we've detected enough consecutive silent frames
                    if self.consecutiveSilenceFrames >= self.requiredSilenceFrames {
                        DispatchQueue.main.async {
                            self.startSilenceTimer()
                        }
                    }
                } else {
                    // Reset consecutive silence frames counter if we detect sound
                    self.consecutiveSilenceFrames = 0
                    
                    DispatchQueue.main.async {
                        self.resetSilenceTimer()
                        
                        // Mark as actively listening when there's audio input
                        if self.isRecording && !self.isListening {
                            self.isListening = true
                        }
                    }
                }
            }
        }
        
        // Start audio engine with error handling - optimized for speed
        do {
            // Start the audio engine directly without prepare() for faster startup
            try audioEngine.start()
            
            print("RECORDING DEBUG: Audio engine started immediately")
            
            // Update state on main thread
            DispatchQueue.main.async {
                self.isRecording = true
                self.isListening = true
                self.errorMessage = nil
                print("RECORDING DEBUG: Recording state updated - isRecording: true, isListening: true")
                
                // Start maximum recording timer to prevent infinite recording
                self.maxRecordingTimer = Timer.scheduledTimer(withTimeInterval: self.maxRecordingDuration, repeats: false) { [weak self] _ in
                    guard let self = self, self.isRecording else { return }
                    print("RECORDING DEBUG: Maximum recording time reached - forcing stop")
                    self.stopRecording()
                }
            }
        } catch {
            print("RECORDING DEBUG: Audio engine failed to start: \(error.localizedDescription)")
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            print("Audio engine error: \(error.localizedDescription)")
        }
        
        // Reset for new recording
        consecutiveSilenceFrames = 0
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
        DispatchQueue.main.async {
            self.isListening = false
        }
        
        // Store current text before clearing it
        let currentText = transcribedText
        
        // Immediately clear transcribed text to ensure UI updates
        DispatchQueue.main.async {
            self.transcribedText = ""
        }
        
        // Stop audio engine if running
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            recognitionRequest?.endAudio()
            
            // Use main thread for UI-related state changes
            DispatchQueue.main.async {
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
        DispatchQueue.main.async {
            self.transcribedText = ""
            self.lastProcessedText = ""
            self.storedTranscribedText = ""
            self.isProcessingRecognition = false
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
            self.startVoiceActivityDetection()
            print("VAD RESTART: VAD restarted immediately")
        } else {
            print("VAD RESTART: VAD already active, no restart needed")
        }
    }
    
    // FORCE restart VAD - ensures it always restarts for multiple tasks
    func forceRestartVAD() {
        print("VAD FORCE RESTART: Forcing VAD restart for multiple tasks")
        
        // Stop current VAD if active
        if isVADActive {
            stopVoiceActivityDetection()
        }
        
        // Reset all state
        resetRecording()
        resetTranscription()
        
        // Force enable and start VAD
        isVADEnabled = true
        startVoiceActivityDetection()
        
        print("VAD FORCE RESTART: VAD force restarted successfully")
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