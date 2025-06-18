//
//  TTSService.swift
//  TEST
//
//  Created by AI Assistant on 6/18/25.
//

import Foundation
import OpenAI
import AVFoundation

// MARK: - TTS Service using MacPaw OpenAI Library
@MainActor
class TTSService: ObservableObject {
    @Published var isGenerating = false
    @Published var lastError: Error?
    
    private let openAI: OpenAI
    private var audioPlayer: AVAudioPlayer?
    
    // TTS Configuration
    struct TTSConfiguration {
        let model: Model
        let voice: AudioSpeechQuery.AudioSpeechVoice
        let responseFormat: AudioSpeechQuery.AudioSpeechResponseFormat
        let speed: Double
        
        static let `default` = TTSConfiguration(
            model: .gpt_4o_mini_tts,
            voice: .alloy,
            responseFormat: .mp3,
            speed: 1.0
        )
        
        static let highQuality = TTSConfiguration(
            model: .tts_1_hd,
            voice: .nova,
            responseFormat: .mp3,
            speed: 1.0
        )
        
        static let voices: [AudioSpeechQuery.AudioSpeechVoice] = [
            .alloy, .echo, .fable, .onyx, .nova, .shimmer
        ]
        
        static func with(voice: AudioSpeechQuery.AudioSpeechVoice) -> TTSConfiguration {
            return TTSConfiguration(
                model: .tts_1,
                voice: voice,
                responseFormat: .mp3,
                speed: 1.0
            )
        }
    }
    
    init(apiKey: String) {
        self.openAI = OpenAI(apiToken: apiKey)
    }
    
    // MARK: - Public Methods
    
    /// Convert text to speech and play it
    func speakText(_ text: String, configuration: TTSConfiguration = .default) async throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("❌ TTS: Empty text provided")
            return
        }
        
        print("🔊 TTS: Starting speech generation for text: \(String(text.prefix(50)))...")
        
        isGenerating = true
        lastError = nil
        
        defer {
            isGenerating = false
        }
        
        do {
            // Create speech query
            let query = AudioSpeechQuery(
                model: configuration.model,
                input: text,
                voice: configuration.voice,
                responseFormat: configuration.responseFormat,
                speed: configuration.speed
            )
            
            print("🔧 TTS: Using model: \(configuration.model), voice: \(configuration.voice)")
            
            // Generate speech using MacPaw OpenAI library
            let audioResult = try await openAI.audioCreateSpeech(query: query)
            
            // Extract the audio data from the result
            let audioData = audioResult.audio
            
            print("✅ TTS: Generated audio data of \(audioData.count) bytes")
            
            // Validate audio data
            guard audioData.count > 0 else {
                throw TTSError.noAudioData
            }
            
            // Validate that it's actually audio data by checking file signature
            if audioData.count >= 4 {
                let signature = audioData.prefix(4)
                print("🔍 TTS: Audio data signature: \(signature.map { String(format: "%02x", $0) }.joined())")
            }
            
            // Configure audio session before playing
            try configureAudioSession()
            
            // Play the audio
            try await playAudio(data: audioData)
            
        } catch {
            print("❌ TTS: Error generating speech: \(error)")
            lastError = error
            throw error
        }
    }
    
    /// Stop current audio playback
    func stopSpeaking() {
        audioPlayer?.stop()
        audioPlayer = nil
        print("🛑 TTS: Stopped audio playback")
    }
    
    /// Check if currently speaking
    var isSpeaking: Bool {
        return audioPlayer?.isPlaying ?? false
    }
    
    // MARK: - Private Methods
    
    private func configureAudioSession() throws {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            // Set category to playback with mixing options
            try audioSession.setCategory(.playback, mode: .default, options: [.mixWithOthers, .allowBluetooth, .allowBluetoothA2DP])
            try audioSession.setActive(true)
            print("✅ TTS: Audio session configured for playback")
        } catch {
            print("❌ TTS: Failed to configure audio session: \(error)")
            throw TTSError.audioSessionError
        }
    }
    
    private func playAudio(data: Data) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                // Stop any current playback
                stopSpeaking()
                
                // Try to create a temporary file first to validate the audio data
                let tempURL = createTemporaryAudioFile(data: data)
                
                // Create audio player from file URL (more reliable than from Data)
                audioPlayer = try AVAudioPlayer(contentsOf: tempURL)
                
                // Configure audio player
                audioPlayer?.prepareToPlay()
                audioPlayer?.volume = 1.0
                
                // Set up completion handler
                let delegate = AudioPlayerDelegate { [weak self] success in
                    DispatchQueue.main.async {
                        if success {
                            print("✅ TTS: Audio playback completed successfully")
                        } else {
                            print("❌ TTS: Audio playback failed or was interrupted")
                        }
                        
                        // Clean up
                        self?.audioPlayer = nil
                        
                        // Remove temporary file
                        try? FileManager.default.removeItem(at: tempURL)
                        
                        continuation.resume()
                    }
                }
                
                audioPlayer?.delegate = delegate
                
                // Keep delegate alive during playback
                objc_setAssociatedObject(audioPlayer!, "delegate", delegate, .OBJC_ASSOCIATION_RETAIN)
                
                // Start playback
                guard let player = audioPlayer, player.play() else {
                    // Clean up on failure
                    try? FileManager.default.removeItem(at: tempURL)
                    throw TTSError.playbackFailed
                }
                
                print("🔊 TTS: Started audio playback (duration: \(audioPlayer?.duration ?? 0) seconds)")
                
            } catch {
                print("❌ TTS: Failed to create audio player: \(error)")
                
                // Provide more specific error information
                if let nsError = error as NSError? {
                    print("❌ TTS: Error domain: \(nsError.domain), code: \(nsError.code)")
                    if nsError.code == 1954115647 { // kAudioFileInvalidFileError
                        print("❌ TTS: Invalid audio file format - the audio data may be corrupted")
                    }
                }
                
                continuation.resume(throwing: error)
            }
        }
    }
    
    private func createTemporaryAudioFile(data: Data) -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = "tts_audio_\(UUID().uuidString).mp3"
        let tempURL = tempDirectory.appendingPathComponent(fileName)
        
        do {
            try data.write(to: tempURL)
            print("📁 TTS: Created temporary audio file: \(tempURL.lastPathComponent)")
        } catch {
            print("❌ TTS: Failed to write temporary audio file: \(error)")
        }
        
        return tempURL
    }
}

// MARK: - Audio Player Delegate
private class AudioPlayerDelegate: NSObject, AVAudioPlayerDelegate {
    private let completion: (Bool) -> Void
    
    init(completion: @escaping (Bool) -> Void) {
        self.completion = completion
    }
    
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        completion(flag)
    }
    
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        if let error = error {
            print("❌ TTS: Audio decode error: \(error)")
        }
        completion(false)
    }
}

// MARK: - TTS Errors
enum TTSError: Error, LocalizedError {
    case playbackFailed
    case audioSessionError
    case noAudioData
    case invalidAudioFormat
    
    var errorDescription: String? {
        switch self {
        case .playbackFailed:
            return "Failed to start audio playback"
        case .audioSessionError:
            return "Failed to configure audio session"
        case .noAudioData:
            return "No audio data received from OpenAI"
        case .invalidAudioFormat:
            return "Invalid audio format received from OpenAI"
        }
    }
} 
