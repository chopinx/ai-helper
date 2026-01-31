import Foundation

// MARK: - Helper Classes

/// Box class to break recursive struct references
class Box<T>: Codable where T: Codable {
    let value: T
    
    init(_ value: T) {
        self.value = value
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        value = try container.decode(T.self)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

// MARK: - Unified Message Structure (UniMsg)

/// Unified message structure that works across all AI providers
/// Records every conversation turn including tool calls and results
struct UniMsg: Codable, Identifiable {
    let id: UUID
    let role: Role
    let content: [ContentBlock]
    let timestamp: Date
    let metadata: [String: String]?
    
    enum Role: String, Codable {
        case user = "user"
        case assistant = "assistant"
        case system = "system"
        case tool = "tool"
    }
    
    enum ContentBlock: Codable {
        case text(String)
        case toolCall(ToolCall)
        case toolResult(ToolResult)
        
        var text: String? {
            if case .text(let text) = self {
                return text
            }
            return nil
        }
        
        var toolCall: ToolCall? {
            if case .toolCall(let call) = self {
                return call
            }
            return nil
        }
        
        var toolResult: ToolResult? {
            if case .toolResult(let result) = self {
                return result
            }
            return nil
        }
    }
    
    struct ToolCall: Codable, Identifiable {
        let id: String
        let name: String
        let arguments: [String: Any]
        
        enum CodingKeys: String, CodingKey {
            case id, name, arguments
        }
        
        init(id: String, name: String, arguments: [String: Any]) {
            self.id = id
            self.name = name
            self.arguments = arguments
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            name = try container.decode(String.self, forKey: .name)
            
            // Handle Any type for arguments
            if let argsData = try container.decodeIfPresent(Data.self, forKey: .arguments) {
                arguments = try JSONSerialization.jsonObject(with: argsData) as? [String: Any] ?? [:]
            } else {
                arguments = [:]
            }
        }
        
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(name, forKey: .name)
            
            // Encode arguments as Data
            let argsData = try JSONSerialization.data(withJSONObject: arguments)
            try container.encode(argsData, forKey: .arguments)
        }
    }
    
    struct ToolResult: Codable, Identifiable {
        let id: String
        let toolCallId: String
        let content: String
        let isError: Bool
        
        init(id: String = UUID().uuidString, toolCallId: String, content: String, isError: Bool = false) {
            self.id = id
            self.toolCallId = toolCallId
            self.content = content
            self.isError = isError
        }
    }
    
    init(role: Role, content: [ContentBlock], metadata: [String: String]? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.metadata = metadata
    }
    
    /// Convenience initializer for text-only messages
    init(role: Role, text: String, metadata: [String: String]? = nil) {
        self.init(role: role, content: [.text(text)], metadata: metadata)
    }
    
    /// Get all text content as a single string
    var textContent: String {
        return content.compactMap { $0.text }.joined(separator: "\n")
    }
    
    /// Get all tool calls in this message
    var toolCalls: [ToolCall] {
        return content.compactMap { $0.toolCall }
    }
    
    /// Get all tool results in this message
    var toolResults: [ToolResult] {
        return content.compactMap { $0.toolResult }
    }
}

// MARK: - Unified Tool Descriptor (UniTool)

/// Unified tool descriptor that holds JSON-Schema for functions
/// Compatible with both OpenAI and Claude tool calling formats
struct UniTool: Codable, Identifiable {
    let id: String
    let name: String
    let description: String
    let parameters: ToolParameters
    let metadata: [String: String]?
    
    struct ToolParameters: Codable {
        let type: String
        let properties: [String: ParameterProperty]
        let required: [String]
        let additionalProperties: Bool?
        
        init(type: String = "object", properties: [String: ParameterProperty], required: [String] = [], additionalProperties: Bool? = false) {
            self.type = type
            self.properties = properties
            self.required = required
            self.additionalProperties = additionalProperties
        }
    }
    
    struct ParameterProperty: Codable {
        let type: String
        let description: String?
        let enumValues: [String]?
        let format: String?
        let items: Box<ParameterProperty>?
        let properties: [String: ParameterProperty]?
        let required: [String]?
        
        enum CodingKeys: String, CodingKey {
            case type, description, format, items, properties, required
            case enumValues = "enum"
        }
        
        init(type: String, description: String? = nil, enumValues: [String]? = nil, format: String? = nil, items: ParameterProperty? = nil, properties: [String: ParameterProperty]? = nil, required: [String]? = nil) {
            self.type = type
            self.description = description
            self.enumValues = enumValues
            self.format = format
            self.items = items.map { Box($0) }
            self.properties = properties
            self.required = required
        }
    }
    
    init(name: String, description: String, parameters: ToolParameters, metadata: [String: String]? = nil) {
        self.id = name // Use name as ID for simplicity
        self.name = name
        self.description = description
        self.parameters = parameters
        self.metadata = metadata
    }
}

// MARK: - Conversation Management

/// In-memory conversation log that maintains unified message history
class UnifiedConversation: ObservableObject {
    @Published private(set) var messages: [UniMsg] = []
    @Published private(set) var availableTools: [UniTool] = []
    private let maxHistorySize: Int
    
    init(maxHistorySize: Int = 50) {
        self.maxHistorySize = maxHistorySize
    }
    
    /// Add a message to the conversation
    func addMessage(_ message: UniMsg) {
        messages.append(message)
        
        // Maintain history size limit
        if messages.count > maxHistorySize {
            messages.removeFirst(messages.count - maxHistorySize)
        }
    }
    
    /// Add a user message
    func addUserMessage(_ text: String, metadata: [String: String]? = nil) {
        let message = UniMsg(role: .user, text: text, metadata: metadata)
        addMessage(message)
    }
    
    /// Add an assistant message
    func addAssistantMessage(_ text: String, toolCalls: [UniMsg.ToolCall] = [], metadata: [String: String]? = nil) {
        var content: [UniMsg.ContentBlock] = []
        
        if !text.isEmpty {
            content.append(.text(text))
        }
        
        content.append(contentsOf: toolCalls.map { .toolCall($0) })
        
        let message = UniMsg(role: .assistant, content: content, metadata: metadata)
        addMessage(message)
    }
    
    /// Add tool results
    func addToolResults(_ results: [UniMsg.ToolResult], metadata: [String: String]? = nil) {
        let content = results.map { UniMsg.ContentBlock.toolResult($0) }
        let message = UniMsg(role: .tool, content: content, metadata: metadata)
        addMessage(message)
    }
    
    /// Set available tools for the conversation
    func setAvailableTools(_ tools: [UniTool]) {
        availableTools = tools
    }
    
    /// Get recent messages for context (excluding tool results unless specifically needed)
    func getRecentMessages(count: Int = 10, includeToolResults: Bool = false) -> [UniMsg] {
        let recentMessages = Array(messages.suffix(count))
        
        if includeToolResults {
            return recentMessages
        } else {
            return recentMessages.filter { $0.role != .tool }
        }
    }
    
    /// Clear conversation history
    func clear() {
        messages.removeAll()
        print("🗑️ Conversation cleared")
    }
    
    /// Export conversation to structured format
    func exportConversation() -> [String: Any] {
        return [
            "messages": messages.map { message in
                [
                    "id": message.id.uuidString,
                    "role": message.role.rawValue,
                    "content": message.content.map { contentBlock in
                        switch contentBlock {
                        case .text(let text):
                            return ["type": "text", "text": text]
                        case .toolCall(let toolCall):
                            return [
                                "type": "tool_call",
                                "id": toolCall.id,
                                "name": toolCall.name,
                                "arguments": String(describing: toolCall.arguments)
                            ]
                        case .toolResult(let toolResult):
                            return [
                                "type": "tool_result",
                                "id": toolResult.id,
                                "tool_call_id": toolResult.toolCallId,
                                "content": toolResult.content,
                                "is_error": String(toolResult.isError)
                            ]
                        }
                    },
                    "timestamp": ISO8601DateFormatter().string(from: message.timestamp),
                    "metadata": message.metadata ?? [:]
                ]
            },
            "statistics": [
                "total_messages": statistics.totalMessages,
                "user_messages": statistics.userMessages,
                "assistant_messages": statistics.assistantMessages,
                "tool_calls": statistics.toolCalls,
                "tool_results": statistics.toolResults,
                "available_tools": statistics.availableTools
            ],
            "export_date": ISO8601DateFormatter().string(from: Date())
        ]
    }
    
    /// Get conversation statistics
    var statistics: ConversationStatistics {
        return ConversationStatistics(
            totalMessages: messages.count,
            userMessages: messages.filter { $0.role == .user }.count,
            assistantMessages: messages.filter { $0.role == .assistant }.count,
            toolCalls: messages.flatMap { $0.toolCalls }.count,
            toolResults: messages.flatMap { $0.toolResults }.count,
            availableTools: availableTools.count
        )
    }
}

struct ConversationStatistics {
    let totalMessages: Int
    let userMessages: Int  
    let assistantMessages: Int
    let toolCalls: Int
    let toolResults: Int
    let availableTools: Int
}

// MARK: - Multi-Role Conversation System

enum ConversationRole: String, CaseIterable, Codable {
    case planner = "planner"
    case toolCaller = "tool_caller"
    case critic = "critic"
    case finalizer = "finalizer"
    
    var systemPrompt: String {
        switch self {
        case .planner:
            return """
            You are the Planner. Analyze the user's goal and create a structured plan.
            
            Return JSON with: content (your analysis), state_diff (facts_add, todos_add, decisions_add, next_role), actions (optional).
            Set next_role to "tool_caller" if tools needed, "finalizer" if simple.
            """
            
        case .toolCaller:
            return """
            You are the ToolCaller. Execute tool calls based on the plan.
            
            Return JSON with: content (actions taken), actions (tool calls), state_diff (facts from results), next_role ("critic" for validation, "finalizer" if done).
            """
            
        case .critic:
            return """
            You are the Critic. Validate work and identify gaps.
            
            Return JSON with: content (critical analysis), state_diff (updated decisions), next_role ("tool_caller" if more work needed, "finalizer" if satisfied).
            """
            
        case .finalizer:
            return """
            You are the Finalizer. Complete the conversation.
            
            Return JSON with: content (final response), state_diff (done: true), next_role (null).
            """
        }
    }
}

struct MultiRoleState: Codable {
    var goal: String
    var facts: [String]
    var todos: [String]
    var decisions: [String]
    var messages: [String]
    var observations: [ToolObservation]
    var nextRole: ConversationRole?
    var done: Bool
    
    init(goal: String) {
        self.goal = goal
        self.facts = []
        self.todos = []
        self.decisions = []
        self.messages = []
        self.observations = []
        self.nextRole = .planner
        self.done = false
    }
    
    mutating func apply(_ diff: StateDiff) {
        if let factsToAdd = diff.factsAdd {
            facts.append(contentsOf: factsToAdd)
        }
        if let todosToAdd = diff.todosAdd {
            todos.append(contentsOf: todosToAdd)
        }
        if let decisionsToAdd = diff.decisionsAdd {
            decisions.append(contentsOf: decisionsToAdd)
        }
        if let nextRole = diff.nextRole {
            self.nextRole = nextRole
        }
        if let done = diff.done {
            self.done = done
        }
    }
}

struct StateDiff: Codable {
    var factsAdd: [String]?
    var todosAdd: [String]?
    var decisionsAdd: [String]?
    var nextRole: ConversationRole?
    var done: Bool?
    
    enum CodingKeys: String, CodingKey {
        case factsAdd = "facts_add"
        case todosAdd = "todos_add"
        case decisionsAdd = "decisions_add"
        case nextRole = "next_role"
        case done
    }
}

struct RoleAction: Codable {
    var type: String
    var name: String
    var args: [String: AnyCodable]
}

struct ToolObservation: Codable, Identifiable {
    let id = UUID()
    var tool: String
    var args: [String: AnyCodable]
    var success: Bool
    var data: AnyCodable?
    var error: String?
    
    private enum CodingKeys: String, CodingKey {
        case tool, args, success, data, error
    }
}

struct RoleResponse: Codable {
    var content: String
    var stateDiff: StateDiff?
    var actions: [RoleAction]?
    
    enum CodingKeys: String, CodingKey {
        case content
        case stateDiff = "state_diff"
        case actions
    }
}

struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unable to decode value"))
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map(AnyCodable.init))
        case let dict as [String: Any]:
            try container.encode(dict.mapValues(AnyCodable.init))
        default:
            throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Unable to encode value"))
        }
    }
}

// MARK: - Provider-Specific Conversion Protocols

/// Protocol for converting unified structures to provider-specific formats
protocol ProviderConverter {
    associatedtype RequestPayload
    associatedtype ResponsePayload
    
    /// Convert unified messages and tools to provider-specific request payload
    func convertToRequest(messages: [UniMsg], tools: [UniTool], configuration: APIConfiguration) -> RequestPayload
    
    /// Convert provider response back to unified message
    func convertFromResponse(_ response: ResponsePayload) -> UniMsg
    
    /// Extract tool calls from provider response
    func extractToolCalls(from response: ResponsePayload) -> [UniMsg.ToolCall]
}