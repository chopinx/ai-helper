//
//  MCPProtocolTests.swift
//  AI Helper2Tests
//
//  Tests for MCP protocol types
//

import Testing
import Foundation
@testable import AI_Helper2

// MARK: - Mock MCP Server

/// A mock MCP server for testing
class MockMCPServer: MCPServer {
    let serverName: String
    let serverDescription: String
    let tools: [MCPTool]
    var initializeCallCount = 0
    var callToolHistory: [(name: String, arguments: [String: Any])] = []
    var callToolResult: MCPResult

    init(
        name: String,
        description: String = "Mock server",
        tools: [MCPTool] = [],
        result: MCPResult = MCPResult(message: "OK", isError: false)
    ) {
        self.serverName = name
        self.serverDescription = description
        self.tools = tools
        self.callToolResult = result
    }

    func initialize() async throws {
        initializeCallCount += 1
    }

    func listTools() async throws -> [MCPTool] {
        return tools
    }

    func callTool(name: String, arguments: [String: Any]) async throws -> MCPResult {
        callToolHistory.append((name: name, arguments: arguments))
        return callToolResult
    }

    func getServerName() -> String { serverName }
    func getServerDescription() -> String { serverDescription }
}

// MARK: - MCPTool Tests

struct MCPToolTests {

    @Test func mcpToolCreation() {
        let tool = MCPTool(
            name: "create_event",
            description: "Create a calendar event",
            parameters: [
                MCPParameter(name: "title", type: "string", description: "Event title", required: true),
                MCPParameter(name: "notes", type: "string", description: "Notes", required: false)
            ]
        )

        #expect(tool.name == "create_event")
        #expect(tool.description == "Create a calendar event")
        #expect(tool.parameters.count == 2)
    }

    @Test func mcpToolWithNoParameters() {
        let tool = MCPTool(name: "get_status", description: "Get status")

        #expect(tool.name == "get_status")
        #expect(tool.parameters.isEmpty)
    }

    @Test func mcpToolToToolConversion() {
        let mcpTool = MCPTool(
            name: "search",
            description: "Search items",
            parameters: [
                MCPParameter(name: "query", type: "string", description: "Search query", required: true),
                MCPParameter(name: "limit", type: "integer", description: "Max results", required: false)
            ]
        )

        let tool = mcpTool.toTool()

        #expect(tool.name == "search")
        #expect(tool.description == "Search items")
        #expect(tool.parameters.count == 2)
        #expect(tool.required == ["query"])
        #expect(tool.parameters["query"]?.type == "string")
        #expect(tool.parameters["limit"]?.type == "integer")
    }
}

// MARK: - MCPParameter Tests

struct MCPParameterTests {

    @Test func mcpParameterRequired() {
        let param = MCPParameter(name: "title", type: "string", description: "Title", required: true)

        #expect(param.name == "title")
        #expect(param.type == "string")
        #expect(param.description == "Title")
        #expect(param.required == true)
    }

    @Test func mcpParameterOptional() {
        let param = MCPParameter(name: "notes", type: "string", description: "Notes")

        #expect(param.required == false) // Default
    }
}

// MARK: - MCPResult Tests

struct MCPResultTests {

    @Test func mcpResultSuccess() {
        let result = MCPResult(message: "Event created successfully", isError: false)

        #expect(result.message == "Event created successfully")
        #expect(result.isError == false)
        #expect(result.metadata.isEmpty)
    }

    @Test func mcpResultError() {
        let result = MCPResult(message: "Permission denied", isError: true)

        #expect(result.isError == true)
    }

    @Test func mcpResultWithMetadata() {
        let result = MCPResult(
            message: "Created",
            isError: false,
            metadata: ["eventId": "abc123", "action": "created"]
        )

        #expect(result.metadata["eventId"] == "abc123")
        #expect(result.metadata["action"] == "created")
    }
}

// MARK: - MCPError Tests

struct MCPErrorTests {

    @Test func toolNotFound() {
        let error = MCPError.toolNotFound("unknown_tool")
        #expect(error.errorDescription == "Tool not found: unknown_tool")
    }

    @Test func invalidArguments() {
        let error = MCPError.invalidArguments("missing title")
        #expect(error.errorDescription == "Invalid arguments: missing title")
    }

    @Test func permissionDenied() {
        let error = MCPError.permissionDenied("calendar access")
        #expect(error.errorDescription == "Permission denied: calendar access")
    }

    @Test func operationFailed() {
        let error = MCPError.operationFailed("event not found")
        #expect(error.errorDescription == "Operation failed: event not found")
    }
}

