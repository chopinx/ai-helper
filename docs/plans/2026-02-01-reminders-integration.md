# Reminders Integration Plan

## Goal
Integrate existing RemindersMCPServer into SimpleAIService so AI can manage both Calendar and Reminders.

## Current State
- ✅ `RemindersMCPServer.swift` refactored (314 lines)
- ✅ 7 tools: create_reminder, list_reminders, complete_reminder, delete_reminder, search_reminders, get_today_reminders, get_overdue_reminders
- ✅ Uses EventKit with proper permission handling
- ✅ Connected to SimpleAIService with multi-server routing
- ✅ System prompt updated with Reminders Manager sub-agent

## Tasks

### Task 1: Update SimpleAIService to support multiple MCP servers

**File:** `Services/AI/SimpleAIService.swift`

**Changes:**
1. Add `remindersServer` property alongside `calendarServer`
2. Initialize both servers in `init()`
3. Combine tools from both servers
4. Route tool calls to correct server based on tool name

```swift
// Add property
private let remindersServer = RemindersMCPServer()

// Update init
init() {
    Task {
        try? await calendarServer.initialize()
        try? await remindersServer.initialize()
    }
}

// Combine tools
let calendarTools = try await calendarServer.listTools().map { $0.toTool() }
let reminderTools = try await remindersServer.listTools().map { $0.toTool() }
let tools = calendarTools + reminderTools

// Route tool calls
private func executeToolCall(_ call: ToolCall) async throws -> MCPResult {
    let calendarToolNames = ["list_events", "create_event", "update_event", "delete_event", "search_events", "get_event_details", "get_upcoming_events"]

    if calendarToolNames.contains(call.name) {
        return try await calendarServer.callTool(name: call.name, arguments: call.arguments)
    } else {
        return try await remindersServer.callTool(name: call.name, arguments: call.arguments)
    }
}
```

### Task 2: Update system prompt with Reminders sub-agent

**File:** `Services/AI/SimpleAIService.swift`

**Add to system prompt:**
```
## ✅ Reminders Manager
Triggers: reminders, todos, tasks, to-do list, things to do
Tools: create_reminder, list_reminders, complete_reminder, delete_reminder, search_reminders
Behaviors:
- List existing reminders before creating duplicates
- Default priority: none (0)
- Confirm before deleting
- After complete/delete, verify by listing again
```

### Task 3: Update CLAUDE.md

**File:** `CLAUDE.md`

**Update architecture section:**
- Add RemindersMCPServer to components table
- Update data flow to show multi-server routing

### Task 4: Test

**Manual tests:**
1. "What reminders do I have?" → lists reminders
2. "Remind me to buy milk tomorrow" → creates reminder
3. "Complete the milk reminder" → marks complete, verifies
4. "Delete the milk reminder" → deletes, verifies

## Verification

- [x] Build succeeds
- [x] All existing tests pass (30/30)
- [x] No compiler warnings
- [x] No hardcoded secrets
- [ ] Calendar tools still work (manual test needed)
- [ ] Reminders tools work (manual test needed)
- [ ] AI correctly routes to right server (manual test needed)
- [ ] AI verifies after write operations (manual test needed)

## Files Modified

| File | Change |
|------|--------|
| `RemindersMCPServer.swift` | Refactored to match CalendarMCPServer, added 2 new tools |
| `SimpleAIService.swift` | Add reminders server, multi-server routing, process callbacks, updated prompt |
| `Models.swift` | Add ProcessTracker, ProcessUpdate, ToolCallRecord for dynamic UI |
| `ChatView.swift` | Add DynamicProcessView, IterationRowView, ToolCallRowView |
| `CLAUDE.md` | Update architecture docs with multi-server routing |
