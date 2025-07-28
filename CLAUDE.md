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
- `NSCalendarsUsageDescription`: "We need calendar access to create events via AI assistant."

## Project Structure

The project follows a clean, organized folder structure for better maintainability:

```
AI Helper2/
├── App/                          # Application entry point
│   ├── AI_Helper2App.swift      # SwiftUI App entry point
│   └── ContentView.swift        # Root content view
├── Views/                        # UI Components by feature
│   ├── Chat/ChatView.swift      # Chat interface with MCP integration
│   └── Settings/SettingsView.swift # Configuration UI
├── Models/                       # Data models and ViewModels
│   └── Models.swift             # Core models (ChatMessage, APIConfiguration, etc.)
├── Services/                     # Business logic and integrations
│   ├── AI/                      # AI service implementations
│   │   ├── AIService.swift      # Base AI service
│   │   └── SimpleMCPAIService.swift # MCP-enhanced AI service
│   ├── MCP/                     # Model Context Protocol
│   │   ├── SimpleMCPProtocol.swift # MCP protocol definitions
│   │   └── SimpleCalendarMCPServer.swift # Calendar integration
│   └── Voice/VoiceInputManager.swift # Speech recognition
└── Resources/Assets.xcassets     # Visual assets
```

## Architecture Overview

### Core Data Flow
1. **ChatView** → **ChatViewModel** → **SimpleMCPAIService** (if MCP enabled) → AI API
2. **SimpleCalendarMCPServer** → EventKit → iOS Calendar
3. **VoiceInputManager** → Speech-to-text → **ChatViewModel**
4. **SettingsView** → **APIConfiguration** → UserDefaults persistence

### Key Components

**Models/Models.swift** - Central data layer:
- `AIProvider` enum with `availableModels` arrays for OpenAI/Claude
- `APIConfiguration` struct with provider, apiKey, model, maxTokens, temperature, enableMCP
- `ChatViewModel` ObservableObject managing state and MCP integration
- `MaxTokensOption` enum for preset token limits

**Services/AI/AIService.swift** - Base AI API abstraction with context:
- `sendMessage()` automatically adds current date/time context to all messages
- `sendMessageWithoutContext()` for internal system prompts that already have context
- `addCommonContext()` generates comprehensive context (date, time, timezone, device, locale)
- `sendOpenAIMessage()` - uses chat/completions endpoint with Bearer auth
- `sendClaudeMessage()` - uses messages endpoint with x-api-key header

**Services/AI/SimpleMCPAIService.swift** - Enhanced AI with MCP:
- Detects calendar requests in natural language
- Uses AI to extract event details (title, date, time, duration)
- Creates calendar events via MCP server
- Falls back to regular AI for non-calendar requests

**Services/MCP/SimpleMCPProtocol.swift** - MCP framework:
- `SimpleMCPServer` protocol for tool integrations
- `SimpleMCPManager` for server coordination
- Basic MCP data structures for tool definitions

**Services/MCP/SimpleCalendarMCPServer.swift** - Calendar MCP server:
- EventKit integration with iOS 17+ permission handling
- `create_event` tool for calendar event creation
- Proper error handling and permission management

**Views/Chat/ChatView.swift** - Main UI with MCP features:
- Message bubbles with calendar event indicators
- MCP status indicator in navigation bar
- Quick action buttons for common calendar tasks
- Voice input integration

**Services/Voice/VoiceInputManager.swift** - Speech integration:
- Manages AVAudioSession and SFSpeechRecognizer
- Real-time transcription with permission handling

**Views/Settings/SettingsView.swift** - Configuration UI:
- Provider picker (segmented control)
- Model dropdown (MenuPickerStyle) - auto-updates on provider change
- Max tokens dropdown with preset options
- Temperature slider with labels
- Calendar integration toggle with status indicator

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
1. Add case to `AIProvider` enum in `Models/Models.swift` with baseURL and availableModels
2. Implement provider method in `Services/AI/AIService.swift`
3. Settings UI in `Views/Settings/SettingsView.swift` will automatically include new provider

### Adding New MCP Integrations
1. Create new server class in `Services/MCP/` implementing `SimpleMCPServer`
2. Register server in `SimpleMCPManager` within `Services/MCP/SimpleMCPProtocol.swift`
3. Update `Services/AI/SimpleMCPAIService.swift` to handle new tool requests
4. Add UI indicators in `Views/Chat/ChatView.swift` and `Views/Settings/SettingsView.swift`

### Voice Feature Testing
- Requires physical device (simulator microphone is limited)  
- Check permissions in `Services/Voice/VoiceInputManager.swift`
- Audio session management in startRecording/stopRecording methods

### Modifying Chat UI
- Message components in `Views/Chat/ChatView.swift`
- Quick action buttons can be added to `ChatInputView`
- Calendar event indicators in `MessageBubble` component

### Settings and Configuration
- Model dropdowns auto-populate from `provider.availableModels` in `Models/Models.swift`
- Provider changes trigger `.onChange` to reset model selection
- Max tokens uses enum with display names for user clarity
- MCP toggle affects which AI service is used (`AIService` vs `SimpleMCPAIService`)

### Calendar Integration Development
- Calendar server in `Services/MCP/SimpleCalendarMCPServer.swift`
- EventKit permissions handled automatically for iOS 17+
- Add new calendar tools by extending the `listTools()` method
- Natural language parsing in `Services/AI/SimpleMCPAIService.swift`

## Project Structure Notes

- Clean folder organization by feature and responsibility
- Modern Xcode project format (no manual Info.plist file)
- Privacy permissions configured in target settings, not separate plist
- No external dependencies - uses system frameworks only (EventKit, Speech, etc.)
- Test targets included but minimally implemented
- All MCP functionality is self-contained in `Services/MCP/` folder