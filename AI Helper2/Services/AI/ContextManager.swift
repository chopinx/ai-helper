import Foundation
import os.log

// MARK: - Context Manager

/// Manages conversation context with automatic compression
class ContextManager: ObservableObject {
    @Published private(set) var scratchpad: [UniMsg] = []
    private let logger = Logger(subsystem: "com.aihelper.context", category: "ContextManager")
    private let maxToolResults = 4
    
    /// Add user message to scratchpad
    func addUserMessage(_ text: String, metadata: [String: String]? = nil) {
        let message = UniMsg(role: .user, text: text, metadata: metadata)
        scratchpad.append(message)
        logger.debug("📝 Added user message to scratchpad")
    }
    
    /// Add assistant message to scratchpad
    func addMessage(_ message: UniMsg) {
        scratchpad.append(message)
        logger.debug("🤖 Added assistant message to scratchpad")
        compressIfNeeded()
    }
    
    /// Add tool results to scratchpad
    func addToolResults(_ results: [UniMsg.ToolResult], metadata: [String: String]? = nil) {
        let content = results.map { UniMsg.ContentBlock.toolResult($0) }
        let message = UniMsg(role: .tool, content: content, metadata: metadata)
        scratchpad.append(message)
        logger.debug("🔧 Added \(results.count) tool results to scratchpad")
        compressIfNeeded()
    }
    
    /// Get current messages formatted for specific provider
    func currentMessages(provider: AIProvider) -> [Any] {
        switch provider {
        case .openai:
            return convertToOpenAI(scratchpad)
        case .claude:
            return convertToClaude(scratchpad)
        }
    }
    
    /// Clear scratchpad
    func clear() {
        scratchpad.removeAll()
        logger.info("🗑️ Cleared scratchpad")
    }
    
    // MARK: - Private Methods
    
    private func compressIfNeeded() {
        let toolResultCount = scratchpad.filter { $0.role == .tool }.count
        
        if toolResultCount > maxToolResults {
            compressOldestToolResults()
        }
    }
    
    private func compressOldestToolResults() {
        logger.info("🗜️ Compressing oldest tool results")
        
        var compressedMessages: [UniMsg] = []
        var toolResultsToCompress: [UniMsg] = []
        var compressionStarted = false
        
        for message in scratchpad {
            if message.role == .tool && !compressionStarted {
                toolResultsToCompress.append(message)
                
                // Start compressing after collecting 2 tool results
                if toolResultsToCompress.count >= 2 {
                    compressionStarted = true
                    
                    // Create compressed summary
                    let summaryText = createToolResultsSummary(toolResultsToCompress)
                    let summaryMessage = UniMsg(
                        role: .assistant,
                        text: summaryText,
                        metadata: ["compressed": "true", "original_count": "\(toolResultsToCompress.count)"]
                    )
                    compressedMessages.append(summaryMessage)
                }
            } else {
                compressedMessages.append(message)
            }
        }
        
        scratchpad = compressedMessages
        logger.info("📦 Compressed \(toolResultsToCompress.count) tool results into summary")
    }
    
    private func createToolResultsSummary(_ toolResults: [UniMsg]) -> String {
        var summaryParts: [String] = []
        
        for (index, toolMessage) in toolResults.enumerated() {
            let results = toolMessage.toolResults
            for result in results {
                let status = result.isError ? "failed" : "succeeded"
                let content = result.content.prefix(100) // Truncate long results
                summaryParts.append("Tool execution \(index + 1) \(status): \(content)")
            }
        }
        
        return "Previous tool executions summary: " + summaryParts.joined(separator: "; ")
    }
    
    // MARK: - Provider Conversion
    
    private func convertToOpenAI(_ messages: [UniMsg]) -> [OpenAIMessage] {
        return messages.compactMap { message in
            switch message.role {
            case .user:
                return OpenAIMessage(role: "user", content: message.textContent)
                
            case .assistant:
                let toolCalls = message.toolCalls.isEmpty ? nil : message.toolCalls.map { toolCall in
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
                    content: message.textContent.isEmpty ? nil : message.textContent,
                    tool_calls: toolCalls
                )
                
            case .tool:
                // Convert first tool result to OpenAI format
                let toolResults = message.toolResults
                if let firstResult = toolResults.first {
                    return OpenAIMessage(
                        role: "tool",
                        content: firstResult.content,
                        tool_call_id: firstResult.toolCallId
                    )
                }
                return nil
                
            case .system:
                return OpenAIMessage(role: "system", content: message.textContent)
            }
        }
    }
    
    private func convertToClaude(_ messages: [UniMsg]) -> [ClaudeMessage] {
        return messages.compactMap { message in
            switch message.role {
            case .user:
                return ClaudeMessage(
                    role: "user",
                    content: [ClaudeContent(type: "text", text: message.textContent)]
                )
                
            case .assistant:
                var claudeContent: [ClaudeContent] = []
                
                if !message.textContent.isEmpty {
                    claudeContent.append(ClaudeContent(type: "text", text: message.textContent))
                }
                
                for toolCall in message.toolCalls {
                    claudeContent.append(ClaudeContent(
                        type: "tool_use",
                        tool_use: ClaudeToolUse(
                            id: toolCall.id,
                            name: toolCall.name,
                            input: toolCall.arguments
                        )
                    ))
                }
                
                return ClaudeMessage(role: "assistant", content: claudeContent)
                
            case .tool:
                var claudeContent: [ClaudeContent] = []
                
                for toolResult in message.toolResults {
                    claudeContent.append(ClaudeContent(
                        type: "tool_result",
                        tool_use_id: toolResult.toolCallId,
                        content: toolResult.content,
                        is_error: toolResult.isError
                    ))
                }
                
                return ClaudeMessage(role: "user", content: claudeContent)
                
            case .system:
                // System messages handled separately in Claude
                return nil
            }
        }
    }
    
    private func serializeArguments(_ arguments: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: arguments),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}