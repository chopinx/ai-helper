# AI Helper - Iteration Checklist

Use this checklist at the end of each development iteration to ensure quality and completeness.

---

## Features

### AI Capabilities
- [ ] **Streaming**: Responses stream incrementally (not waiting for full response)
- [ ] **Conversation Persistence**: Messages saved and restored on app restart
- [ ] **Context Management**: Token limits handled, old messages pruned appropriately
- [ ] **System Prompt**: User can customize assistant personality/behavior
- [ ] **Retry Logic**: Failed requests auto-retry with exponential backoff
- [ ] **Cost Tracking**: Token usage displayed to user
- [ ] **Model Selection**: All current models available for both providers

### MCP Integrations
- [ ] **Calendar**: Create, list, update, delete, search events
- [ ] **Reminders**: Create, list, complete, delete reminders
- [ ] **Contacts**: Search, view, create contacts
- [ ] **Health**: Log workouts, read health data
- [ ] **Location**: Current location, nearby places
- [ ] **Shortcuts**: Trigger iOS shortcuts

### Voice & Input
- [ ] **Speech-to-Text**: Voice input works reliably
- [ ] **Real-time Transcription**: Shows text as user speaks
- [ ] **Multi-line Input**: Text field expands for long messages
- [ ] **Quick Actions**: Suggested prompts accessible

---

## Code Quality

### Architecture
- [ ] **Single Responsibility**: Each class/struct has one clear purpose
- [ ] **No Duplicate Code**: Shared logic extracted to common utilities
- [ ] **Protocol Consistency**: Single MCP protocol (no Simple* variants)
- [ ] **File Size**: No file exceeds 500 lines
- [ ] **Dependency Injection**: Services injected, not created inline

### Testing
- [ ] **Unit Tests Exist**: Core logic has test coverage
- [ ] **Tests Pass**: All tests green before merge
- [ ] **Coverage > 60%**: Critical paths covered
- [ ] **UI Tests**: Key user flows have UI tests
- [ ] **Mock Services**: Tests use mocks, not real APIs

### Error Handling
- [ ] **No Force Unwraps**: All optionals safely handled
- [ ] **Errors Typed**: Custom error enums with LocalizedError
- [ ] **Errors Logged**: All errors logged with context
- [ ] **Errors Recoverable**: User can retry or recover from errors

### Code Style
- [ ] **Swift Conventions**: Follows Swift API Design Guidelines
- [ ] **Consistent Naming**: camelCase for vars/funcs, PascalCase for types
- [ ] **MARK Comments**: Large files organized with `// MARK: -`
- [ ] **No Warnings**: Project builds with zero warnings
- [ ] **No TODOs in Main**: TODOs resolved before merge to main

### Documentation
- [ ] **Public APIs Documented**: Public methods have doc comments
- [ ] **README Current**: README reflects actual functionality
- [ ] **CLAUDE.md Current**: Development guide up to date
- [ ] **Complex Logic Explained**: Non-obvious code has comments

---

## User Experience

### Onboarding
- [ ] **First Launch Flow**: New users guided through setup
- [ ] **API Key Validation**: Keys validated before saving
- [ ] **Permission Requests**: Explains why each permission needed
- [ ] **Success Confirmation**: Clear feedback when setup complete

### Core Interaction
- [ ] **Response Time < 1s**: Streaming starts within 1 second
- [ ] **Loading States**: Clear indicators when processing
- [ ] **Empty States**: Helpful content when no messages/data
- [ ] **Scroll Behavior**: Auto-scrolls to new messages

### Error States
- [ ] **Network Errors**: Clear message + retry button
- [ ] **API Errors**: Specific guidance (invalid key, rate limit, etc.)
- [ ] **Permission Denied**: Links to Settings app
- [ ] **No Crashes**: App never crashes on error

### Visual Design
- [ ] **Dark Mode**: Fully supports dark mode
- [ ] **Dynamic Type**: Respects system font size
- [ ] **Safe Areas**: Content respects notch/home indicator
- [ ] **iPad Layout**: Adapts to larger screens
- [ ] **Haptic Feedback**: Tactile response on actions

### Accessibility
- [ ] **VoiceOver**: All elements have accessibility labels
- [ ] **Contrast**: Text meets WCAG AA contrast ratio
- [ ] **Touch Targets**: Buttons at least 44x44 points
- [ ] **Reduce Motion**: Respects reduce motion preference

### Localization
- [ ] **Strings Extracted**: No hardcoded user-facing strings
- [ ] **English Complete**: All strings in English
- [ ] **Chinese Complete**: All strings in Chinese
- [ ] **RTL Support**: Layout works for RTL languages (future)

### Settings
- [ ] **All Options Accessible**: Every setting reachable
- [ ] **Changes Persist**: Settings saved immediately
- [ ] **Defaults Sensible**: New users get good defaults
- [ ] **Reset Option**: Can reset to defaults

---

## Pre-Release Checklist

### Before TestFlight
- [ ] Version number bumped
- [ ] All tests passing
- [ ] No compiler warnings
- [ ] Privacy permissions documented
- [ ] Screenshots updated (if UI changed)

### Before App Store
- [ ] All above + TestFlight feedback addressed
- [ ] App Store description updated
- [ ] What's New text written
- [ ] Support URL valid
- [ ] Privacy Policy URL valid

---

## Iteration Log

| Date | Focus | Items Completed | Items Remaining |
|------|-------|-----------------|-----------------|
| _YYYY-MM-DD_ | _Phase/Feature_ | _List completed_ | _List remaining_ |

---

## Quick Reference: Current Status

**Last Updated**: 2026-01-31

| Category | Done | Total | % |
|----------|------|-------|---|
| Features - AI | 4 | 7 | 57% |
| Features - MCP | 1 | 6 | 17% |
| Features - Voice | 2 | 4 | 50% |
| Code Quality | 5 | 18 | 28% |
| User Experience | 8 | 24 | 33% |

**Next Priority**: Phase 1 - Streaming, Persistence, Reminders MCP
