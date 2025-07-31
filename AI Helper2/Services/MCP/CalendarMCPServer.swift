import Foundation
import EventKit
import os.log

class CalendarMCPServer: MCPServer {
    private let eventStore = EKEventStore()
    private var isAuthorized = false
    private let logger = Logger(subsystem: "com.aihelper.mcp", category: "CalendarMCPServer")
    
    func initialize() async throws {
        try await requestCalendarAccess()
    }
    
    func listTools() async throws -> [MCPTool] {
        return [
            MCPTool(
                name: "create_event",
                description: "Create a new calendar event",
                parameters: [
                    MCPParameter(name: "title", type: "string", description: "The event title", required: true),
                    MCPParameter(name: "start_date", type: "string", description: "Event start date in ISO 8601 format", required: true),
                    MCPParameter(name: "end_date", type: "string", description: "Event end date in ISO 8601 format", required: true),
                    MCPParameter(name: "notes", type: "string", description: "Optional event notes", required: false)
                ]
            ),
            MCPTool(
                name: "list_events",
                description: "List calendar events for a specific date range",
                parameters: [
                    MCPParameter(name: "start_date", type: "string", description: "Start date for search in ISO 8601 format", required: false),
                    MCPParameter(name: "end_date", type: "string", description: "End date for search in ISO 8601 format", required: false)
                ]
            ),
            MCPTool(
                name: "update_event",
                description: "Update an existing calendar event",
                parameters: [
                    MCPParameter(name: "event_title", type: "string", description: "Title of the event to update", required: true),
                    MCPParameter(name: "new_title", type: "string", description: "New title for the event", required: false),
                    MCPParameter(name: "new_notes", type: "string", description: "New notes for the event", required: false),
                    MCPParameter(name: "new_start_date", type: "string", description: "New start date in ISO 8601 format", required: false),
                    MCPParameter(name: "new_end_date", type: "string", description: "New end date in ISO 8601 format", required: false)
                ]
            ),
            MCPTool(
                name: "delete_event",
                description: "Delete a calendar event",
                parameters: [
                    MCPParameter(name: "event_title", type: "string", description: "Title of the event to delete", required: true)
                ]
            ),
            MCPTool(
                name: "search_events",
                description: "Search for events by title or content",
                parameters: [
                    MCPParameter(name: "query", type: "string", description: "Search query for event titles or notes", required: true)
                ]
            ),
            MCPTool(
                name: "get_today_events",
                description: "Get all events for today",
                parameters: []
            ),
            MCPTool(
                name: "get_upcoming_events",
                description: "Get upcoming events for the next few days",
                parameters: [
                    MCPParameter(name: "days", type: "integer", description: "Number of days to look ahead (default: 7)", required: false)
                ]
            )
        ]
    }
    
    func callTool(name: String, arguments: [String : Any]) async throws -> MCPResult {
        guard isAuthorized else {
            let error = MCPError.permissionDenied("Calendar access not granted")
            MCPLogger.logError(context: "Calendar tool call - \(name)", error: error)
            throw error
        }
        
        MCPLogger.logToolCall(server: "CalendarMCPServer", tool: name, arguments: arguments)
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let result: MCPResult
            
            switch name {
            case "create_event":
                result = try await createEvent(arguments: arguments)
            case "list_events":
                result = try await listEvents(arguments: arguments)
            case "update_event":
                result = try await updateEvent(arguments: arguments)
            case "delete_event":
                result = try await deleteEvent(arguments: arguments)
            case "search_events":
                result = try await searchEvents(arguments: arguments)
            case "get_today_events":
                result = try await getTodayEvents(arguments: arguments)
            case "get_upcoming_events":
                result = try await getUpcomingEvents(arguments: arguments)
            default:
                let error = MCPError.toolNotFound(name)
                MCPLogger.logError(context: "Calendar tool call", error: error)
                throw error
            }
            
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            MCPLogger.logToolResult(server: "CalendarMCPServer", tool: name, result: result, duration: duration)
            
            return result
            
        } catch {
            _ = CFAbsoluteTimeGetCurrent() - startTime
            MCPLogger.logError(context: "Calendar tool execution - \(name)", error: error)
            throw error
        }
    }
    
    private func requestCalendarAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        MCPLogger.logToolCall(server: "CalendarMCPServer", tool: "requestPermission", arguments: ["currentStatus": "\(status.rawValue)"])
        
        switch status {
        case .fullAccess, .authorized:
            isAuthorized = true
            MCPLogger.logToolResult(server: "CalendarMCPServer", tool: "requestPermission", 
                                  result: MCPResult(message: "Already authorized", isError: false), duration: 0)
        case .notDetermined:
            if #available(iOS 17.0, *) {
                let granted = try await eventStore.requestFullAccessToEvents()
                isAuthorized = granted
                if !granted {
                    let error = MCPError.permissionDenied("Calendar access denied by user")
                    MCPLogger.logError(context: "Calendar permission request", error: error)
                    throw error
                } else {
                    MCPLogger.logToolResult(server: "CalendarMCPServer", tool: "requestPermission", 
                                          result: MCPResult(message: "Full access granted", isError: false), duration: 0)
                }
            } else {
                let granted = try await eventStore.requestAccess(to: .event)
                isAuthorized = granted
                if !granted {
                    let error = MCPError.permissionDenied("Calendar access denied by user")
                    MCPLogger.logError(context: "Calendar permission request", error: error)
                    throw error
                } else {
                    MCPLogger.logToolResult(server: "CalendarMCPServer", tool: "requestPermission", 
                                          result: MCPResult(message: "Access granted", isError: false), duration: 0)
                }
            }
        case .denied, .restricted:
            let error = MCPError.permissionDenied("Calendar access is denied or restricted")
            MCPLogger.logError(context: "Calendar permission check", error: error)
            throw error
        case .writeOnly:
            let error = MCPError.permissionDenied("Calendar access is write-only, need full access")
            MCPLogger.logError(context: "Calendar permission check", error: error)
            throw error
        @unknown default:
            let error = MCPError.permissionDenied("Unknown calendar access status")
            MCPLogger.logError(context: "Calendar permission check", error: error)
            throw error
        }
    }
    
    private func createEvent(arguments: [String: Any]) async throws -> MCPResult {
        guard let title = arguments["title"] as? String,
              let startDateString = arguments["start_date"] as? String,
              let endDateString = arguments["end_date"] as? String else {
            throw MCPError.invalidArguments("Missing required fields: title, start_date, end_date")
        }
        
        let dateFormatter = ISO8601DateFormatter()
        guard let startDate = dateFormatter.date(from: startDateString),
              let endDate = dateFormatter.date(from: endDateString) else {
            throw MCPError.invalidArguments("Invalid date format. Use ISO 8601 format.")
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = arguments["notes"] as? String
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        do {
            try eventStore.save(event, span: .thisEvent)
            return MCPResult(
                message: "Calendar event '\(title)' created successfully for \(DateFormatter.localizedString(from: startDate, dateStyle: .medium, timeStyle: .short))",
                isError: false
            )
        } catch {
            throw MCPError.operationFailed("Failed to create event: \(error.localizedDescription)")
        }
    }
    
    private func listEvents(arguments: [String: Any]) async throws -> MCPResult {
        let dateFormatter = ISO8601DateFormatter()
        
        // Default to today and next 7 days if no dates provided
        let startDate: Date
        let endDate: Date
        
        if let startDateString = arguments["start_date"] as? String,
           let endDateString = arguments["end_date"] as? String,
           let parsedStartDate = dateFormatter.date(from: startDateString),
           let parsedEndDate = dateFormatter.date(from: endDateString) {
            startDate = parsedStartDate
            endDate = parsedEndDate
        } else {
            startDate = Calendar.current.startOfDay(for: Date())
            endDate = Calendar.current.date(byAdding: .day, value: 7, to: startDate) ?? startDate
        }
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        if events.isEmpty {
            return MCPResult(
                message: "No events found between \(DateFormatter.localizedString(from: startDate, dateStyle: .medium, timeStyle: .none)) and \(DateFormatter.localizedString(from: endDate, dateStyle: .medium, timeStyle: .none))",
                isError: false
            )
        }
        
        let eventsList = events.map { event in
            let startString = DateFormatter.localizedString(from: event.startDate, dateStyle: .medium, timeStyle: .short)
            let endString = DateFormatter.localizedString(from: event.endDate, dateStyle: .none, timeStyle: .short)
            return "• \(event.title ?? "Untitled") - \(startString) to \(endString)"
        }.joined(separator: "\n")
        
        return MCPResult(
            message: "Found \(events.count) events:\n\n\(eventsList)",
            isError: false
        )
    }
    
    private func updateEvent(arguments: [String: Any]) async throws -> MCPResult {
        guard let eventTitle = arguments["event_title"] as? String else {
            throw MCPError.invalidArguments("Missing required field: event_title")
        }
        
        // Search for the event by title (simplified approach)
        let now = Date()
        let past = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let future = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        
        let predicate = eventStore.predicateForEvents(withStart: past, end: future, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        guard let event = events.first(where: { $0.title?.localizedCaseInsensitiveContains(eventTitle) == true }) else {
            return MCPResult(
                message: "Event '\(eventTitle)' not found in the last 30 days or next 30 days",
                isError: true
            )
        }
        
        // Update fields if provided
        if let newTitle = arguments["new_title"] as? String {
            event.title = newTitle
        }
        
        if let newNotesString = arguments["new_notes"] as? String {
            event.notes = newNotesString
        }
        
        if let startDateString = arguments["new_start_date"] as? String,
           let endDateString = arguments["new_end_date"] as? String {
            let dateFormatter = ISO8601DateFormatter()
            if let newStartDate = dateFormatter.date(from: startDateString),
               let newEndDate = dateFormatter.date(from: endDateString) {
                event.startDate = newStartDate
                event.endDate = newEndDate
            }
        }
        
        do {
            try eventStore.save(event, span: .thisEvent)
            return MCPResult(
                message: "Event '\(event.title ?? "Untitled")' updated successfully",
                isError: false
            )
        } catch {
            throw MCPError.operationFailed("Failed to update event: \(error.localizedDescription)")
        }
    }
    
    private func deleteEvent(arguments: [String: Any]) async throws -> MCPResult {
        guard let eventTitle = arguments["event_title"] as? String else {
            throw MCPError.invalidArguments("Missing required field: event_title")
        }
        
        // Search for the event by title
        let now = Date()
        let past = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now
        let future = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        
        let predicate = eventStore.predicateForEvents(withStart: past, end: future, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        guard let event = events.first(where: { $0.title?.localizedCaseInsensitiveContains(eventTitle) == true }) else {
            return MCPResult(
                message: "Event '\(eventTitle)' not found in the last 30 days or next 30 days",
                isError: true
            )
        }
        
        let eventTitleForMessage = event.title ?? "Untitled"
        
        do {
            try eventStore.remove(event, span: .thisEvent)
            return MCPResult(
                message: "Event '\(eventTitleForMessage)' deleted successfully",
                isError: false
            )
        } catch {
            throw MCPError.operationFailed("Failed to delete event: \(error.localizedDescription)")
        }
    }
    
    private func searchEvents(arguments: [String: Any]) async throws -> MCPResult {
        guard let query = arguments["query"] as? String else {
            throw MCPError.invalidArguments("Missing required field: query")
        }
        
        // Search in the next 3 months
        let startDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let endDate = Calendar.current.date(byAdding: .month, value: 3, to: Date()) ?? Date()
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        let matchingEvents = events.filter { event in
            let titleMatch = event.title?.localizedCaseInsensitiveContains(query) ?? false
            let notesMatch = event.notes?.localizedCaseInsensitiveContains(query) ?? false
            return titleMatch || notesMatch
        }
        
        if matchingEvents.isEmpty {
            return MCPResult(
                message: "No events found matching '\(query)'",
                isError: false
            )
        }
        
        let eventsList = matchingEvents.map { event in
            let dateString = DateFormatter.localizedString(from: event.startDate, dateStyle: .medium, timeStyle: .short)
            return "• \(event.title ?? "Untitled") - \(dateString)"
        }.joined(separator: "\n")
        
        return MCPResult(
            message: "Found \(matchingEvents.count) events matching '\(query)':\n\n\(eventsList)",
            isError: false
        )
    }
    
    private func getTodayEvents(arguments: [String: Any]) async throws -> MCPResult {
        let today = Date()
        let startOfDay = Calendar.current.startOfDay(for: today)
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? today
        
        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        if events.isEmpty {
            return MCPResult(
                message: "No events scheduled for today",
                isError: false
            )
        }
        
        let eventsList = events.map { event in
            let timeString = DateFormatter.localizedString(from: event.startDate, dateStyle: .none, timeStyle: .short)
            let endTimeString = DateFormatter.localizedString(from: event.endDate, dateStyle: .none, timeStyle: .short)
            return "• \(timeString) - \(endTimeString): \(event.title ?? "Untitled")"
        }.joined(separator: "\n")
        
        return MCPResult(
            message: "Today's events (\(events.count)):\n\n\(eventsList)",
            isError: false
        )
    }
    
    private func getUpcomingEvents(arguments: [String: Any]) async throws -> MCPResult {
        let days = arguments["days"] as? Int ?? 7
        let startDate = Calendar.current.startOfDay(for: Date())
        let endDate = Calendar.current.date(byAdding: .day, value: days, to: startDate) ?? startDate
        
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        
        if events.isEmpty {
            return MCPResult(
                message: "No upcoming events in the next \(days) days",
                isError: false
            )
        }
        
        // Group events by date
        let groupedEvents = Dictionary(grouping: events) { event in
            Calendar.current.startOfDay(for: event.startDate)
        }
        
        let sortedDates = groupedEvents.keys.sorted()
        
        var result = "Upcoming events in the next \(days) days:\n\n"
        
        for date in sortedDates {
            let dayEvents = groupedEvents[date] ?? []
            let dayString = DateFormatter.localizedString(from: date, dateStyle: .full, timeStyle: .none)
            result += "\(dayString):\n"
            
            for event in dayEvents.sorted(by: { $0.startDate < $1.startDate }) {
                let timeString = DateFormatter.localizedString(from: event.startDate, dateStyle: .none, timeStyle: .short)
                result += "  • \(timeString): \(event.title ?? "Untitled")\n"
            }
            result += "\n"
        }
        
        return MCPResult(
            message: result.trimmingCharacters(in: .whitespacesAndNewlines),
            isError: false
        )
    }
    
    func canHandle(message: String, context: MCPEvaluationContext, aiService: AIService, configuration: APIConfiguration) async -> MCPCapabilityResult {
        let evaluationStartTime = CFAbsoluteTimeGetCurrent()
        logger.info("🤖 Starting AI-powered calendar capability evaluation")
        logger.debug("📝 Message to evaluate: \(message)")
        logger.debug("🕰️ Context: \(context.currentDate), TZ: \(context.timeZone.identifier), Locale: \(context.locale.identifier)")
        
        // Create comprehensive context for AI evaluation
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .short
        
        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short
        
        // Get available tools for context
        let availableTools = try? await listTools()
        let toolDescriptions = availableTools?.map { "- \($0.name): \($0.description)" }.joined(separator: "\n") ?? ""
        
        logger.debug("🔧 Available tools for evaluation context: \(availableTools?.count ?? 0) tools")
        logger.debug("📋 Conversation history: \(context.conversationHistory.count) messages")
        
        let evaluationPrompt = """
        You are an expert AI assistant evaluating whether a Calendar Management Server should handle a user's message.
        
        ## Current Context:
        - Current Date/Time: \(dateFormatter.string(from: context.currentDate))
        - User Timezone: \(context.timeZone.identifier)
        - User Locale: \(context.locale.identifier)
        - Platform: \(context.deviceInfo["platform"] ?? "Unknown")
        
        ## Recent Conversation History:
        \(context.conversationHistory.isEmpty ? "No previous messages" : context.conversationHistory.joined(separator: "\n"))
        
        ## Calendar Server Capabilities:
        This server can manage iOS calendar events with these tools:
        \(toolDescriptions)
        
        ## User Message to Evaluate:
        "\(message)"
        
        ## Evaluation Task:
        Analyze the user's message and determine:
        1. Can this Calendar Server help with the request?
        2. What's the confidence level (0.0 to 1.0)?
        3. Which tools would be most appropriate?
        4. What's your reasoning?
        
        Consider these factors:
        - Intent behind the message (explicit and implicit)
        - Time/date references (absolute, relative, implied)
        - Calendar-related actions (create, view, modify, delete events)
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
        
        logger.debug("📤 Evaluation prompt length: \(evaluationPrompt.count) chars")
        
        do {
            let aiStartTime = CFAbsoluteTimeGetCurrent()
            logger.info("🌐 Sending evaluation request to AI service...")
            
            let aiResponse = try await aiService.sendMessageWithoutContext(evaluationPrompt, configuration: configuration)
            
            let aiDuration = CFAbsoluteTimeGetCurrent() - aiStartTime
            logger.info("✅ AI evaluation response received - Duration: \(String(format: "%.3f", aiDuration))s, Length: \(aiResponse.count) chars")
            logger.debug("💬 Raw AI Response: \(aiResponse)")
            
            // Parse JSON response
            if let jsonData = aiResponse.data(using: .utf8),
               let jsonObject = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                
                let canHandle = jsonObject["canHandle"] as? Bool ?? false
                let confidence = jsonObject["confidence"] as? Double ?? 0.0
                let suggestedTools = jsonObject["suggestedTools"] as? [String] ?? []
                let reasoning = jsonObject["reasoning"] as? String ?? "AI evaluation completed"
                
                let totalDuration = CFAbsoluteTimeGetCurrent() - evaluationStartTime
                logger.info("✅ JSON Parsing Success - CanHandle: \(canHandle), Confidence: \(String(format: "%.2f", confidence)), Tools: [\(suggestedTools.joined(separator: ", "))]")
                logger.debug("🧠 AI Reasoning: \(reasoning)")
                logger.info("⚡ Total Evaluation Time: \(String(format: "%.3f", totalDuration))s (AI: \(String(format: "%.3f", aiDuration))s, Processing: \(String(format: "%.3f", totalDuration - aiDuration))s)")
                
                return MCPCapabilityResult(
                    canHandle: canHandle,
                    confidence: confidence,
                    suggestedTools: suggestedTools,
                    reasoning: reasoning
                )
            } else {
                logger.warning("⚠️ JSON parsing failed, attempting fallback parsing...")
                logger.debug("🔍 Response content analysis: contains JSON braces: \(aiResponse.contains("{") && aiResponse.contains("}"))")
                
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
                    logger.debug("🔢 Extracted confidence via regex: \(confidence)")
                }
                
                let totalDuration = CFAbsoluteTimeGetCurrent() - evaluationStartTime
                logger.info("🔄 Fallback Parsing Complete - CanHandle: \(canHandle), Confidence: \(String(format: "%.2f", confidence)), Duration: \(String(format: "%.3f", totalDuration))s")
                
                return MCPCapabilityResult(
                    canHandle: canHandle,
                    confidence: confidence,
                    suggestedTools: canHandle ? ["create_event"] : [],
                    reasoning: "AI analysis (fallback parsing): \(aiResponse.prefix(200))..."
                )
            }
        } catch {
            let errorDuration = CFAbsoluteTimeGetCurrent() - evaluationStartTime
            logger.error("❌ AI evaluation failed after \(String(format: "%.3f", errorDuration))s: \(error.localizedDescription)")
            logger.info("🔄 Falling back to basic keyword analysis...")
            
            // Fallback to basic analysis if AI fails
            let keywords = ["calendar", "event", "meeting", "appointment", "schedule", "remind", "book"]
            let messageLower = message.lowercased()
            let matchedKeywords = keywords.filter { messageLower.contains($0) }
            let hasCalendarIntent = !matchedKeywords.isEmpty
            
            logger.debug("🔍 Keyword analysis - Matched: [\(matchedKeywords.joined(separator: ", "))], Intent detected: \(hasCalendarIntent)")
            
            let totalDuration = CFAbsoluteTimeGetCurrent() - evaluationStartTime
            logger.info("🔄 Basic Fallback Complete - CanHandle: \(hasCalendarIntent), Duration: \(String(format: "%.3f", totalDuration))s")
            
            return MCPCapabilityResult(
                canHandle: hasCalendarIntent,
                confidence: hasCalendarIntent ? 0.7 : 0.1,
                suggestedTools: hasCalendarIntent ? ["create_event"] : [],
                reasoning: "AI evaluation failed (\(error.localizedDescription)), used basic fallback analysis. Matched keywords: [\(matchedKeywords.joined(separator: ", "))]"
            )
        }
    }
    
    func getServerName() -> String {
        return "Calendar Server"
    }
    
    func getServerDescription() -> String {
        return "Manages calendar events, appointments, and scheduling tasks using iOS EventKit"
    }
}