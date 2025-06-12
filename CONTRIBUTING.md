# Contributing to SayItDone

Thank you for your interest in contributing to SayItDone! This document provides guidelines and instructions for contributing to this project.

## Code of Conduct

By participating in this project, you agree to maintain a respectful and inclusive environment for everyone.

## How to Contribute

### Reporting Bugs

If you find a bug, please create an issue with:
- A clear title and description
- Steps to reproduce the bug
- Expected behavior
- Screenshots (if applicable)
- Device information (iOS version, device model)

### Suggesting Enhancements

If you have ideas for enhancements:
- Clearly describe the feature
- Explain why it would be valuable
- Provide examples of how it would work

### Pull Requests

1. Fork the repository
2. Create a branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Run tests and ensure they pass
5. Commit your changes (`git commit -m 'Add some amazing feature'`)
6. Push to your branch (`git push origin feature/amazing-feature`)
7. Open a Pull Request

## Development Setup

1. Clone the repository:
```bash
git clone https://github.com/yourusername/SayItDone.git
cd SayItDone
```

2. Open the Xcode project:
```bash
open SayItDone.xcodeproj
```

3. Install SwiftLint (optional but recommended):
```bash
brew install swiftlint
```

## Coding Guidelines

### Swift Style Guide

We follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) and enforce them with SwiftLint.

Key points:
- Use descriptive names
- Follow camelCase for variables and functions, PascalCase for types
- Use meaningful parameter names
- Document public methods and properties

### Architecture

We follow the MVVM (Model-View-ViewModel) architecture:
- Models: Data structures and business logic
- Views: UI components
- ViewModels: Mediators between Models and Views

### Testing

- Write unit tests for all new features
- Ensure all tests pass before submitting a PR
- UI tests are encouraged for UI components

## Git Workflow

1. **Branch Naming**:
   - `feature/short-description` for new features
   - `bugfix/issue-number-description` for bug fixes
   - `refactor/description` for code refactoring
   - `docs/description` for documentation updates

2. **Commit Messages**:
   - Use present tense ("Add feature" not "Added feature")
   - First line should be 50 characters or less
   - Reference issues or PRs when relevant

3. **Pull Request Process**:
   - PRs require at least one review before merging
   - Address all reviewer comments
   - Ensure CI checks pass
   - Update documentation if necessary

## Resources

- [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)
- [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/platforms/ios) 