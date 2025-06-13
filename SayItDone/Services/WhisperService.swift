//
//  WhisperService.swift
//  SayItDone
//
//  Enhanced speech recognition using OpenAI's Whisper API
//  Optimized for elderly users with better accent tolerance and noise handling
//

import Foundation
import AVFoundation
import SwiftUI

@MainActor
class WhisperService: NSObject, ObservableObject {
    private let apiKey = "YOUR_OPENAI_API_KEY" // Replace with your actual API key
    private let baseURL = "https://api.openai.com/v1/audio/transcriptions"
    
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var errorMessage: String?
    @Published var isProcessing = false
    @Published var confidence: Float = 0.0
    
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private let audioEngine = AVAudioEngine()
    
    // Elderly-friendly settings
    private var elderlyModeEnabled: Bool {
        UserDefaults.standard.bool(forKey: "elderlyModeEnabled")
    }
    
    private var beamSearchEnabled: Bool {
        UserDefaults.standard.bool(forKey: "beamSearchEnabled")
    }
    
    private var primaryLanguage: String {
        UserDefaults.standard.string(forKey: "primaryLanguage") ?? "en"
    }
    
    // Completion handler
    var onTranscriptionComplete: ((String, Float) -> Void)?
    
    override init() {
        super.init()
        setupAudioSession()
    }
    
    // MARK: - Audio Session Setup
    
    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true)
            
            // Enhanced settings for elderly users
            if elderlyModeEnabled {
                try audioSession.setPreferredSampleRate(16000) // Optimal for Whisper
                try audioSession.setPreferredIOBufferDuration(0.02)
            }
        } catch {
            errorMessage = "Failed to setup audio session: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Recording Methods
    
    func startRecording() {
        guard !isRecording else { return }
        
        // Create temporary file for recording
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordingURL = documentsPath.appendingPathComponent("whisper_recording.m4a")
        
        guard let url = recordingURL else {
            errorMessage = "Failed to create recording URL"
            return
        }
        
        // Configure audio recorder settings optimized for Whisper
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: elderlyModeEnabled ? 16000 : 44100, // Lower sample rate for elderly mode
            AVNumberOfChannelsKey: 1, // Mono for better processing
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            AVEncoderBitRateKey: elderlyModeEnabled ? 64000 : 128000 // Lower bitrate for elderly mode
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.prepareToRecord()
            
            let success = audioRecorder?.record() ?? false
            if success {
                DispatchQueue.main.async {
                    self.isRecording = true
                    self.errorMessage = nil
                }
                print("Whisper recording started successfully")
            } else {
                errorMessage = "Failed to start recording"
            }
        } catch {
            errorMessage = "Failed to setup audio recorder: \(error.localizedDescription)"
        }
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        audioRecorder?.stop()
        
        DispatchQueue.main.async {
            self.isRecording = false
        }
        
        // Process the recorded audio with Whisper
        if let url = recordingURL {
            transcribeAudio(from: url)
        }
    }
    
    // MARK: - Whisper API Integration
    
    private func transcribeAudio(from url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "Recording file not found"
            return
        }
        
        DispatchQueue.main.async {
            self.isProcessing = true
        }
        
        // Create multipart form data request
        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Create request body
        var body = Data()
        
        // Add model parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)
        
        // Add language parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(primaryLanguage)\r\n".data(using: .utf8)!)
        
        // Add response format parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"response_format\"\r\n\r\n".data(using: .utf8)!)
        body.append("verbose_json\r\n".data(using: .utf8)!)
        
        // Enhanced parameters for elderly users
        if elderlyModeEnabled {
            // Add temperature for more consistent results
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"temperature\"\r\n\r\n".data(using: .utf8)!)
            body.append("0.2\r\n".data(using: .utf8)!)
        }
        
        // Add audio file
        do {
            let audioData = try Data(contentsOf: url)
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
            body.append(audioData)
            body.append("\r\n".data(using: .utf8)!)
        } catch {
            DispatchQueue.main.async {
                self.isProcessing = false
                self.errorMessage = "Failed to read audio file: \(error.localizedDescription)"
            }
            return
        }
        
        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        // Make API request
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isProcessing = false
            }
            
            if let error = error {
                DispatchQueue.main.async {
                    self?.errorMessage = "Network error: \(error.localizedDescription)"
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self?.errorMessage = "No data received from Whisper API"
                }
                return
            }
            
            // Parse response
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    self?.processWhisperResponse(json)
                } else {
                    DispatchQueue.main.async {
                        self?.errorMessage = "Invalid response format from Whisper API"
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.errorMessage = "Failed to parse Whisper response: \(error.localizedDescription)"
                }
            }
            
            // Clean up recording file
            try? FileManager.default.removeItem(at: url)
            
        }.resume()
    }
    
    private func processWhisperResponse(_ json: [String: Any]) {
        guard let text = json["text"] as? String else {
            DispatchQueue.main.async {
                self.errorMessage = "No transcription text in Whisper response"
            }
            return
        }
        
        // Calculate confidence from segments if available
        var avgConfidence: Float = 0.8 // Default confidence for Whisper
        
        if let segments = json["segments"] as? [[String: Any]] {
            var totalConfidence: Float = 0
            var segmentCount = 0
            
            for segment in segments {
                if let confidence = segment["avg_logprob"] as? Float {
                    // Convert log probability to confidence (approximate)
                    let normalizedConfidence = min(max((confidence + 1.0) / 2.0, 0.0), 1.0)
                    totalConfidence += normalizedConfidence
                    segmentCount += 1
                }
            }
            
            if segmentCount > 0 {
                avgConfidence = totalConfidence / Float(segmentCount)
            }
        }
        
        DispatchQueue.main.async {
            self.transcribedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            self.confidence = avgConfidence
            self.errorMessage = nil
            
            // Call completion handler
            self.onTranscriptionComplete?(self.transcribedText, avgConfidence)
        }
        
        print("Whisper transcription completed: '\(text)' with confidence: \(avgConfidence)")
    }
    
    // MARK: - Utility Methods
    
    func resetTranscription() {
        DispatchQueue.main.async {
            self.transcribedText = ""
            self.confidence = 0.0
            self.errorMessage = nil
        }
    }
    
    func isWhisperAvailable() -> Bool {
        return !apiKey.isEmpty && apiKey != "YOUR_OPENAI_API_KEY"
    }
}

// MARK: - AVAudioRecorderDelegate

extension WhisperService: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            Task { @MainActor in
                self.errorMessage = "Recording failed"
                self.isRecording = false
            }
        }
    }
    
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.errorMessage = "Recording error: \(error?.localizedDescription ?? "Unknown error")"
            self.isRecording = false
        }
    }
} 