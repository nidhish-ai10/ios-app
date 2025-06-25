//
//  MemoryService.swift
//  TEST
//
//  Created by Valen Amarasingham on 6/19/25.
//

import Foundation
import NaturalLanguage

class MemoryService {
    static let shared = MemoryService()
    @MainActor private var LLM: LLMManager {
        LLMManager.shared
    }
    private(set) var storedMemories: [MemoryEvent] = []
    private let memoryStorageKey = "storedMemories"
    
    private init() {}

    struct MemoryEvent: Codable {
        let id: String
        let type: String
        let content: String
        let source: String
        var timestamp: String
        let tags: [String]
        let confidence: Double
    }
        
    /// Analyzes a single conversation snippet and returns events only if meaningful information is found
    func analyzeSnippet(assistantMessage: String = "", userMessage: String) async throws -> [[String: Any]]? {
        let prompt = """
        Analyze this single conversation snippet between the assistant and user and extract ONLY specific, meaningful information that should be stored.
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
        
        print("sending snippet to openai:")
        print("prompt: \(prompt)")
        let response = try await LLM.sendMessage(prompt)
        print("response: \(response)")
        if !response.isEmpty {
            guard let jsonData = response.data(using: .utf8),
                  let events = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
                return nil
            }
            print("recieved response, parsing")
            print("returning \(events.count) events")
            return events
        }
        return nil
    }

    func saveMemories(memories: [MemoryEvent]) async throws {
        print("recieved \(memories.count) memories to save")
        storedMemories.append(contentsOf: memories)
        if let data = try? JSONEncoder().encode(storedMemories) {
            UserDefaults.standard.set(data, forKey: memoryStorageKey)
        }
        for memory in memories {
            print("attempting to upload 1 memory")
            FirebaseUserService.shared.backupMemoryToFirebase(memory, completion: { _ in })
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

    func extractImportantWords(from message: String) -> [String] {
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = message.lowercased()
        var importantWords: [String] = []

        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]

        tagger.enumerateTags(in: message.startIndex..<message.endIndex,
                            unit: .word,
                            scheme: .lexicalClass,
                            options: options) { tag, tokenRange in
            if let tag = tag, tag == .noun || tag == .verb {
                let word = String(message[tokenRange])
                importantWords.append(word)
            }
            return true
        }

        return Array(Set(importantWords)) // Remove duplicates
    }
}

