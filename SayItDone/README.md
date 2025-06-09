# SayItDone

SayItDone is a voice-to-task iOS application that allows users to create tasks using natural speech. The app transcribes speech in real-time and automatically extracts task information, including due dates.

## Features

- Real-time speech transcription
- Automatic task creation from voice input
- Date extraction from natural language
- Task management (view, add, delete)
- Clean, intuitive user interface

## Requirements

- iOS 18.0+
- Xcode 16.0+
- Swift 5.0+

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/SayItDone.git
cd SayItDone
```

2. Open the Xcode project:
```bash
open SayItDone.xcodeproj
```

3. Build and run the app in the simulator or on a physical device.

## Project Structure

- `Models/`: Contains the data models for the app
  - `Task.swift`: Task model with title and due date
  - `TaskManager.swift`: Manages the task collection
- `Views/`: UI components
  - `TasksView.swift`: Main view for displaying and creating tasks
  - `TaskRowView.swift`: Individual task row representation
  - `SettingsView.swift`: Settings and configuration view
- `Services/`:
  - `SpeechRecognitionService.swift`: Handles speech recognition and text processing

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## Team Collaboration Guidelines

### Git Workflow

We follow a feature branch workflow:
1. Create a new branch for each feature or bug fix
2. Submit pull requests for code review
3. Merge to main branch after approval

### Coding Standards

- Follow the Swift API Design Guidelines
- Use SwiftLint for consistent code formatting
- Write meaningful commit messages
- Document public methods and complex logic
- Write unit tests for new features

### Code Review Process

All code changes require at least one reviewer approval before merging.
Code reviewers should check for:
- Code quality and maintainability
- Test coverage
- Documentation
- Performance considerations
- UI/UX consistency

## License

This project is licensed under the MIT License - see the LICENSE file for details. 