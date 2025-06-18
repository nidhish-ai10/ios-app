//
//  ConversationViews.swift
//  TEST
//
//  Created by Bairineni Nidhish rao on 6/16/25.
//

import SwiftUI
import Speech

// MARK: - Chat Message View
struct ConversationMessageView: View {
    let message: ConversationMessage
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: message.isFromUser ? "person.circle.fill" : "brain.head.profile")
                .foregroundColor(message.isFromUser ? .blue : .purple)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(message.isFromUser ? "You:" : "AI Assistant:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(message.isFromUser ? .blue : .purple)
                
                Text(message.content)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                Text(DateFormatter.conversationTime.string(from: message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(message.isFromUser ? Color.blue.opacity(0.05) : Color.purple.opacity(0.05))
        .cornerRadius(12)
    }
}

// MARK: - Chat Scroll View
struct ChatScrollView: View {
    @ObservedObject var speechRecognizer: SpeechRecognizer
    let permissionStatus: String
    
    var body: some View {
        ScrollViewReader { proxy in
            chatScrollContent
                .onChange(of: speechRecognizer.conversationHistory.count) { _, _ in
                    scrollToLatestMessage(proxy: proxy)
                }
        }
    }
    
    private var chatScrollContent: some View {
        ScrollView {
            chatContentStack
                .padding(.vertical, 8)
        }
    }
    
    private var chatContentStack: some View {
        LazyVStack(alignment: .leading, spacing: 12) {
            // Status or conversation history
            if speechRecognizer.conversationHistory.isEmpty {
                StatusMessageView(permissionStatus: permissionStatus)
            } else {
                ConversationHistoryView(messages: speechRecognizer.conversationHistory)
            }
            
            // Current input while recording
            if speechRecognizer.isRecording && !speechRecognizer.transcript.isEmpty {
                CurrentInputView(transcript: speechRecognizer.transcript)
            }
            
            // Processing indicator
            if speechRecognizer.isProcessing {
                ProcessingIndicatorView()
            }
        }
    }
    
    private func scrollToLatestMessage(proxy: ScrollViewProxy) {
        if let lastMessage = speechRecognizer.conversationHistory.last {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                withAnimation(.easeInOut(duration: 0.5)) {
                    proxy.scrollTo(lastMessage.id, anchor: .bottom)
                }
            }
        }
    }
}

// MARK: - Supporting Views
struct StatusMessageView: View {
    let permissionStatus: String
    
    var body: some View {
        Text(permissionStatus)
            .font(.title3)
            .fontWeight(.regular)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id("status")
    }
}

struct ConversationHistoryView: View {
    let messages: [ConversationMessage]
    
    var body: some View {
        ForEach(messages, id: \.id) { message in
            ConversationMessageView(message: message)
                .id(message.id)
        }
    }
}

struct CurrentInputView: View {
    let transcript: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "person.circle.fill")
                .foregroundColor(.blue)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("You (typing...):")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                
                Text(transcript)
                    .font(.body)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
        .id("current-input")
    }
}

struct ProcessingIndicatorView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "brain.head.profile")
                .foregroundColor(.purple)
                .font(.title2)
            
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Assistant:")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.purple)
                
                ThinkingDotsView()
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.purple.opacity(0.05))
        .cornerRadius(12)
        .id("processing")
    }
}

struct ThinkingDotsView: View {
    @State private var animating = false
    
    var body: some View {
        HStack {
            Text("Thinking")
                .font(.body)
                .foregroundColor(.purple)
            
            ForEach(0..<3, id: \.self) { index in
                Text(".")
                    .font(.body)
                    .foregroundColor(.purple)
                    .opacity(animating ? 1.0 : 0.3)
                    .animation(
                        .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(Double(index) * 0.2),
                        value: animating
                    )
            }
        }
        .onAppear {
            animating = true
        }
    }
} 