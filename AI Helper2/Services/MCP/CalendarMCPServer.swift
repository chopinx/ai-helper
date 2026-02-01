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

    // MARK: - Date Parsing Helper

    /// Parse date string with multiple format support
    private func parseFlexibleDate(_ dateString: String) -> Date? {
        // Try ISO8601 with timezone (e.g., "2026-02-01T10:00:00Z" or "2026-02-01T10:00:00+00:00")
        let iso8601Formatter = ISO8601DateFormatter()
        iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }

        // Try ISO8601 without fractional seconds
        iso8601Formatter.formatOptions = [.withInternetDateTime]
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }

        // Try common date formats
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss",      // 2026-02-01T10:00:00
            "yyyy-MM-dd HH:mm:ss",         // 2026-02-01 10:00:00
            "yyyy-MM-dd HH:mm",            // 2026-02-01 10:00
            "yyyy-MM-dd'T'HH:mm",          // 2026-02-01T10:00
            "yyyy/MM/dd HH:mm:ss",         // 2026/02/01 10:00:00
            "yyyy/MM/dd HH:mm",            // 2026/02/01 10:00
            "MM/dd/yyyy HH:mm",            // 02/01/2026 10:00
            "dd-MM-yyyy HH:mm"             // 01-02-2026 10:00
        ]

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current

        for format in formats {
            dateFormatter.dateFormat = format
            if let date = dateFormatter.date(from: dateString) {
                return date
            }
        }

        return nil
    }

    // MARK: - Tool Implementations

    private func createEvent(arguments: [String: Any]) async throws -> MCPResult {
        guard let title = arguments["title"] as? String,
              let startDateString = arguments["start_date"] as? String,
              let endDateString = arguments["end_date"] as? String else {
            throw MCPError.invalidArguments("Missing required fields: title, start_date, end_date")
        }

        guard let startDate = parseFlexibleDate(startDateString),
              let endDate = parseFlexibleDate(endDateString) else {
            throw MCPError.invalidArguments("Invalid date format. Expected formats: '2026-02-01T10:00:00Z', '2026-02-01T10:00:00', or '2026-02-01 10:00'")
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = arguments["notes"] as? String
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        do {
            try eventStore.save(event, span: .thisEvent)

            // Include event ID for deep linking to Calendar app
            let eventId = event.eventIdentifier ?? ""
            let startTimestamp = Int(startDate.timeIntervalSince1970)

            return MCPResult(
                message: "Calendar event '\(title)' created successfully for \(DateFormatter.localizedString(from: startDate, dateStyle: .medium, timeStyle: .short))",
                isError: false,
                metadata: [
                    "eventId": eventId,
                    "eventTitle": title,
                    "startTimestamp": "\(startTimestamp)",
                    "action": "created"
                ]
            )
        } catch {
            throw MCPError.operationFailed("Failed to create event: \(error.localizedDescription)")
        }
    }

    private func listEvents(arguments: [String: Any]) async throws -> MCPResult {
        // Default to today and next 7 days if no dates provided
        let startDate: Date
        let endDate: Date
        
        if let startDateString = arguments["start_date"] as? String,
           let endDateString = arguments["end_date"] as? String,
           let parsedStartDate = parseFlexibleDate(startDateString),
           let parsedEndDate = parseFlexibleDate(endDateString) {
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
            if let newStartDate = parseFlexibleDate(startDateString),
               let newEndDate = parseFlexibleDate(endDateString) {
                event.startDate = newStartDate
                event.endDate = newEndDate
            }
        }
        
        do {
            try eventStore.save(event, span: .thisEvent)

            // Include event ID for deep linking to Calendar app
            let eventId = event.eventIdentifier ?? ""
            let startTimestamp = Int(event.startDate.timeIntervalSince1970)

            return MCPResult(
                message: "Event '\(event.title ?? "Untitled")' updated successfully",
                isError: false,
                metadata: [
                    "eventId": eventId,
                    "eventTitle": event.title ?? "Untitled",
                    "startTimestamp": "\(startTimestamp)",
                    "action": "updated"
                ]
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

    func getServerName() -> String {
        return "Calendar Server"
    }
    
    func getServerDescription() -> String {
        return "Manages calendar events, appointments, and scheduling tasks using iOS EventKit"
    }
}