//
//  OpenAIService.swift
//  SayItDone
//
//  Created by Assistant on 6/2/25.
//

import Foundation
import AVFoundation
import Combine

class OpenAIService: NSObject, ObservableObject {
    private let apiKey = "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"
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    // MARK: - Text-to-Speech Properties
    private let speechSynthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false
    @Published var speechRate: Float = 0.5 // Default speech rate (0.0 - 1.0)
    @Published var speechPitch: Float = 1.0 // Default pitch (0.5 - 2.0)
    @Published var speechVolume: Float = 1.0 // Default volume (0.0 - 1.0)
    
    // Speech completion callback
    var onSpeechComplete: (() -> Void)?
    
    override init() {
        super.init()
        setupSpeechSynthesizer()
    }
    
    // MARK: - Data Models
    
    struct ChatCompletionRequest: Codable {
        let model: String
        let messages: [Message]
        let maxTokens: Int?
        let temperature: Double?
        
        enum CodingKeys: String, CodingKey {
            case model, messages, temperature
            case maxTokens = "max_tokens"
        }
    }
    
    struct Message: Codable {
        let role: String
        let content: String
    }
    
    struct ChatCompletionResponse: Codable {
        let id: String
        let object: String
        let created: Int
        let model: String
        let choices: [Choice]
        let usage: Usage?
    }
    
    struct Choice: Codable {
        let index: Int
        let message: Message
        let finishReason: String?
        
        enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }
    
    struct Usage: Codable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
        
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
    
    // MARK: - Main API Function
    
    /// Sends transcribed text to GPT-4 and returns the assistant's response
    /// - Parameters:
    ///   - userPrompt: The transcribed text from speech recognition
    ///   - systemPrompt: Optional system prompt to guide the AI's behavior
    ///   - completion: Completion handler with the result
    func sendToGPT4(
        userPrompt: String,
        systemPrompt: String? = nil,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // Validate input
        guard !userPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(OpenAIError.emptyPrompt))
            return
        }
        
        // Update loading state
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        // Prepare messages
        var messages: [Message] = []
        
        // Add system prompt if provided
        if let systemPrompt = systemPrompt {
            messages.append(Message(role: "system", content: systemPrompt))
        }
        
        // Add user prompt
        messages.append(Message(role: "user", content: userPrompt))
        
        // Create request body
        let requestBody = ChatCompletionRequest(
            model: "gpt-4",
            messages: messages,
            maxTokens: 1000,
            temperature: 0.7
        )
        
        // Perform the API call
        performAPICall(with: requestBody) { [weak self] result in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                switch result {
                case .success(let response):
                    if let assistantMessage = response.choices.first?.message.content {
                        completion(.success(assistantMessage))
                    } else {
                        completion(.failure(OpenAIError.noResponse))
                    }
                case .failure(let error):
                    self?.errorMessage = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Async/await version of the GPT-4 function
    func sendToGPT4Async(
        userPrompt: String,
        systemPrompt: String? = nil
    ) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            sendToGPT4(userPrompt: userPrompt, systemPrompt: systemPrompt) { result in
                continuation.resume(with: result)
            }
        }
    }
    
    // MARK: - Private Methods
    
    private func performAPICall(
        with requestBody: ChatCompletionRequest,
        completion: @escaping (Result<ChatCompletionResponse, Error>) -> Void
    ) {
        // Create URL
        guard let url = URL(string: baseURL) else {
            completion(.failure(OpenAIError.invalidURL))
            return
        }
        
        // Create request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        // Encode request body
        do {
            let jsonData = try JSONEncoder().encode(requestBody)
            request.httpBody = jsonData
            
            print("OpenAI Request: \(String(data: jsonData, encoding: .utf8) ?? "Unable to encode")")
        } catch {
            completion(.failure(OpenAIError.encodingError(error)))
            return
        }
        
        // Perform request
        URLSession.shared.dataTask(with: request) { data, response, error in
            // Handle network error
            if let error = error {
                completion(.failure(OpenAIError.networkError(error)))
                return
            }
            
            // Check HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(OpenAIError.invalidResponse))
                return
            }
            
            // Handle HTTP errors
            guard 200...299 ~= httpResponse.statusCode else {
                if let data = data,
                   let errorString = String(data: data, encoding: .utf8) {
                    print("OpenAI Error Response: \(errorString)")
                    completion(.failure(OpenAIError.httpError(httpResponse.statusCode, errorString)))
                } else {
                    completion(.failure(OpenAIError.httpError(httpResponse.statusCode, "Unknown error")))
                }
                return
            }
            
            // Parse response data
            guard let data = data else {
                completion(.failure(OpenAIError.noData))
                return
            }
            
            do {
                let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
                print("OpenAI Response: \(response)")
                completion(.success(response))
            } catch {
                print("Decoding Error: \(error)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Raw Response: \(responseString)")
                }
                completion(.failure(OpenAIError.decodingError(error)))
            }
        }.resume()
    }
    
    private func setupSpeechSynthesizer() {
        speechSynthesizer.delegate = self
    }
}

// MARK: - Error Types

enum OpenAIError: LocalizedError {
    case emptyPrompt
    case invalidURL
    case encodingError(Error)
    case networkError(Error)
    case invalidResponse
    case httpError(Int, String)
    case noData
    case decodingError(Error)
    case noResponse
    
    var errorDescription: String? {
        switch self {
        case .emptyPrompt:
            return "The prompt cannot be empty"
        case .invalidURL:
            return "Invalid API URL"
        case .encodingError(let error):
            return "Failed to encode request: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, let message):
            return "HTTP error \(code): \(message)"
        case .noData:
            return "No data received from server"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .noResponse:
            return "No response from GPT-4"
        }
    }
}

// MARK: - Convenience Extensions

extension OpenAIService {
    /// Quick function to enhance task descriptions using GPT-4
    func enhanceTaskDescription(
        _ taskText: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let systemPrompt = """
        You are a helpful assistant that improves task descriptions. 
        Take the user's task and make it clearer, more specific, and actionable while keeping it concise.
        Only return the improved task description, nothing else.
        """
        
        sendToGPT4(userPrompt: taskText, systemPrompt: systemPrompt, completion: completion)
    }
    
    /// Quick function to get task suggestions based on transcribed text
    func getTaskSuggestions(
        from transcribedText: String,
        completion: @escaping (Result<[String], Error>) -> Void
    ) {
        let systemPrompt = """
        You are a helpful assistant that extracts actionable tasks from user speech.
        From the given text, extract 1-3 clear, specific tasks.
        Return only the tasks, one per line, without numbers or bullets.
        If no clear tasks can be identified, return "No clear tasks identified".
        """
        
        sendToGPT4(userPrompt: transcribedText, systemPrompt: systemPrompt) { result in
            switch result {
            case .success(let response):
                let tasks = response.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && $0 != "No clear tasks identified" }
                completion(.success(tasks))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

// MARK: - Text-to-Speech Methods

extension OpenAIService {
    /// Speaks the given text using AVSpeechSynthesizer
    /// - Parameters:
    ///   - text: The text to speak (e.g., GPT-4 response)
    ///   - language: Language code (default: "en-US")
    ///   - completion: Optional completion handler called when speech finishes
    func speakText(
        _ text: String,
        language: String = "en-US",
        completion: (() -> Void)? = nil
    ) {
        // Stop any current speech
        stopSpeaking()
        
        // Validate input
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("TTS: Cannot speak empty text")
            completion?()
            return
        }
        
        // Set completion callback
        onSpeechComplete = completion
        
        // Create speech utterance
        let utterance = AVSpeechUtterance(string: text)
        
        // Configure speech parameters
        utterance.rate = speechRate
        utterance.pitchMultiplier = speechPitch
        utterance.volume = speechVolume
        
        // Set voice (try to find the specified language, fallback to default)
        if let voice = AVSpeechSynthesisVoice(language: language) {
            utterance.voice = voice
        } else {
            print("TTS: Voice for language '\(language)' not found, using default")
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }
        
        // Configure audio session for speech
        configureAudioSessionForSpeech()
        
        // Update state and speak
        DispatchQueue.main.async {
            self.isSpeaking = true
        }
        
        speechSynthesizer.speak(utterance)
        print("TTS: Speaking text: '\(text.prefix(50))...'")
    }
    
    /// Stops current speech synthesis
    func stopSpeaking() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
            DispatchQueue.main.async {
                self.isSpeaking = false
            }
            print("TTS: Speech stopped")
        }
    }
    
    /// Pauses current speech synthesis
    func pauseSpeaking() {
        if speechSynthesizer.isSpeaking && !speechSynthesizer.isPaused {
            speechSynthesizer.pauseSpeaking(at: .immediate)
            print("TTS: Speech paused")
        }
    }
    
    /// Resumes paused speech synthesis
    func resumeSpeaking() {
        if speechSynthesizer.isPaused {
            speechSynthesizer.continueSpeaking()
            print("TTS: Speech resumed")
        }
    }
    
    /// Configures audio session for speech synthesis
    private func configureAudioSessionForSpeech() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("TTS: Failed to configure audio session: \(error)")
        }
    }
    
    /// Updates speech rate (0.0 - 1.0)
    func setSpeechRate(_ rate: Float) {
        speechRate = max(0.0, min(1.0, rate))
        print("TTS: Speech rate set to \(speechRate)")
    }
    
    /// Updates speech pitch (0.5 - 2.0)
    func setSpeechPitch(_ pitch: Float) {
        speechPitch = max(0.5, min(2.0, pitch))
        print("TTS: Speech pitch set to \(speechPitch)")
    }
    
    /// Updates speech volume (0.0 - 1.0)
    func setSpeechVolume(_ volume: Float) {
        speechVolume = max(0.0, min(1.0, volume))
        print("TTS: Speech volume set to \(speechVolume)")
    }
    
    /// Convenience method to send text to GPT-4 and speak the response
    func sendToGPT4AndSpeak(
        userPrompt: String,
        systemPrompt: String? = nil,
        language: String = "en-US",
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        sendToGPT4(userPrompt: userPrompt, systemPrompt: systemPrompt) { [weak self] result in
            switch result {
            case .success(let response):
                // Speak the GPT-4 response
                self?.speakText(response, language: language) {
                    print("TTS: Finished speaking GPT-4 response")
                }
                completion(.success(response))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
    
    /// Get available voices for text-to-speech
    func getAvailableVoices() -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices()
    }
    
    /// Get available voices for a specific language
    func getVoicesForLanguage(_ language: String) -> [AVSpeechSynthesisVoice] {
        return AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(language) }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension OpenAIService: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = true
        }
        print("TTS: Speech started")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
        print("TTS: Speech finished")
        onSpeechComplete?()
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didPause utterance: AVSpeechUtterance) {
        print("TTS: Speech paused")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didContinue utterance: AVSpeechUtterance) {
        print("TTS: Speech continued")
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.isSpeaking = false
        }
        print("TTS: Speech cancelled")
        onSpeechComplete?()
    }
} 