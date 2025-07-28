# MCP Framework for Apple App Integration

This document describes the Model Context Protocol (MCP) framework implementation for integrating Apple system apps (Calendar, Notes, Reminders) with the AI Helper2 chatbot.

## Overview

The MCP framework provides a standardized way for AI assistants to interact with external tools and services. This implementation creates MCP servers for Apple's native apps, allowing the AI to perform actions like creating calendar events, adding reminders, and taking notes through natural language commands.

## Architecture

### Core Components

1. **MCPProtocol.swift** - Core MCP protocol definitions
2. **CalendarMCPServer.swift** - Calendar integration using EventKit
3. **NotesMCPServer.swift** - Notes integration using URL schemes and Intents
4. **RemindersMCPServer.swift** - Reminders integration using EventKit
5. **MCPAIService.swift** - Enhanced AI service with MCP integration
6. **MCPChatView.swift** - UI components for MCP-enabled chat

### MCP Protocol Structure

```swift
protocol MCPServer {
    func initialize() async throws
    func listResources() async throws -> [MCPResource]
    func listTools() async throws -> [MCPTool]
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPResult
}
```

## Features Implemented

### 📅 Calendar Integration (EventKit)
- **Tools Available:**
  - `create_event` - Create calendar events with title, dates, location, notes
  - `list_events` - List events in date range
  - `update_event` - Modify existing events
  - `delete_event` - Remove events
  - `search_events` - Find events by text search

- **Permissions Required:**
  - Calendar access (NSCalendarsUsageDescription)

### 📝 Notes Integration (URL Schemes + Intents)
- **Tools Available:**
  - `create_note` - Create new notes with content and optional title
  - `open_notes` - Open Notes app, optionally with search
  - `search_notes` - Search for notes (opens Notes with search)

- **Limitations:**
  - Uses URL schemes (limited read access)
  - Future: CloudKit integration for full CRUD operations

### 🔔 Reminders Integration (EventKit)
- **Tools Available:**
  - `create_reminder` - Create reminders with due dates, priority, location
  - `list_reminders` - List reminders by status, list, due date
  - `update_reminder` - Modify reminder properties
  - `delete_reminder` - Remove reminders
  - `search_reminders` - Find reminders by text
  - `complete_reminder` - Mark reminders as done/undone
  - `list_reminder_lists` - Show all reminder lists

- **Permissions Required:**
  - Reminders access (NSRemindersUsageDescription)

## Usage Examples

### Natural Language Commands

```
User: "Create a meeting with John tomorrow at 2 PM"
→ Triggers: calendar.create_event with parsed arguments

User: "Remind me to buy groceries at 6 PM"
→ Triggers: reminders.create_reminder with due date

User: "Take a note about today's meeting"
→ Triggers: notes.create_note with content

User: "Show me my events for this week"
→ Triggers: calendar.list_events with date range
```

### AI Service Integration

The `MCPAIService` class enhances the regular AI service with:
- Automatic tool detection from user messages
- Argument parsing using AI
- Tool execution and result integration
- Context-aware responses combining tool results with AI responses

## UI Components

### MCPChatView
- Enhanced chat interface with app integration status
- Quick action buttons for common tasks
- App integrations sheet showing available tools

### Settings Integration
- Toggle for enabling/disabling MCP features
- Visual indicators for available integrations
- Permission status display

## Implementation Details

### Permission Handling
```swift
// Calendar & Reminders
let status = EKEventStore.authorizationStatus(for: .event)
let granted = try await eventStore.requestAccess(to: .event)

// Notes (URL schemes)
await UIApplication.shared.canOpenURL(URL(string: "mobilenotes://")!)
```

### Tool Discovery
Tools are automatically discovered and made available to the AI:
```swift
let allTools = try await mcpManager.listAllTools()
// Returns: ["calendar": [tool1, tool2], "reminders": [tool3, tool4]]
```

### Message Processing
1. User sends message
2. Extract tool requests using pattern matching
3. Parse arguments using AI or manual patterns
4. Execute tools through MCP servers
5. Combine results with AI response

## Privacy & Security

- **Local Processing**: All MCP operations happen locally on device
- **Permissions**: Explicit user consent required for each app integration
- **Data Access**: Only accesses data as permitted by iOS frameworks
- **No Cloud Storage**: Tool results are not sent to external servers

## Future Enhancements

### Planned Features
1. **Enhanced Notes Integration**
   - CloudKit-based read/write access
   - Full CRUD operations for notes
   - Folder and tag management

2. **Additional App Support**
   - Contacts integration
   - Messages/iMessage integration
   - Photos and Files app integration

3. **Smart Tool Selection**
   - Machine learning for better tool detection
   - Context-aware argument parsing
   - Multi-tool workflows

4. **Advanced UI Features**
   - Tool execution history
   - Batch operations interface
   - Custom tool configuration

## Development Notes

### Build Requirements
- iOS 14.0+
- EventKit framework
- Intents framework (iOS 13.0+)
- Speech framework for voice integration

### Privacy Permissions Required
Add to your app's Info.plist or target settings:
```xml
<key>NSCalendarsUsageDescription</key>
<string>Access calendar to create and manage events via AI assistant</string>

<key>NSRemindersUsageDescription</key>
<string>Access reminders to create and manage tasks via AI assistant</string>

<key>NSSpeechRecognitionUsageDescription</key>
<string>Convert voice input to text for AI assistant commands</string>

<key>NSMicrophoneUsageDescription</key>
<string>Record voice input for AI assistant interaction</string>
```

### Testing Strategy
1. **Unit Tests**: Test individual MCP server implementations
2. **Integration Tests**: Test AI service with MCP integration
3. **UI Tests**: Test complete user workflows
4. **Device Testing**: Voice features require physical device

## Troubleshooting

### Common Issues
1. **Permission Denied**: Check app permissions in Settings
2. **Tool Not Found**: Verify MCP server initialization
3. **Parse Errors**: Check argument format and types
4. **Voice Issues**: Test on physical device, check microphone permissions

### Debug Tips
- Enable console logging for MCP operations
- Use Xcode debugger for EventKit operations
- Test URL schemes in Safari first
- Verify Intent donation in Shortcuts app

## Conclusion

This MCP framework provides a robust foundation for integrating Apple system apps with AI assistants. The modular design allows for easy extension to additional apps and services while maintaining security and user privacy.

The implementation demonstrates how AI assistants can move beyond simple text responses to become powerful automation tools that interact with the user's digital environment in meaningful ways.