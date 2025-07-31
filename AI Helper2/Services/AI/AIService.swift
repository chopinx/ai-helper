import Foundation
import UIKit
import os.log

// MARK: - Tool Calling Support

struct APITool: Codable {
    let name: String
    let description: String
    let inputSchema: APIToolInputSchema
    
    init(name: String, description: String, properties: [String: APIToolProperty] = [:], required: [String] = []) {
        self.name = name
        self.description = description
        self.inputSchema = APIToolInputSchema(type: "object", properties: properties, required: required)
    }
}

struct APIToolInputSchema: Codable {
    let type: String
    let properties: [String: APIToolProperty]
    let required: [String]
}

class APIToolProperty: Codable {
    let type: String
    let description: String
    let items: APIToolProperty?
    
    init(type: String, description: String, items: APIToolProperty? = nil) {
        self.type = type
        self.description = description
        self.items = items
    }
}

struct ToolCall: Codable {
    let id: String
    let type: String
    let function: ToolFunction
}

struct ToolFunction: Codable {
    let name: String
    let arguments: String // JSON string
}

struct ToolResult {
    let toolCallId: String
    let content: String
    let isError: Bool
}

class AIService: ObservableObject {
    private let urlSession = URLSession.shared
    private let logger = Logger(subsystem: "com.aihelper.ai", category: "AIService")
    
    // Tool execution callback
    var toolHandler: ((String, [String: Any]) async throws -> MCPResult)?
    
    func sendMessage(_ message: String, configuration: APIConfiguration, tools: [APITool] = []) async throws -> String {
        logger.info("🚀 AI Service Request - Provider: \(configuration.provider.rawValue), Model: \(configuration.model)")
        logger.debug("📝 Original Message: \(message)")
        logger.debug("🔧 Available Tools: [\(tools.map { $0.name }.joined(separator: ", "))]")
        
        let messageWithContext = addCommonContext(to: message)
        logger.debug("📋 Message with Context: \(messageWithContext)")
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let response: String
            switch configuration.provider {
            case .openai:
                response = try await sendOpenAIMessage(messageWithContext, configuration: configuration, tools: tools)
            case .claude:
                response = try await sendClaudeMessage(messageWithContext, configuration: configuration, tools: tools)
            }
            
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logger.info("✅ AI Response Success - Duration: \(String(format: "%.3f", duration))s, Length: \(response.count) chars")
            logger.debug("💭 AI Response: \(response)")
            
            return response
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logger.error("❌ AI Request Failed - Duration: \(String(format: "%.3f", duration))s, Error: \(error.localizedDescription)")
            throw error
        }
    }
    
    // Internal method for system prompts that already have context
    func sendMessageWithoutContext(_ message: String, configuration: APIConfiguration, tools: [APITool] = []) async throws -> String {
        switch configuration.provider {
        case .openai:
            return try await sendOpenAIMessage(message, configuration: configuration, tools: tools)
        case .claude:
            return try await sendClaudeMessage(message, configuration: configuration, tools: tools)
        }
    }
    
    private func addCommonContext(to message: String) -> String {
        let now = Date()
        let calendar = Calendar.current
        let timeZone = TimeZone.current
        
        // Full date and time
        let fullDateFormatter = DateFormatter()
        fullDateFormatter.dateStyle = .full
        fullDateFormatter.timeStyle = .short
        
        // ISO format for easy parsing
        let isoDateFormatter = DateFormatter()
        isoDateFormatter.dateFormat = "yyyy-MM-dd"
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        
        // Calculate relative dates
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: now) ?? now
        
        // Device/app context
        let locale = Locale.current
        let deviceModel = UIDevice.current.model
        
        let context = """
        Current context:
        - Current date and time: \(fullDateFormatter.string(from: now))
        - Today: \(isoDateFormatter.string(from: now)) (\(dayFormatter.string(from: now)))
        - Current time: \(timeFormatter.string(from: now))
        - Tomorrow: \(isoDateFormatter.string(from: tomorrow)) (\(dayFormatter.string(from: tomorrow)))
        - Next week (same day): \(isoDateFormatter.string(from: nextWeek))
        - Time zone: \(timeZone.identifier) (\(timeZone.abbreviation(for: now) ?? ""))
        - Week of year: \(calendar.component(.weekOfYear, from: now))
        - Device: \(deviceModel)
        - Locale: \(locale.identifier)
        
        User message: \(message)
        """
        
        return context
    }
    
    private func sendOpenAIMessage(_ message: String, configuration: APIConfiguration, tools: [APITool] = []) async throws -> String {
        let url = URL(string: "\(configuration.provider.baseURL)/chat/completions")!
        logger.debug("🌐 OpenAI API Call - URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey.prefix(10))...", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var requestBody: [String: Any] = [
            "model": configuration.model,
            "messages": [
                ["role": "user", "content": message]
            ],
            "max_tokens": configuration.maxTokens,
            "temperature": configuration.temperature
        ]
        
        // Add tools if provided
        if !tools.isEmpty {
            logger.info("🔧 OpenAI Tools Setup - Count: \(tools.count), Names: [\(tools.map { $0.name }.joined(separator: ", "))]")
            
            let openAITools = tools.map { tool in
                let toolDef = [
                    "type": "function",
                    "function": [
                        "name": tool.name,
                        "description": tool.description,
                        "parameters": [
                            "type": tool.inputSchema.type,
                            "properties": Dictionary(uniqueKeysWithValues: tool.inputSchema.properties.map { key, value in
                                (key, ["type": value.type, "description": value.description])
                            }),
                            "required": tool.inputSchema.required
                        ]
                    ]
                ]
                logger.debug("🛠️ Tool Definition: \(tool.name) - \(tool.description)")
                return toolDef
            }
            requestBody["tools"] = openAITools
            requestBody["tool_choice"] = "auto"
        }
        
        let requestData = try JSONSerialization.data(withJSONObject: requestBody)
        logger.debug("📤 OpenAI Request Body Size: \(requestData.count) bytes")
        request.httpBody = requestData
        
        return try await handleOpenAIResponse(request: request, tools: tools, configuration: configuration, originalMessage: message)
    }
    
    private func handleOpenAIResponse(request: URLRequest, tools: [APITool], configuration: APIConfiguration, originalMessage: String) async throws -> String {
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("❌ OpenAI Invalid HTTP Response")
            throw AIServiceError.invalidResponse
        }
        
        logger.debug("📥 OpenAI Response - Status: \(httpResponse.statusCode), Size: \(data.count) bytes")
        
        guard httpResponse.statusCode == 200 else {
            if let errorData = String(data: data, encoding: .utf8) {
                logger.error("❌ OpenAI API Error - Status: \(httpResponse.statusCode), Body: \(errorData)")
            }
            throw AIServiceError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            logger.error("❌ OpenAI Response Parse Error - Invalid JSON")
            throw AIServiceError.invalidResponse
        }
        
        logger.debug("📊 OpenAI Full Response: \(json)")
        
        guard let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any] else {
            logger.error("❌ OpenAI Response Parse Error - Missing choices/message")
            throw AIServiceError.invalidResponse
        }
        
        // Check if there are tool calls
        if let toolCalls = message["tool_calls"] as? [[String: Any]], !toolCalls.isEmpty {
            logger.info("🔧 OpenAI Tool Calls Detected - Count: \(toolCalls.count)")
            for (index, toolCall) in toolCalls.enumerated() {
                if let function = toolCall["function"] as? [String: Any],
                   let name = function["name"] as? String,
                   let arguments = function["arguments"] as? String {
                    logger.debug("🛠️ Tool Call \(index + 1): \(name) with args: \(arguments)")
                }
            }
            return try await handleOpenAIToolCalls(toolCalls: toolCalls, tools: tools, configuration: configuration, originalMessage: originalMessage)
        } else if let content = message["content"] as? String {
            logger.info("💬 OpenAI Text Response - Length: \(content.count) chars")
            logger.debug("📝 OpenAI Content: \(content)")
            return content
        } else {
            logger.error("❌ OpenAI Response Parse Error - No content or tool_calls")
            throw AIServiceError.invalidResponse
        }
    }
    
    private func handleOpenAIToolCalls(toolCalls: [[String: Any]], tools: [APITool], configuration: APIConfiguration, originalMessage: String) async throws -> String {
        var toolResults: [ToolResult] = []
        logger.info("🔄 Processing OpenAI Tool Calls - Count: \(toolCalls.count)")
        
        for (index, toolCall) in toolCalls.enumerated() {
            guard let id = toolCall["id"] as? String,
                  let function = toolCall["function"] as? [String: Any],
                  let name = function["name"] as? String,
                  let argumentsString = function["arguments"] as? String else {
                logger.error("❌ Invalid tool call format at index \(index)")
                continue
            }
            
            logger.info("🛠️ Executing Tool Call \(index + 1)/\(toolCalls.count) - Tool: \(name), ID: \(id)")
            logger.debug("📋 Raw Arguments: \(argumentsString)")
            
            do {
                // Parse arguments
                let argumentsData = argumentsString.data(using: .utf8) ?? Data()
                let arguments = try JSONSerialization.jsonObject(with: argumentsData) as? [String: Any] ?? [:]
                
                logger.debug("📊 Parsed Arguments: \(arguments)")
                
                // Execute tool via handler
                if let handler = toolHandler {
                    let startTime = CFAbsoluteTimeGetCurrent()
                    let result = try await handler(name, arguments)
                    let duration = CFAbsoluteTimeGetCurrent() - startTime
                    
                    let status = result.isError ? "❌" : "✅"
                    logger.info("\(status) Tool Execution Complete - \(name), Duration: \(String(format: "%.3f", duration))s")
                    logger.debug("📤 Tool Result: \(result.message)")
                    
                    toolResults.append(ToolResult(
                        toolCallId: id,
                        content: result.message,
                        isError: result.isError
                    ))
                } else {
                    logger.error("❌ Tool handler not configured for \(name)")
                    toolResults.append(ToolResult(
                        toolCallId: id,
                        content: "Tool handler not configured",
                        isError: true
                    ))
                }
            } catch {
                logger.error("❌ Tool execution error for \(name): \(error.localizedDescription)")
                toolResults.append(ToolResult(
                    toolCallId: id,
                    content: "Error executing tool: \(error.localizedDescription)",
                    isError: true
                ))
            }
        }
        
        logger.info("📤 Sending tool results back to OpenAI - Results: \(toolResults.count)")
        
        // Send tool results back to OpenAI
        return try await sendOpenAIWithToolResults(toolResults: toolResults, tools: tools, configuration: configuration, originalMessage: originalMessage)
    }
    
    private func sendOpenAIWithToolResults(toolResults: [ToolResult], tools: [APITool], configuration: APIConfiguration, originalMessage: String) async throws -> String {
        let url = URL(string: "\(configuration.provider.baseURL)/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        var messages: [[String: Any]] = [
            ["role": "user", "content": originalMessage]
        ]
        
        // Add tool results as messages
        for result in toolResults {
            messages.append([
                "role": "tool",
                "tool_call_id": result.toolCallId,
                "content": result.content
            ])
        }
        
        let requestBody: [String: Any] = [
            "model": configuration.model,
            "messages": messages,
            "max_tokens": configuration.maxTokens,
            "temperature": configuration.temperature
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AIServiceError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIServiceError.invalidResponse
        }
        
        return content
    }
    
    private func sendClaudeMessage(_ message: String, configuration: APIConfiguration, tools: [APITool] = []) async throws -> String {
        let url = URL(string: "\(configuration.provider.baseURL)/messages")!
        logger.debug("🌐 Claude API Call - URL: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        var requestBody: [String: Any] = [
            "model": configuration.model,
            "max_tokens": configuration.maxTokens,
            "temperature": configuration.temperature,
            "messages": [
                ["role": "user", "content": message]
            ]
        ]
        
        // Add tools if provided
        if !tools.isEmpty {
            logger.info("🔧 Claude Tools Setup - Count: \(tools.count), Names: [\(tools.map { $0.name }.joined(separator: ", "))]")
            
            let claudeTools = tools.map { tool in
                let toolDef = [
                    "name": tool.name,
                    "description": tool.description,
                    "input_schema": [
                        "type": tool.inputSchema.type,
                        "properties": Dictionary(uniqueKeysWithValues: tool.inputSchema.properties.map { key, value in
                            (key, ["type": value.type, "description": value.description])
                        }),
                        "required": tool.inputSchema.required
                    ]
                ]
                logger.debug("🛠️ Tool Definition: \(tool.name) - \(tool.description)")
                return toolDef
            }
            requestBody["tools"] = claudeTools
        }
        
        let requestData = try JSONSerialization.data(withJSONObject: requestBody)
        logger.debug("📤 Claude Request Body Size: \(requestData.count) bytes")
        request.httpBody = requestData
        
        return try await handleClaudeResponse(request: request, tools: tools, configuration: configuration, originalMessage: message)
    }
    
    private func handleClaudeResponse(request: URLRequest, tools: [APITool], configuration: APIConfiguration, originalMessage: String) async throws -> String {
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("❌ Claude Invalid HTTP Response - handleClaudeResponse:332")
            throw AIServiceError.invalidResponse
        }
        
        logger.debug("📥 Claude Response - Status: \(httpResponse.statusCode), Size: \(data.count) bytes")
        
        guard httpResponse.statusCode == 200 else {
            if let errorData = String(data: data, encoding: .utf8) {
                logger.error("❌ Claude API Error - Status: \(httpResponse.statusCode), Body: \(errorData) - handleClaudeResponse:419")
            }
            throw AIServiceError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode data"
            logger.error("❌ Claude Response Parse Error - Invalid JSON - handleClaudeResponse:426")
            logger.error("📄 Raw Response: \(rawResponse)")
            throw AIServiceError.invalidResponse
        }
        
        logger.debug("📊 Claude Full Response: \(json)")
        
        guard let content = json["content"] as? [[String: Any]] else {
            logger.error("❌ Claude Response Parse Error - Missing content array - handleClaudeResponse:435")
            logger.error("📊 Available keys: \(json.keys.joined(separator: ", "))")
            if let contentValue = json["content"] {
                let contentType = String(describing: type(of: contentValue))
                let contentString = String(describing: contentValue)
                logger.error("📄 Content type: \(contentType), Value: \(contentString)")
            }
            throw AIServiceError.invalidResponse
        }
        
        var textResults: [String] = []
        var toolCalls: [[String: Any]] = []
        
        // Process all content blocks
        for (index, contentBlock) in content.enumerated() {
            if let type = contentBlock["type"] as? String {
                logger.debug("📋 Content Block \(index): type = \(type)")
                switch type {
                case "text":
                    if let text = contentBlock["text"] as? String {
                        logger.debug("📝 Text Content: \(text)")
                        textResults.append(text)
                    }
                case "tool_use":
                    logger.info("🔧 Tool Use Block Detected")
                    if let name = contentBlock["name"] as? String,
                       let input = contentBlock["input"] as? [String: Any] {
                        logger.debug("🛠️ Tool: \(name), Input: \(input)")
                    }
                    toolCalls.append(contentBlock)
                default:
                    logger.debug("❓ Unknown content type: \(type)")
                    break
                }
            }
        }
        
        // If there are tool calls, execute them
        if !toolCalls.isEmpty {
            logger.info("🔧 Claude Tool Calls Detected - Count: \(toolCalls.count)")
            let toolResults = try await executeClaudeToolCalls(toolCalls: toolCalls)
            return try await sendClaudeWithToolResults(toolResults: toolResults, toolCalls: toolCalls, tools: tools, configuration: configuration, originalMessage: originalMessage, previousResponse: textResults.joined(separator: "\n"))
        } else {
            let finalText = textResults.joined(separator: "\n")
            logger.info("💬 Claude Text Response - Length: \(finalText.count) chars")
            logger.debug("📝 Claude Content: \(finalText)")
            return finalText
        }
    }
    
    private func executeClaudeToolCalls(toolCalls: [[String: Any]]) async throws -> [[String: Any]] {
        var results: [[String: Any]] = []
        logger.info("🔄 Processing Claude Tool Calls - Count: \(toolCalls.count)")
        
        for (index, toolCall) in toolCalls.enumerated() {
            guard let id = toolCall["id"] as? String,
                  let name = toolCall["name"] as? String,
                  let input = toolCall["input"] as? [String: Any] else {
                logger.error("❌ Invalid Claude tool call format at index \(index)")
                continue
            }
            
            logger.info("🛠️ Executing Claude Tool Call \(index + 1)/\(toolCalls.count) - Tool: \(name), ID: \(id)")
            logger.debug("📋 Tool Input: \(input)")
            
            do {
                // Execute tool via handler
                if let handler = toolHandler {
                    let startTime = CFAbsoluteTimeGetCurrent()
                    let result = try await handler(name, input)
                    let duration = CFAbsoluteTimeGetCurrent() - startTime
                    
                    let status = result.isError ? "❌" : "✅"
                    logger.info("\(status) Claude Tool Execution Complete - \(name), Duration: \(String(format: "%.3f", duration))s")
                    logger.debug("📤 Tool Result: \(result.message)")
                    
                    results.append([
                        "type": "tool_result",
                        "tool_use_id": id,
                        "content": result.message,
                        "is_error": result.isError
                    ])
                } else {
                    logger.error("❌ Tool handler not configured for \(name)")
                    results.append([
                        "type": "tool_result",
                        "tool_use_id": id,
                        "content": "Tool handler not configured",
                        "is_error": true
                    ])
                }
            } catch {
                logger.error("❌ Claude tool execution error for \(name): \(error.localizedDescription)")
                results.append([
                    "type": "tool_result",
                    "tool_use_id": id,
                    "content": "Error executing tool: \(error.localizedDescription)",
                    "is_error": true
                ])
            }
        }
        
        logger.info("📤 Sending Claude tool results back - Results: \(results.count)")
        return results
    }
    
    private func sendClaudeWithToolResults(toolResults: [[String: Any]], toolCalls: [[String: Any]], tools: [APITool], configuration: APIConfiguration, originalMessage: String, previousResponse: String) async throws -> String {
        let url = URL(string: "\(configuration.provider.baseURL)/messages")!
        logger.info("🔄 Sending Claude tool results back to API")
        logger.debug("📊 Tool Results Count: \(toolResults.count)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        // Claude requires proper conversation flow: user -> assistant (with tool_use) -> user (with tool_result)
        // Create assistant message content with both text (if any) and tool_use blocks
        var assistantContent: [[String: Any]] = []
        
        // Add any text response from the assistant first
        if !previousResponse.isEmpty {
            assistantContent.append(["type": "text", "text": previousResponse])
        }
        
        // Add the original tool_use blocks to maintain the conversation flow
        assistantContent.append(contentsOf: toolCalls)
        
        let messages: [[String: Any]] = [
            ["role": "user", "content": originalMessage],
            ["role": "assistant", "content": assistantContent],
            ["role": "user", "content": toolResults]  // tool_result blocks in user message
        ]
        
        logger.debug("📋 Claude Conversation Flow:")
        logger.debug("  1. User: \(originalMessage.prefix(50))...")
        logger.debug("  2. Assistant: \(assistantContent.count) content blocks (\(toolCalls.count) tool_use)")
        logger.debug("  3. User: \(toolResults.count) tool_result blocks")
        
        let requestBody: [String: Any] = [
            "model": configuration.model,
            "max_tokens": configuration.maxTokens,
            "temperature": configuration.temperature,
            "messages": messages
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        logger.debug("📤 Claude Tool Results Request Body Size: \(request.httpBody?.count ?? 0) bytes")
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            logger.error("❌ Claude Tool Results - Invalid HTTP Response - sendClaudeWithToolResults:568")
            throw AIServiceError.invalidResponse
        }
        
        logger.debug("📥 Claude Tool Results Response - Status: \(httpResponse.statusCode), Size: \(data.count) bytes")
        
        guard httpResponse.statusCode == 200 else {
            if let errorData = String(data: data, encoding: .utf8) {
                logger.error("❌ Claude Tool Results API Error - Status: \(httpResponse.statusCode) - sendClaudeWithToolResults:573")
                logger.error("📄 Error Response: \(errorData)")
            }
            throw AIServiceError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let rawResponse = String(data: data, encoding: .utf8) ?? "Unable to decode data"
            logger.error("❌ Claude Tool Results - Invalid JSON - sendClaudeWithToolResults:582")
            logger.error("📄 Raw Response: \(rawResponse)")
            throw AIServiceError.invalidResponse
        }
        
        logger.debug("📊 Claude Tool Results Full Response: \(json)")
        
        guard let content = json["content"] as? [[String: Any]] else {
            logger.error("❌ Claude Tool Results - Missing content array - sendClaudeWithToolResults:589")
            logger.error("📊 Available keys: \(json.keys.joined(separator: ", "))")
            if let contentValue = json["content"] {
                let contentType = String(describing: type(of: contentValue))
                let contentString = String(describing: contentValue)
                logger.error("📄 Content type: \(contentType), Value: \(contentString)")
            }
            throw AIServiceError.invalidResponse
        }
        
        guard let firstContent = content.first else {
            logger.error("❌ Claude Tool Results - Empty content array - sendClaudeWithToolResults:597")
            throw AIServiceError.invalidResponse
        }
        
        guard let text = firstContent["text"] as? String else {
            logger.error("❌ Claude Tool Results - Missing text in first content - sendClaudeWithToolResults:602")
            logger.error("📊 First content keys: \(firstContent.keys.joined(separator: ", "))")
            logger.error("📄 First content: \(firstContent)")
            throw AIServiceError.invalidResponse
        }
        
        logger.info("✅ Claude Tool Results Response Success - Length: \(text.count) chars")
        logger.debug("📝 Final Response: \(text)")
        return text
    }
}

enum AIServiceError: Error, LocalizedError {
    case invalidResponse
    case noAPIKey
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from AI service"
        case .noAPIKey:
            return "API key is required"
        case .networkError:
            return "Network error occurred"
        }
    }
}