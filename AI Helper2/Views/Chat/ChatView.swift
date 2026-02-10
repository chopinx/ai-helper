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
                        .background(Color(.systemGray6))
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
            HStack {
                if !viewModel.messages.isEmpty {
                    Button { viewModel.clearConversation() } label: {
                        Image(systemName: "trash").foregroundColor(.red)
                    }
                }
                Button("Settings") { showingSettings = true }
            }
        }
        ToolbarItem(placement: .navigationBarLeading) {
            HStack {
                Button(viewModel.isReasonActMode ? "💭" : "🔧") { viewModel.toggleReasonActMode() }
                if viewModel.messages.isEmpty {
                    Button { viewModel.toggleSuggestedPrompts() } label: {
                        Image(systemName: viewModel.shouldShowSuggestedPrompts ? "lightbulb.fill" : "lightbulb")
                            .foregroundColor(.orange)
                    }
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
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange).font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                Text("API Key Required").font(.subheadline).fontWeight(.semibold)
                Text("Configure your API key in Settings to start chatting").font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("Settings") { showSettings = true }
                .font(.subheadline).fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.blue).cornerRadius(8)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        .cornerRadius(10)
        .padding(.horizontal).padding(.top, 8)
    }
}

// MARK: - Dynamic Process View (Compact Single Line)

struct DynamicProcessView: View {
    let status: ProcessingStatus
    @ObservedObject var tracker: ProcessTracker

    var body: some View {
        HStack(spacing: 8) {
            // Spinner
            ProgressView().scaleEffect(0.7)

            // Step indicator
            if !tracker.iterations.isEmpty {
                Text("Step \(tracker.iterations.count)")
                    .font(.caption2).fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.blue).cornerRadius(6)
            }

            // Current action
            Text(compactStatus)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer()

            // Tool call badges
            HStack(spacing: 4) {
                ForEach(recentToolCalls.prefix(3)) { tool in
                    HStack(spacing: 2) {
                        Image(systemName: tool.statusIcon)
                            .foregroundColor(tool.statusColor)
                            .font(.system(size: 8))
                        Text(shortToolName(tool.name))
                            .font(.caption2)
                            .foregroundColor(.primary)
                    }
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(Color(.systemGray5))
                    .cornerRadius(4)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(8)
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
                        .foregroundColor(exec.isError ? .red : .green)
                    Text(exec.durationString).font(.caption2).foregroundColor(.secondary)
                }
            }

            if step.toolExecutions.isEmpty {
                Label("Thinking...", systemImage: "brain").font(.caption2).foregroundColor(.blue).italic()
            }
        }
        .padding(8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
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
                Button {
                    if voiceManager.isRecording {
                        voiceManager.stopRecording()
                    } else {
                        voiceManager.startRecording { currentMessage = $0 }
                    }
                } label: {
                    Image(systemName: voiceManager.isRecording ? "mic.fill" : "mic")
                        .foregroundColor(voiceManager.isRecording ? .red : .blue)
                        .font(.title2)
                }
                .padding(.trailing, 4)
            }

            Button(action: sendAction) {
                Image(systemName: "paperplane.fill").foregroundColor(canSend ? .blue : .gray)
            }
            .disabled(!canSend)
        }
        .padding()
    }
}

// MARK: - Network Banner

struct NetworkBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
                .foregroundColor(.white)
                .font(.caption)
            Text("No internet connection")
                .font(.caption)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.red)
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
                } else {
                    Text(cleanedContent)
                        .padding(12)
                        .background(message.isUser ? Color.blue : Color(.systemGray5))
                        .foregroundColor(message.isUser ? .white : .primary)
                        .cornerRadius(16)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: errorType.icon)
                    .foregroundColor(.red)
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
                .tint(.blue)
            }
        }
        .padding(12)
        .background(Color.red.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
        .cornerRadius(12)
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
            HStack(spacing: 8) {
                Image(systemName: "calendar").foregroundColor(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(eventInfo.title).font(.subheadline).fontWeight(.medium)
                    Text(eventInfo.startDate, style: .date).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.blue.opacity(0.3), lineWidth: 1))
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
            HStack(spacing: 8) {
                Image(systemName: "checklist").foregroundColor(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(reminderInfo.title).font(.subheadline).fontWeight(.medium)
                    if reminderInfo.dueDate.timeIntervalSince1970 > 0 {
                        Text(reminderInfo.dueDate, style: .date).font(.caption).foregroundColor(.secondary)
                    }
                    Text(actionText).font(.caption2).foregroundColor(actionColor)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color(.systemBackground))
            .cornerRadius(10)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.3), lineWidth: 1))
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
        case "created": return .green
        case "completed": return .blue
        case "deleted": return .red
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
        hasDelete ? .red : .orange
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack {
                Image(systemName: hasDelete ? "trash.fill" : "pencil.circle.fill")
                    .font(.title)
                    .foregroundColor(primaryColor)
                Text("Confirm \(actionSummary)")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            .padding(.top)

            // Actions list
            ScrollView {
                VStack(spacing: 12) {
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
                        .foregroundColor(.orange)
                    Text("Delete actions cannot be undone")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Buttons
            HStack(spacing: 16) {
                Button(action: onCancel) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .foregroundColor(.primary)
                        .cornerRadius(12)
                }

                Button(action: onConfirm) {
                    Text("Confirm \(actions.count == 1 ? "" : "All")")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(primaryColor)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
            .padding(.bottom)
        }
        .padding(.horizontal)
    }
}

struct PendingActionRow: View {
    let action: PendingAction

    var body: some View {
        HStack(spacing: 12) {
            // Type icon
            Image(systemName: action.icon)
                .font(.title3)
                .foregroundColor(action.color)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: action.isCalendar ? "calendar" : "checklist")
                        .font(.caption)
                        .foregroundColor(action.isCalendar ? .blue : .green)
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
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }
}

// MARK: - Suggested Prompts View

struct SuggestedPromptsView: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("推荐提示词", systemImage: "sparkles").font(.title2).fontWeight(.semibold)
                Spacer()
                Button { viewModel.toggleSuggestedPrompts() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary).font(.title3)
                }
            }
            Text("选择一个提示词快速开始对话").font(.caption).foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PromptCategory.allCases, id: \.self) { category in
                        CategoryView(category: category, prompts: viewModel.promptsByCategory(category)) {
                            viewModel.selectSuggestedPrompt($0)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct CategoryView: View {
    let category: PromptCategory
    let prompts: [SuggestedPrompt]
    let onTap: (SuggestedPrompt) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Circle().fill(category.swiftColor).frame(width: 8, height: 8)
                Text(category.rawValue).font(.caption).fontWeight(.medium)
            }
            ForEach(prompts) { prompt in
                Button { onTap(prompt) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: prompt.icon).foregroundColor(.blue).font(.caption).frame(width: 16)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(prompt.title).font(.caption).fontWeight(.medium).foregroundColor(.primary)
                            Text(prompt.prompt.prefix(40) + (prompt.prompt.count > 40 ? "..." : ""))
                                .font(.caption2).foregroundColor(.secondary).lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(radius: 1)
        .frame(width: 200)
    }
}

// MARK: - Previews

#Preview { ChatView() }
#Preview("Settings") { SettingsView(configuration: .constant(APIConfiguration())) }
