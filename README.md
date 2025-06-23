# Voice-to-Voice Assistant iOS App

A voice assistant iOS app built with SwiftUI, designed specifically for elderly users with large fonts, high contrast UI, and simple navigation.

## Features

### 🏠 Home Tab (Main Voice Assistant)
- **Large microphone button** at center bottom
- **Color-coded status indicators**:
  - 🔴 Red when idle/ready to listen
  - 🟢 Green when actively listening or AI is speaking
  - 🟣 Purple when processing with AI
  - 🟠 Orange when detecting silence
- **Real-time conversation display** with clear, large text
- **Voice synthesis** using AVSpeechSynthesizer
- **Speech recognition** using SFSpeechRecognizer
- **Automatic conversation flow** - just speak naturally!

### 🔔 Reminders Tab
- **Medication reminders** with pill icons
- **Task reminders** with bell icons
- **Daily scheduling** options
- **Large, easy-to-read cards**
- **Simple add/remove functionality**

### 📊 Reports Tab
- **Placeholder for future features**:
  - Conversation logs
  - Mood tracking
  - Health insights
  - Usage statistics

## Design Principles

### 🎯 Elderly-Friendly Design
- **Extra large fonts** (18-32pt) for better readability
- **High contrast colors** for visual clarity
- **Generous spacing** between UI elements
- **Simple, intuitive navigation**
- **Clear visual feedback** for all interactions
- **Rounded corners** and soft edges
- **Consistent color coding** throughout the app

### 🔧 Technical Features
- **SwiftUI** for modern, responsive UI
- **@State** and @AppStorage** for state management
- **Tab-based navigation** with clear icons
- **Automatic permission handling**
- **Real-time speech processing**
- **OpenAI integration** for intelligent responses

## Usage

1. **Grant Permissions**: Allow microphone and speech recognition access
2. **Start Talking**: The app automatically listens when you speak
3. **Get Responses**: AI processes your speech and responds with voice
4. **View History**: See your conversation in the scrollable display
5. **Set Reminders**: Use the Reminders tab for medications and tasks
6. **Check Reports**: View your usage history (coming soon)

## Requirements

- iOS 18.4+
- Xcode 16.3+
- Swift 5.0+
- OpenAI API key (configured in code)
- Device with microphone

## Installation

1. Clone the repository
2. Open `TEST.xcodeproj` in Xcode
3. Add your OpenAI API key in `ContentView.swift`
4. Build and run on device or simulator

## Accessibility

This app is designed with accessibility in mind:
- Large, readable fonts
- High contrast colors
- Clear visual indicators
- Simple gesture requirements
- Voice-first interaction model
- Intuitive tab navigation

---

*Designed for ease of use by elderly users while maintaining powerful voice AI capabilities.* 