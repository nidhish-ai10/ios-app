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
    
    // Completion handler for when speech recognition is complete
    var onRecognitionComplete: ((String, Date?) -> Void)?
    
    // Add these properties to the class after the existing @Published variables
    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.5 // 1.5 seconds of silence to trigger completion
    private let powerThreshold: Float = 0.006 // Slightly lower threshold for better sensitivity
    private var consecutiveSilenceFrames = 0
    private let requiredSilenceFrames = 8 // Reduced for faster response
    
    // Add debouncing timer to prevent duplicate task creation
    private var processingDebounceTimer: Timer?
    private let debounceInterval: TimeInterval = 0.3
    
    // Add a property to track if we're currently processing a completion
    private var isProcessingCompletion = false
    
    override init() {
        super.init()
        
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
    
    // Start recording and recognizing speech
    func startRecording() {
        // Reset previous recording session
        resetRecording()
        
        // Reset processing state
        isProcessingCompletion = false
        
        // Reset last processed text to avoid duplicate tasks
        lastProcessedText = ""
        
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
                
                // Reset silence timer when new text comes in
                self.resetSilenceTimer()
            }
            
            // Handle errors or completion
            if error != nil || isFinal {
                // Clean up audio resources
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)
                
                self.recognitionRequest = nil
                self.recognitionTask = nil
                
                // Process final results on main thread
                DispatchQueue.main.async {
                    self.isRecording = false
                    self.isListening = false
                    
                    // Prevent duplicate processing
                    if !self.isProcessingCompletion {
                        self.isProcessingCompletion = true
                        
                        // Process the transcribed text only if not already processed
                        if !self.transcribedText.isEmpty && self.transcribedText != self.lastProcessedText {
                            self.lastProcessedText = self.transcribedText
                            
                            // Add debouncing to prevent multiple rapid firings
                            self.processingDebounceTimer?.invalidate()
                            self.processingDebounceTimer = Timer.scheduledTimer(withTimeInterval: self.debounceInterval, repeats: false) { _ in
                                let (title, dueDate) = self.processTaskText(self.transcribedText)
                                
                                // Clear transcribed text after processing
                                self.transcribedText = ""
                                
                                // Call completion handler with the extracted task
                                self.onRecognitionComplete?(title, dueDate)
                                self.isProcessingCompletion = false
                            }
                        } else {
                            // If there's no text to process, still notify completion to hide UI
                            self.onRecognitionComplete?("", nil)
                            self.isProcessingCompletion = false
                        }
                    }
                }
            }
        }
        
        // Reset for new recording
        consecutiveSilenceFrames = 0
        
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
                    if !self.transcribedText.isEmpty && self.transcribedText != self.lastProcessedText {
                        self.lastProcessedText = self.transcribedText
                        let (title, dueDate) = self.processTaskText(self.transcribedText)
                        
                        // Clear transcribed text after processing
                        self.transcribedText = ""
                        
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
        // Cancel any existing timers
        silenceTimer?.invalidate()
        silenceTimer = nil
        
        processingDebounceTimer?.invalidate()
        processingDebounceTimer = nil
        
        // Stop audio engine if running
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            recognitionRequest?.endAudio()
        }
        
        // Cancel and reset recognition task
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        
        // Reset state
        DispatchQueue.main.async {
            self.transcribedText = ""
            self.isListening = false
            self.isProcessingCompletion = false
        }
    }
    
    // Process the transcribed text to extract a task title and due date
    func processTaskText(_ text: String) -> (String, Date?) {
        // Extract date using NSDataDetector (more powerful than basic pattern matching)
        var taskText = text
        var dueDate: Date? = nil
        
        // Use NSDataDetector to find dates in the text
        let dateDetector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        if let dateDetector = dateDetector {
            let matches = dateDetector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            
            if let match = matches.first, let date = match.date {
                dueDate = date
                
                // Remove the date part from the task text
                let matchRange = match.range
                if let startIndex = text.index(text.startIndex, offsetBy: matchRange.location, limitedBy: text.endIndex),
                   let endIndex = text.index(startIndex, offsetBy: matchRange.length, limitedBy: text.endIndex) {
                    let dateString = String(text[startIndex..<endIndex])
                    taskText = text.replacingOccurrences(of: dateString, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }
        
        // Use NLTagger to identify verbs and nouns for better task extraction
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = taskText
        
        // Common phrases to remove from the beginning of tasks
        let prefixesToRemove = [
            "add", "create", "make", "set", "new task", "remind me to", 
            "i need to", "set task", "task", "i have to", "please", 
            "remember to", "don't forget to", "i must", "i should"
        ]
        
        // Clean up the task text by removing common prefixes
        for prefix in prefixesToRemove {
            if taskText.lowercased().hasPrefix(prefix) {
                let range = taskText.range(of: prefix, options: .caseInsensitive)!
                taskText = taskText.replacingCharacters(in: range, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Remove prepositions like "by" or "at" that often appear before dates
        let prepositionsToRemove = ["by", "at", "on", "before", "due"]
        for preposition in prepositionsToRemove {
            if taskText.lowercased().hasSuffix(preposition) {
                taskText = taskText.replacingOccurrences(of: "\\s+\(preposition)\\s*$", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        // Clean up any trailing punctuation
        taskText = taskText.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;"))
                          .trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Capitalize first letter for a nicer appearance
        if !taskText.isEmpty {
            let firstChar = taskText.prefix(1).capitalized
            let restOfText = taskText.dropFirst()
            taskText = firstChar + restOfText
        }
        
        return (taskText, dueDate)
    }
    
    // Reset just the transcribed text without stopping the recording
    func resetTranscription() {
        transcribedText = ""
    }
    
    // Add these methods for silence detection
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