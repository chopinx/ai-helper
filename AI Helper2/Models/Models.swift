import Foundation
import SwiftUI

enum AIProvider: String, CaseIterable, Codable {
    case openai = "OpenAI"
    case claude = "Claude"
    
    var baseURL: String {
        switch self {
        case .openai:
            return "https://api.openai.com/v1"
        case .claude:
            return "https://api.anthropic.com/v1"
        }
    }
    
    var availableModels: [String] {
        switch self {
        case .openai:
            return [
                "gpt-4o",              // ✅ Tool calling supported
                "gpt-4o-mini",         // ✅ Tool calling supported
                "gpt-4-turbo",         // ✅ Tool calling supported
                "gpt-4",               // ✅ Tool calling supported
                "gpt-3.5-turbo",       // ✅ Tool calling supported
                "gpt-3.5-turbo-16k"    // ✅ Tool calling supported
            ]
        case .claude:
            return [
                "claude-3-5-sonnet-20241022",  // ✅ Tool calling supported
                "claude-3-5-haiku-20241022",   // ✅ Tool calling supported
                "claude-3-opus-20240229",      // ✅ Tool calling supported
                "claude-3-sonnet-20240229",    // ✅ Tool calling supported
                "claude-3-haiku-20240307"      // ✅ Tool calling supported
            ]
        }
    }
    
    var defaultModel: String {
        switch self {
        case .openai:
            return "gpt-4o-mini"  // Default to a model with tool calling support
        case .claude:
            return "claude-3-5-haiku-20241022"  // Default to newest model with tool calling
        }
    }
    
    /// Check if the current model supports tool calling
    var supportsToolCalling: Bool {
        // All current models in availableModels support tool calling
        return availableModels.contains(where: { $0 == defaultModel })
    }
}

enum MaxTokensOption: Int, CaseIterable {
    case low = 500
    case medium = 1000
    case high = 2000
    case veryHigh = 4000
    
    var displayName: String {
        switch self {
        case .low:
            return "500 (Short)"
        case .medium:
            return "1000 (Medium)"
        case .high:
            return "2000 (Long)"
        case .veryHigh:
            return "4000 (Very Long)"
        }
    }
}

struct APIConfiguration: Codable {
    var provider: AIProvider
    var apiKey: String  // Not stored in UserDefaults - loaded from Keychain
    var model: String
    var maxTokens: Int
    var temperature: Double
    var enableMCP: Bool

    // Exclude apiKey from Codable to avoid storing in UserDefaults
    enum CodingKeys: String, CodingKey {
        case provider, model, maxTokens, temperature, enableMCP
    }

    init(provider: AIProvider = .openai, apiKey: String = "", model: String = "", maxTokens: Int = 1000, temperature: Double = 0.7, enableMCP: Bool = true) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model.isEmpty ? provider.defaultModel : model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.enableMCP = enableMCP
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(AIProvider.self, forKey: .provider)
        model = try container.decode(String.self, forKey: .model)
        maxTokens = try container.decode(Int.self, forKey: .maxTokens)
        temperature = try container.decode(Double.self, forKey: .temperature)
        enableMCP = try container.decode(Bool.self, forKey: .enableMCP)
        apiKey = "" // Will be loaded from Keychain separately
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(model, forKey: .model)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(enableMCP, forKey: .enableMCP)
        // apiKey is NOT encoded - stored in Keychain instead
    }
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date
    
    init(content: String, isUser: Bool) {
        self.id = UUID()
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
    }
}

struct SuggestedPrompt: Identifiable, Codable {
    let id: UUID
    let title: String
    let prompt: String
    let category: PromptCategory
    let icon: String
    
    init(title: String, prompt: String, category: PromptCategory, icon: String) {
        self.id = UUID()
        self.title = title
        self.prompt = prompt
        self.category = category
        self.icon = icon
    }
}

enum PromptCategory: String, CaseIterable, Codable {
    case calendar = "日程管理"
    case productivity = "工作效率"
    case creative = "创意写作"
    case analysis = "数据分析"
    case learning = "学习助手"

    var color: String {
        switch self {
        case .calendar: return "blue"
        case .productivity: return "green"
        case .creative: return "purple"
        case .analysis: return "orange"
        case .learning: return "red"
        }
    }

    var swiftColor: SwiftUI.Color {
        switch self {
        case .calendar: return .blue
        case .productivity: return .green
        case .creative: return .purple
        case .analysis: return .orange
        case .learning: return .red
        }
    }
}

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var apiConfiguration: APIConfiguration = APIConfiguration()
    @Published var streamingText: String = "" // Streaming response text

    @Published var reasonActSteps: [ReasonActStep] = []
    @Published var isReasonActMode: Bool = true
    @Published var showSuggestedPrompts: Bool = true
    @Published var suggestedPrompts: [SuggestedPrompt] = []

    // Progress tracking for user feedback
    @Published var currentStatus: ProcessingStatus = .idle
    @Published var processTracker = ProcessTracker()

    // Pending action confirmation (for delete/update operations)
    @Published var pendingActions: [PendingAction] = []
    @Published var showPendingActionSheet: Bool = false

    // Simple AI service (replaces complex orchestration)
    private let simpleAI = SimpleAIService()
    private let streamingService = StreamingService()
    private let userDefaults = UserDefaults.standard
    private let configKey = "APIConfiguration"

    // Persistence
    private var currentConversationID: UUID?
    private let persistence = PersistenceController.shared

    init() {
        loadConfiguration()
        loadPersistedConversation()
        setupSuggestedPrompts()
    }

    // MARK: - Conversation Persistence

    private func loadPersistedConversation() {
        if let (id, messages) = persistence.loadMostRecentConversation(), !messages.isEmpty {
            self.currentConversationID = id
            self.messages = messages
            self.showSuggestedPrompts = false
        } else {
            self.currentConversationID = persistence.createNewConversation()
        }
    }

    private func saveCurrentConversation() {
        guard let conversationID = currentConversationID else { return }
        persistence.saveConversation(id: conversationID, messages: messages)
    }

    func startNewConversation() {
        currentConversationID = persistence.createNewConversation()
        messages.removeAll()
        reasonActSteps.removeAll()
        showSuggestedPrompts = true
    }
    
    func saveConfiguration() {
        // Save non-sensitive config to UserDefaults
        if let encoded = try? JSONEncoder().encode(apiConfiguration) {
            userDefaults.set(encoded, forKey: configKey)
        }

        // Save API key to Keychain (secure storage)
        if !apiConfiguration.apiKey.isEmpty {
            try? KeychainManager.shared.saveAPIKey(
                apiConfiguration.apiKey,
                for: apiConfiguration.provider.rawValue
            )
        }
    }

    func loadConfiguration() {
        // Load non-sensitive config from UserDefaults
        if let data = userDefaults.data(forKey: configKey),
           let config = try? JSONDecoder().decode(APIConfiguration.self, from: data) {
            apiConfiguration = config

            // Load API key from Keychain (secure storage)
            if let apiKey = KeychainManager.shared.getAPIKey(for: config.provider.rawValue) {
                apiConfiguration.apiKey = apiKey
            }
        }
    }
    
    func sendMessage() async {
        guard !currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !apiConfiguration.apiKey.isEmpty else { return }

        let userMessage = ChatMessage(content: currentMessage, isUser: true)

        await MainActor.run {
            messages.append(userMessage)
            isLoading = true
            showSuggestedPrompts = false
            currentStatus = .loadingTools
            processTracker.reset()
            processTracker.currentPhase = .loadingTools
            saveCurrentConversation()
        }

        let messageToSend = currentMessage

        await MainActor.run {
            currentMessage = ""
        }

        do {
            // Simple AI service: message + tools → response (max 5 API calls)
            // Status callback updates UI with progress during tool execution
            let response = try await simpleAI.chat(
                message: messageToSend,
                history: messages.dropLast(), // Exclude the just-added user message
                config: apiConfiguration,
                onStatusUpdate: { [weak self] status in
                    Task { @MainActor in
                        self?.currentStatus = status
                    }
                },
                onProcessUpdate: { [weak self] update in
                    Task { @MainActor in
                        self?.handleProcessUpdate(update)
                    }
                },
                onPendingAction: { [weak self] action in
                    Task { @MainActor in
                        self?.pendingActions.append(action)
                        self?.showPendingActionSheet = true
                    }
                }
            )

            let aiMessage = ChatMessage(content: response, isUser: false)

            await MainActor.run {
                messages.append(aiMessage)
                isLoading = false
                currentStatus = .completed
                saveCurrentConversation()
            }

            // Reset status after brief delay
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await updateStatus(.idle)

        } catch {
            let errorMessage = ChatMessage(content: "Error: \(error.localizedDescription)", isUser: false)
            await MainActor.run {
                messages.append(errorMessage)
                isLoading = false
                currentStatus = .error(error.localizedDescription)
                saveCurrentConversation()
            }
        }
    }

    @MainActor
    private func updateStatus(_ status: ProcessingStatus) {
        currentStatus = status
    }

    @MainActor
    private func handleProcessUpdate(_ update: ProcessUpdate) {
        switch update {
        case .toolsLoaded(let tools):
            processTracker.setToolsLoaded(tools)
        case .iterationStarted(let number):
            processTracker.startIteration(number)
        case .toolCallStarted(let name, let isCalendar):
            processTracker.addToolCall(name: name, isCalendar: isCalendar)
        case .toolCallCompleted(let name, let success, let message):
            processTracker.completeToolCall(name: name, success: success, message: message)
        case .iterationCompleted:
            processTracker.completeIteration()
        case .completed:
            processTracker.setCompleted()
        case .error(let message):
            processTracker.setError(message)
        }
    }

    /// Send message with streaming response
    func sendMessageStreaming() {
        guard !currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !apiConfiguration.apiKey.isEmpty else { return }

        let userMessage = ChatMessage(content: currentMessage, isUser: true)
        messages.append(userMessage)
        isLoading = true
        streamingText = ""
        showSuggestedPrompts = false
        saveCurrentConversation()
        currentMessage = ""

        // Build messages array for API
        let apiMessages: [[String: Any]] = messages.map { msg in
            ["role": msg.isUser ? "user" : "assistant", "content": msg.content]
        }

        let onChunk: (String) -> Void = { [weak self] chunk in
            self?.streamingText += chunk
        }

        let onComplete: (Result<Void, Error>) -> Void = { [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success:
                if !self.streamingText.isEmpty {
                    let aiMessage = ChatMessage(content: self.streamingText, isUser: false)
                    self.messages.append(aiMessage)
                    self.saveCurrentConversation()
                }
            case .failure(let error):
                let errorMessage = ChatMessage(content: "Error: \(error.localizedDescription)", isUser: false)
                self.messages.append(errorMessage)
                self.saveCurrentConversation()
            }

            self.streamingText = ""
            self.isLoading = false
        }

        switch apiConfiguration.provider {
        case .openai:
            streamingService.streamOpenAI(
                messages: apiMessages,
                configuration: apiConfiguration,
                onChunk: onChunk,
                onComplete: onComplete
            )
        case .claude:
            streamingService.streamClaude(
                messages: apiMessages,
                configuration: apiConfiguration,
                onChunk: onChunk,
                onComplete: onComplete
            )
        }
    }

    /// Toggle between simple and reason-act modes
    func toggleReasonActMode() {
        isReasonActMode.toggle()
        reasonActSteps.removeAll()
    }
    
    /// Clear conversation and reset state (creates new conversation)
    func clearConversation() {
        startNewConversation()
    }
    
    /// Setup suggested prompts for first-time users
    private func setupSuggestedPrompts() {
        suggestedPrompts = [
            // Calendar Management
            SuggestedPrompt(
                title: "创建会议",
                prompt: "帮我安排明天下午2点的团队会议，主题是项目进展讨论，时长2小时",
                category: .calendar,
                icon: "calendar.badge.plus"
            ),
            SuggestedPrompt(
                title: "查看日程",
                prompt: "查看我本周的日程安排，告诉我有哪些重要的会议和任务",
                category: .calendar,
                icon: "calendar"
            ),
            SuggestedPrompt(
                title: "设置提醒",
                prompt: "提醒我每天上午9点开始工作，下午6点结束工作",
                category: .calendar,
                icon: "bell"
            ),
            
            // Productivity
            SuggestedPrompt(
                title: "任务规划",
                prompt: "帮我制定一个完成项目报告的详细计划，包括时间安排和具体步骤",
                category: .productivity,
                icon: "checklist"
            ),
            SuggestedPrompt(
                title: "时间管理",
                prompt: "分析我的工作习惯，给出提高效率的建议，特别是时间分配方面",
                category: .productivity,
                icon: "clock"
            ),
            SuggestedPrompt(
                title: "邮件模板",
                prompt: "帮我写一封专业的项目进展汇报邮件给客户，包含本月完成的工作和下月计划",
                category: .productivity,
                icon: "envelope"
            ),
            
            // Creative Writing
            SuggestedPrompt(
                title: "创意文案",
                prompt: "为我们公司的新产品写一份吸引人的营销文案，突出产品的创新特点",
                category: .creative,
                icon: "pencil.and.outline"
            ),
            SuggestedPrompt(
                title: "故事创作",
                prompt: "创作一个关于人工智能如何改变日常生活的短故事，要有趣且富有想象力",
                category: .creative,
                icon: "book"
            ),
            SuggestedPrompt(
                title: "演讲稿",
                prompt: "帮我准备一份关于团队合作重要性的5分钟演讲稿，包含实际案例",
                category: .creative,
                icon: "mic"
            ),
            
            // Data Analysis
            SuggestedPrompt(
                title: "数据解读",
                prompt: "分析用户反馈数据，找出产品改进的关键点和优先级",
                category: .analysis,
                icon: "chart.bar"
            ),
            SuggestedPrompt(
                title: "趋势分析",
                prompt: "基于市场数据分析当前行业趋势，预测未来6个月的发展方向",
                category: .analysis,
                icon: "chart.line.uptrend.xyaxis"
            ),
            SuggestedPrompt(
                title: "报告总结",
                prompt: "总结季度销售报告的关键指标，突出亮点和需要改进的地方",
                category: .analysis,
                icon: "doc.text"
            ),
            
            // Learning Assistant
            SuggestedPrompt(
                title: "知识解释",
                prompt: "用简单易懂的方式解释机器学习的基本概念，包含实际应用例子",
                category: .learning,
                icon: "brain.head.profile"
            ),
            SuggestedPrompt(
                title: "学习计划",
                prompt: "制定一个3个月的iOS开发学习计划，包括学习资源和里程碑",
                category: .learning,
                icon: "graduationcap"
            ),
            SuggestedPrompt(
                title: "技能提升",
                prompt: "推荐提高沟通技巧的方法和练习，适合职场环境",
                category: .learning,
                icon: "person.2"
            )
        ]
    }
    
    /// Select a suggested prompt
    func selectSuggestedPrompt(_ prompt: SuggestedPrompt) {
        currentMessage = prompt.prompt
        showSuggestedPrompts = false
    }
    
    /// Show/hide suggested prompts
    func toggleSuggestedPrompts() {
        showSuggestedPrompts.toggle()
    }
    
    /// Filter suggested prompts by category
    func promptsByCategory(_ category: PromptCategory) -> [SuggestedPrompt] {
        return suggestedPrompts.filter { $0.category == category }
    }
    
    /// Should show suggested prompts (only when no messages)
    var shouldShowSuggestedPrompts: Bool {
        return messages.isEmpty && showSuggestedPrompts
    }

    // MARK: - Pending Action Handling

    func confirmPendingActions() async {
        guard !pendingActions.isEmpty else { return }

        await MainActor.run {
            isLoading = true
        }

        var successResults: [String] = []
        var errorResults: [String] = []

        for action in pendingActions {
            await MainActor.run {
                currentStatus = .callingTool(action.toolName)
            }

            do {
                let result = try await simpleAI.executeConfirmedAction(action)
                if result.isError {
                    errorResults.append("\(action.title): \(result.message)")
                } else {
                    successResults.append("\(action.title): \(result.message)")
                }
            } catch {
                errorResults.append("\(action.title): \(error.localizedDescription)")
            }
        }

        // Build result message
        var resultText = ""
        if !successResults.isEmpty {
            resultText += "Completed:\n• " + successResults.joined(separator: "\n• ")
        }
        if !errorResults.isEmpty {
            if !resultText.isEmpty { resultText += "\n\n" }
            resultText += "Errors:\n• " + errorResults.joined(separator: "\n• ")
        }

        let resultMessage = ChatMessage(content: resultText, isUser: false)
        await MainActor.run {
            messages.append(resultMessage)
            isLoading = false
            currentStatus = .completed
            pendingActions.removeAll()
            showPendingActionSheet = false
            saveCurrentConversation()
        }
    }

    func cancelPendingActions() {
        let count = pendingActions.count
        let cancelMessage = ChatMessage(content: "\(count) action(s) cancelled.", isUser: false)
        messages.append(cancelMessage)
        pendingActions.removeAll()
        showPendingActionSheet = false
        isLoading = false
        currentStatus = .idle
        saveCurrentConversation()
    }

}

enum ChatError: LocalizedError {
    case orchestratorUnavailable
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .orchestratorUnavailable:
            return "Multi-role orchestrator is not available"
        case .invalidConfiguration:
            return "Invalid configuration"
        }
    }
}

// MARK: - Processing Status

enum ProcessingStatus: Equatable {
    case idle
    case loadingTools
    case thinkingStep(Int)
    case callingTool(String)
    case processingToolResult(String)
    case generatingResponse
    case completed
    case error(String)

    var displayText: String {
        switch self {
        case .idle:
            return ""
        case .loadingTools:
            return "Loading tools..."
        case .thinkingStep(let step):
            return "Thinking (Step \(step))..."
        case .callingTool(let toolName):
            return "Calling \(toolName)..."
        case .processingToolResult(let toolName):
            return "Processing \(toolName)..."
        case .generatingResponse:
            return "Generating response..."
        case .completed:
            return "Done"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var icon: String {
        switch self {
        case .idle:
            return ""
        case .loadingTools:
            return "wrench.and.screwdriver"
        case .thinkingStep:
            return "brain"
        case .callingTool:
            return "hammer"
        case .processingToolResult:
            return "gearshape"
        case .generatingResponse:
            return "text.bubble"
        case .completed:
            return "checkmark.circle"
        case .error:
            return "exclamationmark.triangle"
        }
    }

    var isActive: Bool {
        switch self {
        case .idle, .completed, .error:
            return false
        case .loadingTools, .thinkingStep, .callingTool, .processingToolResult, .generatingResponse:
            return true
        }
    }

    var stepNumber: Int? {
        guard case .thinkingStep(let step) = self else { return nil }
        return step
    }

    var isError: Bool {
        guard case .error = self else { return false }
        return true
    }
}

// MARK: - Process Tracker (Dynamic UI)

/// Tracks the entire processing workflow for dynamic UI display
class ProcessTracker: ObservableObject {
    @Published var iterations: [ProcessIteration] = []
    @Published var currentPhase: ProcessPhase = .idle
    @Published var toolsLoaded: [String] = []

    func reset() {
        iterations.removeAll()
        currentPhase = .idle
        toolsLoaded.removeAll()
    }

    func setToolsLoaded(_ tools: [String]) {
        toolsLoaded = tools
    }

    func startIteration(_ number: Int) {
        let iteration = ProcessIteration(number: number)
        iterations.append(iteration)
        currentPhase = .thinking
    }

    func addToolCall(name: String, isCalendar: Bool) {
        guard var last = iterations.last else { return }
        let toolCall = ToolCallRecord(name: name, isCalendar: isCalendar)
        last.toolCalls.append(toolCall)
        iterations[iterations.count - 1] = last
        currentPhase = .callingTool(name)
    }

    func completeToolCall(name: String, success: Bool, message: String) {
        guard var last = iterations.last,
              let idx = last.toolCalls.lastIndex(where: { $0.name == name && $0.status == .running }) else { return }
        last.toolCalls[idx].status = success ? .success : .failed
        last.toolCalls[idx].resultPreview = String(message.prefix(100))
        last.toolCalls[idx].endTime = Date()
        iterations[iterations.count - 1] = last
        currentPhase = .processingResult(name)
    }

    func completeIteration() {
        guard var last = iterations.last else { return }
        last.endTime = Date()
        iterations[iterations.count - 1] = last
    }

    func setCompleted() {
        currentPhase = .completed
    }

    func setError(_ message: String) {
        currentPhase = .error(message)
    }
}

enum ProcessPhase: Equatable {
    case idle
    case loadingTools
    case thinking
    case callingTool(String)
    case processingResult(String)
    case completed
    case error(String)
}

struct ProcessIteration: Identifiable {
    let id = UUID()
    let number: Int
    var toolCalls: [ToolCallRecord] = []
    let startTime = Date()
    var endTime: Date?

    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }
}

struct ToolCallRecord: Identifiable {
    let id = UUID()
    let name: String
    let isCalendar: Bool
    var status: ToolCallStatus = .running
    var resultPreview: String = ""
    let startTime = Date()
    var endTime: Date?

    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }

    var icon: String {
        isCalendar ? "calendar" : "checkmark.circle"
    }

    var statusIcon: String {
        switch status {
        case .running: return "arrow.trianglehead.2.clockwise"
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var statusColor: Color {
        switch status {
        case .running: return .blue
        case .success: return .green
        case .failed: return .red
        }
    }
}

enum ToolCallStatus {
    case running
    case success
    case failed
}

// MARK: - Process Update Events (for SimpleAIService callbacks)

enum ProcessUpdate {
    case toolsLoaded([String])
    case iterationStarted(Int)
    case toolCallStarted(name: String, isCalendar: Bool)
    case toolCallCompleted(name: String, success: Bool, message: String)
    case iterationCompleted
    case completed
    case error(String)
}

// MARK: - Pending Action (Confirmation for delete/update)

struct PendingAction: Identifiable {
    let id = UUID()
    let type: PendingActionType
    let toolName: String
    let arguments: [String: Any]
    let title: String
    let details: String
    let isCalendar: Bool

    var icon: String {
        switch type {
        case .delete: return "trash"
        case .update: return "pencil"
        case .complete: return "checkmark.circle"
        }
    }

    var color: Color {
        switch type {
        case .delete: return .red
        case .update: return .orange
        case .complete: return .green
        }
    }

    var actionText: String {
        switch type {
        case .delete: return "Delete"
        case .update: return "Update"
        case .complete: return "Complete"
        }
    }
}

enum PendingActionType {
    case delete
    case update
    case complete
}