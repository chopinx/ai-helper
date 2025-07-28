import Foundation

// MARK: - Simple MCP Protocol for Calendar

protocol SimpleMCPServer {
    func initialize() async throws
    func listTools() async throws -> [SimpleMCPTool]
    func callTool(name: String, arguments: [String: Any]) async throws -> SimpleMCPResult
}

struct SimpleMCPTool {
    let name: String
    let description: String
}

struct SimpleMCPResult {
    let message: String
    let isError: Bool
}

enum SimpleMCPError: Error, LocalizedError {
    case serverNotInitialized
    case toolNotFound(String)
    case invalidArguments(String)
    case permissionDenied(String)
    case operationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .serverNotInitialized:
            return "MCP server not initialized"
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

class SimpleMCPManager: ObservableObject {
    @Published var isCalendarEnabled = false
    private var calendarServer: SimpleMCPServer?
    
    func enableCalendarIntegration(_ server: SimpleMCPServer) {
        calendarServer = server
        Task {
            do {
                try await server.initialize()
                await MainActor.run {
                    isCalendarEnabled = true
                }
            } catch {
                print("Failed to initialize calendar server: \(error)")
            }
        }
    }
    
    func createCalendarEvent(title: String, startDate: Date, endDate: Date, notes: String? = nil) async throws -> SimpleMCPResult {
        guard let server = calendarServer else {
            throw SimpleMCPError.serverNotInitialized
        }
        
        let arguments: [String: Any] = [
            "title": title,
            "start_date": ISO8601DateFormatter().string(from: startDate),
            "end_date": ISO8601DateFormatter().string(from: endDate),
            "notes": notes ?? ""
        ]
        
        return try await server.callTool(name: "create_event", arguments: arguments)
    }
}