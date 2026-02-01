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
        [
            MCPTool(
                name: "create_reminder",
                description: "Create a new reminder",
                parameters: [
                    MCPParameter(name: "title", type: "string", description: "The reminder title", required: true),
                    MCPParameter(name: "due_date", type: "string", description: "Due date (e.g., '2026-02-01 10:00')", required: false),
                    MCPParameter(name: "notes", type: "string", description: "Optional notes", required: false),
                    MCPParameter(name: "priority", type: "integer", description: "Priority: 0=none, 1=high, 5=medium, 9=low", required: false)
                ]
            ),
            MCPTool(
                name: "list_reminders",
                description: "List all reminders",
                parameters: [
                    MCPParameter(name: "include_completed", type: "boolean", description: "Include completed (default: false)", required: false)
                ]
            ),
            MCPTool(
                name: "complete_reminder",
                description: "Mark a reminder as completed",
                parameters: [
                    MCPParameter(name: "title", type: "string", description: "Title of reminder to complete", required: true)
                ]
            ),
            MCPTool(
                name: "delete_reminder",
                description: "Delete a reminder",
                parameters: [
                    MCPParameter(name: "title", type: "string", description: "Title of reminder to delete", required: true)
                ]
            ),
            MCPTool(
                name: "search_reminders",
                description: "Search reminders by title or notes",
                parameters: [
                    MCPParameter(name: "query", type: "string", description: "Search query", required: true)
                ]
            ),
            MCPTool(
                name: "get_today_reminders",
                description: "Get reminders due today",
                parameters: []
            ),
            MCPTool(
                name: "get_overdue_reminders",
                description: "Get overdue incomplete reminders",
                parameters: []
            )
        ]
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPResult {
        guard isAuthorized else {
            throw MCPError.permissionDenied("Reminders access not granted")
        }

        MCPLogger.logToolCall(server: "RemindersMCPServer", tool: name, arguments: arguments)
        let startTime = CFAbsoluteTimeGetCurrent()

        let result: MCPResult
        switch name {
        case "create_reminder": result = try await createReminder(arguments: arguments)
        case "list_reminders": result = try await listReminders(arguments: arguments)
        case "complete_reminder": result = try await completeReminder(arguments: arguments)
        case "delete_reminder": result = try await deleteReminder(arguments: arguments)
        case "search_reminders": result = try await searchReminders(arguments: arguments)
        case "get_today_reminders": result = try await getTodayReminders()
        case "get_overdue_reminders": result = try await getOverdueReminders()
        default: throw MCPError.toolNotFound(name)
        }

        MCPLogger.logToolResult(server: "RemindersMCPServer", tool: name, result: result, duration: CFAbsoluteTimeGetCurrent() - startTime)
        return result
    }

    func getServerName() -> String { "Reminders Server" }
    func getServerDescription() -> String { "Manages reminders and to-do items using iOS EventKit" }

    // MARK: - Permission

    private func requestRemindersAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .reminder)

        switch status {
        case .fullAccess, .authorized:
            isAuthorized = true
        case .notDetermined:
            let granted = if #available(iOS 17.0, *) {
                try await eventStore.requestFullAccessToReminders()
            } else {
                try await eventStore.requestAccess(to: .reminder)
            }
            isAuthorized = granted
            if !granted { throw MCPError.permissionDenied("Reminders access denied by user") }
        case .denied, .restricted, .writeOnly:
            throw MCPError.permissionDenied("Reminders access denied or restricted")
        @unknown default:
            throw MCPError.permissionDenied("Unknown reminders access status")
        }
    }

    // MARK: - Date Parsing

    private func parseFlexibleDate(_ dateString: String) -> Date? {
        // Try ISO8601
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: dateString) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: dateString) { return date }

        // Try common formats
        let formats = ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm"]
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone.current

        for format in formats {
            df.dateFormat = format
            if let date = df.date(from: dateString) { return date }
        }
        return nil
    }

    // MARK: - Tool Implementations

    private func createReminder(arguments: [String: Any]) async throws -> MCPResult {
        guard let title = arguments["title"] as? String else {
            throw MCPError.invalidArguments("Missing required field: title")
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = eventStore.defaultCalendarForNewReminders()

        if let dueDateString = arguments["due_date"] as? String, let dueDate = parseFlexibleDate(dueDateString) {
            reminder.dueDateComponents = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        }
        if let notes = arguments["notes"] as? String { reminder.notes = notes }
        if let priority = arguments["priority"] as? Int { reminder.priority = priority }

        try eventStore.save(reminder, commit: true)

        var message = "Reminder '\(title)' created"
        var dueTimestamp = 0
        if let dc = reminder.dueDateComponents, let dueDate = Calendar.current.date(from: dc) {
            message += " (due: \(DateFormatter.localizedString(from: dueDate, dateStyle: .medium, timeStyle: .short)))"
            dueTimestamp = Int(dueDate.timeIntervalSince1970)
        }

        return MCPResult(
            message: message,
            isError: false,
            metadata: [
                "reminderId": reminder.calendarItemIdentifier,
                "reminderTitle": title,
                "dueTimestamp": "\(dueTimestamp)",
                "action": "created"
            ]
        )
    }

    private func listReminders(arguments: [String: Any]) async throws -> MCPResult {
        let includeCompleted = arguments["include_completed"] as? Bool ?? false
        let reminders = await fetchAllReminders()
        let filtered = includeCompleted ? reminders : reminders.filter { !$0.isCompleted }

        if filtered.isEmpty {
            return MCPResult(message: includeCompleted ? "No reminders found" : "No incomplete reminders", isError: false)
        }

        let list = filtered.map { formatReminder($0) }.joined(separator: "\n")
        return MCPResult(message: "Found \(filtered.count) reminders:\n\n\(list)", isError: false)
    }

    private func completeReminder(arguments: [String: Any]) async throws -> MCPResult {
        guard let title = arguments["title"] as? String else {
            throw MCPError.invalidArguments("Missing required field: title")
        }

        let reminders = await fetchAllReminders()
        guard let reminder = reminders.first(where: { $0.title?.localizedCaseInsensitiveContains(title) == true && !$0.isCompleted }) else {
            return MCPResult(message: "Reminder '\(title)' not found or already completed", isError: true)
        }

        reminder.isCompleted = true
        reminder.completionDate = Date()
        try eventStore.save(reminder, commit: true)

        return MCPResult(
            message: "Reminder '\(reminder.title ?? title)' marked as completed",
            isError: false,
            metadata: [
                "reminderId": reminder.calendarItemIdentifier,
                "reminderTitle": reminder.title ?? title,
                "action": "completed"
            ]
        )
    }

    private func deleteReminder(arguments: [String: Any]) async throws -> MCPResult {
        guard let title = arguments["title"] as? String else {
            throw MCPError.invalidArguments("Missing required field: title")
        }

        let reminders = await fetchAllReminders()
        guard let reminder = reminders.first(where: { $0.title?.localizedCaseInsensitiveContains(title) == true }) else {
            return MCPResult(message: "Reminder '\(title)' not found", isError: true)
        }

        let reminderTitle = reminder.title ?? title
        try eventStore.remove(reminder, commit: true)

        return MCPResult(message: "Reminder '\(reminderTitle)' deleted", isError: false)
    }

    private func searchReminders(arguments: [String: Any]) async throws -> MCPResult {
        guard let query = arguments["query"] as? String else {
            throw MCPError.invalidArguments("Missing required field: query")
        }

        let reminders = await fetchAllReminders()
        let matching = reminders.filter {
            ($0.title?.localizedCaseInsensitiveContains(query) ?? false) ||
            ($0.notes?.localizedCaseInsensitiveContains(query) ?? false)
        }

        if matching.isEmpty {
            return MCPResult(message: "No reminders found matching '\(query)'", isError: false)
        }

        let list = matching.map { formatReminder($0) }.joined(separator: "\n")
        return MCPResult(message: "Found \(matching.count) reminders matching '\(query)':\n\n\(list)", isError: false)
    }

    private func getTodayReminders() async throws -> MCPResult {
        let reminders = await fetchAllReminders()
        let today = Calendar.current.startOfDay(for: Date())
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!

        let todayReminders = reminders.filter { reminder in
            guard !reminder.isCompleted,
                  let dc = reminder.dueDateComponents,
                  let dueDate = Calendar.current.date(from: dc) else { return false }
            return dueDate >= today && dueDate < tomorrow
        }

        if todayReminders.isEmpty {
            return MCPResult(message: "No reminders due today", isError: false)
        }

        let list = todayReminders.map { formatReminder($0) }.joined(separator: "\n")
        return MCPResult(message: "Today's reminders (\(todayReminders.count)):\n\n\(list)", isError: false)
    }

    private func getOverdueReminders() async throws -> MCPResult {
        let reminders = await fetchAllReminders()
        let now = Date()

        let overdue = reminders.filter { reminder in
            guard !reminder.isCompleted,
                  let dc = reminder.dueDateComponents,
                  let dueDate = Calendar.current.date(from: dc) else { return false }
            return dueDate < now
        }

        if overdue.isEmpty {
            return MCPResult(message: "No overdue reminders", isError: false)
        }

        let list = overdue.map { formatReminder($0) }.joined(separator: "\n")
        return MCPResult(message: "Overdue reminders (\(overdue.count)):\n\n\(list)", isError: false)
    }

    // MARK: - Helpers

    private func fetchAllReminders() async -> [EKReminder] {
        let calendars = eventStore.calendars(for: .reminder)
        let predicate = eventStore.predicateForReminders(in: calendars)
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func formatReminder(_ reminder: EKReminder) -> String {
        var line = "• \(reminder.title ?? "Untitled")"
        if reminder.isCompleted { line += " ✓" }
        if let dc = reminder.dueDateComponents, let dueDate = Calendar.current.date(from: dc) {
            line += " (due: \(DateFormatter.localizedString(from: dueDate, dateStyle: .medium, timeStyle: .short)))"
        }
        if reminder.priority > 0 {
            let p = reminder.priority == 1 ? "High" : (reminder.priority == 5 ? "Medium" : "Low")
            line += " [\(p)]"
        }
        return line
    }
}
