import Foundation

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
    var apiKey: String
    var model: String
    var maxTokens: Int
    var temperature: Double
    var enableMCP: Bool
    
    init(provider: AIProvider = .openai, apiKey: String = "", model: String = "", maxTokens: Int = 1000, temperature: Double = 0.7, enableMCP: Bool = true) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model.isEmpty ? provider.defaultModel : model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.enableMCP = enableMCP
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
}

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var apiConfiguration: APIConfiguration = APIConfiguration()
    @Published var showMCPDetails: Bool = false
    @Published var useUnifiedAgent: Bool = true
    @Published var useMultiRole: Bool = false // New: Toggle for multi-role conversation
    @Published var streamingText: String = "" // Streaming response text

    @Published var reasonActSteps: [ReasonActStep] = []
    @Published var isReasonActMode: Bool = true
    @Published var showSuggestedPrompts: Bool = true
    @Published var suggestedPrompts: [SuggestedPrompt] = []

    // Progress tracking for user feedback
    @Published var currentStatus: ProcessingStatus = .idle
    @Published var currentStepNumber: Int = 0
    @Published var currentToolName: String = ""
    @Published var availableToolsCount: Int = 0

    private let aiService = AIService()
    private let mcpAIService = MCPAIService()
    private let streamingService = StreamingService()
    @Published var unifiedChatAgent = UnifiedChatAgent()
    @Published var multiRoleOrchestrator: MultiRoleOrchestrator? // New: Multi-role orchestrator
    private let userDefaults = UserDefaults.standard
    private let configKey = "APIConfiguration"

    // Persistence
    private var currentConversationID: UUID?
    private let persistence = PersistenceController.shared
    
    var mcpManager: MCPManager {
        return mcpAIService.mcpManager
    }
    
    init() {
        loadConfiguration()
        loadPersistedConversation()
        setupUnifiedAgent()
        setupMultiRoleOrchestrator()
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
        unifiedChatAgent.clearConversation()
        showSuggestedPrompts = true
    }
    
    private func setupUnifiedAgent() {
        // Configure tool handler for unified agent
        // Parameters: (toolCallId, toolName, arguments) -> ToolResult
        unifiedChatAgent.toolHandler = { [weak self] toolCallId, toolName, arguments in
            guard let self = self else {
                return UniMsg.ToolResult(toolCallId: toolCallId, content: "Service unavailable", isError: true)
            }

            // Execute tool via MCP manager
            do {
                let mcpResult = try await self.mcpManager.executeToolCall(toolName: toolName, arguments: arguments)
                return UniMsg.ToolResult(
                    toolCallId: toolCallId,
                    content: mcpResult.message,
                    isError: mcpResult.isError
                )
            } catch {
                return UniMsg.ToolResult(
                    toolCallId: toolCallId,
                    content: "Tool execution failed: \(error.localizedDescription)",
                    isError: true
                )
            }
        }
    }
    
    private func setupMultiRoleOrchestrator() {
        let mcpManager = mcpAIService.mcpManager
        
        multiRoleOrchestrator = MultiRoleOrchestrator(
            aiService: aiService,
            mcpManager: mcpManager,
            configuration: apiConfiguration,
            maxIterations: 8
        )
    }
    
    func saveConfiguration() {
        if let encoded = try? JSONEncoder().encode(apiConfiguration) {
            userDefaults.set(encoded, forKey: configKey)
        }
    }
    
    func loadConfiguration() {
        if let data = userDefaults.data(forKey: configKey),
           let config = try? JSONDecoder().decode(APIConfiguration.self, from: data) {
            apiConfiguration = config
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
            currentStepNumber = 0
            currentToolName = ""
            saveCurrentConversation()
        }

        let messageToSend = currentMessage

        await MainActor.run {
            currentMessage = ""
        }

        do {
            let response: String

            if useMultiRole && apiConfiguration.enableMCP {
                // Use multi-role conversation system
                guard let orchestrator = multiRoleOrchestrator else {
                    throw ChatError.orchestratorUnavailable
                }

                await orchestrator.startConversation(goal: messageToSend)

                // Extract final response from orchestrator state
                if let lastMessage = orchestrator.state.messages.last {
                    response = lastMessage
                } else {
                    response = "Multi-role conversation completed but no final response was generated."
                }

            } else if useUnifiedAgent && apiConfiguration.enableMCP {
                // Use unified chat agent with MCP tools
                await updateStatus(.loadingTools)
                let availableTools = await getAvailableTools()
                await MainActor.run { self.availableToolsCount = availableTools.count }

                let uniResponse: UniMsg

                // Clear previous steps when starting new request
                await MainActor.run { self.reasonActSteps.removeAll() }

                if isReasonActMode {
                    // Use Reason-Act orchestrator with status callbacks
                    let (finalResponse, steps) = try await unifiedChatAgent.processWithOrchestrator(
                        messageToSend,
                        configuration: apiConfiguration,
                        availableTools: availableTools,
                        maxSteps: 6,
                        onStatusUpdate: { [weak self] status in
                            Task { @MainActor in
                                self?.currentStatus = status
                                if case .thinkingStep(let step) = status {
                                    self?.currentStepNumber = step
                                }
                                if case .callingTool(let tool) = status {
                                    self?.currentToolName = tool
                                }
                            }
                        },
                        onStepComplete: { [weak self] step in
                            Task { @MainActor in
                                self?.reasonActSteps.append(step)
                            }
                        }
                    )

                    uniResponse = finalResponse
                } else {
                    // Use single-step mode
                    await updateStatus(.generatingResponse)
                    uniResponse = try await unifiedChatAgent.sendMessage(messageToSend, configuration: apiConfiguration, availableTools: availableTools)
                }
                response = uniResponse.textContent

            } else if apiConfiguration.enableMCP {
                // Use original MCP system
                await updateStatus(.generatingResponse)
                let recentHistory = messages.suffix(5).map { $0.content }
                response = try await mcpAIService.sendMessage(messageToSend, conversationHistory: Array(recentHistory), configuration: apiConfiguration)

            } else {
                // Use basic AI service
                await updateStatus(.generatingResponse)
                response = try await aiService.sendMessage(messageToSend, configuration: apiConfiguration)
            }

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

        let messageToSend = currentMessage
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

    /// Get available MCP tools as unified tool descriptors
    private func getAvailableTools() async -> [UniTool] {
        var tools: [UniTool] = []
        var toolNames: Set<String> = []
        
        // Get tools from MCP servers first (they have priority)
        for (serverName, server) in mcpManager.availableServers {
            do {
                let mcpTools = try await server.listTools()
                for mcpTool in mcpTools {
                    // Skip if tool name already exists
                    if toolNames.contains(mcpTool.name) {
                        continue
                    }
                    
                    let uniTool = UniTool(
                        name: mcpTool.name,
                        description: mcpTool.description,
                        parameters: UniTool.ToolParameters(
                            properties: convertMCPParameters(mcpTool.parameters),
                            required: mcpTool.parameters.filter { $0.required }.map { $0.name }
                        ),
                        metadata: ["server": serverName]
                    )
                    tools.append(uniTool)
                    toolNames.insert(mcpTool.name)
                }
            } catch {
                // Continue if server fails to list tools
                continue
            }
        }
        
        // Add fallback calendar tool if not provided by MCP servers
        if mcpManager.isCalendarEnabled && !toolNames.contains("create_event") {
            let calendarTool = UniTool.createEventTool()
            tools.append(calendarTool)
            toolNames.insert(calendarTool.name)
        }
        
        // Add search tool if not already present
        if !toolNames.contains("search") {
            let searchTool = UniTool.searchTool()
            tools.append(searchTool)
            toolNames.insert(searchTool.name)
        }
        
        return tools
    }
    
    /// Convert MCP tool parameters to unified format
    private func convertMCPParameters(_ mcpParams: [MCPParameter]) -> [String: UniTool.ParameterProperty] {
        var properties: [String: UniTool.ParameterProperty] = [:]
        
        for param in mcpParams {
            properties[param.name] = UniTool.ParameterProperty(
                type: param.type,
                description: param.description
            )
        }
        
        return properties
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
    
    /// Clean final response marker from text for UI display
    func cleanedMessageContent(_ content: String) -> String {
        return content.replacingOccurrences(of: "<|FINAL_RESPONSE|>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Toggle multi-role conversation mode
    func toggleMultiRoleMode() {
        useMultiRole.toggle()
        if useMultiRole {
            useUnifiedAgent = false // Disable unified agent when using multi-role
        }
    }
    
    /// Toggle unified agent mode
    func toggleUnifiedAgent() {
        useUnifiedAgent.toggle()
        if useUnifiedAgent {
            useMultiRole = false // Disable multi-role when using unified agent
        }
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
            return "Loading available tools..."
        case .thinkingStep(let step):
            return "Thinking (Step \(step))..."
        case .callingTool(let toolName):
            return "Calling \(toolName)..."
        case .processingToolResult(let toolName):
            return "Processing \(toolName) result..."
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
        default:
            return true
        }
    }
}