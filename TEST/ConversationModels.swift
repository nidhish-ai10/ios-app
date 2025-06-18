//
//  ConversationModels.swift
//  TEST
//
//  Created by Bairineni Nidhish rao on 6/16/25.
//

import Foundation

// MARK: - UI Conversation Models
struct ConversationMessage {
    let id = UUID()
    let content: String
    let isFromUser: Bool
    let timestamp: Date
}

// MARK: - DateFormatter Extension
extension DateFormatter {
    static let conversationTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
} 