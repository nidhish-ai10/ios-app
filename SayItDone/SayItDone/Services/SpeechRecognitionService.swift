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
    
    // Completion handler for when speech recognition is complete
    var onRecognitionComplete: ((String, Date?) -> Void)?
    
    // Add these properties to the class after the existing @Published variables
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.5 // 1.5 seconds of silence to trigger completion
    private let powerThreshold: Float = 0.006 // Slightly lower threshold for better sensitivity
    private var consecutiveSilenceFrames = 0 // Add this back in
    private let requiredSilenceFrames = 8 // Reduced for faster response
    
    // Add debouncing timer to prevent duplicate task creation
    private var processingDebounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.3
    
    // Add a property to track if we're currently processing a completion
    private var isProcessingCompletion = false
    
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
            guard let self = self else { return }
            
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
                    if self.consecutiveVoiceFrames >= self.requiredVoiceFrames && !self.isRecording {
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
        } catch {
            errorMessage = "Failed to start VAD audio engine: \(error.localizedDescription)"
            isVADActive = false
        }
    }
    
    /// Stop Voice Activity Detection
    func stopVoiceActivityDetection() {
        if vadAudioEngine?.isRunning == true {
            vadInputNode?.removeTap(onBus: 0)
            vadAudioEngine?.stop()
            isVADActive = false
        }
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
        isProcessingCompletion = false
        
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
                    self.transcribedText = transcription
                    
                    // Only update isListening if we're truly listening (protects against false UI updates)
                    if self.isRecording {
                        self.isListening = true
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
                    
                    // Process final text if we have it
                    if !self.isProcessingCompletion {
                        self.isProcessingCompletion = true
                        
                        // Get the final text to process
                        let finalText = self.storedTranscribedText.isEmpty ? self.transcribedText : self.storedTranscribedText
                        
                        // Clear the transcribed text immediately
                        self.transcribedText = ""
                        
                        // Check if we have text to process and it hasn't been processed already
                        if !finalText.isEmpty && finalText != self.lastProcessedText {
                            self.lastProcessedText = finalText
                            
                            // Process the task text
                            let (title, dueDate) = self.processTaskText(finalText)
                            
                            // Call completion handler with the extracted task
                            self.onRecognitionComplete?(title, dueDate)
                        } else {
                            // If there's no text to process, still notify completion to hide UI
                            self.onRecognitionComplete?("", nil)
                            self.isProcessingCompletion = false
                        }
                    }
                }
            }
        }
        
        // Configure audio recording with monitoring for silence - use smaller buffer size for better responsiveness
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 512, format: recordingFormat) { [weak self] buffer, _ in
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
                if !self.isProcessingCompletion {
                    self.isProcessingCompletion = true
                    
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
                    
                    self.isProcessingCompletion = false
                }
            }
        }
    }
    
    // Reset the recording session
    private func resetRecording() {
        // Cancel any previous recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        // Stop audio engine if running
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
    }
    
    // Reset transcription text
    func resetTranscription() {
        transcribedText = ""
    }
    
    // Process task text with natural language processing for better date extraction
    func processTaskText(_ text: String) -> (String, Date?) {
        guard !text.isEmpty else { return ("", nil) }
        
        var taskTitle = text
        var dueDate: Date?
        
        // Advanced date extraction using Natural Language Processing
        // Look for patterns like "tomorrow", "next Tuesday", etc.
        
        // Common date patterns to search for - Fixed to use proper dictionary type
        let datePatterns: [String: Date?] = [
            // Relative dates
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
            // Check for standalone relative dates like "tomorrow", "next week"
            for (pattern, patternDate) in datePatterns {
                if lowercasedText.contains(pattern), let dateValue = patternDate {
                    dueDate = dateValue
                    
                    // Try to remove the date part from title
                    if let range = lowercasedText.range(of: pattern) {
                        let originalRange = text.range(of: text[range])!
                        
                        // Check if the pattern is at the end of the string
                        if originalRange.upperBound == text.endIndex {
                            taskTitle = String(text[..<originalRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                        } else if originalRange.lowerBound == text.startIndex {
                            taskTitle = String(text[originalRange.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
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
        
        // Capitalize first letter of task title
        if !taskTitle.isEmpty {
            let firstChar = taskTitle.prefix(1).capitalized
            let restOfTitle = taskTitle.dropFirst()
            taskTitle = firstChar + restOfTitle
        }
        
        return (taskTitle, dueDate)
    }
    
    // Helper method to find the next occurrence of a specific weekday
    private func nextWeekday(_ weekday: Int) -> Date {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let todayWeekday = calendar.component(.weekday, from: today)
        
        var daysToAdd = weekday - todayWeekday
        if daysToAdd <= 0 {
            daysToAdd += 7 // Add a week if the target weekday is today or earlier
        }
        
        return calendar.date(byAdding: .day, value: daysToAdd, to: today)!
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