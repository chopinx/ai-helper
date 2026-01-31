import Foundation
import EventKit
import os.log

class RemindersMCPServer: MCPServer {
    private let eventStore = EKEventStore()
    private var isAuthorized = false
    private let logger = Logger(subsystem: "com.aihelper.mcp", category: "RemindersMCPServer")

    func initialize() async throws {
        try await requestRemindersAccess()
    }

    func listTools() async throws -> [MCPTool] {
        return [
            MCPTool(
                name: "create_reminder",
                description: "Create a new reminder",
                parameters: [
                    MCPParameter(name: "title", type: "string", description: "The reminder title", required: true),
                    MCPParameter(name: "due_date", type: "string", description: "Due date in ISO 8601 format (optional)", required: false),
                    MCPParameter(name: "notes", type: "string", description: "Optional reminder notes", required: false),
                    MCPParameter(name: "priority", type: "integer", description: "Priority level: 0 (none), 1 (high), 5 (medium), 9 (low)", required: false)
                ]
            ),
            MCPTool(
                name: "list_reminders",
                description: "List all reminders",
                parameters: [
                    MCPParameter(name: "include_completed", type: "boolean", description: "Include completed reminders (default: false)", required: false)
                ]
            ),
            MCPTool(
                name: "complete_reminder",
                description: "Mark a reminder as completed",
                parameters: [
                    MCPParameter(name: "title", type: "string", description: "Title of the reminder to complete", required: true)
                ]
            ),
            MCPTool(
                name: "delete_reminder",
                description: "Delete a reminder",
                parameters: [
                    MCPParameter(name: "title", type: "string", description: "Title of the reminder to delete", required: true)
                ]
            ),
            MCPTool(
                name: "search_reminders",
                description: "Search for reminders by title or content",
                parameters: [
                    MCPParameter(name: "query", type: "string", description: "Search query for reminder titles or notes", required: true)
                ]
            )
        ]
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPResult {
        guard isAuthorized else {
            let error = MCPError.permissionDenied("Reminders access not granted")
            MCPLogger.logError(context: "Reminders tool call - \(name)", error: error)
            throw error
        }

        MCPLogger.logToolCall(server: "RemindersMCPServer", tool: name, arguments: arguments)
        let startTime = CFAbsoluteTimeGetCurrent()

        do {
            let result: MCPResult

            switch name {
            case "create_reminder":
                result = try await createReminder(arguments: arguments)
            case "list_reminders":
                result = try await listReminders(arguments: arguments)
            case "complete_reminder":
                result = try await completeReminder(arguments: arguments)
            case "delete_reminder":
                result = try await deleteReminder(arguments: arguments)
            case "search_reminders":
                result = try await searchReminders(arguments: arguments)
            default:
                let error = MCPError.toolNotFound(name)
                MCPLogger.logError(context: "Reminders tool call", error: error)
                throw error
            }

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            MCPLogger.logToolResult(server: "RemindersMCPServer", tool: name, result: result, duration: duration)

            return result

        } catch {
            _ = CFAbsoluteTimeGetCurrent() - startTime
            MCPLogger.logError(context: "Reminders tool execution - \(name)", error: error)
            throw error
        }
    }

    private func requestRemindersAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        MCPLogger.logToolCall(server: "RemindersMCPServer", tool: "requestPermission", arguments: ["currentStatus": "\(status.rawValue)"])

        switch status {
        case .fullAccess, .authorized:
            isAuthorized = true
            MCPLogger.logToolResult(server: "RemindersMCPServer", tool: "requestPermission",
                                  result: MCPResult(message: "Already authorized", isError: false), duration: 0)
        case .notDetermined:
            if #available(iOS 17.0, *) {
                let granted = try await eventStore.requestFullAccessToReminders()
                isAuthorized = granted
                if !granted {
                    let error = MCPError.permissionDenied("Reminders access denied by user")
                    MCPLogger.logError(context: "Reminders permission request", error: error)
                    throw error
                } else {
                    MCPLogger.logToolResult(server: "RemindersMCPServer", tool: "requestPermission",
                                          result: MCPResult(message: "Full access granted", isError: false), duration: 0)
                }
            } else {
                let granted = try await eventStore.requestAccess(to: .reminder)
                isAuthorized = granted
                if !granted {
                    let error = MCPError.permissionDenied("Reminders access denied by user")
                    MCPLogger.logError(context: "Reminders permission request", error: error)
                    throw error
                } else {
                    MCPLogger.logToolResult(server: "RemindersMCPServer", tool: "requestPermission",
                                          result: MCPResult(message: "Access granted", isError: false), duration: 0)
                }
            }
        case .denied, .restricted:
            let error = MCPError.permissionDenied("Reminders access is denied or restricted")
            MCPLogger.logError(context: "Reminders permission check", error: error)
            throw error
        case .writeOnly:
            let error = MCPError.permissionDenied("Reminders access is write-only, need full access")
            MCPLogger.logError(context: "Reminders permission check", error: error)
            throw error
        @unknown default:
            let error = MCPError.permissionDenied("Unknown reminders access status")
            MCPLogger.logError(context: "Reminders permission check", error: error)
            throw error
        }
    }

    private func createReminder(arguments: [String: Any]) async throws -> MCPResult {
        guard let title = arguments["title"] as? String else {
            throw MCPError.invalidArguments("Missing required field: title")
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        // Set due date if provided
        if let dueDateString = arguments["due_date"] as? String {
            let dateFormatter = ISO8601DateFormatter()
            if let dueDate = dateFormatter.date(from: dueDateString) {
                let dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
                reminder.dueDateComponents = dueDateComponents
            }
        }

        // Set notes if provided
        if let notes = arguments["notes"] as? String {
            reminder.notes = notes
        }

        // Set priority if provided (0 = none, 1 = high, 5 = medium, 9 = low)
        if let priority = arguments["priority"] as? Int {
            reminder.priority = priority
        }

        do {
            try eventStore.save(reminder, commit: true)
            var message = "Reminder '\(title)' created successfully"
            if let dueComponents = reminder.dueDateComponents,
               let dueDate = Calendar.current.date(from: dueComponents) {
                message += " (due: \(DateFormatter.localizedString(from: dueDate, dateStyle: .medium, timeStyle: .short)))"
            }
            return MCPResult(message: message, isError: false)
        } catch {
            throw MCPError.operationFailed("Failed to create reminder: \(error.localizedDescription)")
        }
    }

    private func listReminders(arguments: [String: Any]) async throws -> MCPResult {
        let includeCompleted = arguments["include_completed"] as? Bool ?? false

        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForReminders(in: calendars)

        let reminders = await fetchReminders(with: predicate)

        let filteredReminders = includeCompleted ? reminders : reminders.filter { !$0.isCompleted }

        if filteredReminders.isEmpty {
            return MCPResult(
                message: includeCompleted ? "No reminders found" : "No incomplete reminders found",
                isError: false
            )
        }

        let remindersList = filteredReminders.map { reminder in
            var line = "• \(reminder.title ?? "Untitled")"
            if reminder.isCompleted {
                line += " [Completed]"
            }
            if let dueComponents = reminder.dueDateComponents,
               let dueDate = Calendar.current.date(from: dueComponents) {
                line += " (due: \(DateFormatter.localizedString(from: dueDate, dateStyle: .medium, timeStyle: .short)))"
            }
            if reminder.priority > 0 {
                let priorityText = reminder.priority == 1 ? "High" : (reminder.priority == 5 ? "Medium" : "Low")
                line += " [\(priorityText) priority]"
            }
            return line
        }.joined(separator: "\n")

        return MCPResult(
            message: "Found \(filteredReminders.count) reminders:\n\n\(remindersList)",
            isError: false
        )
    }

    private func completeReminder(arguments: [String: Any]) async throws -> MCPResult {
        guard let title = arguments["title"] as? String else {
            throw MCPError.invalidArguments("Missing required field: title")
        }

        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForReminders(in: calendars)

        let reminders = await fetchReminders(with: predicate)

        guard let reminder = reminders.first(where: { $0.title?.localizedCaseInsensitiveContains(title) == true && !$0.isCompleted }) else {
            return MCPResult(
                message: "Reminder '\(title)' not found or already completed",
                isError: true
            )
        }

        reminder.isCompleted = true
        reminder.completionDate = Date()

        do {
            try eventStore.save(reminder, commit: true)
            return MCPResult(
                message: "Reminder '\(reminder.title ?? title)' marked as completed",
                isError: false
            )
        } catch {
            throw MCPError.operationFailed("Failed to complete reminder: \(error.localizedDescription)")
        }
    }

    private func deleteReminder(arguments: [String: Any]) async throws -> MCPResult {
        guard let title = arguments["title"] as? String else {
            throw MCPError.invalidArguments("Missing required field: title")
        }

        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForReminders(in: calendars)

        let reminders = await fetchReminders(with: predicate)

        guard let reminder = reminders.first(where: { $0.title?.localizedCaseInsensitiveContains(title) == true }) else {
            return MCPResult(
                message: "Reminder '\(title)' not found",
                isError: true
            )
        }

        let reminderTitle = reminder.title ?? title

        do {
            try eventStore.remove(reminder, commit: true)
            return MCPResult(
                message: "Reminder '\(reminderTitle)' deleted successfully",
                isError: false
            )
        } catch {
            throw MCPError.operationFailed("Failed to delete reminder: \(error.localizedDescription)")
        }
    }

    private func searchReminders(arguments: [String: Any]) async throws -> MCPResult {
        guard let query = arguments["query"] as? String else {
            throw MCPError.invalidArguments("Missing required field: query")
        }

        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForReminders(in: calendars)

        let reminders = await fetchReminders(with: predicate)

        let matchingReminders = reminders.filter { reminder in
            let titleMatch = reminder.title?.localizedCaseInsensitiveContains(query) ?? false
            let notesMatch = reminder.notes?.localizedCaseInsensitiveContains(query) ?? false
            return titleMatch || notesMatch
        }

        if matchingReminders.isEmpty {
            return MCPResult(
                message: "No reminders found matching '\(query)'",
                isError: false
            )
        }

        let remindersList = matchingReminders.map { reminder in
            var line = "• \(reminder.title ?? "Untitled")"
            if reminder.isCompleted {
                line += " [Completed]"
            }
            if let dueComponents = reminder.dueDateComponents,
               let dueDate = Calendar.current.date(from: dueComponents) {
                line += " (due: \(DateFormatter.localizedString(from: dueDate, dateStyle: .medium, timeStyle: .short)))"
            }
            return line
        }.joined(separator: "\n")

        return MCPResult(
            message: "Found \(matchingReminders.count) reminders matching '\(query)':\n\n\(remindersList)",
            isError: false
        )
    }

    /// Fetch reminders using async/await pattern with withCheckedContinuation
    private func fetchReminders(with predicate: NSPredicate) async -> [EKReminder] {
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    func canHandle(message: String, context: MCPEvaluationContext, aiService: AIService, configuration: APIConfiguration) async -> MCPCapabilityResult {
        let evaluationStartTime = CFAbsoluteTimeGetCurrent()
        logger.info("Starting AI-powered reminders capability evaluation")
        logger.debug("Message to evaluate: \(message)")
        logger.debug("Context: \(context.currentDate), TZ: \(context.timeZone.identifier), Locale: \(context.locale.identifier)")

        // Create comprehensive context for AI evaluation
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short

        // Get available tools for context
        let availableTools = try? await listTools()
        let toolDescriptions = availableTools?.map { "- \($0.name): \($0.description)" }.joined(separator: "\n") ?? ""

        logger.debug("Available tools for evaluation context: \(availableTools?.count ?? 0) tools")
        logger.debug("Conversation history: \(context.conversationHistory.count) messages")

        let evaluationPrompt = """
        You are an expert AI assistant evaluating whether a Reminders Management Server should handle a user's message.

        ## Current Context:
        - Current Date/Time: \(dateFormatter.string(from: context.currentDate))
        - User Timezone: \(context.timeZone.identifier)
        - User Locale: \(context.locale.identifier)
        - Platform: \(context.deviceInfo["platform"] ?? "Unknown")

        ## Recent Conversation History:
        \(context.conversationHistory.isEmpty ? "No previous messages" : context.conversationHistory.joined(separator: "\n"))

        ## Reminders Server Capabilities:
        This server can manage iOS reminders with these tools:
        \(toolDescriptions)

        ## User Message to Evaluate:
        "\(message)"

        ## Evaluation Task:
        Analyze the user's message and determine:
        1. Can this Reminders Server help with the request?
        2. What's the confidence level (0.0 to 1.0)?
        3. Which tools would be most appropriate?
        4. What's your reasoning?

        Consider these factors:
        - Intent behind the message (explicit and implicit)
        - Time/date references (absolute, relative, implied)
        - Reminder-related actions (create, view, complete, delete, search)
        - Task/to-do related language
        - Context from conversation history
        - Natural language patterns beyond keywords
        - User's probable needs and goals

        ## Response Format:
        Respond with ONLY this JSON format:
        {
            "canHandle": true/false,
            "confidence": 0.0-1.0,
            "suggestedTools": ["tool1", "tool2"],
            "reasoning": "Detailed explanation of analysis and decision"
        }

        Be thorough in your analysis. Consider edge cases and implicit requests. Focus on user intent rather than specific keywords.
        """

        logger.debug("Evaluation prompt length: \(evaluationPrompt.count) chars")

        do {
            let aiStartTime = CFAbsoluteTimeGetCurrent()
            logger.info("Sending evaluation request to AI service...")

            let aiResponse = try await aiService.sendMessageWithoutContext(evaluationPrompt, configuration: configuration)

            let aiDuration = CFAbsoluteTimeGetCurrent() - aiStartTime
            logger.info("AI evaluation response received - Duration: \(String(format: "%.3f", aiDuration))s, Length: \(aiResponse.count) chars")
            logger.debug("Raw AI Response: \(aiResponse)")

            // Parse JSON response
            if let jsonData = aiResponse.data(using: .utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {

                let canHandle = jsonObject["canHandle"] as? Bool ?? false
                let confidence = jsonObject["confidence"] as? Double ?? 0.0
                let suggestedTools = jsonObject["suggestedTools"] as? [String] ?? []
                let reasoning = jsonObject["reasoning"] as? String ?? "AI evaluation completed"

                let totalDuration = CFAbsoluteTimeGetCurrent() - evaluationStartTime
                logger.info("JSON Parsing Success - CanHandle: \(canHandle), Confidence: \(String(format: "%.2f", confidence)), Tools: [\(suggestedTools.joined(separator: ", "))]")
                logger.debug("AI Reasoning: \(reasoning)")
                logger.info("Total Evaluation Time: \(String(format: "%.3f", totalDuration))s (AI: \(String(format: "%.3f", aiDuration))s, Processing: \(String(format: "%.3f", totalDuration - aiDuration))s)")

                return MCPCapabilityResult(
                    canHandle: canHandle,
                    confidence: confidence,
                    suggestedTools: suggestedTools,
                    reasoning: reasoning
                )
            } else {
                logger.warning("JSON parsing failed, attempting fallback parsing...")
                logger.debug("Response content analysis: contains JSON braces: \(aiResponse.contains("{") && aiResponse.contains("}"))")

                // Fallback: try to parse a simpler response
                let canHandle = aiResponse.lowercased().contains("\"canhandle\": true") ||
                               aiResponse.lowercased().contains("can handle this request")

                // Extract confidence if possible
                let confidenceRegex = try? NSRegularExpression(pattern: "\"confidence\":\\s*(\\d+\\.?\\d*)", options: [])
                var confidence = 0.0
                if let regex = confidenceRegex,
                   let match = regex.firstMatch(in: aiResponse, options: [], range: NSRange(location: 0, length: aiResponse.count)),
                   let confidenceRange = Range(match.range(at: 1), in: aiResponse) {
                    confidence = Double(String(aiResponse[confidenceRange])) ?? 0.0
                    logger.debug("Extracted confidence via regex: \(confidence)")
                }

                let totalDuration = CFAbsoluteTimeGetCurrent() - evaluationStartTime
                logger.info("Fallback Parsing Complete - CanHandle: \(canHandle), Confidence: \(String(format: "%.2f", confidence)), Duration: \(String(format: "%.3f", totalDuration))s")

                return MCPCapabilityResult(
                    canHandle: canHandle,
                    confidence: confidence,
                    suggestedTools: canHandle ? ["create_reminder"] : [],
                    reasoning: "AI analysis (fallback parsing): \(aiResponse.prefix(200))..."
                )
            }
        } catch {
            let errorDuration = CFAbsoluteTimeGetCurrent() - evaluationStartTime
            logger.error("AI evaluation failed after \(String(format: "%.3f", errorDuration))s: \(error.localizedDescription)")
            logger.info("Falling back to basic keyword analysis...")

            // Fallback to basic analysis if AI fails
            let keywords = ["reminder", "remind", "todo", "to-do", "task", "complete", "done", "finish", "check off"]
            let messageLower = message.lowercased()
            let matchedKeywords = keywords.filter { messageLower.contains($0) }
            let hasRemindersIntent = !matchedKeywords.isEmpty

            logger.debug("Keyword analysis - Matched: [\(matchedKeywords.joined(separator: ", "))], Intent detected: \(hasRemindersIntent)")

            let totalDuration = CFAbsoluteTimeGetCurrent() - evaluationStartTime
            logger.info("Basic Fallback Complete - CanHandle: \(hasRemindersIntent), Duration: \(String(format: "%.3f", totalDuration))s")

            return MCPCapabilityResult(
                canHandle: hasRemindersIntent,
                confidence: hasRemindersIntent ? 0.7 : 0.1,
                suggestedTools: hasRemindersIntent ? ["create_reminder"] : [],
                reasoning: "AI evaluation failed (\(error.localizedDescription)), used basic fallback analysis. Matched keywords: [\(matchedKeywords.joined(separator: ", "))]"
            )
        }
    }

    func getServerName() -> String {
        return "Reminders Server"
    }

    func getServerDescription() -> String {
        return "Manages reminders and to-do items using iOS EventKit"
    }
}
