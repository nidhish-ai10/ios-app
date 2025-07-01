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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.isFromUser ? "person.circle.fill" : "brain.head.profile")
                .foregroundColor(message.isFromUser ? .blue : .purple)
                .font(.title3)
            
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
        .cornerRadius(10)
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
        LazyVStack(alignment: .leading, spacing: 10) {
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
        .padding(.horizontal, 12)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Go ahead, I'm listening. 😊")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(10)
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
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "person.circle.fill")
                .foregroundColor(.blue)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("You (speaking...):")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                    
                    Spacer()
                    
                    // Animated dots to show recording
                    HStack(spacing: 2) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 4, height: 4)
                                .opacity(0.7)
                                .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.2), value: true)
                        }
                    }
                }
                
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
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.blue.opacity(0.2), lineWidth: 1)
        )
        .id("current-input")
    }
}

struct ProcessingIndicatorView: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "brain.head.profile")
                .foregroundColor(.purple)
                .font(.title3)
            
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
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.purple.opacity(0.2), lineWidth: 1)
        )
        .id("processing")
    }
}

struct ThinkingDotsView: View {
    @State private var animating = false
    
    var body: some View {
        HStack(spacing: 2) {
            Text("Thinking")
                .font(.body)
                .foregroundColor(.purple)
            
            ForEach(0..<3, id: \.self) { index in
                Text(".")
                    .font(.body)
                    .fontWeight(.bold)
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