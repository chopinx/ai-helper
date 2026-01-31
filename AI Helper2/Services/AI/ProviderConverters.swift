import Foundation

// MARK: - OpenAI Converter

struct OpenAIConverter: ProviderConverter {
    typealias RequestPayload = OpenAIRequest
    typealias ResponsePayload = OpenAIResponse
    
    func convertToRequest(messages: [UniMsg], tools: [UniTool], configuration: APIConfiguration) -> OpenAIRequest {
        let openAIMessages = messages.compactMap { convertMessage($0) }
        let openAITools = tools.map { convertTool($0) }
        
        return OpenAIRequest(
            model: configuration.model,
            messages: openAIMessages,
            tools: openAITools.isEmpty ? nil : openAITools,
            tool_choice: openAITools.isEmpty ? nil : "auto",
            max_tokens: configuration.maxTokens,
            temperature: configuration.temperature
        )
    }
    
    func convertFromResponse(_ response: OpenAIResponse) -> UniMsg {
        guard let choice = response.choices.first else {
            return UniMsg(role: .assistant, text: "No response received")
        }
        
        var content: [UniMsg.ContentBlock] = []
        
        // Add text content if present
        if let text = choice.message.content, !text.isEmpty {
            content.append(.text(text))
        }
        
        // Add tool calls if present
        if let toolCalls = choice.message.tool_calls {
            for toolCall in toolCalls {
                let uniToolCall = UniMsg.ToolCall(
                    id: toolCall.id,
                    name: toolCall.function.name,
                    arguments: parseArguments(toolCall.function.arguments)
                )
                content.append(.toolCall(uniToolCall))
            }
        }
        
        return UniMsg(role: .assistant, content: content, metadata: [
            "provider": "openai",
            "model": response.model ?? "",
            "finish_reason": choice.finish_reason ?? ""
        ])
    }
    
    func extractToolCalls(from response: OpenAIResponse) -> [UniMsg.ToolCall] {
        guard let choice = response.choices.first,
              let toolCalls = choice.message.tool_calls else {
            return []
        }
        
        return toolCalls.map { toolCall in
            UniMsg.ToolCall(
                id: toolCall.id,
                name: toolCall.function.name,
                arguments: parseArguments(toolCall.function.arguments)
            )
        }
    }
    
    // MARK: - Private Helpers
    
    private func convertMessage(_ uniMsg: UniMsg) -> OpenAIMessage? {
        switch uniMsg.role {
        case .user:
            return OpenAIMessage(
                role: "user",
                content: uniMsg.textContent
            )
            
        case .assistant:
            let toolCalls = uniMsg.toolCalls.isEmpty ? nil : uniMsg.toolCalls.map { toolCall in
                OpenAIToolCall(
                    id: toolCall.id,
                    type: "function",
                    function: OpenAIFunction(
                        name: toolCall.name,
                        arguments: serializeArguments(toolCall.arguments)
                    )
                )
            }
            
            return OpenAIMessage(
                role: "assistant",
                content: uniMsg.textContent.isEmpty ? nil : uniMsg.textContent,
                tool_calls: toolCalls
            )
            
        case .tool:
            // Convert tool results to OpenAI format
            let toolResults = uniMsg.toolResults
            if let firstResult = toolResults.first {
                return OpenAIMessage(
                    role: "tool",
                    content: firstResult.content,
                    tool_call_id: firstResult.toolCallId
                )
            }
            return nil
            
        case .system:
            return OpenAIMessage(
                role: "system",
                content: uniMsg.textContent
            )
        }
    }
    
    private func convertTool(_ uniTool: UniTool) -> OpenAITool {
        return OpenAITool(
            type: "function",
            function: OpenAIToolFunction(
                name: uniTool.name,
                description: uniTool.description,
                parameters: convertParameters(uniTool.parameters)
            )
        )
    }
    
    private func convertParameters(_ params: UniTool.ToolParameters) -> [String: Any] {
        var result: [String: Any] = [
            "type": params.type,
            "properties": convertProperties(params.properties)
        ]
        
        if !params.required.isEmpty {
            result["required"] = params.required
        }
        
        if let additionalProperties = params.additionalProperties {
            result["additionalProperties"] = additionalProperties
        }
        
        return result
    }
    
    private func convertProperties(_ properties: [String: UniTool.ParameterProperty]) -> [String: Any] {
        var result: [String: Any] = [:]
        
        for (key, property) in properties {
            var propDict: [String: Any] = ["type": property.type]
            
            if let description = property.description {
                propDict["description"] = description
            }
            
            if let enumValues = property.enumValues {
                propDict["enum"] = enumValues
            }
            
            if let format = property.format {
                propDict["format"] = format
            }
            
            if let items = property.items {
                propDict["items"] = convertProperty(items.value)
            }
            
            if let nestedProps = property.properties {
                propDict["properties"] = convertProperties(nestedProps)
            }
            
            if let required = property.required {
                propDict["required"] = required
            }
            
            result[key] = propDict
        }
        
        return result
    }
    
    private func convertProperty(_ property: UniTool.ParameterProperty) -> [String: Any] {
        var result: [String: Any] = ["type": property.type]
        
        if let description = property.description {
            result["description"] = description
        }
        
        if let enumValues = property.enumValues {
            result["enum"] = enumValues
        }
        
        if let format = property.format {
            result["format"] = format
        }
        
        return result
    }
    
    private func parseArguments(_ argumentsString: String) -> [String: Any] {
        guard let data = argumentsString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }
        return json
    }
    
    private func serializeArguments(_ arguments: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

// MARK: - Claude Converter

struct ClaudeConverter: ProviderConverter {
    typealias RequestPayload = ClaudeRequest
    typealias ResponsePayload = ClaudeResponse
    
    func convertToRequest(messages: [UniMsg], tools: [UniTool], configuration: APIConfiguration) -> ClaudeRequest {
        let claudeMessages = messages.compactMap { convertMessage($0) }
        let claudeTools = tools.map { convertTool($0) }
        
        return ClaudeRequest(
            model: configuration.model,
            max_tokens: configuration.maxTokens,
            temperature: configuration.temperature,
            messages: claudeMessages,
            tools: claudeTools.isEmpty ? nil : claudeTools
        )
    }
    
    func convertFromResponse(_ response: ClaudeResponse) -> UniMsg {
        var content: [UniMsg.ContentBlock] = []
        
        for contentBlock in response.content {
            switch contentBlock.type {
            case "text":
                if let text = contentBlock.text {
                    content.append(.text(text))
                }
                
            case "tool_use":
                if let toolUse = contentBlock.tool_use {
                    let uniToolCall = UniMsg.ToolCall(
                        id: toolUse.id,
                        name: toolUse.name,
                        arguments: toolUse.input
                    )
                    content.append(.toolCall(uniToolCall))
                }
                
            default:
                break
            }
        }
        
        return UniMsg(role: .assistant, content: content, metadata: [
            "provider": "claude",
            "model": response.model,
            "stop_reason": response.stop_reason ?? ""
        ])
    }
    
    func extractToolCalls(from response: ClaudeResponse) -> [UniMsg.ToolCall] {
        return response.content.compactMap { contentBlock in
            guard contentBlock.type == "tool_use",
                  let toolUse = contentBlock.tool_use else {
                return nil
            }
            
            return UniMsg.ToolCall(
                id: toolUse.id,
                name: toolUse.name,
                arguments: toolUse.input
            )
        }
    }
    
    // MARK: - Private Helpers
    
    private func convertMessage(_ uniMsg: UniMsg) -> ClaudeMessage? {
        switch uniMsg.role {
        case .user:
            return ClaudeMessage(
                role: "user",
                content: [ClaudeContent(type: "text", text: uniMsg.textContent)]
            )
            
        case .assistant:
            var claudeContent: [ClaudeContent] = []
            
            for contentBlock in uniMsg.content {
                switch contentBlock {
                case .text(let text):
                    claudeContent.append(ClaudeContent(type: "text", text: text))
                    
                case .toolCall(let toolCall):
                    claudeContent.append(ClaudeContent(
                        type: "tool_use",
                        tool_use: ClaudeToolUse(
                            id: toolCall.id,
                            name: toolCall.name,
                            input: toolCall.arguments
                        )
                    ))
                    
                case .toolResult:
                    // Tool results are handled separately in Claude
                    continue
                }
            }
            
            return ClaudeMessage(role: "assistant", content: claudeContent)
            
        case .tool:
            // Convert tool results to Claude format
            var claudeContent: [ClaudeContent] = []
            
            for toolResult in uniMsg.toolResults {
                claudeContent.append(ClaudeContent(
                    type: "tool_result",
                    tool_use_id: toolResult.toolCallId,
                    content: toolResult.content,
                    is_error: toolResult.isError
                ))
            }
            
            return ClaudeMessage(role: "user", content: claudeContent)
            
        case .system:
            // System messages are handled separately in Claude requests
            return nil
        }
    }
    
    private func convertTool(_ uniTool: UniTool) -> ClaudeTool {
        return ClaudeTool(
            name: uniTool.name,
            description: uniTool.description,
            input_schema: convertParameters(uniTool.parameters)
        )
    }
    
    private func convertParameters(_ params: UniTool.ToolParameters) -> [String: Any] {
        var result: [String: Any] = [
            "type": params.type,
            "properties": convertProperties(params.properties)
        ]
        
        if !params.required.isEmpty {
            result["required"] = params.required
        }
        
        if let additionalProperties = params.additionalProperties {
            result["additionalProperties"] = additionalProperties
        }
        
        return result
    }
    
    private func convertProperties(_ properties: [String: UniTool.ParameterProperty]) -> [String: Any] {
        var result: [String: Any] = [:]
        
        for (key, property) in properties {
            var propDict: [String: Any] = ["type": property.type]
            
            if let description = property.description {
                propDict["description"] = description
            }
            
            if let enumValues = property.enumValues {
                propDict["enum"] = enumValues
            }
            
            if let format = property.format {
                propDict["format"] = format
            }
            
            if let items = property.items {
                propDict["items"] = convertProperty(items.value)
            }
            
            if let nestedProps = property.properties {
                propDict["properties"] = convertProperties(nestedProps)
            }
            
            if let required = property.required {
                propDict["required"] = required
            }
            
            result[key] = propDict
        }
        
        return result
    }
    
    private func convertProperty(_ property: UniTool.ParameterProperty) -> [String: Any] {
        var result: [String: Any] = ["type": property.type]
        
        if let description = property.description {
            result["description"] = description
        }
        
        if let enumValues = property.enumValues {
            result["enum"] = enumValues
        }
        
        if let format = property.format {
            result["format"] = format
        }
        
        return result
    }
}

// MARK: - Provider-Specific Data Structures

// OpenAI Structures
struct OpenAIRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let tools: [OpenAITool]?
    let tool_choice: String?
    let max_tokens: Int
    let temperature: Double
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String?
    let tool_calls: [OpenAIToolCall]?
    let tool_call_id: String?
    
    init(role: String, content: String? = nil, tool_calls: [OpenAIToolCall]? = nil, tool_call_id: String? = nil) {
        self.role = role
        self.content = content
        self.tool_calls = tool_calls
        self.tool_call_id = tool_call_id
    }
}

struct OpenAIToolCall: Codable {
    let id: String
    let type: String
    let function: OpenAIFunction
}

struct OpenAIFunction: Codable {
    let name: String
    let arguments: String
}

struct OpenAITool: Codable {
    let type: String
    let function: OpenAIToolFunction
}

struct OpenAIToolFunction: Codable {
    let name: String
    let description: String
    let parameters: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case name, description, parameters
    }
    
    init(name: String, description: String, parameters: [String: Any]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        
        if let paramsData = try container.decodeIfPresent(Data.self, forKey: .parameters) {
            parameters = try JSONSerialization.jsonObject(with: paramsData) as? [String: Any] ?? [:]
        } else {
            parameters = [:]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        
        let paramsData = try JSONSerialization.data(withJSONObject: parameters)
        try container.encode(paramsData, forKey: .parameters)
    }
}

struct OpenAIResponse: Codable {
    let id: String?
    let model: String?
    let choices: [OpenAIChoice]
    let usage: OpenAIUsage?
}

struct OpenAIChoice: Codable {
    let index: Int
    let message: OpenAIMessage
    let finish_reason: String?
}

struct OpenAIUsage: Codable {
    let prompt_tokens: Int
    let completion_tokens: Int
    let total_tokens: Int
}

// Claude Structures
struct ClaudeRequest: Codable {
    let model: String
    let max_tokens: Int
    let temperature: Double
    let messages: [ClaudeMessage]
    let tools: [ClaudeTool]?
}

struct ClaudeMessage: Codable {
    let role: String
    let content: [ClaudeContent]
}

struct ClaudeContent: Codable {
    let type: String
    let text: String?
    let tool_use: ClaudeToolUse?
    let tool_use_id: String?
    let content: String?
    let is_error: Bool?
    
    init(type: String, text: String? = nil, tool_use: ClaudeToolUse? = nil, tool_use_id: String? = nil, content: String? = nil, is_error: Bool? = nil) {
        self.type = type
        self.text = text
        self.tool_use = tool_use
        self.tool_use_id = tool_use_id
        self.content = content
        self.is_error = is_error
    }
}

struct ClaudeToolUse: Codable {
    let id: String
    let name: String
    let input: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case id, name, input
    }
    
    init(id: String, name: String, input: [String: Any]) {
        self.id = id
        self.name = name
        self.input = input
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        
        if let inputData = try container.decodeIfPresent(Data.self, forKey: .input) {
            input = try JSONSerialization.jsonObject(with: inputData) as? [String: Any] ?? [:]
        } else {
            input = [:]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        
        let inputData = try JSONSerialization.data(withJSONObject: input)
        try container.encode(inputData, forKey: .input)
    }
}

struct ClaudeTool: Codable {
    let name: String
    let description: String
    let input_schema: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case name, description, input_schema
    }
    
    init(name: String, description: String, input_schema: [String: Any]) {
        self.name = name
        self.description = description
        self.input_schema = input_schema
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decode(String.self, forKey: .description)
        
        if let schemaData = try container.decodeIfPresent(Data.self, forKey: .input_schema) {
            input_schema = try JSONSerialization.jsonObject(with: schemaData) as? [String: Any] ?? [:]
        } else {
            input_schema = [:]
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(description, forKey: .description)
        
        let schemaData = try JSONSerialization.data(withJSONObject: input_schema)
        try container.encode(schemaData, forKey: .input_schema)
    }
}

struct ClaudeResponse: Codable {
    let id: String
    let model: String
    let content: [ClaudeResponseContent]
    let stop_reason: String?
    let usage: ClaudeUsage?
}

struct ClaudeResponseContent: Codable {
    let type: String
    let text: String?
    let tool_use: ClaudeToolUse?
}

struct ClaudeUsage: Codable {
    let input_tokens: Int
    let output_tokens: Int
}

// MARK: - API Request Encoder

/// Shared encoder for API requests to avoid code duplication
enum APIRequestEncoder {

    static func encodeOpenAIRequest(_ request: OpenAIRequest) throws -> Data {
        var requestDict: [String: Any] = [
            "model": request.model,
            "messages": encodeOpenAIMessages(request.messages),
            "max_tokens": request.max_tokens,
            "temperature": request.temperature
        ]

        if let tools = request.tools {
            requestDict["tools"] = encodeOpenAITools(tools)
        }

        if let toolChoice = request.tool_choice {
            requestDict["tool_choice"] = toolChoice
        }

        return try JSONSerialization.data(withJSONObject: requestDict)
    }

    static func encodeClaudeRequest(_ request: ClaudeRequest) throws -> Data {
        var requestDict: [String: Any] = [
            "model": request.model,
            "max_tokens": request.max_tokens,
            "temperature": request.temperature,
            "messages": encodeClaudeMessages(request.messages)
        ]

        if let tools = request.tools {
            requestDict["tools"] = encodeClaudeTools(tools)
        }

        return try JSONSerialization.data(withJSONObject: requestDict)
    }

    static func encodeOpenAIMessages(_ messages: [OpenAIMessage]) -> [[String: Any]] {
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

    static func encodeClaudeMessages(_ messages: [ClaudeMessage]) -> [[String: Any]] {
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

    static func encodeOpenAITools(_ tools: [OpenAITool]) -> [[String: Any]] {
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

    static func encodeClaudeTools(_ tools: [ClaudeTool]) -> [[String: Any]] {
        return tools.map { tool in
            [
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.input_schema
            ]
        }
    }
}