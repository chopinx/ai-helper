# AI Helper - Iteration Checklist

---

## Pre-Push Checklist (Required)

**Run before every push:**

| # | Check | Command/Action | Pass |
|---|-------|----------------|------|
| 1 | Build succeeds | `xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" -sdk iphonesimulator build` | [ ] |
| 2 | Tests pass | `xcodebuild ... -destination "platform=iOS Simulator,name=iPhone 16" test` | [ ] |
| 3 | No warnings | Check build output for warnings | [ ] |
| 4 | Code simplified | Review for unnecessary complexity | [ ] |
| 5 | No secrets | No API keys or credentials in code | [ ] |
| 6 | Docs aligned | CLAUDE.md, README match code changes | [ ] |

---

## Feature Checklist

### AI Capabilities
| # | Feature | Status |
|---|---------|--------|
| 1 | Streaming responses | [x] |
| 2 | Conversation persistence | [x] |
| 3 | System prompt customization | [ ] |
| 4 | Retry logic on failure | [ ] |
| 5 | Token/cost tracking | [ ] |
| 6 | Context window management | [ ] |

### MCP Integrations
| # | Server | Status |
|---|--------|--------|
| 1 | Calendar (7 tools) | [x] |
| 2 | Reminders (5 tools) | [x] |
| 3 | Contacts | [ ] |
| 4 | Health | [ ] |
| 5 | Location | [ ] |
| 6 | Shortcuts | [ ] |

### Input Methods
| # | Feature | Status |
|---|---------|--------|
| 1 | Text input | [x] |
| 2 | Voice input (Whisper) | [x] |
| 3 | Suggested prompts | [x] |
| 4 | Real-time transcription | [ ] |

---

## Code Quality Checklist

### Architecture
| # | Check | Status |
|---|-------|--------|
| 1 | No duplicate code | [ ] |
| 2 | Files < 500 lines | [ ] |
| 3 | Single MCP protocol | [ ] |
| 4 | Services injected | [ ] |

### Testing
| # | Check | Status |
|---|-------|--------|
| 1 | Unit tests exist | [ ] |
| 2 | Coverage > 60% | [ ] |
| 3 | UI tests for key flows | [ ] |
| 4 | Mocks for API calls | [ ] |

### Error Handling
| # | Check | Status |
|---|-------|--------|
| 1 | No force unwraps | [ ] |
| 2 | Typed errors | [x] |
| 3 | Errors logged | [x] |
| 4 | Errors recoverable | [ ] |

### Code Style
| # | Check | Status |
|---|-------|--------|
| 1 | Swift conventions | [x] |
| 2 | MARK comments | [x] |
| 3 | No TODOs in main | [ ] |
| 4 | Public APIs documented | [ ] |

### Documentation
| # | Check | Status |
|---|-------|--------|
| 1 | CLAUDE.md matches code | [ ] |
| 2 | README.md current | [ ] |
| 3 | PRD updated if scope changed | [ ] |
| 4 | New files/dirs documented | [ ] |

---

## UX Checklist

### Onboarding
| # | Check | Status |
|---|-------|--------|
| 1 | First launch flow | [ ] |
| 2 | API key validation | [x] |
| 3 | Permission explanations | [ ] |

### Core Interaction
| # | Check | Status |
|---|-------|--------|
| 1 | Response < 1s (streaming) | [x] |
| 2 | Loading indicators | [x] |
| 3 | Auto-scroll to new | [x] |
| 4 | Empty state content | [ ] |

### Error States
| # | Check | Status |
|---|-------|--------|
| 1 | Retry buttons | [ ] |
| 2 | Specific error messages | [ ] |
| 3 | No crashes | [x] |

### Visual
| # | Check | Status |
|---|-------|--------|
| 1 | Dark mode | [x] |
| 2 | Dynamic type | [ ] |
| 3 | iPad layout | [ ] |
| 4 | Haptic feedback | [ ] |

### Accessibility
| # | Check | Status |
|---|-------|--------|
| 1 | VoiceOver labels | [ ] |
| 2 | Contrast ratio | [ ] |
| 3 | Touch targets 44pt | [ ] |

### Localization
| # | Check | Status |
|---|-------|--------|
| 1 | Strings extracted | [ ] |
| 2 | English complete | [ ] |
| 3 | Chinese complete | [ ] |

---

## Release Checklist

### TestFlight
| # | Check | Pass |
|---|-------|------|
| 1 | Version bumped | [ ] |
| 2 | All tests pass | [ ] |
| 3 | No warnings | [ ] |
| 4 | Privacy descriptions set | [ ] |

### App Store
| # | Check | Pass |
|---|-------|------|
| 1 | TestFlight feedback addressed | [ ] |
| 2 | Screenshots updated | [ ] |
| 3 | Description updated | [ ] |
| 4 | Privacy policy URL valid | [ ] |

---

## Progress Tracking

**Last Updated**: 2026-01-31

| Category | Done | Total |
|----------|------|-------|
| Pre-Push | 0 | 6 |
| Features - AI | 2 | 6 |
| Features - MCP | 2 | 6 |
| Features - Input | 3 | 4 |
| Code Quality | 4 | 20 |
| UX | 5 | 18 |
| **Total** | **16** | **60** |
