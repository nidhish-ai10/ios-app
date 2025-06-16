import Foundation

class ConversationAnalysisService {
    static let shared = ConversationAnalysisService()
    private let openAIService = OpenAIService()
    
    private init() {}
    
    /// Analyzes a single conversation snippet and returns events only if meaningful information is found
    func analyzeSnippet(assistantMessage: String, userMessage: String) async throws -> [[String: Any]]? {
        let prompt = """
        Analyze this single conversation snippet and extract ONLY specific, meaningful information that should be stored.
        If there is no clear, specific information worth storing, return an empty array.

        Return an array of events in JSON format, where each event follows this structure:
        {
            "event": "event_type",
            "data": {
                // Event-specific data fields
            }
        }

        Event types and their data structures:

        // User Preferences and Information
        - "preference": {
            "category": "topics/goals/constraints",
            "value": "the specific preference",
            "context": "additional context if available"
          }
        - "personal_info": {
            "type": "name/location/occupation",
            "value": "the specific information",
            "context": "additional context if available"
          }
        - "interaction_style": {
            "type": "communication_preference/response_time",
            "value": "the specific style",
            "context": "additional context if available"
          }

        // Specific Mentions
        - "mentioned_family_member": {
            "relation": "relationship type",
            "name": "person's name",
            "age": number,
            "details": "additional information"
          }
        - "mentioned_activity": {
            "activity": "activity name",
            "frequency": "how often",
            "preference": "likes/dislikes"
          }
        - "mentioned_location": {
            "place": "location name",
            "type": "home/work/other",
            "details": "additional context"
          }
        - "mentioned_goal": {
            "goal": "goal description",
            "timeline": "when they want to achieve it",
            "priority": "high/medium/low"
          }

        IMPORTANT RULES:
        1. Only include events where you have clear, specific information
        2. For each event, include only the fields where you have concrete information
        3. If you're unsure about any information, omit that field
        4. If there is no clear, specific information worth storing, return an empty array
        5. Do not make assumptions or infer information
        6. Only extract information that is explicitly stated
        7. For preferences, personal info, and interaction style, use the specific event types above
        8. For specific mentions (family, activities, etc.), use the mentioned_* event types

        Conversation snippet:
        Assistant: \(assistantMessage)
        User: \(userMessage)
        """
        
        return try await withCheckedThrowingContinuation { continuation in
            openAIService.sendToModel(prompt: prompt, model: .o3Mini) { result in
                switch result {
                case .success(let response):
                    // Parse the JSON response
                    guard let jsonData = response.data(using: .utf8),
                          let events = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
                        continuation.resume(throwing: NSError(domain: "ConversationAnalysis", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON response"]))
                        return
                    }
                    
                    // If no events were found, return nil
                    if events.isEmpty {
                        continuation.resume(returning: nil)
                        return
                    }
                    
                    // Add timestamp to each event
                    let timestamp = ISO8601DateFormatter().string(from: Date())
                    let eventsWithTimestamp = events.map { event -> [String: Any] in
                        var updatedEvent = event
                        updatedEvent["timestamp"] = timestamp
                        return updatedEvent
                    }
                    
                    continuation.resume(returning: eventsWithTimestamp)
                    
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
} 
