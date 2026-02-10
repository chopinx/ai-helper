import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @StateObject private var voiceManager = VoiceInputManager()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    @State private var showingSettings = false

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if viewModel.isReasonActMode && !viewModel.reasonActSteps.isEmpty {
                    ReasonActTimelineView(steps: viewModel.reasonActSteps)
                        .frame(maxHeight: 200)
                        .background(DS.Colors.groupedBackground)
                }
                chatContent
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(isPresented: $showingSettings, onDismiss: viewModel.saveConfiguration) {
                SettingsView(configuration: $viewModel.apiConfiguration)
            }
            .sheet(isPresented: $viewModel.showPendingActionSheet) {
                if !viewModel.pendingActions.isEmpty {
                    PendingActionsSheet(
                        actions: viewModel.pendingActions,
                        onConfirm: { Task { await viewModel.confirmPendingActions() } },
                        onCancel: { viewModel.cancelPendingActions() }
                    )
                    .presentationDetents([.medium, .large])
                }
            }
        }
        .onAppear {
            voiceManager.requestPermissions()
            voiceManager.apiKey = viewModel.apiConfiguration.apiKey
        }
        .onChange(of: viewModel.apiConfiguration.apiKey) {
            voiceManager.apiKey = viewModel.apiConfiguration.apiKey
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            HStack(spacing: 12) {
                if !viewModel.messages.isEmpty {
                    Button { viewModel.clearConversation() } label: {
                        Image(systemName: "trash")
                            .foregroundColor(DS.Colors.error)
                    }
                    .accessibilityLabel("Clear conversation")
                }
                Button { showingSettings = true } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
        }
        ToolbarItem(placement: .navigationBarLeading) {
            HStack(spacing: 12) {
                Button { viewModel.toggleReasonActMode() } label: {
                    Image(systemName: viewModel.isReasonActMode ? "bubble.left.and.text.bubble.right" : "wrench.and.screwdriver")
                }
                .accessibilityLabel(viewModel.isReasonActMode ? "Switch to simple mode" : "Switch to reason-act mode")

                if viewModel.messages.isEmpty {
                    Button { viewModel.toggleSuggestedPrompts() } label: {
                        Image(systemName: viewModel.shouldShowSuggestedPrompts ? "lightbulb.fill" : "lightbulb")
                            .foregroundColor(DS.Colors.warning)
                    }
                    .accessibilityLabel(viewModel.shouldShowSuggestedPrompts ? "Hide suggested prompts" : "Show suggested prompts")
                }
            }
        }
    }

    private var chatContent: some View {
        VStack(spacing: 0) {
            if !networkMonitor.isConnected {
                NetworkBanner()
            }

            if viewModel.apiConfiguration.apiKey.isEmpty {
                APIKeyWarningBanner(showSettings: $showingSettings)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        if viewModel.messages.isEmpty && !viewModel.shouldShowSuggestedPrompts {
                            EmptyChatView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 60)
                        }
                        if viewModel.shouldShowSuggestedPrompts {
                            SuggestedPromptsView(viewModel: viewModel)
                                .padding(.horizontal).padding(.top)
                        }
                        ForEach(viewModel.messages) { message in
                            MessageBubble(
                                message: message,
                                onRetry: message.isError ? { Task { await viewModel.retryMessage(message) } } : nil
                            )
                            .id(message.id)
                        }
                        if viewModel.isLoading && !viewModel.streamingText.isEmpty {
                            MessageBubble(message: ChatMessage(content: viewModel.streamingText, isUser: false))
                                .opacity(0.8)
                        }
                    }
                    .padding()
                }
                .onChange(of: viewModel.messages.count) { scrollToBottom(proxy) }
                .onChange(of: viewModel.reasonActSteps.count) { if !viewModel.isLoading { scrollToBottom(proxy) } }
            }

            // Dynamic process view - fixed at bottom, always visible during loading
            if viewModel.isLoading {
                DynamicProcessView(
                    status: viewModel.currentStatus,
                    tracker: viewModel.processTracker
                )
                .padding(.horizontal)
                .padding(.top, 8)
            }

            ChatInputView(
                currentMessage: $viewModel.currentMessage,
                isLoading: viewModel.isLoading,
                voiceManager: voiceManager,
                sendAction: { Task { await viewModel.sendMessage() } }
            )
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation {
            if let last = viewModel.messages.last { proxy.scrollTo(last.id, anchor: .bottom) }
        }
    }
}

// MARK: - API Key Warning Banner

struct APIKeyWarningBanner: View {
    @Binding var showSettings: Bool

    var body: some View {
        HStack(spacing: DS.Spacing.lg) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(DS.Colors.warning).font(.title3)
            VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                Text("API Key Required").font(.subheadline).fontWeight(.semibold)
                Text("Configure your API key in Settings to start chatting").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("Settings") { showSettings = true }
                .buttonStyle(PillButtonStyle())
        }
        .bannerStyle(tintColor: DS.Colors.warning)
        .padding(.horizontal).padding(.top, DS.Spacing.md)
    }
}

// MARK: - Dynamic Process View (Compact Single Line)

struct DynamicProcessView: View {
    let status: ProcessingStatus
    @ObservedObject var tracker: ProcessTracker

    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            // Spinner
            ProgressView().scaleEffect(0.7)

            // Step indicator
            if !tracker.iterations.isEmpty {
                Text("Step \(tracker.iterations.count)")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, DS.Spacing.sm + 2).padding(.vertical, DS.Spacing.xs)
                    .background(DS.Colors.accent).cornerRadius(DS.CornerRadius.small)
            }

            // Current action
            Text(compactStatus)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            // Tool call badges
            HStack(spacing: DS.Spacing.sm) {
                ForEach(recentToolCalls.prefix(3)) { tool in
                    HStack(spacing: DS.Spacing.xs) {
                        Image(systemName: tool.statusIcon)
                            .foregroundColor(tool.statusColor)
                            .font(.system(size: 8))
                        Text(shortToolName(tool.name))
                            .font(.caption2)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, DS.Spacing.sm).padding(.vertical, DS.Spacing.xs)
                    .background(DS.Colors.aiBubble)
                    .cornerRadius(DS.Spacing.sm)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.lg).padding(.vertical, DS.Spacing.md)
        .background(DS.Colors.groupedBackground)
        .cornerRadius(DS.Spacing.md)
    }

    private var compactStatus: String {
        switch status {
        case .loadingTools: return "Loading tools..."
        case .thinkingStep: return "Thinking..."
        case .callingTool(let name): return "Calling \(shortToolName(name))..."
        case .processingToolResult(let name): return "\(shortToolName(name)) done"
        case .generatingResponse: return "Generating..."
        default: return status.displayText
        }
    }

    private var recentToolCalls: [ToolCallRecord] {
        tracker.iterations.flatMap { $0.toolCalls }
    }

    private func shortToolName(_ name: String) -> String {
        let short = name.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "reminder", with: "")
            .replacingOccurrences(of: "event", with: "")
            .trimmingCharacters(in: .whitespaces)
        return short.prefix(1).uppercased() + short.dropFirst().prefix(6)
    }
}

// MARK: - Reason-Act Timeline View

struct ReasonActTimelineView: View {
    let steps: [ReasonActStep]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(steps) { ReasonActStepView(step: $0) }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
}

struct ReasonActStepView: View {
    let step: ReasonActStep

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Step \(step.stepNumber)").font(.caption).fontWeight(.semibold)

            if !step.assistantMessage.isEmpty {
                Text(step.assistantMessage.prefix(50) + (step.assistantMessage.count > 50 ? "..." : ""))
                    .font(.caption2).foregroundColor(.secondary).lineLimit(2)
            }

            ForEach(step.toolExecutions) { exec in
                HStack(spacing: 4) {
                    Text(exec.statusIcon).font(.caption2)
                    Text(exec.toolName).font(.caption2).fontWeight(.medium)
                        .foregroundColor(exec.isError ? DS.Colors.error : DS.Colors.success)
                    Text(exec.durationString).font(.caption2).foregroundColor(.secondary)
                }
            }

            if step.toolExecutions.isEmpty {
                Label("Thinking...", systemImage: "brain").font(.caption2).foregroundColor(DS.Colors.accent).italic()
            }
        }
        .padding(DS.Spacing.md)
        .background(DS.Colors.surface)
        .cornerRadius(DS.Spacing.md)
        .shadow(radius: 1)
        .frame(width: 120)
    }
}

// MARK: - Chat Input View

struct ChatInputView: View {
    @Binding var currentMessage: String
    let isLoading: Bool
    let voiceManager: VoiceInputManager
    let sendAction: () -> Void

    private var canSend: Bool {
        !isLoading && !currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack {
            TextField("Type your message...", text: $currentMessage, axis: .vertical)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .lineLimit(1...4)
                .onSubmit { if canSend { sendAction() } }

            if voiceManager.hasPermissions {
                if voiceManager.isTranscribing {
                    ProgressView()
                        .font(.title2)
                        .padding(.trailing, 4)
                } else {
                    Button {
                        if voiceManager.isRecording {
                            voiceManager.stopRecording()
                        } else {
                            voiceManager.startRecording { currentMessage = $0 }
                        }
                    } label: {
                        Image(systemName: voiceManager.isRecording ? "mic.fill" : "mic")
                            .foregroundColor(voiceManager.isRecording ? DS.Colors.error : DS.Colors.accent)
                            .font(.title2)
                    }
                    .accessibilityLabel(voiceManager.isRecording ? "Stop recording" : "Start voice input")
                    .padding(.trailing, 4)
                }
            }

            Button(action: sendAction) {
                Image(systemName: "paperplane.fill").foregroundColor(canSend ? DS.Colors.accent : .gray)
            }
            .disabled(!canSend)
            .accessibilityLabel("Send message")
        }
        .padding()
    }
}

// MARK: - Network Banner

struct NetworkBanner: View {
    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            Image(systemName: "wifi.slash")
                .foregroundColor(.white)
                .font(.caption)
            Text("No internet connection")
                .font(.caption)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DS.Spacing.sm + 2)
        .background(DS.Colors.error)
    }
}

// MARK: - Markdown Content View

struct MarkdownContentView: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(contentBlocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    Text(markdownAttributedString(from: text))
                        .textSelection(.enabled)
                case .code(let code, let language):
                    CodeBlockView(code: code, language: language)
                case .header(let text, let level):
                    Text(markdownAttributedString(from: text))
                        .font(fontForHeaderLevel(level))
                        .bold()
                        .textSelection(.enabled)
                case .bulletItem(let text):
                    HStack(alignment: .top, spacing: 6) {
                        Text("\u{2022}")
                        Text(markdownAttributedString(from: text))
                            .textSelection(.enabled)
                    }
                    .padding(.leading, 8)
                }
            }
        }
    }

    private func fontForHeaderLevel(_ level: Int) -> Font {
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        default: return .headline
        }
    }

    private enum ContentBlock {
        case text(String)
        case code(String, String?)
        case header(String, Int)
        case bulletItem(String)
    }

    private var contentBlocks: [ContentBlock] {
        let lines = content.components(separatedBy: "\n")
        var blocks: [ContentBlock] = []
        var currentText = ""
        var currentCode = ""
        var codeLanguage: String?
        var inCodeBlock = false

        for line in lines {
            if !inCodeBlock && line.hasPrefix("```") {
                // Start of code block
                let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    blocks.append(.text(trimmed))
                }
                currentText = ""
                inCodeBlock = true
                let lang = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                codeLanguage = lang.isEmpty ? nil : lang
                currentCode = ""
            } else if inCodeBlock && line.trimmingCharacters(in: .whitespaces) == "```" {
                // End of code block
                blocks.append(.code(currentCode, codeLanguage))
                currentCode = ""
                codeLanguage = nil
                inCodeBlock = false
            } else if inCodeBlock {
                if !currentCode.isEmpty { currentCode += "\n" }
                currentCode += line
            } else if let headerMatch = headerLevel(of: line) {
                // Flush accumulated text before header
                let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    blocks.append(.text(trimmed))
                    currentText = ""
                }
                blocks.append(.header(headerMatch.text, headerMatch.level))
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                // Flush accumulated text before bullet item
                let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    blocks.append(.text(trimmed))
                    currentText = ""
                }
                let itemText = String(line.dropFirst(2))
                blocks.append(.bulletItem(itemText))
            } else {
                if !currentText.isEmpty { currentText += "\n" }
                currentText += line
            }
        }

        // Handle remaining content
        if inCodeBlock {
            // Unclosed code fence (e.g. during streaming) — render as code block
            blocks.append(.code(currentCode, codeLanguage))
        } else {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(.text(trimmed))
            }
        }

        return blocks
    }

    private func markdownAttributedString(from text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        if let attributed = try? AttributedString(markdown: text, options: options) {
            return attributed
        }
        return AttributedString(text)
    }

    private func headerLevel(of line: String) -> (text: String, level: Int)? {
        if line.hasPrefix("#### ") {
            return (String(line.dropFirst(5)), 4)
        } else if line.hasPrefix("### ") {
            return (String(line.dropFirst(4)), 3)
        } else if line.hasPrefix("## ") {
            return (String(line.dropFirst(3)), 2)
        } else if line.hasPrefix("# ") {
            return (String(line.dropFirst(2)), 1)
        }
        return nil
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let code: String
    let language: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let language, !language.isEmpty {
                Text(language)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, language != nil ? 4 : 8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Colors.groupedBackground)
        .cornerRadius(DS.Spacing.md)
    }
}

// MARK: - Message Bubble

struct MessageBubble: View {
    let message: ChatMessage
    var onRetry: (() -> Void)?

    var body: some View {
        HStack {
            if message.isUser { Spacer() }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 8) {
                if let errorType = message.errorType {
                    // Error message with guidance and retry
                    ErrorMessageView(
                        errorType: errorType,
                        content: cleanedContent,
                        onRetry: onRetry
                    )
                } else if message.isUser {
                    Text(cleanedContent)
                        .padding(DS.Spacing.lg)
                        .background(DS.Colors.accent)
                        .foregroundColor(.white)
                        .cornerRadius(DS.CornerRadius.bubble)
                } else {
                    MarkdownContentView(content: cleanedContent)
                        .padding(DS.Spacing.lg)
                        .background(DS.Colors.aiBubble)
                        .foregroundColor(.primary)
                        .cornerRadius(DS.CornerRadius.bubble)
                }

                if let eventInfo = calendarEventInfo {
                    CalendarEventButton(eventInfo: eventInfo)
                }

                if let reminderInfo = reminderInfo {
                    ReminderButton(reminderInfo: reminderInfo)
                }
            }
            .frame(maxWidth: .infinity * 0.8, alignment: message.isUser ? .trailing : .leading)

            if !message.isUser { Spacer() }
        }
    }

    private var cleanedContent: String {
        message.content
            .replacingOccurrences(of: "<|FINAL_RESPONSE|>", with: "")
            .replacingOccurrences(of: "\\[\\[CALENDAR_EVENT\\|\\|.*?\\]\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\[\\[REMINDER\\|\\|.*?\\]\\]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var calendarEventInfo: CalendarEventInfo? {
        let pattern = "\\[\\[CALENDAR_EVENT\\|\\|([^|]+)\\|\\|([^|]+)\\|\\|([^|]+)\\|\\|([^|]+)\\]\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: message.content, range: NSRange(message.content.startIndex..., in: message.content)),
              let r1 = Range(match.range(at: 1), in: message.content),
              let r2 = Range(match.range(at: 2), in: message.content),
              let r3 = Range(match.range(at: 3), in: message.content),
              let r4 = Range(match.range(at: 4), in: message.content) else { return nil }

        return CalendarEventInfo(
            eventId: String(message.content[r1]),
            title: String(message.content[r2]),
            startDate: Date(timeIntervalSince1970: TimeInterval(Int(message.content[r3]) ?? 0)),
            action: String(message.content[r4])
        )
    }

    private var reminderInfo: ReminderInfo? {
        let pattern = "\\[\\[REMINDER\\|\\|([^|]+)\\|\\|([^|]+)\\|\\|([^|]+)\\|\\|([^|]+)\\]\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: message.content, range: NSRange(message.content.startIndex..., in: message.content)),
              let r1 = Range(match.range(at: 1), in: message.content),
              let r2 = Range(match.range(at: 2), in: message.content),
              let r3 = Range(match.range(at: 3), in: message.content),
              let r4 = Range(match.range(at: 4), in: message.content) else { return nil }

        return ReminderInfo(
            reminderId: String(message.content[r1]),
            title: String(message.content[r2]),
            dueDate: Date(timeIntervalSince1970: TimeInterval(Int(message.content[r3]) ?? 0)),
            action: String(message.content[r4])
        )
    }
}

// MARK: - Error Message View

struct ErrorMessageView: View {
    let errorType: ChatMessageError
    let content: String
    var onRetry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm + 2) {
                Image(systemName: errorType.icon)
                    .foregroundColor(DS.Colors.error)
                    .font(.caption)
                Text(content)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }

            Text(errorType.guidance)
                .font(.caption)
                .foregroundColor(.secondary)

            if let onRetry {
                Button(action: onRetry) {
                    Label("Retry", systemImage: "arrow.clockwise")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(DS.Colors.accent)
            }
        }
        .bannerStyle(tintColor: DS.Colors.error)
    }
}

// MARK: - Calendar Event Button

struct CalendarEventInfo {
    let eventId: String
    let title: String
    let startDate: Date
    let action: String
}

struct CalendarEventButton: View {
    let eventInfo: CalendarEventInfo

    var body: some View {
        Button(action: openCalendarEvent) {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "calendar").foregroundColor(DS.Colors.accent)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(eventInfo.title).font(.subheadline).fontWeight(.medium)
                    Text(eventInfo.startDate, style: .date).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
            .padding(DS.Spacing.lg)
            .background(DS.Colors.surface)
            .cornerRadius(DS.CornerRadius.medium)
            .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.medium).stroke(DS.Colors.tint(DS.Colors.accent, opacity: 0.3), lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func openCalendarEvent() {
        if let url = URL(string: "calshow:\(eventInfo.startDate.timeIntervalSinceReferenceDate)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Reminder Button

struct ReminderInfo {
    let reminderId: String
    let title: String
    let dueDate: Date
    let action: String
}

struct ReminderButton: View {
    let reminderInfo: ReminderInfo

    var body: some View {
        Button(action: openReminders) {
            HStack(spacing: DS.Spacing.md) {
                Image(systemName: "checklist").foregroundColor(DS.Colors.success)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Text(reminderInfo.title).font(.subheadline).fontWeight(.medium)
                    if reminderInfo.dueDate.timeIntervalSince1970 > 0 {
                        Text(reminderInfo.dueDate, style: .date).font(.caption).foregroundColor(.secondary)
                    }
                    Text(actionText).font(.caption2).foregroundColor(actionColor)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
            .padding(DS.Spacing.lg)
            .background(DS.Colors.surface)
            .cornerRadius(DS.CornerRadius.medium)
            .overlay(RoundedRectangle(cornerRadius: DS.CornerRadius.medium).stroke(DS.Colors.tint(DS.Colors.success, opacity: 0.3), lineWidth: 1))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var actionText: String {
        switch reminderInfo.action {
        case "created": return "Created"
        case "completed": return "Completed"
        case "deleted": return "Deleted"
        default: return reminderInfo.action.capitalized
        }
    }

    private var actionColor: Color {
        switch reminderInfo.action {
        case "created": return DS.Colors.success
        case "completed": return DS.Colors.accent
        case "deleted": return DS.Colors.error
        default: return .secondary
        }
    }

    private func openReminders() {
        // Open Reminders app - x-apple-reminderkit:// opens Reminders app
        if let url = URL(string: "x-apple-reminderkit://") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Pending Actions Confirmation Sheet

struct PendingActionsSheet: View {
    let actions: [PendingAction]
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var hasDelete: Bool {
        actions.contains { $0.type == .delete }
    }

    private var actionSummary: String {
        if actions.count == 1 {
            return actions[0].actionText
        }
        return "\(actions.count) Actions"
    }

    private var primaryColor: Color {
        hasDelete ? DS.Colors.error : DS.Colors.warning
    }

    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            // Header
            HStack {
                Image(systemName: hasDelete ? "trash.fill" : "pencil.circle.fill")
                    .font(.title)
                    .foregroundColor(primaryColor)
                Text("Confirm \(actionSummary)")
                    .heading(.medium)
            }
            .padding(.top)

            // Actions list
            ScrollView {
                VStack(spacing: DS.Spacing.lg) {
                    ForEach(actions.indices, id: \.self) { index in
                        PendingActionRow(action: actions[index])
                    }
                }
            }
            .frame(maxHeight: 300)

            // Warning for delete
            if hasDelete {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(DS.Colors.warning)
                    Text("Delete actions cannot be undone")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Buttons
            HStack(spacing: DS.Spacing.xl) {
                Button(action: onCancel) {
                    Text("Cancel")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button(action: onConfirm) {
                    Text("Confirm \(actions.count == 1 ? "" : "All")")
                }
                .buttonStyle(PrimaryButtonStyle(color: primaryColor))
            }
            .padding(.bottom)
        }
        .padding(.horizontal)
    }
}

struct PendingActionRow: View {
    let action: PendingAction

    var body: some View {
        HStack(spacing: DS.Spacing.lg) {
            // Type icon
            Image(systemName: action.icon)
                .font(.title3)
                .foregroundColor(action.color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: DS.Spacing.sm) {
                HStack {
                    Image(systemName: action.isCalendar ? "calendar" : "checklist")
                        .font(.caption)
                        .foregroundColor(action.isCalendar ? DS.Colors.accent : DS.Colors.success)
                    Text(action.isCalendar ? "Calendar" : "Reminder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text(action.title)
                    .font(.subheadline)
                    .fontWeight(.medium)

                if !action.details.isEmpty && action.details != "No additional details" {
                    Text(action.details)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer()
        }
        .padding()
        .background(DS.Colors.groupedBackground)
        .cornerRadius(DS.CornerRadius.medium)
    }
}

// MARK: - Suggested Prompts View

struct SuggestedPromptsView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.xl) {
            HStack {
                Label("Suggested Prompts", systemImage: "sparkles").heading(.medium)
                Spacer()
                Button { viewModel.toggleSuggestedPrompts() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.title3)
                }
                .accessibilityLabel("Dismiss suggested prompts")
            }
            Text("Pick a prompt to get started quickly").font(.caption).foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.lg) {
                    ForEach(PromptCategory.allCases, id: \.self) { category in
                        CategoryView(category: category, prompts: viewModel.promptsByCategory(category)) {
                            viewModel.selectSuggestedPrompt($0)
                        }
                    }
                }
            }
        }
        .padding()
        .background(DS.Colors.groupedBackground)
        .cornerRadius(DS.CornerRadius.medium + 2)
    }
}

struct CategoryView: View {
    let category: PromptCategory
    let prompts: [SuggestedPrompt]
    let onTap: (SuggestedPrompt) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack(spacing: DS.Spacing.sm + 2) {
                Circle().fill(category.swiftColor).frame(width: 8, height: 8)
                Text(category.rawValue).font(.caption).fontWeight(.medium)
            }
            ForEach(prompts) { prompt in
                Button { onTap(prompt) } label: {
                    HStack(spacing: DS.Spacing.md) {
                        Image(systemName: prompt.icon).foregroundColor(DS.Colors.accent).font(.caption).frame(width: 16)
                        VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                            Text(prompt.title).font(.caption).fontWeight(.medium).foregroundColor(.primary)
                            Text(prompt.prompt.prefix(40) + (prompt.prompt.count > 40 ? "..." : ""))
                                .font(.caption2).foregroundColor(.secondary).lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(DS.Spacing.md)
                    .background(DS.Colors.groupedBackground)
                    .cornerRadius(DS.CornerRadius.small)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(DS.Spacing.lg)
        .background(DS.Colors.surface)
        .cornerRadius(DS.Spacing.md)
        .shadow(radius: 1)
        .frame(width: 200)
    }
}

// MARK: - Empty Chat View

struct EmptyChatView: View {
    var body: some View {
        VStack(spacing: DS.Spacing.xl) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary.opacity(0.6))

            Text("How can I help?")
                .font(.title3)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Text("Ask me anything, or try managing your calendar and reminders.")
                .font(.subheadline)
                .foregroundColor(.secondary.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

// MARK: - Previews

#Preview { ChatView() }
#Preview("Settings") { SettingsView(configuration: .constant(APIConfiguration())) }
