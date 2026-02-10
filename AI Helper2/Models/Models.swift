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
                "gpt-5",               // ✅ Latest flagship, tool calling supported
                "gpt-5-mini",          // ✅ Fast + intelligent, tool calling supported
                "gpt-5-nano",          // ✅ Most cost-efficient, tool calling supported
                "o3",                  // ✅ Reasoning model, tool calling supported
                "o4-mini",             // ✅ Reasoning model, tool calling supported
                "gpt-4.1",            // ✅ Previous gen flagship, tool calling supported
                "gpt-4.1-mini",       // ✅ Tool calling supported
                "gpt-4o",             // ✅ Tool calling supported
            ]
        case .claude:
            return [
                "claude-opus-4-6",             // ✅ Most intelligent, tool calling supported
                "claude-sonnet-4-5",           // ✅ Best speed + intelligence, tool calling supported
                "claude-haiku-4-5",            // ✅ Fastest, tool calling supported
                "claude-3-5-sonnet-20241022",  // ✅ Tool calling supported
            ]
        }
    }
    
    var defaultModel: String {
        switch self {
        case .openai:
            return "gpt-5-mini"  // Default to a model with tool calling support
        case .claude:
            return "claude-haiku-4-5"  // Default to newest fast model with tool calling
        }
    }
    
    /// Check if the current model supports tool calling
    var supportsToolCalling: Bool {
        // All current models in availableModels support tool calling
        return availableModels.contains(where: { $0 == defaultModel })
    }

    /// OpenAI reasoning models use different parameters
    static func isReasoningModel(_ model: String) -> Bool {
        model.hasPrefix("o3") || model.hasPrefix("o4") || model.hasPrefix("o1")
    }
}

enum SystemPersona: String, CaseIterable, Codable {
    case professional = "Professional"
    case casual = "Casual"
    case technical = "Technical"
    case custom = "Custom"

    var displayName: String { rawValue }

    var icon: String {
        switch self {
        case .professional: return "briefcase"
        case .casual: return "face.smiling"
        case .technical: return "wrench.and.screwdriver"
        case .custom: return "pencil"
        }
    }

    /// The persona instruction prepended to the system prompt
    var promptPrefix: String {
        switch self {
        case .professional:
            return "You are a professional, concise, and business-oriented assistant. Use formal language, provide structured responses, and focus on actionable insights."
        case .casual:
            return "You are a friendly and approachable assistant. Use conversational language, be warm and encouraging, and explain things in simple terms."
        case .technical:
            return "You are a technical expert assistant. Provide detailed, precise answers with technical depth. Include relevant technical terminology and implementation details when appropriate."
        case .custom:
            return "" // Uses customSystemPrompt instead
        }
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
    var systemPersona: SystemPersona
    var customSystemPrompt: String

    // Exclude apiKey from Codable to avoid storing in UserDefaults
    enum CodingKeys: String, CodingKey {
        case provider, model, maxTokens, temperature, enableMCP, systemPersona, customSystemPrompt
    }

    init(provider: AIProvider = .openai, apiKey: String = "", model: String = "", maxTokens: Int = 1000, temperature: Double = 0.7, enableMCP: Bool = true, systemPersona: SystemPersona = .professional, customSystemPrompt: String = "") {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model.isEmpty ? provider.defaultModel : model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.enableMCP = enableMCP
        self.systemPersona = systemPersona
        self.customSystemPrompt = customSystemPrompt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        provider = try container.decode(AIProvider.self, forKey: .provider)
        model = try container.decode(String.self, forKey: .model)
        maxTokens = try container.decode(Int.self, forKey: .maxTokens)
        temperature = try container.decode(Double.self, forKey: .temperature)
        enableMCP = try container.decode(Bool.self, forKey: .enableMCP)
        systemPersona = try container.decodeIfPresent(SystemPersona.self, forKey: .systemPersona) ?? .professional
        customSystemPrompt = try container.decodeIfPresent(String.self, forKey: .customSystemPrompt) ?? ""
        apiKey = "" // Will be loaded from Keychain separately
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(provider, forKey: .provider)
        try container.encode(model, forKey: .model)
        try container.encode(maxTokens, forKey: .maxTokens)
        try container.encode(temperature, forKey: .temperature)
        try container.encode(enableMCP, forKey: .enableMCP)
        try container.encode(systemPersona, forKey: .systemPersona)
        try container.encode(customSystemPrompt, forKey: .customSystemPrompt)
        // apiKey is NOT encoded - stored in Keychain instead
    }
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date
    var errorType: ChatMessageError?
    /// The original user prompt that triggered this error (for retry)
    var failedPrompt: String?

    init(content: String, isUser: Bool) {
        self.id = UUID()
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
    }

    init(content: String, isUser: Bool, errorType: ChatMessageError, failedPrompt: String) {
        self.id = UUID()
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
        self.errorType = errorType
        self.failedPrompt = failedPrompt
    }

    var isError: Bool { errorType != nil }
}

enum ChatMessageError: String, Codable {
    case network
    case authentication
    case rateLimit
    case serverError
    case unknown

    var guidance: String {
        switch self {
        case .network:
            return "Check your internet connection and try again."
        case .authentication:
            return "Your API key may be invalid. Check Settings."
        case .rateLimit:
            return "Rate limit reached. Wait a moment and retry."
        case .serverError:
            return "The AI service is experiencing issues. Try again later."
        case .unknown:
            return "An unexpected error occurred. Try again."
        }
    }

    var icon: String {
        switch self {
        case .network: return "wifi.slash"
        case .authentication: return "key.slash"
        case .rateLimit: return "clock.badge.exclamationmark"
        case .serverError: return "server.rack"
        case .unknown: return "exclamationmark.triangle"
        }
    }

    static func classify(_ error: Error) -> ChatMessageError {
        let desc = error.localizedDescription.lowercased()
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost:
                return .network
            default:
                break
            }
        }
        if desc.contains("401") || desc.contains("unauthorized") || desc.contains("invalid api key") || desc.contains("authentication") {
            return .authentication
        }
        if desc.contains("429") || desc.contains("rate limit") || desc.contains("too many requests") {
            return .rateLimit
        }
        if desc.contains("500") || desc.contains("502") || desc.contains("503") || desc.contains("server") {
            return .serverError
        }
        if desc.contains("network") || desc.contains("connection") || desc.contains("timeout") {
            return .network
        }
        return .unknown
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
    case calendar = "Calendar"
    case productivity = "Productivity"
    case creative = "Creative Writing"
    case analysis = "Data Analysis"
    case learning = "Learning"

    var swiftColor: SwiftUI.Color {
        switch self {
        case .calendar: return DS.Colors.accent
        case .productivity: return DS.Colors.success
        case .creative: return .purple
        case .analysis: return DS.Colors.warning
        case .learning: return DS.Colors.error
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
        // Save config to Keychain (persists across reinstalls)
        if let encoded = try? JSONEncoder().encode(apiConfiguration) {
            try? KeychainManager.shared.saveData(encoded, for: configKey)
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
        // Load config from Keychain (persists across reinstalls)
        if let data = KeychainManager.shared.getData(for: configKey),
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
            HapticManager.send()
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
                HapticManager.receive()
                saveCurrentConversation()
            }

            // Reset status after brief delay
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            await updateStatus(.idle)

        } catch {
            let classified = ChatMessageError.classify(error)
            let errorMessage = ChatMessage(
                content: error.localizedDescription,
                isUser: false,
                errorType: classified,
                failedPrompt: messageToSend
            )
            await MainActor.run {
                messages.append(errorMessage)
                isLoading = false
                currentStatus = .error(error.localizedDescription)
                HapticManager.error()
                saveCurrentConversation()
            }
        }
    }

    /// Retry sending a failed message
    func retryMessage(_ message: ChatMessage) async {
        guard let prompt = message.failedPrompt else { return }

        // Remove the error message
        await MainActor.run {
            messages.removeAll { $0.id == message.id }
        }

        // Re-send
        await MainActor.run {
            currentMessage = prompt
        }
        await sendMessage()
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
                title: "Create Meeting",
                prompt: "Schedule a team meeting tomorrow at 2 PM to discuss project progress, duration 2 hours",
                category: .calendar,
                icon: "calendar.badge.plus"
            ),
            SuggestedPrompt(
                title: "View Schedule",
                prompt: "Show my schedule for this week and highlight important meetings and tasks",
                category: .calendar,
                icon: "calendar"
            ),
            SuggestedPrompt(
                title: "Set Reminder",
                prompt: "Remind me to start work at 9 AM and finish at 6 PM every day",
                category: .calendar,
                icon: "bell"
            ),

            // Productivity
            SuggestedPrompt(
                title: "Task Planning",
                prompt: "Help me create a detailed plan to complete a project report, including timeline and steps",
                category: .productivity,
                icon: "checklist"
            ),
            SuggestedPrompt(
                title: "Time Management",
                prompt: "Analyze my work habits and suggest ways to improve efficiency, especially time allocation",
                category: .productivity,
                icon: "clock"
            ),
            SuggestedPrompt(
                title: "Email Template",
                prompt: "Write a professional project progress email to a client covering this month's work and next month's plan",
                category: .productivity,
                icon: "envelope"
            ),

            // Creative Writing
            SuggestedPrompt(
                title: "Marketing Copy",
                prompt: "Write compelling marketing copy for our new product, highlighting its innovative features",
                category: .creative,
                icon: "pencil.and.outline"
            ),
            SuggestedPrompt(
                title: "Story Writing",
                prompt: "Write a short story about how AI is changing everyday life, make it fun and imaginative",
                category: .creative,
                icon: "book"
            ),
            SuggestedPrompt(
                title: "Speech Draft",
                prompt: "Prepare a 5-minute speech on the importance of teamwork, with real-world examples",
                category: .creative,
                icon: "mic"
            ),

            // Data Analysis
            SuggestedPrompt(
                title: "Data Insights",
                prompt: "Analyze user feedback data and identify key areas for product improvement and priorities",
                category: .analysis,
                icon: "chart.bar"
            ),
            SuggestedPrompt(
                title: "Trend Analysis",
                prompt: "Analyze current industry trends from market data and forecast the next 6 months",
                category: .analysis,
                icon: "chart.line.uptrend.xyaxis"
            ),
            SuggestedPrompt(
                title: "Report Summary",
                prompt: "Summarize the quarterly sales report's key metrics, highlighting strengths and areas to improve",
                category: .analysis,
                icon: "doc.text"
            ),

            // Learning Assistant
            SuggestedPrompt(
                title: "Explain Concepts",
                prompt: "Explain the basics of machine learning in simple terms, with practical examples",
                category: .learning,
                icon: "brain.head.profile"
            ),
            SuggestedPrompt(
                title: "Learning Plan",
                prompt: "Create a 3-month iOS development learning plan with resources and milestones",
                category: .learning,
                icon: "graduationcap"
            ),
            SuggestedPrompt(
                title: "Skill Building",
                prompt: "Recommend methods and exercises to improve communication skills in the workplace",
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

