# Phase 1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add API key validation, Reminders MCP server, conversation persistence, streaming responses, and OpenAI Whisper transcription.

**Architecture:**
- API validation uses lightweight API calls to verify keys before saving
- Reminders MCP follows existing CalendarMCPServer pattern with EventKit
- Persistence uses CoreData with Conversation/Message entities
- Streaming uses URLSession with SSE parsing for both providers
- Voice uses OpenAI Whisper API instead of on-device Speech framework

**Tech Stack:** SwiftUI, CoreData, EventKit, URLSession, OpenAI Whisper API

---

## Task 1: API Key Validation

**Files:**
- Create: `AI Helper2/Services/AI/APIKeyValidator.swift`
- Modify: `AI Helper2/Views/Settings/SettingsView.swift`
- Modify: `AI Helper2/Models/Models.swift`

**Step 1: Create APIKeyValidator service**

Create `AI Helper2/Services/AI/APIKeyValidator.swift`:

```swift
import Foundation
import os.log

enum APIKeyValidationResult {
    case valid
    case invalid(String)
    case networkError(String)
}

class APIKeyValidator {
    private let logger = Logger(subsystem: "com.aihelper.validation", category: "APIKeyValidator")

    func validate(apiKey: String, provider: AIProvider) async -> APIKeyValidationResult {
        guard !apiKey.isEmpty else {
            return .invalid("API key is empty")
        }

        logger.info("🔑 Validating \(provider.rawValue) API key...")

        switch provider {
        case .openai:
            return await validateOpenAI(apiKey: apiKey)
        case .claude:
            return await validateClaude(apiKey: apiKey)
        }
    }

    private func validateOpenAI(apiKey: String) async -> APIKeyValidationResult {
        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .networkError("Invalid response")
            }

            switch httpResponse.statusCode {
            case 200:
                logger.info("✅ OpenAI API key valid")
                return .valid
            case 401:
                logger.warning("❌ OpenAI API key invalid")
                return .invalid("Invalid API key")
            case 429:
                logger.warning("⚠️ OpenAI rate limited, assuming valid")
                return .valid // Rate limited means key is valid
            default:
                return .invalid("Unexpected status: \(httpResponse.statusCode)")
            }
        } catch {
            logger.error("❌ OpenAI validation error: \(error.localizedDescription)")
            return .networkError(error.localizedDescription)
        }
    }

    private func validateClaude(apiKey: String) async -> APIKeyValidationResult {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10

        // Minimal request to validate key
        let body: [String: Any] = [
            "model": "claude-3-haiku-20240307",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .networkError("Invalid response")
            }

            switch httpResponse.statusCode {
            case 200:
                logger.info("✅ Claude API key valid")
                return .valid
            case 401:
                logger.warning("❌ Claude API key invalid")
                return .invalid("Invalid API key")
            case 429:
                logger.warning("⚠️ Claude rate limited, assuming valid")
                return .valid
            default:
                return .invalid("Unexpected status: \(httpResponse.statusCode)")
            }
        } catch {
            logger.error("❌ Claude validation error: \(error.localizedDescription)")
            return .networkError(error.localizedDescription)
        }
    }
}
```

**Step 2: Add validation state to SettingsView**

Modify `AI Helper2/Views/Settings/SettingsView.swift` - add state and validation UI:

```swift
import SwiftUI

struct SettingsView: View {
    @Binding var configuration: APIConfiguration
    @Environment(\.dismiss) private var dismiss

    @State private var isValidating = false
    @State private var validationResult: APIKeyValidationResult?
    @State private var showValidationAlert = false

    private let validator = APIKeyValidator()

    var body: some View {
        NavigationView {
            Form {
                // ... existing sections ...

                Section(header: Text("API Configuration")) {
                    SecureField("API Key", text: $configuration.apiKey)
                        .textContentType(.password)

                    // Validation button and status
                    HStack {
                        Button(action: validateAPIKey) {
                            HStack {
                                if isValidating {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "checkmark.shield")
                                }
                                Text(isValidating ? "Validating..." : "Validate Key")
                            }
                        }
                        .disabled(configuration.apiKey.isEmpty || isValidating)

                        Spacer()

                        if let result = validationResult {
                            validationStatusView(result)
                        }
                    }

                    // ... existing model picker ...
                }

                // ... rest of sections ...
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("API Key Validation", isPresented: $showValidationAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(validationAlertMessage)
            }
        }
    }

    private func validateAPIKey() {
        isValidating = true
        validationResult = nil

        Task {
            let result = await validator.validate(
                apiKey: configuration.apiKey,
                provider: configuration.provider
            )

            await MainActor.run {
                isValidating = false
                validationResult = result
                showValidationAlert = true
            }
        }
    }

    @ViewBuilder
    private func validationStatusView(_ result: APIKeyValidationResult) -> some View {
        switch result {
        case .valid:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .invalid:
            Image(systemName: "xmark.circle.fill")
                .foregroundColor(.red)
        case .networkError:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
        }
    }

    private var validationAlertMessage: String {
        guard let result = validationResult else { return "" }
        switch result {
        case .valid:
            return "API key is valid!"
        case .invalid(let message):
            return "Invalid API key: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
```

**Step 3: Build and test**

Run: `xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" -sdk iphonesimulator build`
Expected: BUILD SUCCEEDED

**Step 4: Commit**

```bash
git add "AI Helper2/Services/AI/APIKeyValidator.swift" "AI Helper2/Views/Settings/SettingsView.swift"
git commit -m "feat: add API key validation in settings"
```

---

## Task 2: Reminders MCP Server

**Files:**
- Create: `AI Helper2/Services/MCP/RemindersMCPServer.swift`
- Modify: `AI Helper2/Models/Models.swift` (register server)

**Step 1: Create RemindersMCPServer**

Create `AI Helper2/Services/MCP/RemindersMCPServer.swift`:

```swift
import Foundation
import EventKit
import os.log

class RemindersMCPServer: MCPServer {
    private let eventStore = EKEventStore()
    private var isAuthorized = false
    private let logger = Logger(subsystem: "com.aihelper.mcp", category: "RemindersMCPServer")

    func initialize() async throws {
        try await requestRemindersAccess()
    }

    func listTools() async throws -> [MCPTool] {
        return [
            MCPTool(
                name: "create_reminder",
                description: "Create a new reminder",
                parameters: [
                    MCPParameter(name: "title", type: "string", description: "The reminder title", required: true),
                    MCPParameter(name: "due_date", type: "string", description: "Due date in ISO 8601 format", required: false),
                    MCPParameter(name: "notes", type: "string", description: "Optional notes", required: false),
                    MCPParameter(name: "priority", type: "integer", description: "Priority 1-9 (1=high, 9=low)", required: false)
                ]
            ),
            MCPTool(
                name: "list_reminders",
                description: "List reminders, optionally filtered by completion status",
                parameters: [
                    MCPParameter(name: "include_completed", type: "boolean", description: "Include completed reminders", required: false)
                ]
            ),
            MCPTool(
                name: "complete_reminder",
                description: "Mark a reminder as completed",
                parameters: [
                    MCPParameter(name: "title", type: "string", description: "Title of reminder to complete", required: true)
                ]
            ),
            MCPTool(
                name: "delete_reminder",
                description: "Delete a reminder",
                parameters: [
                    MCPParameter(name: "title", type: "string", description: "Title of reminder to delete", required: true)
                ]
            ),
            MCPTool(
                name: "search_reminders",
                description: "Search reminders by title or notes",
                parameters: [
                    MCPParameter(name: "query", type: "string", description: "Search query", required: true)
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPResult {
        guard isAuthorized else {
            throw MCPError.permissionDenied("Reminders access not granted")
        }

        MCPLogger.logToolCall(server: "RemindersMCPServer", tool: name, arguments: arguments)
        let startTime = CFAbsoluteTimeGetCurrent()

        let result: MCPResult
        switch name {
        case "create_reminder":
            result = try await createReminder(arguments: arguments)
        case "list_reminders":
            result = try await listReminders(arguments: arguments)
        case "complete_reminder":
            result = try await completeReminder(arguments: arguments)
        case "delete_reminder":
            result = try await deleteReminder(arguments: arguments)
        case "search_reminders":
            result = try await searchReminders(arguments: arguments)
        default:
            throw MCPError.toolNotFound(name)
        }

        let duration = CFAbsoluteTimeGetCurrent() - startTime
        MCPLogger.logToolResult(server: "RemindersMCPServer", tool: name, result: result, duration: duration)
        return result
    }

    func canHandle(message: String, context: MCPEvaluationContext, aiService: AIService, configuration: APIConfiguration) async -> MCPCapabilityResult {
        let keywords = ["reminder", "remind", "todo", "task", "to-do", "to do"]
        let messageLower = message.lowercased()
        let hasIntent = keywords.contains { messageLower.contains($0) }

        return MCPCapabilityResult(
            canHandle: hasIntent,
            confidence: hasIntent ? 0.8 : 0.1,
            suggestedTools: hasIntent ? ["create_reminder", "list_reminders"] : [],
            reasoning: hasIntent ? "Message contains reminder-related keywords" : "No reminder intent detected"
        )
    }

    func getServerName() -> String { "Reminders Server" }
    func getServerDescription() -> String { "Manages iOS reminders and tasks" }

    // MARK: - Private Methods

    private func requestRemindersAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .fullAccess, .authorized:
            isAuthorized = true
        case .notDetermined:
            if #available(iOS 17.0, *) {
                isAuthorized = try await eventStore.requestFullAccessToReminders()
            } else {
                isAuthorized = try await eventStore.requestAccess(to: .reminder)
            }
            if !isAuthorized {
                throw MCPError.permissionDenied("Reminders access denied")
            }
        default:
            throw MCPError.permissionDenied("Reminders access denied or restricted")
        }
    }

    private func createReminder(arguments: [String: Any]) async throws -> MCPResult {
        guard let title = arguments["title"] as? String else {
            throw MCPError.invalidArguments("Missing required field: title")
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        if let notes = arguments["notes"] as? String {
            reminder.notes = notes
        }

        if let priority = arguments["priority"] as? Int {
            reminder.priority = min(max(priority, 1), 9)
        }

        if let dueDateString = arguments["due_date"] as? String,
           let dueDate = ISO8601DateFormatter().date(from: dueDateString) {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }

        try eventStore.save(reminder, commit: true)

        return MCPResult(
            message: "Reminder '\(title)' created successfully",
            isError: false
        )
    }

    private func listReminders(arguments: [String: Any]) async throws -> MCPResult {
        let includeCompleted = arguments["include_completed"] as? Bool ?? false

        let predicate = eventStore.predicateForReminders(in: nil)

        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                guard let reminders = reminders else {
                    continuation.resume(returning: MCPResult(message: "Failed to fetch reminders", isError: true))
                    return
                }

                let filtered = includeCompleted ? reminders : reminders.filter { !$0.isCompleted }

                if filtered.isEmpty {
                    continuation.resume(returning: MCPResult(message: "No reminders found", isError: false))
                    return
                }

                let list = filtered.map { reminder -> String in
                    let status = reminder.isCompleted ? "✓" : "○"
                    let due = reminder.dueDateComponents.flatMap {
                        Calendar.current.date(from: $0)
                    }.map {
                        " (due: \(DateFormatter.localizedString(from: $0, dateStyle: .short, timeStyle: .short)))"
                    } ?? ""
                    return "\(status) \(reminder.title ?? "Untitled")\(due)"
                }.joined(separator: "\n")

                continuation.resume(returning: MCPResult(
                    message: "Found \(filtered.count) reminders:\n\n\(list)",
                    isError: false
                ))
            }
        }
    }

    private func completeReminder(arguments: [String: Any]) async throws -> MCPResult {
        guard let title = arguments["title"] as? String else {
            throw MCPError.invalidArguments("Missing required field: title")
        }

        let predicate = eventStore.predicateForReminders(in: nil)

        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
                guard let self = self,
                      let reminders = reminders,
                      let reminder = reminders.first(where: {
                          $0.title?.localizedCaseInsensitiveContains(title) == true
                      }) else {
                    continuation.resume(returning: MCPResult(
                        message: "Reminder '\(title)' not found",
                        isError: true
                    ))
                    return
                }

                reminder.isCompleted = true

                do {
                    try self.eventStore.save(reminder, commit: true)
                    continuation.resume(returning: MCPResult(
                        message: "Reminder '\(reminder.title ?? title)' marked as completed",
                        isError: false
                    ))
                } catch {
                    continuation.resume(returning: MCPResult(
                        message: "Failed to complete reminder: \(error.localizedDescription)",
                        isError: true
                    ))
                }
            }
        }
    }

    private func deleteReminder(arguments: [String: Any]) async throws -> MCPResult {
        guard let title = arguments["title"] as? String else {
            throw MCPError.invalidArguments("Missing required field: title")
        }

        let predicate = eventStore.predicateForReminders(in: nil)

        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { [weak self] reminders in
                guard let self = self,
                      let reminders = reminders,
                      let reminder = reminders.first(where: {
                          $0.title?.localizedCaseInsensitiveContains(title) == true
                      }) else {
                    continuation.resume(returning: MCPResult(
                        message: "Reminder '\(title)' not found",
                        isError: true
                    ))
                    return
                }

                let reminderTitle = reminder.title ?? title

                do {
                    try self.eventStore.remove(reminder, commit: true)
                    continuation.resume(returning: MCPResult(
                        message: "Reminder '\(reminderTitle)' deleted",
                        isError: false
                    ))
                } catch {
                    continuation.resume(returning: MCPResult(
                        message: "Failed to delete reminder: \(error.localizedDescription)",
                        isError: true
                    ))
                }
            }
        }
    }

    private func searchReminders(arguments: [String: Any]) async throws -> MCPResult {
        guard let query = arguments["query"] as? String else {
            throw MCPError.invalidArguments("Missing required field: query")
        }

        let predicate = eventStore.predicateForReminders(in: nil)

        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                guard let reminders = reminders else {
                    continuation.resume(returning: MCPResult(message: "Failed to fetch reminders", isError: true))
                    return
                }

                let matches = reminders.filter { reminder in
                    let titleMatch = reminder.title?.localizedCaseInsensitiveContains(query) ?? false
                    let notesMatch = reminder.notes?.localizedCaseInsensitiveContains(query) ?? false
                    return titleMatch || notesMatch
                }

                if matches.isEmpty {
                    continuation.resume(returning: MCPResult(
                        message: "No reminders found matching '\(query)'",
                        isError: false
                    ))
                    return
                }

                let list = matches.map { "• \($0.title ?? "Untitled")" }.joined(separator: "\n")
                continuation.resume(returning: MCPResult(
                    message: "Found \(matches.count) reminders matching '\(query)':\n\n\(list)",
                    isError: false
                ))
            }
        }
    }
}
```

**Step 2: Register Reminders server in ChatViewModel**

Modify `AI Helper2/Models/Models.swift` - in `ChatViewModel.init()` after calendar setup, add:

```swift
// In setupUnifiedAgent() or init(), add:
let remindersServer = RemindersMCPServer()
mcpAIService.mcpManager.registerServer(remindersServer, name: "reminders")
```

**Step 3: Add privacy permission**

Add to Info.plist in Xcode target settings:
- Key: `NSRemindersUsageDescription`
- Value: "AI Helper needs access to Reminders to create and manage your tasks."

**Step 4: Build and test**

Run: `xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" -sdk iphonesimulator build`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add "AI Helper2/Services/MCP/RemindersMCPServer.swift" "AI Helper2/Models/Models.swift"
git commit -m "feat: add Reminders MCP server with 5 tools"
```

---

## Task 3: OpenAI Whisper Transcription

**Files:**
- Create: `AI Helper2/Services/Voice/WhisperTranscriptionService.swift`
- Modify: `AI Helper2/Services/Voice/VoiceInputManager.swift`
- Modify: `AI Helper2/Models/Models.swift`

**Step 1: Create WhisperTranscriptionService**

Create `AI Helper2/Services/Voice/WhisperTranscriptionService.swift`:

```swift
import Foundation
import AVFoundation
import os.log

class WhisperTranscriptionService {
    private let logger = Logger(subsystem: "com.aihelper.voice", category: "WhisperTranscription")

    func transcribe(audioURL: URL, apiKey: String) async throws -> String {
        logger.info("🎤 Starting Whisper transcription...")

        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)

        // Add audio file
        let audioData = try Data(contentsOf: audioURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let startTime = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await URLSession.shared.data(for: request)
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhisperError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("❌ Whisper API error: \(errorMessage)")
            throw WhisperError.apiError(errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw WhisperError.parseError
        }

        logger.info("✅ Whisper transcription complete - Duration: \(String(format: "%.2f", duration))s, Text: \(text.prefix(50))...")
        return text
    }
}

enum WhisperError: LocalizedError {
    case invalidResponse
    case apiError(String)
    case parseError
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from Whisper API"
        case .apiError(let msg): return "Whisper API error: \(msg)"
        case .parseError: return "Failed to parse transcription"
        case .recordingFailed: return "Failed to record audio"
        }
    }
}
```

**Step 2: Update VoiceInputManager to use Whisper**

Modify `AI Helper2/Services/Voice/VoiceInputManager.swift`:

```swift
import Foundation
import AVFoundation
import os.log

class VoiceInputManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var hasPermissions = false
    @Published var transcriptionText = ""
    @Published var isTranscribing = false

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private let whisperService = WhisperTranscriptionService()
    private let logger = Logger(subsystem: "com.aihelper.voice", category: "VoiceInputManager")

    var apiKey: String = ""

    override init() {
        super.init()
        requestPermissions()
    }

    func requestPermissions() {
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                self?.hasPermissions = granted
            }
        }
    }

    func startRecording() {
        guard hasPermissions, !isRecording else { return }

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
        } catch {
            logger.error("❌ Audio session setup failed: \(error.localizedDescription)")
            return
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        recordingURL = documentsPath.appendingPathComponent("recording_\(Date().timeIntervalSince1970).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: recordingURL!, settings: settings)
            audioRecorder?.record()
            isRecording = true
            transcriptionText = ""
            logger.info("🎙️ Recording started")
        } catch {
            logger.error("❌ Recording failed: \(error.localizedDescription)")
        }
    }

    func stopRecording(completion: @escaping (String) -> Void) {
        guard isRecording, let recorder = audioRecorder, let url = recordingURL else { return }

        recorder.stop()
        isRecording = false
        logger.info("🛑 Recording stopped")

        guard !apiKey.isEmpty else {
            logger.warning("⚠️ No API key for Whisper transcription")
            completion("")
            return
        }

        isTranscribing = true

        Task {
            do {
                let text = try await whisperService.transcribe(audioURL: url, apiKey: apiKey)
                await MainActor.run {
                    self.transcriptionText = text
                    self.isTranscribing = false
                    completion(text)
                }
            } catch {
                await MainActor.run {
                    self.isTranscribing = false
                    self.logger.error("❌ Transcription failed: \(error.localizedDescription)")
                    completion("")
                }
            }

            // Cleanup
            try? FileManager.default.removeItem(at: url)
        }
    }

    func cancelRecording() {
        audioRecorder?.stop()
        isRecording = false
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
    }
}
```

**Step 3: Update ChatView to pass API key**

In `AI Helper2/Views/Chat/ChatView.swift`, update voice manager setup:

```swift
// In ChatView, update onAppear or add onChange:
.onAppear {
    voiceInputManager.apiKey = chatViewModel.apiConfiguration.apiKey
    voiceInputManager.requestPermissions()
}
.onChange(of: chatViewModel.apiConfiguration.apiKey) { newKey in
    voiceInputManager.apiKey = newKey
}
```

**Step 4: Build and test**

Run: `xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" -sdk iphonesimulator build`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add "AI Helper2/Services/Voice/"
git commit -m "feat: replace Speech framework with OpenAI Whisper API"
```

---

## Task 4: Conversation Persistence (CoreData)

**Files:**
- Create: `AI Helper2/Models/Persistence.swift`
- Create: `AI Helper2/Models/AIHelper.xcdatamodeld` (via Xcode)
- Modify: `AI Helper2/Models/Models.swift`
- Modify: `AI Helper2/App/AI_Helper2App.swift`

**Step 1: Create CoreData model**

In Xcode:
1. File → New → File → Data Model
2. Name: `AIHelper`
3. Add entities:

**Entity: Conversation**
- id: UUID
- title: String (optional)
- createdAt: Date
- updatedAt: Date

**Entity: Message**
- id: UUID
- content: String
- role: String (user/assistant/system)
- timestamp: Date
- Relationship: conversation (to-one, inverse: messages)

**Step 2: Create Persistence controller**

Create `AI Helper2/Models/Persistence.swift`:

```swift
import CoreData
import os.log

class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer
    private let logger = Logger(subsystem: "com.aihelper.persistence", category: "CoreData")

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "AIHelper")

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { description, error in
            if let error = error {
                self.logger.error("❌ CoreData failed to load: \(error.localizedDescription)")
            } else {
                self.logger.info("✅ CoreData loaded successfully")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    // MARK: - Conversation Management

    func createConversation(title: String? = nil) -> NSManagedObjectID? {
        let context = container.viewContext
        let conversation = NSEntityDescription.insertNewObject(forEntityName: "Conversation", into: context)
        conversation.setValue(UUID(), forKey: "id")
        conversation.setValue(title, forKey: "title")
        conversation.setValue(Date(), forKey: "createdAt")
        conversation.setValue(Date(), forKey: "updatedAt")

        do {
            try context.save()
            return conversation.objectID
        } catch {
            logger.error("❌ Failed to create conversation: \(error.localizedDescription)")
            return nil
        }
    }

    func addMessage(to conversationID: NSManagedObjectID, content: String, role: String) {
        let context = container.viewContext

        guard let conversation = try? context.existingObject(with: conversationID) else {
            logger.error("❌ Conversation not found")
            return
        }

        let message = NSEntityDescription.insertNewObject(forEntityName: "Message", into: context)
        message.setValue(UUID(), forKey: "id")
        message.setValue(content, forKey: "content")
        message.setValue(role, forKey: "role")
        message.setValue(Date(), forKey: "timestamp")
        message.setValue(conversation, forKey: "conversation")

        conversation.setValue(Date(), forKey: "updatedAt")

        do {
            try context.save()
        } catch {
            logger.error("❌ Failed to save message: \(error.localizedDescription)")
        }
    }

    func loadMessages(for conversationID: NSManagedObjectID) -> [ChatMessage] {
        let context = container.viewContext

        guard let conversation = try? context.existingObject(with: conversationID) else {
            return []
        }

        let messages = conversation.value(forKey: "messages") as? Set<NSManagedObject> ?? []

        return messages.compactMap { msg -> ChatMessage? in
            guard let content = msg.value(forKey: "content") as? String,
                  let role = msg.value(forKey: "role") as? String else {
                return nil
            }
            return ChatMessage(content: content, isUser: role == "user")
        }.sorted { $0.timestamp < $1.timestamp }
    }

    func loadRecentConversation() -> NSManagedObjectID? {
        let context = container.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "Conversation")
        request.sortDescriptors = [NSSortDescriptor(key: "updatedAt", ascending: false)]
        request.fetchLimit = 1

        do {
            let results = try context.fetch(request)
            return results.first?.objectID
        } catch {
            logger.error("❌ Failed to load recent conversation: \(error.localizedDescription)")
            return nil
        }
    }
}
```

**Step 3: Integrate with ChatViewModel**

Modify `AI Helper2/Models/Models.swift` - add persistence to ChatViewModel:

```swift
class ChatViewModel: ObservableObject {
    // Add property:
    private var currentConversationID: NSManagedObjectID?
    private let persistence = PersistenceController.shared

    // In init(), add:
    func loadPersistedConversation() {
        if let conversationID = persistence.loadRecentConversation() {
            currentConversationID = conversationID
            messages = persistence.loadMessages(for: conversationID)
        } else {
            currentConversationID = persistence.createConversation(title: "New Chat")
        }
    }

    // Modify sendMessage() to persist:
    // After adding user message:
    if let id = currentConversationID {
        persistence.addMessage(to: id, content: userMessage.content, role: "user")
    }

    // After adding AI response:
    if let id = currentConversationID {
        persistence.addMessage(to: id, content: response, role: "assistant")
    }
}
```

**Step 4: Build and test**

Run: `xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" -sdk iphonesimulator build`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add "AI Helper2/Models/"
git commit -m "feat: add CoreData persistence for conversations"
```

---

## Task 5: Streaming Responses

**Files:**
- Create: `AI Helper2/Services/AI/StreamingService.swift`
- Modify: `AI Helper2/Services/AI/AIService.swift`
- Modify: `AI Helper2/Models/Models.swift`
- Modify: `AI Helper2/Views/Chat/ChatView.swift`

**Step 1: Create StreamingService**

Create `AI Helper2/Services/AI/StreamingService.swift`:

```swift
import Foundation
import os.log

class StreamingService: NSObject, URLSessionDataDelegate {
    private let logger = Logger(subsystem: "com.aihelper.streaming", category: "StreamingService")

    private var onChunk: ((String) -> Void)?
    private var onComplete: ((Result<Void, Error>) -> Void)?
    private var buffer = ""

    func streamOpenAI(
        message: String,
        configuration: APIConfiguration,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        self.onChunk = onChunk
        self.onComplete = onComplete

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": configuration.model,
            "messages": [["role": "user", "content": message]],
            "max_tokens": configuration.maxTokens,
            "temperature": configuration.temperature,
            "stream": true
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        task.resume()

        logger.info("🌊 Started OpenAI streaming request")
    }

    func streamClaude(
        message: String,
        configuration: APIConfiguration,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        self.onChunk = onChunk
        self.onComplete = onComplete

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": configuration.model,
            "max_tokens": configuration.maxTokens,
            "temperature": configuration.temperature,
            "messages": [["role": "user", "content": message]],
            "stream": true
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.dataTask(with: request)
        task.resume()

        logger.info("🌊 Started Claude streaming request")
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer += text

        // Process SSE lines
        while let lineEnd = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<lineEnd])
            buffer = String(buffer[buffer.index(after: lineEnd)...])

            processSSELine(line)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async {
            if let error = error {
                self.onComplete?(.failure(error))
            } else {
                self.onComplete?(.success(()))
            }
        }
        logger.info("🏁 Streaming complete")
    }

    private func processSSELine(_ line: String) {
        guard line.hasPrefix("data: ") else { return }
        let jsonString = String(line.dropFirst(6))

        if jsonString == "[DONE]" { return }

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // OpenAI format
        if let choices = json["choices"] as? [[String: Any]],
           let delta = choices.first?["delta"] as? [String: Any],
           let content = delta["content"] as? String {
            DispatchQueue.main.async {
                self.onChunk?(content)
            }
        }

        // Claude format
        if let type = json["type"] as? String, type == "content_block_delta",
           let delta = json["delta"] as? [String: Any],
           let text = delta["text"] as? String {
            DispatchQueue.main.async {
                self.onChunk?(text)
            }
        }
    }
}
```

**Step 2: Add streaming to ChatViewModel**

Modify `AI Helper2/Models/Models.swift`:

```swift
// Add property:
@Published var streamingText = ""
private let streamingService = StreamingService()

// Add streaming method:
func sendMessageStreaming() async {
    guard !currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          !apiConfiguration.apiKey.isEmpty else { return }

    let userMessage = ChatMessage(content: currentMessage, isUser: true)

    await MainActor.run {
        messages.append(userMessage)
        isLoading = true
        streamingText = ""
        showSuggestedPrompts = false
    }

    let messageToSend = currentMessage
    await MainActor.run { currentMessage = "" }

    let onChunk: (String) -> Void = { [weak self] chunk in
        self?.streamingText += chunk
    }

    let onComplete: (Result<Void, Error>) -> Void = { [weak self] result in
        guard let self = self else { return }

        let finalText = self.streamingText
        let aiMessage = ChatMessage(content: finalText, isUser: false)

        DispatchQueue.main.async {
            self.messages.append(aiMessage)
            self.streamingText = ""
            self.isLoading = false
        }
    }

    switch apiConfiguration.provider {
    case .openai:
        streamingService.streamOpenAI(
            message: messageToSend,
            configuration: apiConfiguration,
            onChunk: onChunk,
            onComplete: onComplete
        )
    case .claude:
        streamingService.streamClaude(
            message: messageToSend,
            configuration: apiConfiguration,
            onChunk: onChunk,
            onComplete: onComplete
        )
    }
}
```

**Step 3: Update ChatView to show streaming text**

Modify `AI Helper2/Views/Chat/ChatView.swift`:

```swift
// In the messages list, add streaming indicator:
if chatViewModel.isLoading && !chatViewModel.streamingText.isEmpty {
    MessageBubble(message: ChatMessage(content: chatViewModel.streamingText, isUser: false))
        .opacity(0.8)
}
```

**Step 4: Build and test**

Run: `xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" -sdk iphonesimulator build`
Expected: BUILD SUCCEEDED

**Step 5: Commit**

```bash
git add "AI Helper2/Services/AI/StreamingService.swift" "AI Helper2/Models/Models.swift" "AI Helper2/Views/Chat/ChatView.swift"
git commit -m "feat: add streaming responses for OpenAI and Claude"
```

---

## Task 6: Update Documentation

**Step 1: Update CLAUDE.md**

Add new services to project structure and document new features.

**Step 2: Update checklist**

Mark completed items in `docs/ITERATION_CHECKLIST.md`.

**Step 3: Commit**

```bash
git add CLAUDE.md docs/ITERATION_CHECKLIST.md
git commit -m "docs: update documentation for Phase 1 features"
```

---

## Final: Pre-Push Verification

**Step 1: Run full build**

```bash
xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" -sdk iphonesimulator clean build
```

**Step 2: Run tests**

```bash
xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" -destination "platform=iOS Simulator,name=iPhone 16" test
```

**Step 3: Check warnings**

```bash
xcodebuild -project "AI Helper2.xcodeproj" -scheme "AI Helper2" -sdk iphonesimulator build 2>&1 | grep -i warning
```

**Step 4: Verify checklist**

Review `docs/ITERATION_CHECKLIST.md` pre-push items are all checked.

---

## Summary

| Task | Files | Description |
|------|-------|-------------|
| 1 | APIKeyValidator.swift, SettingsView.swift | Validate API keys before use |
| 2 | RemindersMCPServer.swift, Models.swift | 5 reminder tools via EventKit |
| 3 | WhisperTranscriptionService.swift, VoiceInputManager.swift | OpenAI Whisper for voice |
| 4 | Persistence.swift, AIHelper.xcdatamodeld | CoreData for conversations |
| 5 | StreamingService.swift, Models.swift, ChatView.swift | SSE streaming for both providers |
| 6 | CLAUDE.md, ITERATION_CHECKLIST.md | Documentation updates |
