//
//  SubtitleBarView.swift
//  SayItDone
//
//  Enhanced subtitle bar for elderly users with real-time speech transcription
//

import SwiftUI

struct SubtitleBarView: View {
    @ObservedObject var speechService: SpeechRecognitionService
    @AppStorage("elderlyModeEnabled") private var elderlyModeEnabled = false
    @AppStorage("subtitleFontSize") private var subtitleFontSize: Double = 18.0
    @AppStorage("highContrastMode") private var highContrastMode = false
    
    // Animation states
    @State private var isVisible = false
    @State private var confidenceAnimation = false
    
    var body: some View {
        VStack(spacing: 0) {
            if shouldShowSubtitles {
                VStack(spacing: 8) {
                    // Confidence indicator
                    if elderlyModeEnabled && speechService.speechConfidence > 0 {
                        HStack {
                            Text("Recognition Quality:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 2) {
                                ForEach(0..<5) { index in
                                    Circle()
                                        .fill(confidenceColor(for: index))
                                        .frame(width: 8, height: 8)
                                        .scaleEffect(confidenceAnimation ? 1.2 : 1.0)
                                        .animation(.easeInOut(duration: 0.3).delay(Double(index) * 0.1), value: confidenceAnimation)
                                }
                            }
                            
                            Spacer()
                            
                            // Slow speech indicator
                            if speechService.isSlowSpeechMode {
                                HStack(spacing: 4) {
                                    Image(systemName: "tortoise.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    Text("Slow Speech Detected")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
                    
                    // Main subtitle text
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Text(displayText)
                                .font(.system(size: CGFloat(subtitleFontSize), weight: .medium, design: .rounded))
                                .foregroundColor(textColor)
                                .multilineTextAlignment(.center)
                                .lineLimit(elderlyModeEnabled ? 2 : 3)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(backgroundColor)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(borderColor, lineWidth: elderlyModeEnabled ? 2 : 1)
                                        )
                                )
                                .shadow(color: shadowColor, radius: 4, x: 0, y: 2)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Corrected transcript (if different from original)
                    if elderlyModeEnabled && !speechService.correctedTranscript.isEmpty && 
                       speechService.correctedTranscript != speechService.subtitleText {
                        VStack(spacing: 4) {
                            Text("Corrected:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(speechService.correctedTranscript)
                                .font(.system(size: CGFloat(subtitleFontSize - 2), weight: .regular))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.green.opacity(0.1))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.green.opacity(0.3), lineWidth: 1)
                                        )
                                )
                        }
                        .padding(.horizontal)
                    }
                    
                    // Status indicators - Enhanced to show VAD status clearly
                    HStack(spacing: 16) {
                        Spacer()
                        
                        // Enhanced VAD status indicator
                        HStack(spacing: 4) {
                            if speechService.isVADActive && speechService.isVADEnabled {
                                // Active listening indicator
                                Image(systemName: "ear.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                
                                Text("Listening")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            } else if speechService.isVADEnabled {
                                // VAD enabled but not active (starting up)
                                Image(systemName: "ear")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                
                                Text("Starting...")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            } else {
                                // VAD disabled
                                Image(systemName: "ear.trianglebadge.exclamationmark")
                                    .foregroundColor(.red)
                                    .font(.caption)
                                
                                Text("Paused")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(UIColor.secondarySystemBackground))
                                .opacity(0.8)
                        )
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(containerBackgroundColor)
                        .shadow(color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                )
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        isVisible = true
                        confidenceAnimation = true
                    }
                }
                .onDisappear {
                    isVisible = false
                    confidenceAnimation = false
                }
            }
        }
        .onChange(of: speechService.speechConfidence) { _, _ in
            // Trigger confidence animation when confidence changes
            withAnimation(.easeInOut(duration: 0.2)) {
                confidenceAnimation.toggle()
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var shouldShowSubtitles: Bool {
        return speechService.isRecording || 
               speechService.isListening || 
               !speechService.subtitleText.isEmpty ||
               !speechService.correctedTranscript.isEmpty
    }
    
    private var displayText: String {
        if !speechService.subtitleText.isEmpty {
            return speechService.subtitleText
        } else if speechService.isRecording {
            return "🎤"
        } else {
            return ""
        }
    }
    
    private var textColor: Color {
        if highContrastMode {
            return .primary
        } else if elderlyModeEnabled {
            return .primary
        } else {
            return .primary
        }
    }
    
    private var backgroundColor: Color {
        if highContrastMode {
            return Color.black.opacity(0.9)
        } else if elderlyModeEnabled {
            return Color(UIColor.systemBackground)
        } else {
            return Color(UIColor.secondarySystemBackground)
        }
    }
    
    private var containerBackgroundColor: Color {
        if highContrastMode {
            return Color.black.opacity(0.8)
        } else {
            return Color(UIColor.systemBackground).opacity(0.95)
        }
    }
    
    private var borderColor: Color {
        if highContrastMode {
            return .white
        } else if speechService.speechConfidence < 0.5 {
            return .orange
        } else if speechService.speechConfidence < 0.7 {
            return .yellow
        } else {
            return .green
        }
    }
    
    private var shadowColor: Color {
        return highContrastMode ? .white.opacity(0.3) : .black.opacity(0.1)
    }
    
    private func confidenceColor(for index: Int) -> Color {
        let confidence = speechService.speechConfidence
        let threshold = Float(index + 1) * 0.2
        
        if confidence >= threshold {
            if confidence >= 0.8 {
                return .green
            } else if confidence >= 0.6 {
                return .yellow
            } else {
                return .orange
            }
        } else {
            return .gray.opacity(0.3)
        }
    }
}

// MARK: - Preview

struct SubtitleBarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            Spacer()
            
            SubtitleBarView(speechService: {
                let service = SpeechRecognitionService()
                service.subtitleText = "This is a sample subtitle text for testing the subtitle bar component"
                service.speechConfidence = 0.85
                service.isListening = true
                return service
            }())
            
            Spacer()
        }
        .background(Color.gray.opacity(0.1))
    }
} 