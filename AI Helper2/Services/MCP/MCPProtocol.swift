import Foundation
import EventKit
import os.log

// MARK: - MCP Debug Logging

struct MCPLogger {
    private static let logger = Logger(subsystem: "com.aihelper.mcp", category: "MCPOperations")
    
    static func logToolCall(server: String, tool: String, arguments: [String: Any]) {
        let argsString = arguments.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        logger.info("🔧 MCP Tool Call - Server: \(server), Tool: \(tool), Args: [\(argsString)]")
    }
    
    static func logToolResult(server: String, tool: String, result: MCPResult, duration: TimeInterval) {
        let status = result.isError ? "❌ ERROR" : "✅ SUCCESS"
        logger.info("📊 MCP Result - Server: \(server), Tool: \(tool), Status: \(status), Duration: \(String(format: "%.3f", duration))s")
        logger.debug("📄 Result Message: \(result.message)")
    }
    
    static func logError(context: String, error: Error) {
        logger.error("🚨 MCP Error - Context: \(context), Error: \(error.localizedDescription)")
    }
}

// MARK: - MCP Protocol

protocol MCPServer {
    func initialize() async throws
    func listTools() async throws -> [MCPTool]
    func callTool(name: String, arguments: [String: Any]) async throws -> MCPResult
    func getServerName() -> String
    func getServerDescription() -> String
}

struct MCPTool {
    let name: String
    let description: String
    let parameters: [MCPParameter]
    
    init(name: String, description: String, parameters: [MCPParameter] = []) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

struct MCPParameter {
    let name: String
    let type: String
    let description: String
    let required: Bool
    
    init(name: String, type: String, description: String, required: Bool = false) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
    }
}

struct MCPResult {
    let message: String
    let isError: Bool
    let metadata: [String: String]  // Optional metadata like eventId, etc.

    init(message: String, isError: Bool, metadata: [String: String] = [:]) {
        self.message = message
        self.isError = isError
        self.metadata = metadata
    }
}

// MARK: - Shared Date Parsing

/// Parse date string with multiple format support (used by Calendar and Reminders servers)
func parseFlexibleDate(_ dateString: String) -> Date? {
    // Try ISO8601 with timezone (e.g., "2026-02-01T10:00:00Z" or "2026-02-01T10:00:00+00:00")
    let iso8601Formatter = ISO8601DateFormatter()
    iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = iso8601Formatter.date(from: dateString) { return date }

    // Try ISO8601 without fractional seconds
    iso8601Formatter.formatOptions = [.withInternetDateTime]
    if let date = iso8601Formatter.date(from: dateString) { return date }

    // Try common date formats
    let formats = [
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "yyyy-MM-dd HH:mm",
        "yyyy-MM-dd'T'HH:mm",
        "yyyy/MM/dd HH:mm:ss",
        "yyyy/MM/dd HH:mm",
        "MM/dd/yyyy HH:mm",
        "dd-MM-yyyy HH:mm"
    ]

    let dateFormatter = DateFormatter()
    dateFormatter.locale = Locale(identifier: "en_US_POSIX")
    dateFormatter.timeZone = TimeZone.current

    for format in formats {
        dateFormatter.dateFormat = format
        if let date = dateFormatter.date(from: dateString) { return date }
    }

    return nil
}

// MARK: - Shared Recurrence Parsing

/// Parse recurrence string to EKRecurrenceRule (used by Calendar and Reminders servers)
func parseRecurrence(_ string: String) -> EKRecurrenceRule? {
    let frequency: EKRecurrenceFrequency
    switch string.lowercased() {
    case "daily": frequency = .daily
    case "weekly": frequency = .weekly
    case "monthly": frequency = .monthly
    case "yearly": frequency = .yearly
    default: return nil
    }
    return EKRecurrenceRule(recurrenceWith: frequency, interval: 1, end: nil)
}

// MARK: - MCP Error

enum MCPError: Error, LocalizedError {
    case toolNotFound(String)
    case invalidArguments(String)
    case permissionDenied(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .toolNotFound(let tool):
            return "Tool not found: \(tool)"
        case .invalidArguments(let message):
            return "Invalid arguments: \(message)"
        case .permissionDenied(let message):
            return "Permission denied: \(message)"
        case .operationFailed(let message):
            return "Operation failed: \(message)"
        }
    }
}