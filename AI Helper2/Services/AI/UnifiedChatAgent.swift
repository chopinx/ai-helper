import Foundation
import os.log

// MARK: - Constants

/// Special marker to indicate final response to user (not displayed in UI)
private let FINAL_RESPONSE_MARKER = "<|FINAL_RESPONSE|>"

// MARK: - Unified Chat Agent

/// Cross-provider chat agent that can talk to OpenAI or Claude APIs
/// Supports multi-step Reason-Act loops with context management
class UnifiedChatAgent: ObservableObject {
    @Published private(set) var conversation = UnifiedConversation()
    @Published private(set) var isProcessing = false
    @Published private(set) var currentProvider: AIProvider = .openai
    
    private let logger = Logger(subsystem: "com.aihelper.unified", category: "UnifiedChatAgent")
    private let openAIConverter = OpenAIConverter()
    private let claudeConverter = ClaudeConverter()
    private let contextManager = ContextManager()
    
    // Tool execution handler
    var toolHandler: ((String, [String: Any]) async throws -> UniMsg.ToolResult)?
    
    init() {
        logger.info("🤖 UnifiedChatAgent initialized")
    }
    
    /// Multi-step orchestrator with Reason-Act loop
    func processWithOrchestrator(_ message: String, configuration: APIConfiguration, availableTools: [UniTool] = [], maxSteps: Int = 6) async throws -> (UniMsg, [ReasonActStep]) {
        let orchestrator = ReasonActOrchestrator(
            contextManager: contextManager,
            toolHandler: toolHandler,
            openAIConverter: openAIConverter,
            claudeConverter: claudeConverter
        )
        
        return try await orchestrator.process(message: message, configuration: configuration, availableTools: availableTools, maxSteps: maxSteps)
    }
    
    /// Send a message and get response from configured AI provider
    /// Legacy single-step method - kept for backward compatibility
    @available(*, deprecated, message: "Use processWithOrchestrator for multi-step capabilities")
    func sendMessage(_ message: String, configuration: APIConfiguration, availableTools: [UniTool] = []) async throws -> UniMsg {
        logger.info("🚀 UNIFIED: Sending message to \(configuration.provider.rawValue)")
        logger.debug("📝 Message: \(message)")
        logger.debug("🛠️ Available tools: \(availableTools.count)")
        
        await MainActor.run {
            self.isProcessing = true
            self.currentProvider = configuration.provider
        }
        
        // Add user message to conversation
        conversation.addUserMessage(message, metadata: ["provider": configuration.provider.rawValue])
        conversation.setAvailableTools(availableTools)
        
        do {
            let response = try await processWithProvider(configuration: configuration)
            
            await MainActor.run {
                self.isProcessing = false
            }
            
            logger.info("✅ UNIFIED: Message processed successfully")
            return response
            
        } catch {
            await MainActor.run {
                self.isProcessing = false
            }
            
            logger.error("❌ UNIFIED: Message processing failed - \(error.localizedDescription)")
            
            // Add error response to conversation
            let errorMessage = UniMsg(
                role: .assistant,
                text: "Sorry, I encountered an error: \(error.localizedDescription)",
                metadata: ["error": "true", "provider": configuration.provider.rawValue]
            )
            conversation.addMessage(errorMessage)
            
            throw error
        }
    }
    
    /// Get conversation history
    func getConversationHistory(includeToolResults: Bool = true) -> [UniMsg] {
        return conversation.getRecentMessages(count: 50, includeToolResults: includeToolResults)
    }
    
    /// Clear conversation history
    func clearConversation() {
        conversation.clear()
        logger.info("🗑️ UNIFIED: Conversation cleared")
    }
    
    /// Get conversation statistics
    func getStatistics() -> ConversationStatistics {
        return conversation.statistics
    }
    
    // MARK: - Private Methods
    
    private func processWithProvider(configuration: APIConfiguration) async throws -> UniMsg {
        let recentMessages = conversation.getRecentMessages(count: 20, includeToolResults: true)
        let availableTools = conversation.availableTools
        
        switch configuration.provider {
        case .openai:
            return try await processWithOpenAI(messages: recentMessages, tools: availableTools, configuration: configuration)
        case .claude:
            return try await processWithClaude(messages: recentMessages, tools: availableTools, configuration: configuration)
        }
    }
    
    private func processWithOpenAI(messages: [UniMsg], tools: [UniTool], configuration: APIConfiguration) async throws -> UniMsg {
        logger.info("🔵 UNIFIED: Processing with OpenAI")
        
        let request = openAIConverter.convertToRequest(messages: messages, tools: tools, configuration: configuration)
        
        // Make API call
        let response = try await makeOpenAIRequest(request: request, configuration: configuration)
        let responseMessage = openAIConverter.convertFromResponse(response)
        
        // Add response to conversation
        conversation.addMessage(responseMessage)
        
        // Handle tool calls if present
        let toolCalls = openAIConverter.extractToolCalls(from: response)
        if !toolCalls.isEmpty {
            try await executeToolCalls(toolCalls, configuration: configuration)
        }
        
        return responseMessage
    }
    
    private func processWithClaude(messages: [UniMsg], tools: [UniTool], configuration: APIConfiguration) async throws -> UniMsg {
        logger.info("🟡 UNIFIED: Processing with Claude")
        
        let request = claudeConverter.convertToRequest(messages: messages, tools: tools, configuration: configuration)
        
        // Make API call
        let response = try await makeClaudeRequest(request: request, configuration: configuration)
        let responseMessage = claudeConverter.convertFromResponse(response)
        
        // Add response to conversation
        conversation.addMessage(responseMessage)
        
        // Handle tool calls if present
        let toolCalls = claudeConverter.extractToolCalls(from: response)
        if !toolCalls.isEmpty {
            try await executeToolCalls(toolCalls, configuration: configuration)
        }
        
        return responseMessage
    }
    
    private func executeToolCalls(_ toolCalls: [UniMsg.ToolCall], configuration: APIConfiguration) async throws {
        logger.info("🔧 UNIFIED: Executing \(toolCalls.count) tool calls")
        
        var toolResults: [UniMsg.ToolResult] = []
        
        for toolCall in toolCalls {
            logger.debug("🛠️ Executing tool: \(toolCall.name) with args: \(toolCall.arguments)")
            
            do {
                if let toolHandler = toolHandler {
                    let result = try await toolHandler(toolCall.name, toolCall.arguments)
                    toolResults.append(result)
                    logger.debug("✅ Tool call successful: \(toolCall.name)")
                } else {
                    let errorResult = UniMsg.ToolResult(
                        toolCallId: toolCall.id,
                        content: "Tool handler not configured",
                        isError: true
                    )
                    toolResults.append(errorResult)
                    logger.warning("⚠️ No tool handler configured for: \(toolCall.name)")
                }
            } catch {
                let errorResult = UniMsg.ToolResult(
                    toolCallId: toolCall.id,
                    content: "Tool execution failed: \(error.localizedDescription)",
                    isError: true
                )
                toolResults.append(errorResult)
                logger.error("❌ Tool call failed: \(toolCall.name) - \(error.localizedDescription)")
            }
        }
        
        // Add tool results to conversation
        if !toolResults.isEmpty {
            conversation.addToolResults(toolResults)
            
            // Continue conversation with tool results
            let followUpResponse = try await processWithProvider(configuration: configuration)
            logger.info("🔄 UNIFIED: Follow-up response after tool execution completed")
        }
    }
    
    // MARK: - API Calls
    
    private func makeOpenAIRequest(request: OpenAIRequest, configuration: APIConfiguration) async throws -> OpenAIResponse {
        let url = URL(string: "\(configuration.provider.baseURL)/chat/completions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        
        let encoder = JSONEncoder()
        // Custom encoding for OpenAI request
        let requestData = try encodeOpenAIRequest(request)
        urlRequest.httpBody = requestData
        
        logger.debug("📤 UNIFIED: Sending OpenAI request")
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UnifiedChatError.invalidResponse("Invalid HTTP response")
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw UnifiedChatError.apiError("OpenAI API error (\(httpResponse.statusCode)): \(errorMessage)")
        }
        
        logger.debug("📥 UNIFIED: Received OpenAI response")
        
        let decoder = JSONDecoder()
        return try decoder.decode(OpenAIResponse.self, from: data)
    }
    
    private func makeClaudeRequest(request: ClaudeRequest, configuration: APIConfiguration) async throws -> ClaudeResponse {
        let url = URL(string: "\(configuration.provider.baseURL)/messages")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let encoder = JSONEncoder()
        // Custom encoding for Claude request
        let requestData = try encodeClaudeRequest(request)
        urlRequest.httpBody = requestData
        
        logger.debug("📤 UNIFIED: Sending Claude request")
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UnifiedChatError.invalidResponse("Invalid HTTP response")
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw UnifiedChatError.apiError("Claude API error (\(httpResponse.statusCode)): \(errorMessage)")
        }
        
        logger.debug("📥 UNIFIED: Received Claude response")
        
        let decoder = JSONDecoder()
        return try decoder.decode(ClaudeResponse.self, from: data)
    }
    
    // MARK: - Custom Encoding Helpers
    
    private func encodeOpenAIRequest(_ request: OpenAIRequest) throws -> Data {
        var requestDict: [String: Any] = [
            "model": request.model,
            "messages": try encodeOpenAIMessages(request.messages),
            "max_tokens": request.max_tokens,
            "temperature": request.temperature
        ]
        
        if let tools = request.tools {
            requestDict["tools"] = try encodeOpenAITools(tools)
        }
        
        if let toolChoice = request.tool_choice {
            requestDict["tool_choice"] = toolChoice
        }
        
        return try JSONSerialization.data(withJSONObject: requestDict)
    }
    
    private func encodeOpenAIMessages(_ messages: [OpenAIMessage]) throws -> [[String: Any]] {
        return messages.map { message in
            var messageDict: [String: Any] = ["role": message.role]
            
            if let content = message.content {
                messageDict["content"] = content
            }
            
            if let toolCalls = message.tool_calls {
                messageDict["tool_calls"] = toolCalls.map { toolCall in
                    [
                        "id": toolCall.id,
                        "type": toolCall.type,
                        "function": [
                            "name": toolCall.function.name,
                            "arguments": toolCall.function.arguments
                        ]
                    ]
                }
            }
            
            if let toolCallId = message.tool_call_id {
                messageDict["tool_call_id"] = toolCallId
            }
            
            return messageDict
        }
    }
    
    private func encodeOpenAITools(_ tools: [OpenAITool]) throws -> [[String: Any]] {
        return tools.map { tool in
            [
                "type": tool.type,
                "function": [
                    "name": tool.function.name,
                    "description": tool.function.description,
                    "parameters": tool.function.parameters
                ]
            ]
        }
    }
    
    private func encodeClaudeRequest(_ request: ClaudeRequest) throws -> Data {
        var requestDict: [String: Any] = [
            "model": request.model,
            "max_tokens": request.max_tokens,
            "temperature": request.temperature,
            "messages": try encodeClaudeMessages(request.messages)
        ]
        
        if let tools = request.tools {
            requestDict["tools"] = try encodeClaudeTools(tools)
        }
        
        return try JSONSerialization.data(withJSONObject: requestDict)
    }
    
    private func encodeClaudeMessages(_ messages: [ClaudeMessage]) throws -> [[String: Any]] {
        return messages.map { message in
            [
                "role": message.role,
                "content": message.content.map { content in
                    var contentDict: [String: Any] = ["type": content.type]
                    
                    if let text = content.text {
                        contentDict["text"] = text
                    }
                    
                    if let toolUse = content.tool_use {
                        contentDict["id"] = toolUse.id
                        contentDict["name"] = toolUse.name
                        contentDict["input"] = toolUse.input
                    }
                    
                    if let toolUseId = content.tool_use_id {
                        contentDict["tool_use_id"] = toolUseId
                    }
                    
                    if let resultContent = content.content {
                        contentDict["content"] = resultContent
                    }
                    
                    if let isError = content.is_error {
                        contentDict["is_error"] = isError
                    }
                    
                    return contentDict
                }
            ]
        }
    }
    
    private func encodeClaudeTools(_ tools: [ClaudeTool]) throws -> [[String: Any]] {
        return tools.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.input_schema
            ]
        }
    }
}

// MARK: - Error Types

enum UnifiedChatError: Error, LocalizedError {
    case invalidConfiguration(String)
    case invalidResponse(String)
    case apiError(String)
    case toolExecutionError(String)
    case encodingError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .apiError(let message):
            return "API error: \(message)"
        case .toolExecutionError(let message):
            return "Tool execution error: \(message)"
        case .encodingError(let message):
            return "Encoding error: \(message)"
        }
    }
}

// MARK: - Helper Extensions

extension UniTool {
    /// Create a calendar event tool descriptor
    static func createEventTool() -> UniTool {
        return UniTool(
            name: "create_event",
            description: "Create a calendar event with specified details",
            parameters: UniTool.ToolParameters(
                properties: [
                    "title": UniTool.ParameterProperty(
                        type: "string",
                        description: "The title of the event"
                    ),
                    "start_date": UniTool.ParameterProperty(
                        type: "string",
                        description: "The start date and time in ISO 8601 format"
                    ),
                    "end_date": UniTool.ParameterProperty(
                        type: "string",
                        description: "The end date and time in ISO 8601 format"
                    ),
                    "description": UniTool.ParameterProperty(
                        type: "string",
                        description: "Optional description of the event"
                    )
                ],
                required: ["title", "start_date", "end_date"]
            ),
            metadata: ["category": "calendar"]
        )
    }
    
    /// Create a search tool descriptor
    static func searchTool() -> UniTool {
        return UniTool(
            name: "search",
            description: "Search for information",
            parameters: UniTool.ToolParameters(
                properties: [
                    "query": UniTool.ParameterProperty(
                        type: "string",
                        description: "The search query"
                    ),
                    "scope": UniTool.ParameterProperty(
                        type: "string",
                        description: "The scope of the search",
                        enumValues: ["local", "web", "documents"]
                    )
                ],
                required: ["query"]
            ),
            metadata: ["category": "search"]
        )
    }
}

// MARK: - Multi-Role Orchestrator

class MultiRoleOrchestrator: ObservableObject {
    @Published private(set) var state: MultiRoleState
    @Published private(set) var isProcessing = false
    
    private let aiService: AIService
    private let mcpManager: SimpleMCPManager
    private let maxIterations: Int
    private let logger = Logger(subsystem: "com.aihelper.multirole", category: "MultiRoleOrchestrator")
    
    init(aiService: AIService, mcpManager: SimpleMCPManager, maxIterations: Int = 10) {
        self.aiService = aiService
        self.mcpManager = mcpManager
        self.maxIterations = maxIterations
        self.state = MultiRoleState(goal: "")
    }
    
    @MainActor
    func startConversation(goal: String) async {
        state = MultiRoleState(goal: goal)
        isProcessing = true
        
        await runOrchestratorLoop()
        
        isProcessing = false
    }
    
    private func runOrchestratorLoop() async {
        var iterations = 0
        
        while !state.done && iterations < maxIterations {
            guard let currentRole = state.nextRole else {
                logger.error("❌ No next role specified")
                break
            }
            
            logger.info("🎭 Role: \(currentRole.rawValue) (iteration \(iterations + 1))")
            
            let rolePrompt = buildRolePrompt(for: currentRole)
            
            do {
                let response = try await aiService.sendMessageWithoutContext(rolePrompt)
                let roleResponse = try parseRoleResponse(response)
                
                await MainActor.run {
                    state.messages.append(roleResponse.content)
                }
                
                if let stateDiff = roleResponse.stateDiff {
                    await MainActor.run {
                        state.apply(stateDiff)
                    }
                }
                
                if let actions = roleResponse.actions {
                    let observations = await executeActions(actions)
                    await MainActor.run {
                        state.observations.append(contentsOf: observations)
                    }
                }
                
                iterations += 1
                
            } catch {
                logger.error("❌ Role execution failed: \(error)")
                await MainActor.run {
                    state.done = true
                }
            }
        }
        
        if iterations >= maxIterations {
            logger.warning("⏰ Max iterations reached")
            await MainActor.run {
                state.done = true
            }
        }
    }
    
    private func buildRolePrompt(for role: ConversationRole) -> String {
        let toolCatalog = mcpManager.getAllTools().map { tool in
            "- \(tool.name): \(tool.description)"
        }.joined(separator: "\n")
        
        let recentMessages = state.messages.suffix(3).joined(separator: "\n")
        let recentObservations = state.observations.suffix(3).map { obs in
            "Tool: \(obs.tool), Success: \(obs.success), Data: \(obs.data?.value ?? "none")"
        }.joined(separator: "\n")
        
        return """
        \(role.systemPrompt)
        
        GOAL: \(state.goal)
        
        CURRENT STATE:
        Facts: \(state.facts.joined(separator: "; "))
        Todos: \(state.todos.joined(separator: "; "))
        Decisions: \(state.decisions.joined(separator: "; "))
        
        RECENT MESSAGES:
        \(recentMessages.isEmpty ? "None" : recentMessages)
        
        RECENT OBSERVATIONS:
        \(recentObservations.isEmpty ? "None" : recentObservations)
        
        AVAILABLE TOOLS:
        \(toolCatalog.isEmpty ? "None" : toolCatalog)
        
        Respond with valid JSON only, no other text.
        """
    }
    
    private func parseRoleResponse(_ response: String) throws -> RoleResponse {
        guard let data = response.data(using: .utf8) else {
            throw MultiRoleError.invalidResponse("Invalid UTF-8")
        }
        
        let decoder = JSONDecoder()
        
        do {
            return try decoder.decode(RoleResponse.self, from: data)
        } catch {
            let cleanedResponse = extractJSONFromResponse(response)
            guard let cleanedData = cleanedResponse.data(using: .utf8) else {
                throw MultiRoleError.invalidResponse("No valid JSON found")
            }
            return try decoder.decode(RoleResponse.self, from: cleanedData)
        }
    }
    
    private func extractJSONFromResponse(_ response: String) -> String {
        if let startRange = response.range(of: "{"),
           let endRange = response.range(of: "}", options: .backwards) {
            return String(response[startRange.lowerBound...endRange.upperBound])
        }
        return response
    }
    
    private func executeActions(_ actions: [RoleAction]) async -> [ToolObservation] {
        var observations: [ToolObservation] = []
        
        for action in actions {
            guard action.type == "tool.call" else {
                logger.warning("⚠️ Unknown action type: \(action.type)")
                continue
            }
            
            do {
                let args = convertAnyCodableDict(action.args)
                let result = try await mcpManager.callTool(action.name, arguments: args)
                
                let observation = ToolObservation(
                    tool: action.name,
                    args: action.args,
                    success: true,
                    data: AnyCodable(result),
                    error: nil
                )
                observations.append(observation)
                logger.info("✅ Tool call successful: \(action.name)")
                
            } catch {
                let observation = ToolObservation(
                    tool: action.name,
                    args: action.args,
                    success: false,
                    data: nil,
                    error: error.localizedDescription
                )
                observations.append(observation)
                logger.error("❌ Tool call failed: \(action.name) - \(error)")
            }
        }
        
        return observations
    }
    
    private func convertAnyCodableDict(_ dict: [String: AnyCodable]) -> [String: Any] {
        return dict.mapValues { $0.value }
    }
}

enum MultiRoleError: LocalizedError {
    case invalidResponse(String)
    case maxIterationsReached
    case noNextRole
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .maxIterationsReached:
            return "Maximum iterations reached"
        case .noNextRole:
            return "No next role specified"
        }
    }
}

// MARK: - Reason-Act Orchestrator

class ReasonActOrchestrator {
    private let contextManager: ContextManager
    private let toolHandler: ((String, [String: Any]) async throws -> UniMsg.ToolResult)?
    private let openAIConverter: OpenAIConverter
    private let claudeConverter: ClaudeConverter
    private let logger = Logger(subsystem: "com.aihelper.orchestrator", category: "ReasonActOrchestrator")
    
    init(contextManager: ContextManager, toolHandler: ((String, [String: Any]) async throws -> UniMsg.ToolResult)?, openAIConverter: OpenAIConverter, claudeConverter: ClaudeConverter) {
        self.contextManager = contextManager
        self.toolHandler = toolHandler
        self.openAIConverter = openAIConverter
        self.claudeConverter = claudeConverter
    }
    
    func process(message: String, configuration: APIConfiguration, availableTools: [UniTool], maxSteps: Int) async throws -> (UniMsg, [ReasonActStep]) {
        logger.info("🔄 Starting Reason-Act loop with maxSteps: \(maxSteps)")
        
        // Add system instructions for Reason-Act loop
        let systemPrompt = """
        You are an AI assistant that uses multi-step reasoning and tool calling to solve complex tasks.
        
        For each step:
        1. Think about what you need to do
        2. Use available tools if needed to gather information or take actions
        3. Continue reasoning until you have enough information to provide a final answer
        
        When you are ready to provide your final response to the user:
        - Add \(FINAL_RESPONSE_MARKER) at the beginning of your response
        - This marker will not be shown to the user, it's only for internal processing
        - After the marker, provide your complete final answer to the user's question
        
        Available tools: \(availableTools.map { $0.name }.joined(separator: ", "))
        
        Think step by step and use tools as needed.
        """
        
        let systemMessage = UniMsg(role: .system, text: systemPrompt)
        contextManager.addMessage(systemMessage)
        
        // Initialize context with user message
        contextManager.addUserMessage(message)
        
        var steps: [ReasonActStep] = []
        var stepCount = 0
        var lastError: String?
        var consecutiveErrors = 0
        
        while stepCount < maxSteps {
            stepCount += 1
            logger.info("🔄 Starting Reason-Act step \(stepCount)/\(maxSteps)")
            
            do {
                // Get current context for the provider
                let currentMessages = contextManager.currentMessages(provider: configuration.provider)
                logger.debug("📝 Context messages count: \(currentMessages.count)")
                
                // Call LLM
                logger.info("🤖 Calling \(configuration.provider.rawValue) API for step \(stepCount)")
                let response = try await callLLM(messages: currentMessages, tools: availableTools, configuration: configuration)
                contextManager.addMessage(response)
                
                let responseText = response.textContent
                logger.debug("💬 Response text length: \(responseText.count) chars")
                if !responseText.isEmpty {
                    logger.debug("💭 Response preview: \(String(responseText.prefix(100)))...")
                }
                
                // Check if response contains final response marker
                if responseText.contains(FINAL_RESPONSE_MARKER) {
                    // Final response - clean the marker and end the loop
                    let cleanedText = responseText.replacingOccurrences(of: FINAL_RESPONSE_MARKER, with: "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let finalResponse = UniMsg(role: .assistant, text: cleanedText)
                    logger.info("✅ Reason-Act completed with final response marker at step \(stepCount)")
                    logger.info("📋 Final response length: \(cleanedText.count) chars")
                    return (finalResponse, steps)
                }
                
                // Check if response contains tool calls
                let toolCalls = response.toolCalls
                logger.info("🔧 Found \(toolCalls.count) tool calls in step \(stepCount)")
                
                // Execute tool calls
                var toolResults: [UniMsg.ToolResult] = []
                var stepToolCalls: [ReasonActStep.ToolExecution] = []
                
                for toolCall in toolCalls {
                    let startTime = Date()
                    
                    do {
                        let result = try await executeToolCall(toolCall)
                        toolResults.append(result)
                        
                        stepToolCalls.append(ReasonActStep.ToolExecution(
                            toolName: toolCall.name,
                            arguments: toolCall.arguments,
                            result: result.content,
                            isError: result.isError,
                            duration: Date().timeIntervalSince(startTime)
                        ))
                        
                        // Reset consecutive errors on success
                        if !result.isError {
                            consecutiveErrors = 0
                            lastError = nil
                        }
                        
                    } catch {
                        let errorResult = UniMsg.ToolResult(
                            toolCallId: toolCall.id,
                            content: "Tool execution failed: \(error.localizedDescription)",
                            isError: true
                        )
                        toolResults.append(errorResult)
                        
                        stepToolCalls.append(ReasonActStep.ToolExecution(
                            toolName: toolCall.name,
                            arguments: toolCall.arguments,
                            result: errorResult.content,
                            isError: true,
                            duration: Date().timeIntervalSince(startTime)
                        ))
                        
                        // Track consecutive errors
                        if lastError == error.localizedDescription {
                            consecutiveErrors += 1
                        } else {
                            consecutiveErrors = 1
                            lastError = error.localizedDescription
                        }
                        
                        // Stop if same error occurs twice in a row
                        if consecutiveErrors >= 2 {
                            logger.error("❌ Stopping Reason-Act loop due to consecutive errors: \(error.localizedDescription)")
                            throw ReasonActError.consecutiveErrors(error.localizedDescription)
                        }
                    }
                }
                
                // Add tool results to context
                if !toolResults.isEmpty {
                    contextManager.addToolResults(toolResults)
                }
                
                // Record step
                steps.append(ReasonActStep(
                    stepNumber: stepCount,
                    assistantMessage: response.textContent,
                    toolExecutions: stepToolCalls
                ))
                
            } catch {
                logger.error("❌ Reason-Act step \(stepCount) failed: \(error.localizedDescription)")
                throw error
            }
        }
        
        // Max steps reached - return last response or generate summary
        logger.warning("⚠️ Reason-Act loop reached maxSteps (\(maxSteps))")
        let summaryResponse = UniMsg(role: .assistant, text: "I've completed \(maxSteps) reasoning steps but need more time to fully address your request. Here's what I've accomplished so far based on the tool executions.")
        return (summaryResponse, steps)
    }
    
    private func callLLM(messages: [Any], tools: [UniTool], configuration: APIConfiguration) async throws -> UniMsg {
        switch configuration.provider {
        case .openai:
            let openAIMessages = messages as! [OpenAIMessage]
            let request = openAIConverter.convertToRequest(messages: [], tools: tools, configuration: configuration)
            let modifiedRequest = OpenAIRequest(
                model: request.model,
                messages: openAIMessages,
                tools: request.tools,
                tool_choice: request.tool_choice,
                max_tokens: request.max_tokens,
                temperature: request.temperature
            )
            let response = try await makeOpenAIRequest(request: modifiedRequest, configuration: configuration)
            return openAIConverter.convertFromResponse(response)
            
        case .claude:
            let claudeMessages = messages as! [ClaudeMessage]
            let request = claudeConverter.convertToRequest(messages: [], tools: tools, configuration: configuration)
            let modifiedRequest = ClaudeRequest(
                model: request.model,
                max_tokens: request.max_tokens,
                temperature: request.temperature,
                messages: claudeMessages,
                tools: request.tools
            )
            let response = try await makeClaudeRequest(request: modifiedRequest, configuration: configuration)
            return claudeConverter.convertFromResponse(response)
        }
    }
    
    private func executeToolCall(_ toolCall: UniMsg.ToolCall) async throws -> UniMsg.ToolResult {
        guard let toolHandler = toolHandler else {
            return UniMsg.ToolResult(
                toolCallId: toolCall.id,
                content: "Tool handler not configured",
                isError: true
            )
        }
        
        return try await toolHandler(toolCall.name, toolCall.arguments)
    }
    
    // Duplicate API methods from UnifiedChatAgent for orchestrator use
    private func makeOpenAIRequest(request: OpenAIRequest, configuration: APIConfiguration) async throws -> OpenAIResponse {
        let url = URL(string: "\(configuration.provider.baseURL)/chat/completions")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        
        let requestData = try encodeOpenAIRequest(request)
        urlRequest.httpBody = requestData
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UnifiedChatError.invalidResponse("Invalid HTTP response")
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw UnifiedChatError.apiError("OpenAI API error (\(httpResponse.statusCode)): \(errorMessage)")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(OpenAIResponse.self, from: data)
    }
    
    private func makeClaudeRequest(request: ClaudeRequest, configuration: APIConfiguration) async throws -> ClaudeResponse {
        let url = URL(string: "\(configuration.provider.baseURL)/messages")!
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let requestData = try encodeClaudeRequest(request)
        urlRequest.httpBody = requestData
        
        let (data, response) = try await URLSession.shared.data(for: urlRequest)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UnifiedChatError.invalidResponse("Invalid HTTP response")
        }
        
        guard 200...299 ~= httpResponse.statusCode else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw UnifiedChatError.apiError("Claude API error (\(httpResponse.statusCode)): \(errorMessage)")
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(ClaudeResponse.self, from: data)
    }
    
    private func encodeOpenAIRequest(_ request: OpenAIRequest) throws -> Data {
        var requestDict: [String: Any] = [
            "model": request.model,
            "messages": try encodeOpenAIMessages(request.messages),
            "max_tokens": request.max_tokens,
            "temperature": request.temperature
        ]
        
        if let tools = request.tools {
            requestDict["tools"] = try encodeOpenAITools(tools)
        }
        
        if let toolChoice = request.tool_choice {
            requestDict["tool_choice"] = toolChoice
        }
        
        return try JSONSerialization.data(withJSONObject: requestDict)
    }
    
    private func encodeClaudeRequest(_ request: ClaudeRequest) throws -> Data {
        var requestDict: [String: Any] = [
            "model": request.model,
            "max_tokens": request.max_tokens,
            "temperature": request.temperature,
            "messages": try encodeClaudeMessages(request.messages)
        ]
        
        if let tools = request.tools {
            requestDict["tools"] = try encodeClaudeTools(tools)
        }
        
        return try JSONSerialization.data(withJSONObject: requestDict)
    }
    
    private func encodeOpenAIMessages(_ messages: [OpenAIMessage]) throws -> [[String: Any]] {
        return messages.map { message in
            var messageDict: [String: Any] = ["role": message.role]
            
            if let content = message.content {
                messageDict["content"] = content
            }
            
            if let toolCalls = message.tool_calls {
                messageDict["tool_calls"] = toolCalls.map { toolCall in
                    [
                        "id": toolCall.id,
                        "type": toolCall.type,
                        "function": [
                            "name": toolCall.function.name,
                            "arguments": toolCall.function.arguments
                        ]
                    ]
                }
            }
            
            if let toolCallId = message.tool_call_id {
                messageDict["tool_call_id"] = toolCallId
            }
            
            return messageDict
        }
    }
    
    private func encodeClaudeMessages(_ messages: [ClaudeMessage]) throws -> [[String: Any]] {
        return messages.map { message in
            [
                "role": message.role,
                "content": message.content.map { content in
                    var contentDict: [String: Any] = ["type": content.type]
                    
                    if let text = content.text {
                        contentDict["text"] = text
                    }
                    
                    if let toolUse = content.tool_use {
                        contentDict["id"] = toolUse.id
                        contentDict["name"] = toolUse.name
                        contentDict["input"] = toolUse.input
                    }
                    
                    if let toolUseId = content.tool_use_id {
                        contentDict["tool_use_id"] = toolUseId
                    }
                    
                    if let resultContent = content.content {
                        contentDict["content"] = resultContent
                    }
                    
                    if let isError = content.is_error {
                        contentDict["is_error"] = isError
                    }
                    
                    return contentDict
                }
            ]
        }
    }
    
    private func encodeOpenAITools(_ tools: [OpenAITool]) throws -> [[String: Any]] {
        return tools.map { tool in
            [
                "type": tool.type,
                "function": [
                    "name": tool.function.name,
                    "description": tool.function.description,
                    "parameters": tool.function.parameters
                ]
            ]
        }
    }
    
    private func encodeClaudeTools(_ tools: [ClaudeTool]) throws -> [[String: Any]] {
        return tools.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.input_schema
            ]
        }
    }
}