//
//  LLM.swift
//  TEST
//
//  Created by Bairineni Nidhish rao on 6/16/25.
//

import Foundation

// MARK: - ChatGPT API Models
struct ChatGPTRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxTokens: Int?
    let stream: Bool
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatGPTResponse: Codable {
    let id: String
    let object: String
    let created: Int
    let model: String
    let choices: [Choice]
    let usage: Usage?
}

struct Choice: Codable {
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

// MARK: - Error Types
enum LLMError: Error, LocalizedError {
    case noAPIKey
    case invalidResponse
    case networkError(NetworkError)
    case emptyResponse
    
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "No API key provided"
        case .invalidResponse:
            return "Invalid response from API"
        case .networkError(let networkError):
            return "Network error: \(networkError.localizedDescription)"
        case .emptyResponse:
            return "Received empty response from API"
        }
    }
}

// MARK: - LLM Manager
@MainActor
class LLMManager: ObservableObject {
    @Published var isLoading = false
    @Published var lastResponse: String = ""
    @Published var errorMessage: String?
    
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1/chat/completions"
    private let defaultModel = "gpt-4.1-nano"
    private let networkManager: NetworkManager
    
    init(apiKey: String, networkManager: NetworkManager = NetworkManager.shared) {
        self.apiKey = apiKey
        self.networkManager = networkManager
    }
    
    // MARK: - Public Methods
    
    /// Send a simple text message to ChatGPT
    func sendMessage(_ message: String, temperature: Double = 0.7, maxTokens: Int? = nil) async throws -> String {
        let messages = [ChatMessage(role: "user", content: message)]
        return try await sendMessages(messages, temperature: temperature, maxTokens: maxTokens)
    }
    
    /// Send a conversation (multiple messages) to ChatGPT
    func sendMessages(_ messages: [ChatMessage], temperature: Double = 0.7, maxTokens: Int? = nil) async throws -> String {
        isLoading = true
        errorMessage = nil
        
        defer {
            isLoading = false
        }
        
        do {
            let response = try await makeAPICall(messages: messages, temperature: temperature, maxTokens: maxTokens)
            
            guard let choice = response.choices.first else {
                throw LLMError.invalidResponse
            }
            
            let responseText = choice.message.content
            lastResponse = responseText
            return responseText
            
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    /// Process transcribed text with a specific prompt
    func processTranscription(_ transcription: String, systemPrompt: String = "You are a helpful assistant. Please respond to the following transcribed text:") async throws -> String {
        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: transcription)
        ]
        return try await sendMessages(messages)
    }
    
    /// Summarize long text
    func summarizeText(_ text: String) async throws -> String {
        let prompt = "Please provide a concise summary of the following text:\n\n\(text)"
        return try await sendMessage(prompt)
    }
    
    /// Answer questions based on transcribed content
    func answerQuestion(_ question: String, basedOn context: String) async throws -> String {
        let messages = [
            ChatMessage(role: "system", content: "Answer the following question based on the provided context. If the context doesn't contain enough information, say so."),
            ChatMessage(role: "user", content: "Context: \(context)\n\nQuestion: \(question)")
        ]
        return try await sendMessages(messages)
    }
    
    // MARK: - Private Methods
    
    private func makeAPICall(messages: [ChatMessage], temperature: Double, maxTokens: Int?) async throws -> ChatGPTResponse {
        guard !apiKey.isEmpty else {
            throw LLMError.noAPIKey
        }
        
        guard let url = URL(string: baseURL) else {
            throw LLMError.networkError(.invalidURL)
        }
        
        let chatRequest = ChatGPTRequest(
            model: defaultModel,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: false
        )
        
        let headers = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
        
        do {
            let response = try await networkManager.post(
                url: url,
                body: chatRequest,
                headers: headers,
                responseType: ChatGPTResponse.self
            )
            
            return response
            
        } catch let networkError as NetworkError {
            throw LLMError.networkError(networkError)
        } catch {
            throw LLMError.networkError(.requestFailed(error))
        }
    }
}

// MARK: - Convenience Extensions
extension LLMManager {
    /// Create a conversation-style interaction
    static func createConversation(apiKey: String, networkManager: NetworkManager = NetworkManager.shared) -> LLMManager {
        return LLMManager(apiKey: apiKey, networkManager: networkManager)
    }
    
    /// Quick one-shot question
    static func quickQuery(_ query: String, apiKey: String, networkManager: NetworkManager = NetworkManager.shared) async throws -> String {
        let manager = LLMManager(apiKey: apiKey, networkManager: networkManager)
        return try await manager.sendMessage(query)
    }
}

// MARK: - Configuration
struct LLMConfiguration {
    static let defaultTemperature: Double = 0.7
    static let defaultMaxTokens: Int = 1000
    
    // Common system prompts
    struct SystemPrompts {
        static let assistant = "You are a helpful assistant."
        static let transcriptionProcessor = "You are an AI assistant that processes transcribed speech. Please respond naturally and helpfully to what the user has said."
        static let summarizer = "You are an expert at creating concise, accurate summaries."
        static let questionAnswerer = "You are an AI that answers questions based on provided context accurately and concisely."
    }
}

