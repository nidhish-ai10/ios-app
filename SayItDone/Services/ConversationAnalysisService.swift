import Foundation

class ConversationAnalysisService {
    static let shared = ConversationAnalysisService()
    private let openAIService = OpenAIService()
    
    private init() {}
    
    func analyzeConversation(_ messages: [String]) async throws -> [String: Any] {
        let prompt = """
        Analyze the following conversation and extract key information about the user. 
        Return the information in JSON format with the following structure:
        {
            "preferences": {
                "topics": [array of topics they're interested in],
                "goals": [array of their goals],
                "constraints": [array of any constraints mentioned]
            },
            "personal_info": {
                "name": "their name if mentioned",
                "location": "their location if mentioned",
                "occupation": "their occupation if mentioned"
            },
            "interaction_style": {
                "communication_preference": "their preferred communication style",
                "response_time": "their typical response time if mentioned"
            }
        }
        
        Conversation:
        \(messages.joined(separator: "\n"))
        """
        
        return try await withCheckedThrowingContinuation { continuation in
            openAIService.sendToGPT4(prompt: prompt) { result in
                switch result {
                case .success(let response):
                    // Parse the JSON response
                    guard let jsonData = response.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
                        continuation.resume(throwing: NSError(domain: "ConversationAnalysis", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON response"]))
                        return
                    }
                    continuation.resume(returning: json)
                    
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
} 