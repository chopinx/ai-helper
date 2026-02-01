import Foundation
import os.log

/// AI service with ReAct (Review-Plan-Execute-Validate) loop workflow
/// Iterates until task is complete, needs user input, or max iterations reached
class SimpleAIService {
    private let logger = Logger(subsystem: "com.aihelper", category: "SimpleAIService")
    private let calendarServer = CalendarMCPServer()
    private let remindersServer = RemindersMCPServer()
    private let maxIterations = 5

    // Calendar tool names for routing
    private let calendarTools = ["list_events", "create_event", "update_event", "delete_event", "search_events", "get_event_details", "get_upcoming_events"]

    // Tools requiring user confirmation before execution
    private let confirmationRequiredTools = ["delete_event", "update_event", "delete_reminder", "complete_reminder"]

    init() {
        Task {
            try? await calendarServer.initialize()
            try? await remindersServer.initialize()
        }
    }

    // MARK: - Public API

    func chat(
        message: String,
        history: [ChatMessage],
        config: APIConfiguration,
        onStatusUpdate: ((ProcessingStatus) -> Void)? = nil,
        onProcessUpdate: ((ProcessUpdate) -> Void)? = nil,
        onPendingAction: ((PendingAction) -> Void)? = nil
    ) async throws -> String {
        logger.info("Chat request: \(message.prefix(50))...")

        // Load tools from both servers
        onStatusUpdate?(.loadingTools)
        let calendarToolList = try await calendarServer.listTools().map { $0.toTool() }
        let reminderToolList = try await remindersServer.listTools().map { $0.toTool() }
        let tools = calendarToolList + reminderToolList
        logger.info("Available tools: \(tools.map { $0.name }.joined(separator: ", "))")
        onProcessUpdate?(.toolsLoaded(tools.map { $0.name }))

        // Build initial messages
        var messages = buildMessages(history: history, currentMessage: message)
        var eventMetadata: [String: String]? = nil
        var iteration = 0

        // ReAct Loop: Review → Plan → Execute → Validate → (Loop or Reply)
        while iteration < maxIterations {
            iteration += 1
            onStatusUpdate?(.thinkingStep(iteration))
            onProcessUpdate?(.iterationStarted(iteration))
            logger.info("=== Iteration \(iteration) ===")

            // Call API (AI reviews context, plans, and may call tools)
            let (responseText, toolCalls) = try await callAPI(messages: messages, tools: tools, config: config)

            // No tool calls = AI is ready to reply to user
            if toolCalls.isEmpty {
                logger.info("No tools called - AI ready to respond")
                onProcessUpdate?(.completed)
                return appendEventMarker(responseText, metadata: eventMetadata)
            }

            // Execute all tool calls
            logger.info("Executing \(toolCalls.count) tool calls")
            var toolResults: [ToolResult] = []

            // First pass: collect all confirmation-required tools
            var pendingActions: [PendingAction] = []
            var executableCalls: [ToolCall] = []

            for call in toolCalls {
                let isCalendarTool = calendarTools.contains(call.name)
                if confirmationRequiredTools.contains(call.name) {
                    let pendingAction = createPendingAction(toolName: call.name, arguments: call.arguments, isCalendar: isCalendarTool)
                    pendingActions.append(pendingAction)
                } else {
                    executableCalls.append(call)
                }
            }

            // If any tools need confirmation, add them all and return
            if !pendingActions.isEmpty, let onPendingAction = onPendingAction {
                for action in pendingActions {
                    onPendingAction(action)
                }
                onProcessUpdate?(.completed)
                let count = pendingActions.count
                return "I need your confirmation to proceed with \(count) action\(count > 1 ? "s" : ""). Please review and confirm."
            }

            // Second pass: execute tools that don't need confirmation
            for call in executableCalls {
                let isCalendarTool = calendarTools.contains(call.name)
                onStatusUpdate?(.callingTool(call.name))
                onProcessUpdate?(.toolCallStarted(name: call.name, isCalendar: isCalendarTool))
                logger.info("Tool: \(call.name)")

                do {
                    // Route to correct server based on tool name
                    let result = if isCalendarTool {
                        try await calendarServer.callTool(name: call.name, arguments: call.arguments)
                    } else {
                        try await remindersServer.callTool(name: call.name, arguments: call.arguments)
                    }
                    onStatusUpdate?(.processingToolResult(call.name))
                    onProcessUpdate?(.toolCallCompleted(name: call.name, success: !result.isError, message: result.message))
                    toolResults.append(ToolResult(callId: call.id, content: result.message, isError: result.isError))
                    logger.info("Result: \(result.isError ? "ERROR" : "OK") - \(result.message.prefix(80))...")

                    // Capture metadata for UI button (calendar events or reminders)
                    if let action = result.metadata["action"], ["created", "updated"].contains(action) {
                        eventMetadata = result.metadata
                    }
                } catch {
                    onProcessUpdate?(.toolCallCompleted(name: call.name, success: false, message: error.localizedDescription))
                    toolResults.append(ToolResult(callId: call.id, content: "Error: \(error.localizedDescription)", isError: true))
                    logger.error("Tool error: \(error.localizedDescription)")
                }
            }

            // Append tool interaction to messages for next iteration
            messages = appendToolInteraction(messages: messages, responseText: responseText, toolCalls: toolCalls, toolResults: toolResults, config: config)

            // Mark iteration complete
            onProcessUpdate?(.iterationCompleted)

            // Check if any tool had errors - AI will review and decide next action
            let hasErrors = toolResults.contains { $0.isError }
            if hasErrors {
                logger.info("Tool errors detected - AI will review and retry or report")
            }
        }

        // Max iterations reached - get final response
        logger.warning("Max iterations (\(self.maxIterations)) reached")
        onStatusUpdate?(.generatingResponse)
        let (finalResponse, _) = try await callAPI(messages: messages, tools: [], config: config)
        return appendEventMarker(finalResponse, metadata: eventMetadata)
    }

    // MARK: - Private Methods

    private func appendEventMarker(_ response: String, metadata: [String: String]?) -> String {
        guard let m = metadata, let action = m["action"] else { return response }

        // Calendar event marker
        if let eventId = m["eventId"], !eventId.isEmpty,
           let title = m["eventTitle"],
           let timestamp = m["startTimestamp"] {
            return response + "\n\n[[CALENDAR_EVENT||\(eventId)||\(title)||\(timestamp)||\(action)]]"
        }

        // Reminder marker
        if let reminderId = m["reminderId"], !reminderId.isEmpty,
           let title = m["reminderTitle"],
           let timestamp = m["dueTimestamp"] {
            return response + "\n\n[[REMINDER||\(reminderId)||\(title)||\(timestamp)||\(action)]]"
        }

        return response
    }

    private func createPendingAction(toolName: String, arguments: [String: Any], isCalendar: Bool) -> PendingAction {
        let type: PendingActionType
        switch toolName {
        case "delete_event", "delete_reminder": type = .delete
        case "update_event": type = .update
        case "complete_reminder": type = .complete
        default: type = .update
        }

        let title = arguments["title"] as? String ?? arguments["event_id"] as? String ?? "Item"
        var details = ""
        if let notes = arguments["notes"] as? String { details += notes }
        if let startDate = arguments["start_date"] as? String { details += " Start: \(startDate)" }

        return PendingAction(
            type: type,
            toolName: toolName,
            arguments: arguments,
            title: title,
            details: details.isEmpty ? "No additional details" : details,
            isCalendar: isCalendar
        )
    }

    /// Execute a confirmed pending action
    func executeConfirmedAction(_ action: PendingAction) async throws -> MCPResult {
        if action.isCalendar {
            return try await calendarServer.callTool(name: action.toolName, arguments: action.arguments)
        } else {
            return try await remindersServer.callTool(name: action.toolName, arguments: action.arguments)
        }
    }

    private func buildMessages(history: [ChatMessage], currentMessage: String) -> [[String: Any]] {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: Date())
        df.dateFormat = "HH:mm"
        let time = df.string(from: Date())

        var messages: [[String: Any]] = [[
            "role": "system",
            "content": """
            You are an intelligent AI assistant that follows a structured workflow to complete tasks.

            # WORKFLOW: ReAct Loop (Review → Plan → Execute → Validate)

            For each user request, follow this cycle:

            ## 1. REVIEW
            - Analyze the user's request and current context
            - Check what information you already have
            - Identify what information is missing

            ## 2. PLAN
            - Decide which tools (if any) are needed
            - Plan the sequence of actions
            - Consider potential issues or edge cases

            ## 3. EXECUTE
            - Call the necessary tools
            - Wait for results before proceeding

            ## 4. VALIDATE (Critical!)
            - Do NOT trust tool success messages blindly
            - READ the data again to verify the change was applied
            - Example: After create_event, call list_events to confirm the event exists
            - If verification fails: retry the operation
            - If errors occurred: analyze why and try different approach
            - Only proceed to respond when you have VERIFIED the task is complete

            ## 5. LOOP OR REPLY
            - If task is NOT complete: go back to REVIEW with new information
            - If task IS complete: respond to user with results
            - If task CANNOT be done: explain why to user
            - If NEED MORE INFO: ask user specific questions

            # AVAILABLE SUB-AGENTS

            ## 📅 Calendar Secretary
            Triggers: scheduling, meetings, events, appointments, calendar queries
            Tools: list_events, create_event, update_event, delete_event, search_events
            Behaviors:
            - ALWAYS check existing schedule before creating events (call list_events first)
            - Default duration: 1 hour
            - Warn about conflicts
            - Summarize workload (e.g., "4 meetings, 5 hours total")

            ## ✅ Reminders Manager
            Triggers: reminders, todos, tasks, to-do list, things to do, remind me
            Tools: create_reminder, list_reminders, complete_reminder, delete_reminder, search_reminders, get_today_reminders, get_overdue_reminders
            Behaviors:
            - List existing reminders before creating duplicates (call list_reminders first)
            - Default priority: none (0)
            - Confirm before deleting
            - After complete/delete, verify by listing again
            - Use get_today_reminders for daily task review
            - Use get_overdue_reminders to find missed tasks

            ## 💬 General Assistant
            Triggers: general questions, conversation, advice
            No tools needed - respond directly

            # TOOL USAGE RULES

            1. **Check before create**:
               - Calendar: list_events before create_event to check conflicts
               - Reminders: list_reminders before create_reminder to avoid duplicates
            2. **Verify after write**: After create/update/delete, READ the data again to confirm success
               - Created event? → list_events to verify it exists
               - Updated event? → list_events to verify changes applied
               - Deleted event? → list_events to verify it's gone
               - Created reminder? → list_reminders to verify it exists
               - Completed reminder? → list_reminders to verify status
               - Deleted reminder? → list_reminders to verify it's gone
            3. **Handle errors**: If a tool fails or verification fails, retry with different approach
            4. **One goal at a time**: Complete one task fully before moving to next
            5. **Only respond when verified**: Do NOT respond to user until you have VERIFIED the task is complete

            # DATE FORMAT

            For calendar tools: "YYYY-MM-DD HH:mm"
            Examples: "2026-02-01 10:00", "2026-02-01 14:30"

            # CONTEXT

            Today: \(today)
            Time: \(time)

            # LANGUAGE

            Respond in user's language (Chinese if they write Chinese, English if English).

            # IMPORTANT

            - Do NOT respond to user until task is complete or you need their input
            - If tools return errors, analyze and retry before giving up
            - Be thorough but efficient - minimize unnecessary tool calls
            """
        ]]

        // Add history
        for msg in history.suffix(10) {
            messages.append(["role": msg.isUser ? "user" : "assistant", "content": msg.content])
        }

        // Add current message
        messages.append(["role": "user", "content": currentMessage])
        return messages
    }

    private func callAPI(messages: [[String: Any]], tools: [Tool], config: APIConfiguration) async throws -> (String, [ToolCall]) {
        switch config.provider {
        case .openai: return try await callOpenAI(messages: messages, tools: tools, config: config)
        case .claude: return try await callClaude(messages: messages, tools: tools, config: config)
        }
    }

    // MARK: - OpenAI API

    private func callOpenAI(messages: [[String: Any]], tools: [Tool], config: APIConfiguration) async throws -> (String, [ToolCall]) {
        var body: [String: Any] = [
            "model": config.model,
            "messages": messages,
            "max_tokens": config.maxTokens,
            "temperature": config.temperature
        ]
        if !tools.isEmpty { body["tools"] = tools.map { $0.toOpenAI() } }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw AIError.apiError("OpenAI error: \(String(data: data, encoding: .utf8) ?? "Unknown")")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw AIError.invalidResponse
        }

        let content = message["content"] as? String ?? ""
        var toolCalls: [ToolCall] = []

        if let rawCalls = message["tool_calls"] as? [[String: Any]] {
            for tc in rawCalls {
                guard let id = tc["id"] as? String,
                      let fn = tc["function"] as? [String: Any],
                      let name = fn["name"] as? String,
                      let argsStr = fn["arguments"] as? String,
                      let args = try? JSONSerialization.jsonObject(with: argsStr.data(using: .utf8)!) as? [String: Any] else { continue }
                toolCalls.append(ToolCall(id: id, name: name, arguments: args))
            }
        }
        return (content, toolCalls)
    }

    // MARK: - Claude API

    private func callClaude(messages: [[String: Any]], tools: [Tool], config: APIConfiguration) async throws -> (String, [ToolCall]) {
        var systemPrompt = ""
        var claudeMessages: [[String: Any]] = []

        for msg in messages {
            guard let role = msg["role"] as? String, let content = msg["content"] else { continue }
            if role == "system" {
                systemPrompt = content as? String ?? ""
            } else {
                claudeMessages.append(["role": role, "content": content])
            }
        }

        var body: [String: Any] = [
            "model": config.model,
            "messages": claudeMessages,
            "max_tokens": config.maxTokens,
            "temperature": config.temperature
        ]
        if !systemPrompt.isEmpty { body["system"] = systemPrompt }
        if !tools.isEmpty { body["tools"] = tools.map { $0.toClaude() } }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, 200...299 ~= http.statusCode else {
            throw AIError.apiError("Claude error: \(String(data: data, encoding: .utf8) ?? "Unknown")")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = json["content"] as? [[String: Any]] else {
            throw AIError.invalidResponse
        }

        var text = ""
        var toolCalls: [ToolCall] = []

        for block in contentArray {
            guard let type = block["type"] as? String else { continue }
            if type == "text", let t = block["text"] as? String { text += t }
            else if type == "tool_use",
                    let id = block["id"] as? String,
                    let name = block["name"] as? String,
                    let input = block["input"] as? [String: Any] {
                toolCalls.append(ToolCall(id: id, name: name, arguments: input))
            }
        }
        return (text, toolCalls)
    }

    // MARK: - Tool Result Handling

    private func appendToolInteraction(messages: [[String: Any]], responseText: String, toolCalls: [ToolCall], toolResults: [ToolResult], config: APIConfiguration) -> [[String: Any]] {
        var msgs = messages

        switch config.provider {
        case .openai:
            var assistantMsg: [String: Any] = ["role": "assistant"]
            if !responseText.isEmpty { assistantMsg["content"] = responseText }
            assistantMsg["tool_calls"] = toolCalls.map { [
                "id": $0.id, "type": "function",
                "function": ["name": $0.name, "arguments": (try? JSONSerialization.data(withJSONObject: $0.arguments)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"]
            ]}
            msgs.append(assistantMsg)
            for r in toolResults {
                msgs.append(["role": "tool", "tool_call_id": r.callId, "content": r.content])
            }

        case .claude:
            var content: [[String: Any]] = []
            if !responseText.isEmpty { content.append(["type": "text", "text": responseText]) }
            for tc in toolCalls {
                content.append(["type": "tool_use", "id": tc.id, "name": tc.name, "input": tc.arguments])
            }
            msgs.append(["role": "assistant", "content": content])

            var results: [[String: Any]] = []
            for r in toolResults {
                results.append(["type": "tool_result", "tool_use_id": r.callId, "content": r.content, "is_error": r.isError])
            }
            msgs.append(["role": "user", "content": results])
        }
        return msgs
    }
}

// MARK: - Error Types

enum AIError: Error, LocalizedError {
    case invalidResponse
    case apiError(String)
    case noAPIKey

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from AI"
        case .apiError(let msg): return msg
        case .noAPIKey: return "API key not configured"
        }
    }
}
