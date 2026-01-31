# AI Helper 2 - Product Requirements Document

**Date**: 2026-01-31
**Status**: Draft
**Author**: Code Review Session

---

## 1. Executive Summary

**Current State**: AI Helper 2 is an iOS chatbot app that supports OpenAI and Claude APIs with voice input and calendar integration via a custom MCP (Model Context Protocol) implementation. The app features a Reason-Act orchestration loop for multi-step task completion.

**Vision**: Transform AI Helper into a powerful on-device AI assistant that integrates deeply with iOS capabilities, providing seamless natural language interaction for productivity tasks.

**Key Gaps Identified**:
- Limited MCP server coverage (only calendar)
- No streaming responses (waiting for full responses)
- Missing conversation persistence
- No user onboarding flow
- Limited error recovery and retry mechanisms

---

## 2. Current Architecture Assessment

| Component | Status | Quality |
|-----------|--------|---------|
| **AI Service Layer** | Functional | Good - supports both OpenAI/Claude with tool calling |
| **MCP Framework** | Partial | Good foundation - only calendar server implemented |
| **Reason-Act Loop** | Functional | Solid - 6-step max with error tracking |
| **Voice Input** | Functional | Basic - relies on Apple Speech framework |
| **UI/UX** | Functional | Needs polish - basic SwiftUI implementation |
| **Settings** | Functional | Minimal - no validation or guidance |

### 2.1 Current Project Structure

```
AI Helper2/
├── App/                          # Application entry point
│   ├── AI_Helper2App.swift
│   └── ContentView.swift
├── Views/                        # UI Components
│   ├── Chat/ChatView.swift       # Main chat interface + Reason-Act timeline
│   └── Settings/SettingsView.swift
├── Models/                       # Data models
│   ├── Models.swift              # Core models (ChatMessage, APIConfiguration, ChatViewModel)
│   └── ReasonActModels.swift     # Reason-Act step tracking
├── Services/
│   ├── AI/                       # AI service implementations
│   │   ├── AIService.swift       # Base AI service with tool calling
│   │   ├── MCPAIService.swift    # MCP-enhanced AI service
│   │   ├── UnifiedChatAgent.swift # Cross-provider agent with orchestration
│   │   ├── ContextManager.swift
│   │   └── ProviderConverters.swift
│   ├── MCP/                      # Model Context Protocol
│   │   ├── MCPProtocol.swift     # MCP protocol definitions
│   │   └── CalendarMCPServer.swift # Calendar integration
│   └── Voice/
│       └── VoiceInputManager.swift
└── Resources/Assets.xcassets
```

### 2.2 Current Features

- **Dual AI Provider Support**: OpenAI (GPT-4o, GPT-4, GPT-3.5) and Claude (3.5 Sonnet, 3.5 Haiku, 3 Opus)
- **Native Tool Calling**: Both providers support function calling for MCP tools
- **Reason-Act Orchestration**: Multi-step reasoning with up to 6 iterations
- **Calendar Integration**: 7 tools (create, list, update, delete, search, today, upcoming)
- **Voice Input**: Speech-to-text via Apple Speech framework
- **Context Awareness**: Auto-injects date, time, timezone, device info
- **Suggested Prompts**: Preset prompts across 5 categories (in Chinese)

---

## 3. Gap Analysis & Proposed Improvements

### 3.1 MCP/Tool Integrations

**Current State**: Only `CalendarMCPServer` is implemented with 7 tools.

**Gaps & Opportunities**:

| MCP Server | Priority | iOS Framework | Use Cases |
|------------|----------|---------------|-----------|
| **Reminders** | High | EventKit | Task management, to-do lists, recurring tasks |
| **Contacts** | High | Contacts | Look up people, add contacts, share info |
| **Notes** | Medium | - | Quick note capture (requires app group or files) |
| **Health** | Medium | HealthKit | Log workouts, check steps, health summaries |
| **Location** | Medium | CoreLocation | "Where am I?", nearby places, travel time |
| **Shortcuts** | Low | Shortcuts | Trigger iOS shortcuts via Siri Intents |
| **Files** | Low | FileManager | Document access in app sandbox |

**Recommendation**: Start with Reminders and Contacts - they share EventKit patterns and have high user value.

---

### 3.2 AI Capabilities

**Current State**:
- Single-shot requests with full response wait
- Reason-Act loop with max 6 steps
- Context injection (date, time, device info)
- Tool calling works for both providers

**Gaps**:

| Gap | Impact | Complexity |
|-----|--------|------------|
| **No streaming** | Poor UX - users wait for full response | Medium |
| **No conversation persistence** | Lost context on app restart | Low |
| **No system prompt customization** | Can't personalize assistant behavior | Low |
| **Limited context window management** | May hit token limits on long conversations | Medium |
| **No retry/fallback logic** | Single failure = error shown | Low |
| **No cost tracking** | Users unaware of API usage | Low |

**Proposed Improvements**:

#### 3.2.1 Streaming Responses (High Priority)
- Implement SSE parsing for both OpenAI and Claude
- Update UI to show incremental text
- Handle tool calls in streaming mode

#### 3.2.2 Conversation Persistence (High Priority)
- Store messages in CoreData or SQLite
- Load recent context on app launch
- Add conversation history/search

#### 3.2.3 System Prompt Configuration (Medium Priority)
- Allow users to set assistant personality
- Predefined personas (Professional, Casual, Technical)

---

### 3.3 User Experience

**Current State**:
- Basic chat interface with message bubbles
- Settings sheet with provider/model selection
- Suggested prompts in Chinese
- Reason-Act timeline visualization
- Voice input button

**Gaps**:

| Gap | Description |
|-----|-------------|
| **No onboarding** | Users must figure out API key setup themselves |
| **No API key validation** | Invalid keys fail silently on first message |
| **Language mismatch** | Suggested prompts in Chinese, UI in English |
| **No haptic feedback** | Missing tactile responses for actions |
| **Limited error messages** | Generic errors without recovery guidance |
| **No dark mode optimization** | Uses system colors but not fully optimized |
| **No iPad support** | No adaptive layout for larger screens |
| **No widget** | No quick-action widget for common tasks |

**Proposed Improvements**:

#### 3.3.1 Onboarding Flow (High Priority)
```
Welcome → Choose Provider → Enter API Key → Validate → Grant Permissions → Ready
```

#### 3.3.2 API Key Validation (High Priority)
- Test API key on entry with minimal request
- Show clear success/failure feedback
- Link to provider console for key creation

#### 3.3.3 Localization (Medium Priority)
- Extract all strings to Localizable.strings
- Support English and Chinese
- Match suggested prompts to system language

#### 3.3.4 Error Recovery UX (Medium Priority)
- Retry buttons on failed messages
- Specific guidance per error type
- Network connectivity indicator

---

### 3.4 Code Quality & Architecture

**Current State**:
- Clean folder structure (App/, Views/, Models/, Services/)
- MVVM pattern with ObservableObject
- Good separation of concerns
- Comprehensive logging with os.log

**Gaps**:

| Gap | Risk |
|-----|------|
| **No unit tests** | Test files exist but are empty |
| **Duplicate code** | API encoding logic duplicated in UnifiedChatAgent and ReasonActOrchestrator |
| **Large files** | Models.swift (547 lines), UnifiedChatAgent.swift (1053 lines) |
| **Mixed protocols** | Both `MCPServer` and `SimpleMCPServer` exist |
| **Unused code** | `SimpleMCPAIService`, `SimpleMCPManager` appear redundant |

**Proposed Improvements**:

#### 3.4.1 Consolidate MCP Implementations (High Priority)
- Remove Simple* variants or merge functionality
- Single MCPServer protocol with clear contract

#### 3.4.2 Extract Shared Logic (Medium Priority)
- Create `APIRequestBuilder` for OpenAI/Claude encoding
- Share between AIService, UnifiedChatAgent, ReasonActOrchestrator

#### 3.4.3 Add Test Coverage (Medium Priority)
- Unit tests for API response parsing
- Unit tests for MCP tool execution
- UI tests for critical flows

---

## 4. Proposed Roadmap

### Phase 1: Foundation (Immediate)
- [ ] Add conversation persistence (CoreData)
- [ ] Implement streaming responses
- [ ] API key validation on settings save
- [ ] Consolidate MCP implementations
- [ ] Add Reminders MCP server

### Phase 2: Polish (Short-term)
- [ ] Onboarding flow
- [ ] Localization (EN/CN)
- [ ] Error recovery UX
- [ ] Add Contacts MCP server
- [ ] Basic unit test coverage

### Phase 3: Expansion (Medium-term)
- [ ] System prompt customization
- [ ] Token/cost tracking
- [ ] iPad adaptive layout
- [ ] Home screen widget
- [ ] Health MCP server

### Phase 4: Advanced (Long-term)
- [ ] Siri Shortcuts integration
- [ ] Share extension
- [ ] iCloud sync for conversations
- [ ] Multi-conversation support
- [ ] Location-aware suggestions

---

## 5. Technical Specifications

### 5.1 Streaming Implementation

```swift
// Proposed interface
protocol StreamingAIService {
    func streamMessage(
        _ message: String,
        configuration: APIConfiguration,
        onChunk: @escaping (String) -> Void,
        onToolCall: @escaping (ToolCall) -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    )
}

// OpenAI streaming endpoint
// POST /v1/chat/completions with "stream": true
// Response: Server-Sent Events with data: {"choices":[{"delta":{"content":"..."}}]}

// Claude streaming endpoint
// POST /v1/messages with "stream": true
// Response: Server-Sent Events with event types: content_block_delta, message_stop
```

### 5.2 Conversation Persistence Schema

```swift
// CoreData entities

// Entity: Conversation
// - id: UUID (primary key)
// - title: String (auto-generated from first message)
// - createdAt: Date
// - updatedAt: Date
// - provider: String (openai/claude)
// - model: String

// Entity: Message
// - id: UUID (primary key)
// - content: String
// - role: String (user/assistant/system/tool)
// - timestamp: Date
// - conversation: Relationship -> Conversation
// - toolCalls: Transformable ([ToolCallRecord])

// Entity: ToolCallRecord (stored as Transformable)
// - id: String
// - toolName: String
// - arguments: [String: Any]
// - result: String
// - isError: Bool
// - duration: TimeInterval
```

### 5.3 New MCP Server: Reminders

```swift
class RemindersMCPServer: MCPServer {
    // Required permissions: NSRemindersUsageDescription in Info.plist

    // Tools:
    // - create_reminder(title, dueDate?, notes?, priority?, list?)
    // - list_reminders(list?, completed?, dueBefore?, dueAfter?)
    // - complete_reminder(title)
    // - delete_reminder(title)
    // - get_reminder_lists()
    // - search_reminders(query)

    // Implementation uses EKEventStore with .reminder entity type
}
```

### 5.4 New MCP Server: Contacts

```swift
class ContactsMCPServer: MCPServer {
    // Required permissions: NSContactsUsageDescription in Info.plist

    // Tools:
    // - search_contacts(query) - search by name, email, phone
    // - get_contact(name) - get full contact details
    // - create_contact(firstName, lastName, phone?, email?, ...)
    // - update_contact(name, field, value)
    // - get_contact_groups()

    // Implementation uses CNContactStore from Contacts framework
}
```

### 5.5 API Key Validation

```swift
// Validation approach
func validateAPIKey(_ key: String, provider: AIProvider) async -> ValidationResult {
    switch provider {
    case .openai:
        // GET /v1/models - minimal request to verify key
        // Success: 200 with model list
        // Failure: 401 unauthorized

    case .claude:
        // POST /v1/messages with minimal payload
        // Success: 200 with response
        // Failure: 401 unauthorized
    }
}

enum ValidationResult {
    case valid
    case invalid(reason: String)
    case networkError
}
```

---

## 6. Success Metrics

| Metric | Current | Target |
|--------|---------|--------|
| Time to first message | ~5 min (manual setup) | < 2 min (guided onboarding) |
| Message response latency | 3-8s (full wait) | < 1s (streaming start) |
| MCP tools available | 7 (calendar only) | 20+ (4 servers) |
| Test coverage | 0% | > 60% |
| Supported languages | 1 (mixed) | 2 (EN/CN) |
| Conversation persistence | None | Unlimited with search |
| Error recovery rate | 0% (no retry) | > 80% (auto-retry + guidance) |

---

## 7. Open Questions

1. **Keychain vs UserDefaults**: Should API keys be stored in Keychain for better security?
2. **iCloud Sync Scope**: Should conversation history sync across devices?
3. **Monetization**: Any plans for premium features or usage limits?
4. **Analytics**: Should we track usage patterns (locally or remotely)?
5. **Offline Mode**: Should the app provide any functionality without network?

---

## 8. References

- [OpenAI API Documentation](https://platform.openai.com/docs/api-reference)
- [Anthropic Claude API](https://docs.anthropic.com/claude/reference)
- [Apple EventKit](https://developer.apple.com/documentation/eventkit)
- [Apple Contacts](https://developer.apple.com/documentation/contacts)
- [Model Context Protocol](https://modelcontextprotocol.io/)

---

## Appendix A: Current File Inventory

| File | Lines | Purpose |
|------|-------|---------|
| Models.swift | 547 | Core data models, ChatViewModel |
| UnifiedChatAgent.swift | 1053 | Cross-provider chat agent |
| AIService.swift | 656 | Base AI service with tool calling |
| ChatView.swift | 443 | Main UI, timeline, suggested prompts |
| MCPProtocol.swift | 286 | MCP framework definitions |
| CalendarMCPServer.swift | 586 | Calendar integration |
| SettingsView.swift | ~150 | Settings UI |
| VoiceInputManager.swift | ~100 | Speech recognition |

## Appendix B: Privacy Permissions Required

Current:
- `NSMicrophoneUsageDescription` - Voice input
- `NSSpeechRecognitionUsageDescription` - Speech-to-text
- `NSCalendarsUsageDescription` - Calendar access

Proposed additions:
- `NSRemindersUsageDescription` - Reminders MCP
- `NSContactsUsageDescription` - Contacts MCP
- `NSHealthShareUsageDescription` - Health MCP (read)
- `NSHealthUpdateUsageDescription` - Health MCP (write)
- `NSLocationWhenInUseUsageDescription` - Location MCP
