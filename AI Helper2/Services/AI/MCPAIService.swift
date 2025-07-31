import Foundation
import os.log

class MCPAIService: ObservableObject {
    private let aiService = AIService()
    @Published var mcpManager = MCPManager()
    private let logger = Logger(subsystem: "com.aihelper.mcp", category: "MCPAIService")
    
    init() {
        // Initialize calendar integration
        let calendarServer = CalendarMCPServer()
        mcpManager.enableCalendarIntegration(calendarServer)
        
        // Set up tool handler for native API tool calling
        aiService.toolHandler = { [weak self] toolName, arguments in
            guard let self = self else {
                return MCPResult(message: "Service unavailable", isError: true)
            }
            return try await self.mcpManager.executeToolCall(toolName: toolName, arguments: arguments)
        }
    }
    
    /// Send message using native AI tool calling with MCP integration
    /// AI models can directly call MCP tools via their native tool calling APIs
    func sendMessage(_ message: String, conversationHistory: [String] = [], configuration: APIConfiguration) async throws -> String {
        logger.info("🚀 MCP AI Service Request Started")
        logger.debug("📝 User Message: \(message)")
        logger.debug("📋 Conversation History: \(conversationHistory.count) messages")
        logger.debug("⚙️ Configuration: Provider=\(configuration.provider.rawValue), Model=\(configuration.model), MCP=\(configuration.enableMCP)")
        
        MCPLogger.logToolCall(server: "MCPAIService", tool: "sendMessage", arguments: ["message": message, "availableServers": self.mcpManager.availableServers.count, "historyCount": conversationHistory.count])
        let startTime = CFAbsoluteTimeGetCurrent()
        
        do {
            // Get all available MCP tools in API format
            logger.info("🔍 Loading available MCP tools...")
            let availableTools = await self.mcpManager.getAllAPITools()
            
            logger.info("🔧 MCP Tools Available: \(availableTools.count) tools from \(self.mcpManager.availableServers.count) servers")
            for tool in availableTools {
                logger.debug("🛠️ Tool: \(tool.name) - \(tool.description)")
            }
            
            MCPLogger.logToolCall(server: "MCPAIService", tool: "toolsLoaded", arguments: ["toolCount": availableTools.count, "tools": availableTools.map { $0.name }.joined(separator: ", ")])
            
            // Log conversation context if provided
            if !conversationHistory.isEmpty {
                logger.debug("📋 Recent Conversation Context:")
                for (index, historyMessage) in conversationHistory.suffix(3).enumerated() {
                    logger.debug("  \(index + 1). \(historyMessage.prefix(100))...")
                }
            }
            
            // Send message with tools to AI API - the AI will decide which tools to call
            logger.info("🤖 Sending request to AI with native tool calling enabled")
            let response = try await aiService.sendMessage(message, configuration: configuration, tools: availableTools)
            
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logger.info("✅ MCP AI Service Request Completed - Duration: \(String(format: "%.3f", duration))s")
            logger.debug("💬 Final Response Length: \(response.count) chars")
            logger.debug("📝 Final Response: \(response)")
            
            MCPLogger.logToolResult(server: "MCPAIService", tool: "sendMessage", 
                                   result: MCPResult(message: "Request processed with native tool calling - Response: \(response.prefix(100))...", isError: false), duration: duration)
            
            return response
            
        } catch {
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            logger.error("❌ MCP AI Service Request Failed - Duration: \(String(format: "%.3f", duration))s, Error: \(error.localizedDescription)")
            MCPLogger.logError(context: "MCPAIService.sendMessage", error: error)
            throw error
        }
    }
    
    /// Get available MCP tools for display purposes
    func getAvailableTools() async -> [MCPTool] {
        logger.info("📋 Retrieving all MCP tools for display")
        var allTools: [MCPTool] = []
        
        for (serverName, server) in self.mcpManager.availableServers {
            logger.debug("🔍 Fetching tools from server: \(serverName)")
            do {
                let tools = try await server.listTools()
                logger.debug("🔧 Server \(serverName) provides \(tools.count) tools: [\(tools.map { $0.name }.joined(separator: ", "))]")
                allTools.append(contentsOf: tools)
            } catch {
                logger.error("❌ Failed to get tools from \(serverName): \(error.localizedDescription)")
                MCPLogger.logError(context: "Getting tools for display from \(serverName)", error: error)
            }
        }
        
        logger.info("📋 Total tools available: \(allTools.count) from \(self.mcpManager.availableServers.count) servers")
        return allTools
    }
    
    /// Check if MCP integration is enabled
    var isMCPEnabled: Bool {
        return !self.mcpManager.availableServers.isEmpty
    }
    
    /// Get count of available MCP servers
    var availableServerCount: Int {
        return self.mcpManager.availableServers.count
    }
}