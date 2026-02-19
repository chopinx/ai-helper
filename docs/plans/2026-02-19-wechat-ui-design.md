# WeChat-Inspired Chat UI Design Spec

**Date**: 2026-02-19
**Scope**: Chat experience only (message bubbles, input bar, timestamps, avatars, background, animations)

---

## 1. Design System Changes (DesignSystem.swift)

### Colors — Add WeChat tokens

```swift
// WeChat-inspired colors
static let userBubble = Color(red: 149/255, green: 236/255, blue: 105/255)  // #95EC69
static let aiBubble = Color.white                                            // #FFFFFF (was systemGray5)
static let chatBackground = Color(red: 237/255, green: 237/255, blue: 240/255) // #EDEDF0
static let wechatBrand = Color(red: 7/255, green: 193/255, blue: 96/255)     // #07C160
static let timestampText = Color.black.opacity(0.5)                           // 50% black
static let linkColor = Color(red: 87/255, green: 107/255, blue: 149/255)     // #576B95
```

Keep existing `accent`, `success`, `error`, `warning` for non-chat UI.

### Corner Radius

```swift
static let bubble: CGFloat = 6  // Was 16, WeChat uses subtle ~4-6pt rounding
```

### Spacing — Add avatar size token

```swift
static let avatarSize: CGFloat = 40
```

---

## 2. Message Bubbles (ChatView.swift → MessageBubble)

### Layout Change

```
BEFORE:  [        Spacer        ] [  bubble  ]     (user)
         [  bubble  ] [        Spacer        ]     (AI)

AFTER:   [   Spacer   ] [ bubble ] [ avatar ]      (user)
         [ avatar ] [ bubble ] [   Spacer   ]      (AI)
```

### Avatar

- Size: 40x40pt
- Shape: `RoundedRectangle(cornerRadius: 6)` (WeChat uses slightly rounded square, NOT circle)
- AI avatar: SF Symbol `brain.head.profile` on light purple background
- User avatar: SF Symbol `person.fill` on light blue background
- Alignment: `.top` within the HStack (avatar aligns to top of bubble)
- Spacing: 8pt between avatar and bubble

### User Bubble

- Background: `DS.Colors.userBubble` (#95EC69 green)
- Text color: `.black` (not .white — WeChat uses black text on green)
- Padding: 10pt all sides
- Corner radius: 6pt (with custom shape — see bubble tail below)

### AI Bubble

- Background: `Color.white`
- Text color: `.black`
- Padding: 10pt all sides
- Corner radius: 6pt

### Bubble Tail

Add a small triangular tail using a custom `Shape`:
- 6pt wide, 8pt tall
- Positioned at top of bubble, outside edge
- User: right side, pointing right
- AI: left side, pointing left
- Same color as bubble background

### Max Width

- Change from `0.8` (80%) to `0.72` (~72%)

---

## 3. Timestamps (ChatView.swift → new TimestampSeparator)

### New View: `TimestampSeparator`

- Shown between messages when time gap > 5 minutes
- Centered text, no background
- Font: `.caption2` (12pt equivalent)
- Color: `DS.Colors.timestampText` (black 50% opacity)
- Padding: 8pt vertical

### Format Logic

```swift
func formatTimestamp(_ date: Date) -> String {
    if Calendar.current.isDateInToday(date) {
        return date.formatted(date: .omitted, time: .shortened)  // "10:30"
    } else if Calendar.current.isDateInYesterday(date) {
        return "Yesterday " + date.formatted(date: .omitted, time: .shortened)
    } else if Calendar.current.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
        // Same week: "Monday 09:15"
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE HH:mm"
        return formatter.string(from: date)
    } else {
        return date.formatted(date: .abbreviated, time: .shortened)  // "Feb 19, 10:30"
    }
}
```

### Integration

In the `ForEach(viewModel.messages)` loop, before each `MessageBubble`, check if a timestamp separator is needed:
```swift
if shouldShowTimestamp(current: message, previous: previousMessage) {
    TimestampSeparator(date: message.timestamp)
}
```

---

## 4. Chat Background

- Change ScrollView background from default (white/system) to `DS.Colors.chatBackground` (#EDEDF0)
- Apply to the full chat content area

---

## 5. Input Bar (ChatInputView)

### Container

- Background: `Color(red: 246/255, green: 246/255, blue: 246/255)` (#F6F6F6)
- Top border: 0.5pt line, `Color.black.opacity(0.1)`
- Padding: 8pt all sides

### Text Field

- Remove `RoundedBorderTextFieldStyle()` — use plain style with custom background
- Background: `.white`
- Corner radius: 6pt
- Padding: 8pt horizontal, 6pt vertical inside
- No border on focus
- Placeholder: "Type your message..."

### Send Button

- When text present: use `DS.Colors.wechatBrand` (#07C160) fill circle with white arrow
- When empty: keep as gray icon
- Size: 32x32pt

### Voice Button

- Keep existing behavior but match sizing to 32x32pt

### Layout Order (left to right)

1. Voice button (if available)
2. Text field (flex)
3. Send button

---

## 6. Navigation Bar

### Typing Indicator

- When `viewModel.isLoading`: change nav title from "AI Assistant" to "Typing..."
- Use `.italic()` style for the typing state
- Revert when loading completes

---

## 7. Message Spacing

- LazyVStack spacing: keep at 12pt (slightly tighter than WeChat's 16pt, appropriate for chat with AI which has longer messages)
- Consecutive same-sender messages: reduce to 4pt spacing (message grouping)

---

## 8. Animations

### Message Appear

- Add `.transition(.asymmetric(insertion: .opacity.combined(with: .move(edge: .bottom)), removal: .opacity))`
- Wrap message list changes in `withAnimation(.easeOut(duration: 0.2))`

---

## Summary of Files to Modify

1. **DesignSystem.swift** — Add WeChat color tokens, update bubble corner radius
2. **ChatView.swift** — MessageBubble (avatar + tail + colors), TimestampSeparator (new), ChatInputView (restyle), chat background, typing nav title, animations
