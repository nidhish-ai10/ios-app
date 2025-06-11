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
    private let silenceThreshold: TimeInterval = 1.2 // Reduced to 1.2 seconds for faster response
    private let powerThreshold: Float = 0.007 // Slightly higher threshold for better sensitivity
    private var consecutiveSilenceFrames = 0
    private let requiredSilenceFrames = 6 // Reduced for faster response
    
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
                    
                    // Start recording if voice detected for enough consecutive frames
                    if self.consecutiveVoiceFrames >= self.requiredVoiceFrames && !self.isRecording && !self.isProcessingRecognition {
                        DispatchQueue.main.async {
                            print("VAD detected voice - starting recording")
                            self.startRecording()
                        }
                    }
                } else {
                    self.vadSilenceFrames += 1
                    self.consecutiveVoiceFrames = 0
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
        // Reset previous recording session
        resetRecording()
        
        // Reset processing state
        isProcessingRecognition = false
        
        // Reset last processed text to avoid duplicate tasks
        lastProcessedText = ""
        
        // Store empty string for transcribed text
        storedTranscribedText = ""
        
        // Configure audio session with enhanced settings
        let audioSession = AVAudioSession.sharedInstance()
        do {
            // Use playAndRecord to enable higher quality audio capture
            try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // Set preferred input to optimize for voice
            try audioSession.setPreferredIOBufferDuration(0.005) // Smaller buffer for faster processing
            try audioSession.setPreferredSampleRate(44100) // Higher sample rate for better quality
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
                            self.onRecognitionComplete?(title, dueDate)
                            
                            // Reset processing state after a shorter delay to improve responsiveness
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                self.isProcessingRecognition = false
                            }
                        } else {
                            // If there's no text to process, still notify completion to hide UI
                            self.transcribedText = "" // Ensure text is cleared
                            self.onRecognitionComplete?("", nil)
                            
                            // Reset processing state after a shorter delay
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                self.isProcessingRecognition = false
                            }
                        }
                    }
                }
            }
        }
        
        // Configure audio recording with monitoring for silence - use smaller buffer size for better responsiveness
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 256, format: recordingFormat) { [weak self] buffer, _ in
            // Use smaller buffer size (256 instead of 512) for improved responsiveness
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
                
                // Use both metrics for more accurate silence detection
                if averagePower < self.powerThreshold && peakPower < self.powerThreshold * 3 {
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
        
        // Start audio engine with error handling
        do {
            // Prepare and start the audio engine
            audioEngine.prepare()
            try audioEngine.start()
            
            // Update state on main thread
            DispatchQueue.main.async {
                self.isRecording = true
                self.isListening = true
                self.errorMessage = nil
            }
        } catch {
            errorMessage = "Failed to start audio engine: \(error.localizedDescription)"
            print("Audio engine error: \(error.localizedDescription)")
        }
        
        // Reset for new recording
        consecutiveSilenceFrames = 0
    }
    
    // Stop recording
    func stopRecording() {
        // Invalidate silence timer
        silenceTimer?.invalidate()
        silenceTimer = nil
        
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
                
                // Prevent duplicate processing
                if !self.isProcessingRecognition {
                    self.isProcessingRecognition = true
                    
                    // Process any final transcription if we have text and it hasn't been processed
                    if !currentText.isEmpty && currentText != self.lastProcessedText {
                        self.lastProcessedText = currentText
                        let (title, dueDate) = self.processTaskText(currentText)
                        
                        // Call completion handler with the extracted task
                        self.onRecognitionComplete?(title, dueDate)
                    } else {
                        // If there's no text to process, still notify completion to hide UI
                        self.onRecognitionComplete?("", nil)
                    }
                    
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
    
    // Process task text with natural language processing for better date extraction
    func processTaskText(_ text: String) -> (String, Date?) {
        guard !text.isEmpty else { return ("", nil) }
        
        var taskTitle = text
        var dueDate: Date?
        var timeSpecified = false
        
        // Advanced date extraction using Natural Language Processing
        // Look for patterns like "tomorrow", "next Tuesday", etc.
        
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
        
        // Time extraction - Look for time patterns
        var extractedHour: Int?
        var extractedMinute: Int?
        var isPM = false
        
        // First check for time patterns in the entire text
        if extractTimeFromText(lowercasedText, &extractedHour, &extractedMinute, &isPM) {
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
            var calendar = Calendar.current
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
        
        return (taskTitle, dueDate)
    }
    
    // Helper method to find the next occurrence of a specific weekday with optional offset
    private func nextWeekdayWithOffset(_ weekday: Int, offset: Int) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)
        
        var daysToAdd = weekday - todayWeekday
        
        // If weekday has already occurred this week
        if daysToAdd <= 0 {
            // For "this weekday" when it's already passed, use next week
            daysToAdd += 7
        }
        
        // Add additional offset (for "next" we add 7 more days)
        daysToAdd += offset
        
        return calendar.date(byAdding: .day, value: daysToAdd, to: today)!
    }
    
    // Keep the original nextWeekday method for backward compatibility
    private func nextWeekday(_ weekday: Int) -> Date {
        return nextWeekdayWithOffset(weekday, offset: 0)
    }
    
    private func startSilenceTimer() {
        // Only start timer if not already running
        if silenceTimer == nil {
            silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
                guard let self = self, self.isRecording else { return }
                
                // Stop recording after silence period
                self.stopRecording()
            }
        }
    }
    
    private func resetSilenceTimer() {
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
        
        // Pattern 3: Time with "at" or "by" - "at 3 PM", "by 10:30 AM", etc.
        let prepositionTimePatterns = [
            #"at\s+(\d{1,2})\s*(am|pm)"#,
            #"by\s+(\d{1,2})\s*(am|pm)"#,
            #"at\s+(\d{1,2}):(\d{2})\s*(am|pm)"#,
            #"by\s+(\d{1,2}):(\d{2})\s*(am|pm)"#
        ]
        
        for pattern in prepositionTimePatterns {
            if let timeRange = text.range(of: pattern, options: .regularExpression) {
                let timeText = String(text[timeRange])
                
                if timeText.contains(":") {
                    // Handle "at 3:30 PM" format
                    let components = timeText.components(separatedBy: CharacterSet(charactersIn: ": "))
                    let filteredComponents = components.filter { !$0.isEmpty && !$0.lowercased().hasPrefix("at") && !$0.lowercased().hasPrefix("by") }
                    
                    if filteredComponents.count >= 2,
                       let hourValue = Int(filteredComponents[0]),
                       let minuteValue = Int(filteredComponents[1]) {
                        hour = hourValue
                        minute = minuteValue
                        isPM = timeText.lowercased().contains("pm")
                        return true
                    }
                } else {
                    // Handle "at 3 PM" format
                    let components = timeText.components(separatedBy: CharacterSet.letters.union(CharacterSet.whitespaces))
                    let filteredComponents = components.filter { !$0.isEmpty }
                    
                    if let hourValue = Int(filteredComponents.last ?? "") {
                        hour = hourValue
                        minute = 0
                        isPM = timeText.lowercased().contains("pm")
                        return true
                    }
                }
            }
        }
        
        // Pattern 4: 24-hour time format - "15:30", "08:00"
        let militaryTimePattern = #"(\d{1,2}):(\d{2})"#
        if let timeRange = text.range(of: militaryTimePattern, options: .regularExpression) {
            let timeText = String(text[timeRange])
            let components = timeText.components(separatedBy: ":")
            
            if components.count == 2,
               let hourValue = Int(components[0]),
               let minuteValue = Int(components[1]),
               hourValue >= 0 && hourValue <= 23,
               minuteValue >= 0 && minuteValue <= 59 {
                hour = hourValue
                minute = minuteValue
                isPM = hourValue >= 12
                return true
            }
        }
        
        return false
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