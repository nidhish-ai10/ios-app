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
    // SECURITY: API key should be stored securely, not hardcoded
    // For development: Set your API key in Xcode scheme environment variables
    // For production: Use Keychain or secure configuration
    private let apiKey: String = {
        // Try to get from environment variable first (recommended)
        if let envKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"] {
            return envKey
        }
        
        // Fallback: You can temporarily set your key here for development
        // IMPORTANT: Never commit your actual API key to version control!
        return "REPLACE_WITH_ACTUAL_OPENAI_KEY" // Replace with your actual key locally
    }()
    
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastResponse: String = ""
    
    // Retry configuration
    private let maxRetries = 3
    private let retryDelay: TimeInterval = 1.0
    
    // MARK: - Text-to-Speech Properties
    private let speechSynthesizer = AVSpeechSynthesizer()
    @Published var isSpeaking = false
    @Published var speechRate: Float = 0.5 // Default speech rate (0.0 - 1.0)
    @Published var speechPitch: Float = 1.0 // Default pitch (0.5 - 2.0)
    @Published var speechVolume: Float = 1.0 // Default volume (0.0 - 1.0)
    
    // Speech completion callback - using a queue to handle multiple callbacks
    private var speechCompletionCallbacks: [() -> Void] = []
    private let callbackQueue = DispatchQueue(label: "speechCallbacks", qos: .userInitiated)
    
    override init() {
        super.init()
        setupSpeechSynthesizer()
    }
    
    // MARK: - Data Models
    
    struct ChatCompletionRequest: Codable {
        let model: String
        let messages: [ChatMessage]
        let maxTokens: Int?
        let temperature: Double?
        
        enum CodingKeys: String, CodingKey {
            case model, messages, temperature
            case maxTokens = "max_tokens"
        }
    }
    
    struct ChatMessage: Codable {
        let role: String
        let content: String
    }
    
    struct ChatCompletionResponse: Codable {
        let id: String
        let object: String
        let created: Int
        let model: String
        let choices: [ChatChoice]
        let usage: Usage?
    }
    
    struct ChatChoice: Codable {
        let index: Int
        let message: ChatMessage
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
    
    // MARK: - Enhanced Main API Function
    
    /// Send transcribed text to GPT-3.5-turbo with retry logic and better error handling
    func sendToGPT4(prompt: String, completion: @escaping (Result<String, Error>) -> Void) {
        sendToGPT4WithRetry(prompt: prompt, retryCount: 0, completion: completion)
    }
    
    private func sendToGPT4WithRetry(prompt: String, retryCount: Int, completion: @escaping (Result<String, Error>) -> Void) {
        // Validate API key first
        guard !apiKey.contains("REPLACE_WITH_ACTUAL_OPENAI_KEY") && apiKey.hasPrefix("sk-") else {
            completion(.failure(OpenAIError.invalidAPIKey))
            return
        }
        
        // Validate input
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completion(.failure(OpenAIError.emptyPrompt))
            return
        }
        
        // Update loading state
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        // Create the request with optimized settings
        let requestBody = ChatCompletionRequest(
            model: "gpt-3.5-turbo",
            messages: [
                ChatMessage(role: "system", content: "You are a helpful, concise assistant. Keep responses brief and conversational (1-2 sentences max)."),
                ChatMessage(role: "user", content: prompt)
            ],
            maxTokens: 100, // Reduced for faster responses and lower cost
            temperature: 0.7
        )
        
        // Send the request
        sendChatCompletionRequest(requestBody: requestBody) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                self.isLoading = false
                
                switch result {
                case .success(let response):
                    if let message = response.choices.first?.message.content.trimmingCharacters(in: .whitespacesAndNewlines) {
                        self.lastResponse = message
                        print("✅ OpenAI Success: \(message)")
                        completion(.success(message))
                    } else {
                        completion(.failure(OpenAIError.noResponse))
                    }
                    
                case .failure(let error):
                    // Handle specific errors with retry logic
                    if self.shouldRetry(error: error) && retryCount < self.maxRetries {
                        print("🔄 Retrying OpenAI request (\(retryCount + 1)/\(self.maxRetries))")
                        
                        // Exponential backoff
                        let delay = self.retryDelay * pow(2.0, Double(retryCount))
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                            self.sendToGPT4WithRetry(prompt: prompt, retryCount: retryCount + 1, completion: completion)
                        }
                    } else {
                        // Final failure
                        self.errorMessage = self.getUserFriendlyError(error)
                        print("❌ OpenAI Error: \(error.localizedDescription)")
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    /// Enhanced function for task-specific queries with better prompting
    func processTaskQuery(transcribedText: String, completion: @escaping (Result<String, Error>) -> Void) {
        let enhancedPrompt = """
        User said: "\(transcribedText)"
        
        Respond helpfully and briefly (1-2 sentences). If it's:
        - A question: Give a concise, helpful answer
        - A greeting: Respond warmly
        - A request: Acknowledge and offer brief guidance
        - General chat: Be friendly and conversational
        """
        
        sendToGPT4(prompt: enhancedPrompt, completion: completion)
    }
    
    /// Speak the GPT-4 response using text-to-speech
    func speakResponse(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.volume = 0.8
        
        speechSynthesizer.speak(utterance)
    }
    
    /// Stop speaking if currently active
    func stopSpeaking() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
        }
    }
    
    // MARK: - Private Methods
    
    private func sendChatCompletionRequest(
        requestBody: ChatCompletionRequest,
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
        } catch {
            completion(.failure(OpenAIError.encodingError(error)))
            return
        }
        
        // Send request
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
    
    // MARK: - Enhanced Error Handling
    
    private func shouldRetry(error: Error) -> Bool {
        if let openAIError = error as? OpenAIError {
            switch openAIError {
            case .networkError(_):
                return true // Network issues can be temporary
            case .httpError(let code, _):
                // Retry on server errors (5xx) and some client errors
                return code >= 500 || code == 429 // Rate limiting
            default:
                return false
            }
        }
        return false
    }
    
    private func getUserFriendlyError(_ error: Error) -> String {
        if let openAIError = error as? OpenAIError {
            switch openAIError {
            case .httpError(429, _):
                return "OpenAI usage limit reached. Please add credits to your account."
            case .httpError(401, _):
                return "Invalid OpenAI API key. Please check your key."
            case .networkError(_):
                return "Network connection issue. Please check your internet."
            case .invalidAPIKey:
                return "Please set up your OpenAI API key."
            default:
                return "AI service temporarily unavailable."
            }
        }
        return "AI service error occurred."
    }
    
    // MARK: - Combined GPT-4 Processing Function
    
    /// Complete GPT-4 processing pipeline: Send → Display → Speak
    /// - Parameters:
    ///   - transcribedText: The user's transcribed speech
    ///   - showFeedback: Closure to display feedback messages in UI
    ///   - provideHaptic: Closure to provide haptic feedback
    ///   - completion: Called when the entire process completes
    func processTranscribedTextComplete(
        _ transcribedText: String,
        showFeedback: @escaping (String, TimeInterval) -> Void,
        provideHaptic: @escaping () -> Void,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        // Step 1: Show loading state
        showFeedback("🤔 Thinking...", 0.5)
        
        // Step 2: Send to GPT-4
        processTaskQuery(transcribedText: transcribedText) { [weak self] result in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                switch result {
                case .success(let response):
                    // Step 3: Display the response
                    showFeedback("🤖 \(response)", 4.0)
                    provideHaptic() // Success haptic
                    
                    // Step 4: Speak the response with completion callback
                    self.readGPT4ResponseAloud(response) {
                        // Wait a moment after speech completes before calling completion
                        // This ensures UI updates and speech synthesis are fully done
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            print("✅ Complete GPT-4 pipeline finished")
                            completion(.success(response))
                        }
                    }
                    
                case .failure(let error):
                    // Handle error with user-friendly message
                    let errorMessage = self.getErrorMessage(from: error)
                    showFeedback("❌ \(errorMessage)", 3.0)
                    
                    // Provide error-specific guidance
                    if errorMessage.contains("usage limit") {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
                            showFeedback("💡 Add OpenAI credits to enable AI features", 3.0)
                        }
                    }
                    
                    // For errors, call completion after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        completion(.failure(error))
                    }
                }
            }
        }
    }
    
    /// Get user-friendly error message from OpenAI errors
    private func getErrorMessage(from error: Error) -> String {
        if let openAIError = error as? OpenAIError {
            switch openAIError {
            case .httpError(429, _):
                return "OpenAI usage limit reached"
            case .httpError(401, _):
                return "Invalid OpenAI API key"
            case .networkError(_):
                return "Network connection issue"
            case .invalidAPIKey:
                return "OpenAI API key not configured"
            case .emptyPrompt:
                return "No text to process"
            case .noResponse:
                return "No response from AI"
            default:
                return "AI service temporarily unavailable"
            }
        }
        return "Something went wrong"
    }
    
    /// Reads GPT-4 response text aloud with optimized settings for AI responses
    /// - Parameters:
    ///   - responseText: The GPT-4 response text to speak
    ///   - completion: Optional completion handler called when speech finishes
    func readGPT4ResponseAloud(_ responseText: String, completion: (() -> Void)? = nil) {
        // Stop any current speech
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: AVSpeechBoundary.immediate)
        }
        
        // Validate input
        guard !responseText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("TTS: Cannot speak empty GPT-4 response")
            completion?()
            return
        }
        
        // Add completion callback to queue if provided
        if let completion = completion {
            callbackQueue.async {
                self.speechCompletionCallbacks.append(completion)
            }
        }
        
        // Create speech utterance with GPT-4 optimized settings
        let utterance = AVSpeechUtterance(string: responseText)
        
        // Optimized settings for AI responses
        utterance.rate = 0.55 // Slightly faster for conversational feel
        utterance.pitchMultiplier = 1.1 // Slightly higher pitch for clarity
        utterance.volume = 0.9 // High volume for clear delivery
        
        // Use a natural-sounding voice
        if let voice = AVSpeechSynthesisVoice(language: "en-US") {
            utterance.voice = voice
        }
        
        // Configure audio session for speech
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
            try audioSession.setActive(true)
        } catch {
            print("TTS: Failed to configure audio session: \(error)")
            // If audio session fails, still call completion
            completion?()
            return
        }
        
        // Update state and speak
        DispatchQueue.main.async {
            self.isSpeaking = true
        }
        
        speechSynthesizer.speak(utterance)
        print("TTS: Reading GPT-4 response: '\(responseText.prefix(50))...'")
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
    case invalidAPIKey
    
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
        case .invalidAPIKey:
            return "Please set a valid OpenAI API key in OpenAIService.swift"
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
        
        sendToGPT4(prompt: systemPrompt, completion: completion)
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
        
        sendToGPT4(prompt: systemPrompt) { result in
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
        callbackQueue.async {
            completion?()
        }
        
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
        sendToGPT4(prompt: userPrompt) { [weak self] result in
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
        print("TTS: Speech finished - executing completion callbacks")
        
        // Execute all completion callbacks
        callbackQueue.async {
            let callbacks = self.speechCompletionCallbacks
            self.speechCompletionCallbacks.removeAll()
            
            // Execute callbacks on main thread
            DispatchQueue.main.async {
                for callback in callbacks {
                    callback()
                }
            }
        }
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
        print("TTS: Speech cancelled - executing completion callbacks")
        
        // Execute all completion callbacks even when cancelled
        callbackQueue.async {
            let callbacks = self.speechCompletionCallbacks
            self.speechCompletionCallbacks.removeAll()
            
            // Execute callbacks on main thread
            DispatchQueue.main.async {
                for callback in callbacks {
                    callback()
                }
            }
        }
    }
} 