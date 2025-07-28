# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AI Helper2 is an iOS chatbot app supporting OpenAI and Claude APIs with voice input. Built with SwiftUI following MVVM architecture.

## Build and Development Commands

### Building
```bash
# Build the project
xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" -sdk iphonesimulator build

# Build and run on specific simulator
xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" -destination "platform=iOS Simulator,name=iPhone 16" build

# Clean build
xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" clean
```

### Testing
```bash
# Run all tests
xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" test

# Run specific test target
xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2Tests" test
```

### Required Privacy Permissions
Must add these to target's Info.plist settings in Xcode (not a separate file):
- `NSMicrophoneUsageDescription`: "We need microphone to record your voice input."
- `NSSpeechRecognitionUsageDescription`: "We need speech recognition to convert your voice input into text for creating calendar events."

## Architecture Overview

### Core Data Flow
1. **ChatView** → **ChatViewModel** → **AIService** → API
2. **VoiceInputManager** → Speech-to-text → **ChatViewModel**
3. **SettingsView** → **APIConfiguration** → UserDefaults persistence

### Key Components

**Models.swift** - Central data layer:
- `AIProvider` enum with `availableModels` arrays for OpenAI/Claude
- `APIConfiguration` struct with provider, apiKey, model, maxTokens, temperature
- `ChatViewModel` ObservableObject managing state and persistence
- `MaxTokensOption` enum for preset token limits

**AIService.swift** - API abstraction:
- `sendMessage()` routes to provider-specific methods
- `sendOpenAIMessage()` - uses chat/completions endpoint with Bearer auth
- `sendClaudeMessage()` - uses messages endpoint with x-api-key header

**ChatView.swift** - Main UI:
- Message bubbles with user/AI distinction
- Text input with voice toggle
- Loading states and auto-scroll

**VoiceInputManager.swift** - Speech integration:
- Manages AVAudioSession and SFSpeechRecognizer
- Real-time transcription with permission handling

**SettingsView.swift** - Configuration UI:
- Provider picker (segmented control)
- Model dropdown (MenuPickerStyle) - auto-updates on provider change
- Max tokens dropdown with preset options
- Temperature slider with labels

### Provider-Specific Details

**OpenAI**:
- Endpoint: `https://api.openai.com/v1/chat/completions`
- Auth: `Bearer {apiKey}` header  
- Models: gpt-4o, gpt-4o-mini, gpt-4-turbo, gpt-4, gpt-3.5-turbo, gpt-3.5-turbo-16k

**Claude**:
- Endpoint: `https://api.anthropic.com/v1/messages`
- Auth: `x-api-key: {apiKey}` header
- Version: `anthropic-version: 2023-06-01` header
- Models: claude-3-5-sonnet-20241022, claude-3-5-haiku-20241022, claude-3-opus-20240229, etc.

## Development Patterns

### State Management
- Use `@StateObject` for view models, `@ObservedObject` for passed objects
- `ChatViewModel` is central coordinator, created in ChatView
- Settings persist via JSON encoding to UserDefaults

### UI Conventions  
- SwiftUI with Navigation-based hierarchy
- Settings presented as sheet from toolbar button
- Custom view components (MessageBubble, VoiceInputView) for reusability
- Dropdown pickers use MenuPickerStyle for better UX

### Error Handling
- `AIServiceError` enum for service failures
- User-friendly error messages displayed as AI responses
- Permission checks before enabling voice features

## Common Tasks

### Adding AI Providers
1. Add case to `AIProvider` enum with baseURL and availableModels
2. Implement provider method in `AIService.sendMessage()`
3. Settings UI will automatically include new provider

### Voice Feature Testing
- Requires physical device (simulator microphone is limited)  
- Check permissions in VoiceInputManager.isAuthorized
- Audio session management in startRecording/stopRecording

### Modifying Settings UI
- Model dropdowns auto-populate from `provider.availableModels`
- Provider changes trigger `.onChange` to reset model selection
- Max tokens uses enum with display names for user clarity

## Project Structure Notes

- Modern Xcode project format (no manual Info.plist file)
- Privacy permissions configured in target settings, not separate plist
- No external dependencies - uses system frameworks only
- Test targets included but minimally implemented