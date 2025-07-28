# AI Context Feature

This document describes the context feature that automatically adds current date, time, and device information to AI messages for more relevant responses.

## Overview

Every message sent to the AI (both OpenAI and Claude) now includes comprehensive context information to help the AI provide more accurate and time-aware responses.

## Context Information Included

### Date and Time Context
- **Current date and time**: Full formatted date with time (e.g., "Sunday, July 28, 2024 at 9:06 PM")
- **Today**: ISO date format with day name (e.g., "2024-07-28 (Sunday)")
- **Current time**: 24-hour format (e.g., "21:06")
- **Tomorrow**: ISO date with day name (e.g., "2024-07-29 (Monday)")
- **Next week**: Same day next week (e.g., "2024-08-04")

### Location and Time Zone
- **Time zone**: Full identifier and abbreviation (e.g., "America/New_York (EDT)")
- **Week of year**: Current week number (e.g., "Week 31")

### Device Context
- **Device type**: Device model (e.g., "iPhone", "iPad")
- **Locale**: User's locale identifier (e.g., "en_US")

## Implementation Details

### Core Implementation
Located in `Services/AI/AIService.swift`:

```swift
private func addCommonContext(to message: String) -> String {
    // Generates comprehensive context and prepends to user message
}
```

### Context Flow
1. **User sends message** → ChatViewModel.sendMessage()
2. **Context added** → AIService.addCommonContext()
3. **Enhanced message sent** → AI API (OpenAI/Claude)
4. **Response received** → Displayed to user

### MCP Integration
For calendar event creation, `SimpleMCPAIService` provides specialized context:
- Uses `sendMessageWithoutContext()` for internal AI parsing
- Includes specific date parsing context for relative terms
- Provides current date/time reference for "today", "tomorrow", etc.

## Benefits

### Enhanced AI Responses
- **Time-aware answers**: AI knows current date/time for relevant responses
- **Better calendar integration**: Accurate parsing of relative dates ("tomorrow", "next week")
- **Localized responses**: AI understands user's timezone and locale
- **Device-appropriate suggestions**: Responses tailored to iPhone/iPad usage

### Examples of Improved Responses

**Without Context:**
```
User: "What should I do this weekend?"
AI: "Here are some weekend activity ideas..." (generic, no date awareness)
```

**With Context:**
```
User: "What should I do this weekend?"
AI: "Since this weekend is July 29-30, 2024, here are some summer activities..." (specific, date-aware)
```

**Calendar Events:**
```
User: "Schedule dentist appointment tomorrow at 2 PM"
Context: Today is 2024-07-28 (Sunday), Tomorrow is 2024-07-29 (Monday)
Result: Creates calendar event for Monday, July 29, 2024 at 2:00 PM
```

## Technical Architecture

### Service Layer
- **AIService**: Base service that adds context to all messages
- **SimpleMCPAIService**: Enhanced service with calendar-specific context
- **Context separation**: Internal AI calls bypass context to avoid duplication

### Context Format
```
Current context:
- Current date and time: Sunday, July 28, 2024 at 9:06 PM
- Today: 2024-07-28 (Sunday)
- Current time: 21:06
- Tomorrow: 2024-07-29 (Monday)
- Next week (same day): 2024-08-04
- Time zone: America/New_York (EDT)
- Week of year: 31
- Device: iPhone
- Locale: en_US

User message: [original message]
```

## Performance Considerations

### Minimal Overhead
- Context generation is lightweight (date/time calculations)
- No network calls or heavy processing
- Context cached per message (not per session)

### Token Usage
- Context adds ~150-200 tokens per message
- Balanced against significantly improved response quality
- More accurate responses reduce need for follow-up clarification

## Privacy and Security

### Local Data Only
- All context information is generated locally on device
- No external services called for context generation
- No personal information beyond device type/locale included

### Data Included
- ✅ Current date/time (public information)
- ✅ Time zone (necessary for accurate responses)
- ✅ Device type (iPhone/iPad - for appropriate suggestions)
- ✅ Locale (for localized responses)
- ❌ No location data
- ❌ No personal identifiers
- ❌ No sensitive device information

## Future Enhancements

### Potential Additions
1. **Weather context**: Current weather conditions (with permission)
2. **Calendar context**: Upcoming events (with permission)
3. **Battery level**: For energy-aware suggestions
4. **App usage context**: Recent app activity patterns

### Configuration Options
- Settings toggle to enable/disable context
- Granular control over context components
- Privacy-focused context level selection

## Usage Examples

### Regular Conversations
```
User: "What's a good time for a meeting?"
AI: "Since it's currently 9:06 PM on Sunday, you might want to schedule for Monday morning around 9-10 AM EST..."
```

### Calendar Integration
```
User: "Book lunch with Sarah next Tuesday"
AI: "I'll create a calendar event for Tuesday, August 1st, 2024. What time works best?"
```

### Time-Sensitive Queries
```
User: "Is it too late to call someone on the west coast?"
AI: "It's currently 9:06 PM EDT, which means it's 6:06 PM PDT on the west coast - still a reasonable time to call."
```

This context feature significantly improves the AI assistant's ability to provide relevant, timely, and accurate responses while maintaining user privacy and optimal performance.