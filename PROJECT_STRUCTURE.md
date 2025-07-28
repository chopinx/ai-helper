# AI Helper2 - Project Structure

This document outlines the organized project structure for better maintainability and scalability.

## Directory Structure

```
AI Helper2/
├── App/                          # Application entry point and root views
│   ├── AI_Helper2App.swift      # SwiftUI App entry point
│   └── ContentView.swift        # Root content view
│
├── Views/                        # UI Components organized by feature
│   ├── Chat/                    # Chat-related views
│   │   └── ChatView.swift       # Main chat interface with message bubbles
│   └── Settings/                # Settings-related views
│       └── SettingsView.swift   # Configuration and settings UI
│
├── Models/                       # Data models and ViewModels
│   └── Models.swift             # Core data models (ChatMessage, APIConfiguration, etc.)
│
├── Services/                     # Business logic and external integrations
│   ├── AI/                      # AI service implementations
│   │   ├── AIService.swift      # Base AI service for OpenAI/Claude
│   │   └── SimpleMCPAIService.swift # MCP-enhanced AI service
│   ├── MCP/                     # Model Context Protocol implementations
│   │   ├── SimpleMCPProtocol.swift # MCP protocol definitions
│   │   └── SimpleCalendarMCPServer.swift # Calendar integration via EventKit
│   └── Voice/                   # Voice input functionality
│       └── VoiceInputManager.swift # Speech recognition service
│
└── Resources/                    # Static resources
    └── Assets.xcassets          # Images, colors, and other assets
```

## Architecture Overview

### App Layer
- **AI_Helper2App.swift**: SwiftUI application entry point
- **ContentView.swift**: Root view that hosts the main chat interface

### Views Layer
Organized by feature areas for better maintainability:

- **Chat/**: All chat-related UI components
  - Main chat interface with message bubbles
  - Voice input integration
  - MCP quick actions

- **Settings/**: Configuration and settings UI
  - API provider selection
  - MCP integration toggles
  - Parameter configuration

### Models Layer
- **Models.swift**: Contains all core data structures:
  - `ChatMessage`: Individual chat message data
  - `APIConfiguration`: AI service configuration
  - `ChatViewModel`: Main chat state management
  - `AIProvider`: Enumeration of supported AI providers

### Services Layer
Business logic organized by functionality:

- **AI/**: AI service implementations
  - `AIService`: Base service for OpenAI and Claude APIs
  - `SimpleMCPAIService`: Enhanced service with MCP capabilities

- **MCP/**: Model Context Protocol implementations
  - `SimpleMCPProtocol`: Core MCP definitions and manager
  - `SimpleCalendarMCPServer`: Calendar integration using EventKit

- **Voice/**: Voice input functionality
  - `VoiceInputManager`: Speech recognition and audio permissions

### Resources Layer
- **Assets.xcassets**: All visual assets including app icons and colors

## Benefits of This Structure

1. **Separation of Concerns**: Each layer has a clear responsibility
2. **Feature-based Organization**: Views are grouped by functionality
3. **Scalability**: Easy to add new features (e.g., new MCP servers, views)
4. **Maintainability**: Related files are grouped together
5. **Team Collaboration**: Clear ownership boundaries for different areas

## Adding New Features

### New MCP Integration
1. Create new server in `Services/MCP/`
2. Register in `SimpleMCPProtocol.swift`
3. Update `SimpleMCPAIService.swift` for integration

### New UI Feature
1. Create new folder under `Views/` (e.g., `Views/Calendar/`)
2. Add view files to the appropriate folder
3. Update navigation in `ContentView.swift` if needed

### New AI Provider
1. Update `AIProvider` enum in `Models.swift`
2. Add implementation in `AIService.swift`
3. Update settings UI in `Views/Settings/SettingsView.swift`

This structure provides a solid foundation for future development while keeping the codebase organized and maintainable.