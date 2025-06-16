import Foundation

class MemoryService {
    static let shared = MemoryService()
    private let openAIService = OpenAIService()
    private(set) var storedMemories: [MemoryEvent] = []
    private let memoryStorageKey = "storedMemories"
    
    private init() {}

    struct MemoryEvent: Codable {
        let type: String
        let content: String
        let source: String
        var timestamp: String
        let tags: [String]
        let confidence: Double
    }
        
    /// Analyzes a single conversation snippet and returns events only if meaningful information is found
    func analyzeSnippet(assistantMessage: String, userMessage: String) async throws -> [[String: Any]]? {
        let prompt = """
        Analyze this single conversation snippet and extract ONLY specific, meaningful information that should be stored.
        If there is no clear, specific information worth storing, return an empty array.

        Return an array of events in JSON format, where each event follows this structure:
        {
          "type": "memory",
          "content": "User enjoys classical music.",
          "source": "conversation",
          "timestamp": "2025-06-16T15:00:00Z",
          "tags": ["music", "preference"],
          "confidence": 0.9
        }

        IMPORTANT RULES:
        1. Only include events where you have clear, specific information
        2. Do not return any information that is not explicitly stated in the conversation
        3. If there is no clear, specific information worth storing, return an empty array
        4. Do not make assumptions or infer information
        5. Only extract information that is explicitly stated
        6. Keep tags very simple and general for easy searching

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

    func saveMemories(memories: [MemoryEvent]) async throws {
        storedMemories.append(contentsOf: memories)
        if let data = try? JSONEncoder().encode(storedMemories) {
            UserDefaults.standard.set(data, forKey: memoryStorageKey)
        }
    }

    func loadStoredMemories() {
        if let data = UserDefaults.standard.data(forKey: memoryStorageKey),
        let memories = try? JSONDecoder().decode([MemoryEvent].self, from: data) {
            storedMemories = memories
        }
    }

    func searchMemories(query: [String]) async throws -> [[String: Any]]? {
        let matchingMemories = storedMemories.filter { memory in
            memory.tags.contains { tag in
                query.contains { searchTag in
                    tag.localizedCaseInsensitiveContains(searchTag)
                }
            }
        }
        guard !matchingMemories.isEmpty else { return nil }

        // Convert to [[String: Any]] for compatibility
        let encodedData = try JSONEncoder().encode(matchingMemories)
        let jsonObject = try JSONSerialization.jsonObject(with: encodedData) as? [[String: Any]]
        return jsonObject
    }
}
