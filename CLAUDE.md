# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

AI Helper2 is an iOS chatbot app supporting OpenAI and Claude APIs with voice input and MCP (Model Context Protocol) integrations. Built with SwiftUI following MVVM architecture.

**Key Documentation**:
- `docs/plans/2026-01-31-ai-helper-prd.md` - Product roadmap and improvement plans
- `docs/ITERATION_CHECKLIST.md` - Quality checklist for each iteration

---

## IMPORTANT: Pre-Push Checklist

**Before every push, verify these items pass:**

```bash
# 1. Build succeeds
xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" -sdk iphonesimulator build

# 2. Tests pass
xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" -destination "platform=iOS Simulator,name=iPhone 16" test
```

**Manual checks before push:**
- [ ] Build succeeds (no errors)
- [ ] Tests pass (all green)
- [ ] Code simplified (no unnecessary complexity)
- [ ] No compiler warnings
- [ ] No hardcoded secrets/API keys
- [ ] Docs aligned (CLAUDE.md, README match code)

**Full checklist**: See `docs/ITERATION_CHECKLIST.md` for comprehensive review.

---

## Build and Development Commands

### Building
```bash
# Build the project
xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" -sdk iphonesimulator build

# Build for specific simulator
xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" -destination "platform=iOS Simulator,name=iPhone 16" build

# Clean build
xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" clean

# Clean and rebuild
xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" clean build
```

### Testing
```bash
# Run all tests
xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" -destination "platform=iOS Simulator,name=iPhone 16" test

# Run specific test target
xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2Tests" -destination "platform=iOS Simulator,name=iPhone 16" test
```

### Code Quality
```bash
# Check for warnings (build and capture output)
xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" -sdk iphonesimulator build 2>&1 | grep -i warning

# Format Swift files (if swiftformat installed)
swiftformat "AI Helper2" --config .swiftformat
```

---

## Project Structure

```
AI Helper2/
├── App/                           # Application entry point
│   ├── AI_Helper2App.swift        # SwiftUI App entry point
│   └── ContentView.swift          # Root content view
├── Views/                         # UI Components
│   ├── Chat/ChatView.swift        # Main chat UI + calendar event buttons
│   └── Settings/SettingsView.swift # Configuration UI + API key validation
├── Models/                        # Data models
│   ├── Models.swift               # Core models, ChatViewModel
│   ├── ReasonActModels.swift      # Reason-Act step tracking (legacy)
│   └── Persistence.swift          # JSON-based conversation persistence
├── Services/
│   ├── AI/                        # AI service implementations
│   │   ├── SimpleAIService.swift  # Simple 2-call AI service with tool calling
│   │   ├── ToolModels.swift       # Universal tool interface (Tool, ToolCall, ToolResult)
│   │   ├── APIKeyValidator.swift  # API key validation for OpenAI/Claude
│   │   └── StreamingService.swift # SSE streaming for both providers
│   ├── MCP/                       # Model Context Protocol
│   │   ├── MCPProtocol.swift      # MCP protocol + manager
│   │   ├── CalendarMCPServer.swift # Calendar integration (7 tools)
│   │   └── RemindersMCPServer.swift # Reminders integration (5 tools)
│   ├── Voice/
│   │   ├── VoiceInputManager.swift # Voice recording + Whisper transcription
│   │   └── WhisperTranscriptionService.swift # OpenAI Whisper API
│   └── KeychainManager.swift      # Secure API key storage
├── Resources/Assets.xcassets      # Visual assets
└── docs/                          # Documentation
    ├── ITERATION_CHECKLIST.md     # Quality checklist
    └── plans/                     # PRDs and design docs
```

---

## Architecture Overview

### Core Components

| Component | File | Purpose |
|-----------|------|---------|
| **ChatViewModel** | Models/Models.swift | Central state coordinator |
| **SimpleAIService** | Services/AI/SimpleAIService.swift | ReAct loop AI with multi-server tool routing (max 5 iterations) |
| **ToolModels** | Services/AI/ToolModels.swift | Universal tool interface (OpenAI/Claude) |
| **StreamingService** | Services/AI/StreamingService.swift | SSE streaming for OpenAI/Claude |
| **APIKeyValidator** | Services/AI/APIKeyValidator.swift | Validates API keys before use |
| **KeychainManager** | Services/KeychainManager.swift | Secure API key storage |
| **PersistenceController** | Models/Persistence.swift | JSON-based conversation storage |
| **CalendarMCPServer** | Services/MCP/CalendarMCPServer.swift | Calendar tools (7 operations) |
| **RemindersMCPServer** | Services/MCP/RemindersMCPServer.swift | Reminders tools (7 operations) |
| **WhisperTranscriptionService** | Services/Voice/WhisperTranscriptionService.swift | OpenAI Whisper API for voice |

### Data Flow (ReAct Loop with Multi-Server Routing)
```
User message → AI reviews → needs tools?
                              │
              ┌───────────────┴───────────────┐
              ↓                               ↓
           NO: Reply                    YES: Route to server
           immediately                        ↓
                                      ┌───────┴───────┐
                                      ↓               ↓
                               Calendar tools   Reminder tools
                               (7 operations)   (7 operations)
                                      └───────┬───────┘
                                              ↓
                                      Validate results
                                              ↓
                                      Task done? ──→ YES: Reply
                                              │
                                              ↓ NO
                                      Loop back (max 5x)
```
- Simple questions: 1 API call, no tools
- Calendar/Reminders tasks: loops until complete or needs user input
- Tool routing based on tool name (calendar tools → CalendarMCPServer, reminder tools → RemindersMCPServer)

### Provider Configuration

**OpenAI**:
- Endpoint: `https://api.openai.com/v1/chat/completions`
- Auth: `Bearer {apiKey}` header (stored in Keychain)
- Models: gpt-5, gpt-5-mini, gpt-5-nano, o3, o4-mini, gpt-4.1, gpt-4.1-mini, gpt-4o
- Note: Reasoning models (o3, o4-mini) use "developer" role instead of "system" and ignore temperature

**Claude**:
- Endpoint: `https://api.anthropic.com/v1/messages`
- Auth: `x-api-key: {apiKey}` header (stored in Keychain)
- Version: `anthropic-version: 2023-06-01`
- Models: claude-opus-4-6, claude-sonnet-4-5, claude-haiku-4-5, claude-3-5-sonnet-20241022

---

## Development Patterns

### State Management
- `@StateObject` for view models created in view
- `@ObservedObject` for passed objects
- `@Published` for observable properties
- UserDefaults for non-sensitive settings
- Keychain for API keys (secure storage)

### Error Handling
- Custom error enums conforming to `LocalizedError`
- Errors logged with `os.log` Logger
- User-friendly messages shown in chat

### MCP Server Pattern
```swift
class NewMCPServer: MCPServer {
    func initialize() async throws { /* Setup */ }
    func listTools() async throws -> [MCPTool] { /* Tool definitions */ }
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPResult { /* Execute */ }
    func canHandle(message: String, ...) async -> MCPCapabilityResult { /* AI evaluation */ }
    func getServerName() -> String { /* Display name */ }
    func getServerDescription() -> String { /* Description */ }
}
```

---

## Common Tasks

### Adding New MCP Server
1. Create `Services/MCP/NewMCPServer.swift` implementing `MCPServer`
2. Define tools in `listTools()`
3. Implement tool execution in `callTool()`
4. Register in `SimpleAIService`:
   - Add server property
   - Initialize in `init()`
   - Add tool names to routing logic
   - Combine tools in chat method
   - Update system prompt with new sub-agent
5. Add required privacy permissions to Info.plist

### Adding AI Provider
1. Add case to `AIProvider` enum in `Models/Models.swift`
2. Implement provider method in `Services/AI/AIService.swift`
3. Add converter in `Services/AI/ProviderConverters.swift`

### Modifying Chat UI
1. Message display: `MessageBubble` in `ChatView.swift`
2. Input area: `ChatInputView` in `ChatView.swift`
3. Reason-Act timeline: `ReasonActTimelineView` in `ChatView.swift`

---

## Required Privacy Permissions

Add to target's Info.plist settings in Xcode:

**Current**:
- `NSMicrophoneUsageDescription` - Voice input (Whisper transcription)
- `NSCalendarsUsageDescription` - Calendar access
- `NSRemindersUsageDescription` - Reminders access

**Planned** (for future MCP servers):
- `NSContactsUsageDescription` - Contacts
- `NSHealthShareUsageDescription` - Health (read)
- `NSHealthUpdateUsageDescription` - Health (write)

---

## Code Quality Standards

### Before Committing
1. **Build passes** - No compilation errors
2. **Tests pass** - All tests green
3. **No warnings** - Zero compiler warnings
4. **Code simplified** - Remove unnecessary complexity
5. **No large files** - Split files > 500 lines

### Style Guidelines
- Follow Swift API Design Guidelines
- Use `// MARK: -` for file organization
- Document public APIs with `///` comments
- Use meaningful variable names (no single letters except loops)

### Avoid
- Force unwrapping (`!`) - use `guard let` or `if let`
- Hardcoded strings - extract to constants
- Duplicate code - extract to shared functions
- Deep nesting - extract to helper methods
