import Foundation
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
    
    static func logServerInitialization(server: String, success: Bool, error: Error? = nil) {
        if success {
            logger.info("🚀 MCP Server Initialized - \(server)")
        } else {
            logger.error("💥 MCP Server Init Failed - \(server): \(error?.localizedDescription ?? "Unknown error")")
        }
    }
    
    static func logRequestType(message: String, detectedType: String) {
        logger.info("🤖 AI Request Analysis - Message: '\(message)' → Type: \(detectedType)")
    }
    
    static func logAIExtraction(prompt: String, response: String, type: String) {
        logger.debug("🧠 AI Extraction - Type: \(type)")
        logger.debug("📝 Prompt: \(prompt)")
        logger.debug("💭 Response: \(response)")
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
    func canHandle(message: String, context: MCPEvaluationContext, aiService: AIService, configuration: APIConfiguration) async -> MCPCapabilityResult
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
    
    /// Convert MCP tool to API tool format for native tool calling
    func toAPITool() -> APITool {
        var properties: [String: APIToolProperty] = [:]
        var required: [String] = []
        
        for param in parameters {
            properties[param.name] = APIToolProperty(
                type: param.type,
                description: param.description
            )
            if param.required {
                required.append(param.name)
            }
        }
        
        return APITool(
            name: name,
            description: description,
            properties: properties,
            required: required
        )
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
}

struct MCPCapabilityResult {
    let canHandle: Bool
    let confidence: Double // 0.0 to 1.0
    let suggestedTools: [String]
    let reasoning: String
}

struct MCPEvaluationStep {
    let serverName: String
    let step: String
    let details: String
    let timestamp: Date
}

struct MCPEvaluationContext {
    let currentDate: Date
    let timeZone: TimeZone
    let locale: Locale
    let conversationHistory: [String] // Recent messages for context
    let userPreferences: [String: Any] // User settings and preferences
    let deviceInfo: [String: String] // Device and app context
}

struct MCPEvaluationResult {
    let message: String
    let evaluationSteps: [MCPEvaluationStep]
    let selectedServers: [String: MCPCapabilityResult]
    let executionResults: [String: MCPResult]
}

enum MCPError: Error, LocalizedError {
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

class MCPManager: ObservableObject {
    @Published var isCalendarEnabled = false
    @Published var evaluationSteps: [MCPEvaluationStep] = []
    @Published var showEvaluationDetails = false
    
    private var calendarServer: MCPServer?
    private var registeredServers: [String: MCPServer] = [:]
    
    var availableServers: [String: MCPServer] {
        return registeredServers
    }
    
    /// Get all MCP tools converted to API tool format for native tool calling
    func getAllAPITools() async -> [APITool] {
        var allTools: [APITool] = []
        
        for (serverName, server) in registeredServers {
            do {
                let mcpTools = try await server.listTools()
                let apiTools = mcpTools.map { $0.toAPITool() }
                allTools.append(contentsOf: apiTools)
            } catch {
                MCPLogger.logError(context: "Getting tools from \(serverName)", error: error)
            }
        }
        
        return allTools
    }
    
    /// Execute a tool call from native API tool calling
    func executeToolCall(toolName: String, arguments: [String: Any]) async throws -> MCPResult {
        // Find which server has this tool
        for (serverName, server) in registeredServers {
            do {
                let tools = try await server.listTools()
                if tools.contains(where: { $0.name == toolName }) {
                    MCPLogger.logToolCall(server: serverName, tool: toolName, arguments: arguments)
                    let startTime = CFAbsoluteTimeGetCurrent()
                    
                    let result = try await server.callTool(name: toolName, arguments: arguments)
                    
                    let duration = CFAbsoluteTimeGetCurrent() - startTime
                    MCPLogger.logToolResult(server: serverName, tool: toolName, result: result, duration: duration)
                    
                    return result
                }
            } catch {
                MCPLogger.logError(context: "Checking tools for \(serverName)", error: error)
                continue
            }
        }
        
        throw MCPError.toolNotFound(toolName)
    }
    
    func registerServer(_ server: MCPServer, name: String) {
        registeredServers[name] = server
        
        // Keep backward compatibility for calendar
        if name == "calendar" {
            calendarServer = server
        }
        
        Task {
            do {
                try await server.initialize()
                MCPLogger.logServerInitialization(server: name, success: true)
                await MainActor.run {
                    if name == "calendar" {
                        isCalendarEnabled = true
                    }
                }
            } catch {
                MCPLogger.logServerInitialization(server: name, success: false, error: error)
                MCPLogger.logError(context: "\(name) server initialization", error: error)
            }
        }
    }
    
    func enableCalendarIntegration(_ server: MCPServer) {
        registerServer(server, name: "calendar")
    }
    
    func createCalendarEvent(title: String, startDate: Date, endDate: Date, notes: String? = nil) async throws -> MCPResult {
        guard let server = calendarServer else {
            throw MCPError.serverNotInitialized
        }
        
        let arguments: [String: Any] = [
            "title": title,
            "start_date": ISO8601DateFormatter().string(from: startDate),
            "end_date": ISO8601DateFormatter().string(from: endDate),
            "notes": notes ?? ""
        ]
        
        MCPLogger.logToolCall(server: "calendar", tool: "create_event", arguments: arguments)
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            let result = try await server.callTool(name: "create_event", arguments: arguments)
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            MCPLogger.logToolResult(server: "calendar", tool: "create_event", result: result, duration: duration)
            return result
        } catch {
            _ = CFAbsoluteTimeGetCurrent() - startTime
            MCPLogger.logError(context: "create_event tool call", error: error)
            throw error
        }
    }
    
    /// Get all available tool names for debugging
    private func getAllAvailableToolNames() async -> [String] {
        var toolNames: [String] = []
        
        for (_, server) in registeredServers {
            do {
                let tools = try await server.listTools()
                toolNames.append(contentsOf: tools.map { $0.name })
            } catch {
                // Ignore errors for this debug function
            }
        }
        
        return toolNames
    }
}