//
//  TTSService.swift
//  TEST
//
//  Created by AI Assistant on 6/18/25.
//

import Foundation
import AVFoundation
import UIKit

// MARK: - TTS Service using iOS Built-in Speech Synthesizer
@MainActor
class TTSService: ObservableObject {
    @Published var isGenerating = false
    @Published var lastError: Error?
    
    private let speechSynthesizer: AVSpeechSynthesizer
    private var currentUtterance: AVSpeechUtterance?
    
    // TTS Configuration
    struct TTSConfiguration {
        let voice: AVSpeechSynthesisVoice?
        let rate: Float
        let pitchMultiplier: Float
        let volume: Float
        
        static let `default` = TTSConfiguration(
            voice: nil, // Uses system default voice
            rate: 0.5, // Slower rate for better clarity
            pitchMultiplier: 1.0,
            volume: 1.0
        )
        
        static let highQuality = TTSConfiguration(
            voice: AVSpeechSynthesisVoice(language: "en-US"),
            rate: 0.5,
            pitchMultiplier: 1.0,
            volume: 1.0
        )
        
        static func with(voice: AVSpeechSynthesisVoice?) -> TTSConfiguration {
            return TTSConfiguration(
                voice: voice,
                rate: 0.5,
                pitchMultiplier: 1.0,
                volume: 1.0
            )
        }
    }
    
    // NEW: Enhanced callback support
    var onSpeechStarted: (() -> Void)?
    var onSpeechCompleted: (() -> Void)?
    var onSpeechFailed: ((Error) -> Void)?
    
    init() {
        self.speechSynthesizer = AVSpeechSynthesizer()
        setupAudioSession()
        
        // Print available voices for debugging
        let voices = AVSpeechSynthesisVoice.speechVoices()
        print("🎤 Available TTS voices: \(voices.count)")
        for voice in voices.prefix(5) {
            print("  - \(voice.name) (\(voice.language))")
        }
    }
    
    // MARK: - Public Methods
    
    /// Convert text to speech and play it
    func speakText(_ text: String, configuration: TTSConfiguration = .default) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("❌ TTS: Empty text provided")
            return
        }
        
        print("🔊 TTS: Starting speech generation for text: \(String(text.prefix(50)))...")
        #if targetEnvironment(simulator)
        print("📱 TTS: Running on iOS Simulator: YES")
        #else
        print("📱 TTS: Running on iOS Simulator: NO")
        #endif
        
        // Stop any current speech
        stopSpeaking()
        
        isGenerating = true
        lastError = nil
        
        // NEW: Notify that speech is starting
        onSpeechStarted?()
        
        defer {
            isGenerating = false
            // NEW: Notify when speech processing is complete (success or failure)
            if lastError == nil {
                onSpeechCompleted?()
            } else {
                onSpeechFailed?(lastError!)
            }
        }
        
        do {
            // Configure audio session more aggressively
            try await configureAudioSessionForSpeech()
            
            // Create speech utterance
            let utterance = AVSpeechUtterance(string: text)
            
            // Apply configuration with simulator-friendly settings
            if let voice = configuration.voice {
                utterance.voice = voice
                print("🔧 TTS: Using voice: \(voice.name) (\(voice.language))")
            } else {
                // Try to use a specific English voice for better simulator compatibility
                let englishVoices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("en") }
                if let englishVoice = englishVoices.first {
                    utterance.voice = englishVoice
                    print("🔧 TTS: Using English voice: \(englishVoice.name)")
                } else {
                    print("🔧 TTS: Using system default voice")
                }
            }
            
            utterance.rate = max(configuration.rate, 0.1) // Ensure minimum rate
            utterance.pitchMultiplier = configuration.pitchMultiplier
            utterance.volume = configuration.volume
            
            print("🔧 TTS: Rate: \(utterance.rate), Pitch: \(utterance.pitchMultiplier), Volume: \(utterance.volume)")
            
            currentUtterance = utterance
            
            // Use synchronous approach for better simulator compatibility
            try await speakUtteranceWithFallback(utterance)
            
            print("✅ TTS: Speech completed successfully")
            
        } catch {
            print("❌ TTS: Error generating speech: \(error)")
            lastError = error
            throw error
        }
    }
    
    /// Stop current speech
    func stopSpeaking() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
            print("🛑 TTS: Stopped speech immediately")
        }
        currentUtterance = nil
    }
    
    /// Check if currently speaking
    var isSpeaking: Bool {
        return speechSynthesizer.isSpeaking
    }
    
    /// Test TTS functionality (for debugging)
    func testSpeak() async {
        print("🧪 TTS: Testing speech synthesis...")
        #if targetEnvironment(simulator)
        print("🧪 TTS: Simulator check: YES - Audio may not work in simulator")
        #else
        print("🧪 TTS: Simulator check: NO - Running on real device")
        #endif
        
        // Show a system alert to confirm TTS is working (visual feedback)
        #if targetEnvironment(simulator)
        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                let alert = UIAlertController(title: "TTS Test", 
                                            message: "TTS is running - you may not hear audio in iOS Simulator. Try on a real device for audio.", 
                                            preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                window.rootViewController?.present(alert, animated: true)
            }
        }
        #endif
        
        do {
            try await speakText("Hello, this is a test of the text to speech functionality. If you're on a real device, you should hear this.")
        } catch {
            print("❌ TTS Test Error: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    private func setupAudioSession() {
        do {
            try configureAudioSession()
            print("✅ TTS: Initial audio session setup completed")
        } catch {
            print("❌ TTS: Failed to setup initial audio session: \(error)")
        }
    }
    
    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            // More aggressive audio session configuration for simulator
            print("🔧 TTS: Configuring audio session...")
            
            // Set category with options that work better in simulator
            try audioSession.setCategory(.playAndRecord, 
                                       mode: .default, 
                                       options: [.defaultToSpeaker, .allowBluetooth, .mixWithOthers])
            
            try audioSession.setActive(true, options: [])
            
            print("✅ TTS: Audio session configured")
            print("🔧 TTS: Category: \(audioSession.category), Mode: \(audioSession.mode)")
            print("🔧 TTS: Available outputs: \(audioSession.currentRoute.outputs.map { $0.portName })")
            
        } catch {
            print("❌ TTS: Failed to configure audio session: \(error)")
            throw TTSError.audioSessionError
        }
    }
    
    private func configureAudioSessionForSpeech() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async {
                do {
                    try self.configureAudioSession()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    private func speakUtteranceWithFallback(_ utterance: AVSpeechUtterance) async throws {
        // First try the async delegate approach
        do {
            try await speakUtteranceAsync(utterance)
            return
        } catch {
            print("⚠️ TTS: Async approach failed, trying direct approach: \(error)")
        }
        
        // Fallback: Direct synchronous approach
        return try await withCheckedThrowingContinuation { continuation in
            print("🔊 TTS: Using direct speech synthesis...")
            
            // Start speaking directly
            speechSynthesizer.speak(utterance)
            
            // Wait a bit and check if it started
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if self.speechSynthesizer.isSpeaking {
                    print("✅ TTS: Direct speech started successfully")
                    
                    // Poll for completion
                    self.pollForSpeechCompletion { success in
                        if success {
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: TTSError.playbackFailed)
                        }
                    }
                } else {
                    print("❌ TTS: Direct speech failed to start")
                    continuation.resume(throwing: TTSError.playbackFailed)
                }
            }
        }
    }
    
    private func speakUtteranceAsync(_ utterance: AVSpeechUtterance) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            
            // Create a delegate to handle speech events
            let delegate = SpeechSynthesizerDelegate { result in
                switch result {
                case .success:
                    print("✅ TTS: Speech synthesis completed successfully")
                    continuation.resume()
                case .failure(let error):
                    print("❌ TTS: Speech synthesis failed: \(error)")
                    continuation.resume(throwing: error)
                }
            }
            
            // Set the delegate
            speechSynthesizer.delegate = delegate
            
            // Keep delegate alive during speech
            objc_setAssociatedObject(speechSynthesizer, "currentDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
            
            print("🔊 TTS: Starting speech synthesis...")
            
            // Start speaking
            speechSynthesizer.speak(utterance)
            
            // Verify that speech started
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if !self.speechSynthesizer.isSpeaking {
                    print("❌ TTS: Speech failed to start")
                    continuation.resume(throwing: TTSError.playbackFailed)
                }
            }
        }
    }
    
    private func pollForSpeechCompletion(completion: @escaping (Bool) -> Void) {
        let startTime = Date()
        let maxWaitTime: TimeInterval = 30.0 // Maximum wait time
        
        func checkCompletion() {
            if !speechSynthesizer.isSpeaking {
                print("✅ TTS: Polling detected speech completion")
                completion(true)
            } else if Date().timeIntervalSince(startTime) > maxWaitTime {
                print("⏰ TTS: Polling timeout - assuming completion")
                completion(true)
            } else {
                // Check again in 0.5 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    checkCompletion()
                }
            }
        }
        
        checkCompletion()
    }
}

// MARK: - Speech Synthesizer Delegate
private class SpeechSynthesizerDelegate: NSObject, AVSpeechSynthesizerDelegate {
    private let completion: (Result<Void, Error>) -> Void
    
    init(completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("🎤 TTS: Speech synthesis started")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("✅ TTS: Speech synthesis finished")
        completion(.success(()))
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("⚠️ TTS: Speech synthesis cancelled")
        completion(.failure(TTSError.playbackCancelled))
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        print("⏸️ TTS: Speech synthesis paused")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        print("▶️ TTS: Speech synthesis resumed")
    }
}

// MARK: - TTS Errors
enum TTSError: Error, LocalizedError {
    case playbackFailed
    case playbackCancelled
    case audioSessionError
    case noAudioData
    case invalidAudioFormat
    
    var errorDescription: String? {
        switch self {
        case .playbackFailed:
            return "Failed to start speech playback"
        case .playbackCancelled:
            return "Speech playback was cancelled"
        case .audioSessionError:
            return "Failed to configure audio session"
        case .noAudioData:
            return "No audio data available"
        case .invalidAudioFormat:
            return "Invalid audio format"
        }
    }
} 
