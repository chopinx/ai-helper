//
//  ToolModelsTests.swift
//  AI Helper2Tests
//
//  Tests for the LLM-friendly tool interface
//

import Testing
@testable import AI_Helper2

struct ToolModelsTests {

    // MARK: - Tool Tests

    @Test func toolCreationWithDefaults() {
        let tool = Tool(name: "test_tool", description: "A test tool")

        #expect(tool.name == "test_tool")
        #expect(tool.description == "A test tool")
        #expect(tool.parameters.isEmpty)
        #expect(tool.required.isEmpty)
    }

    @Test func toolCreationWithParameters() {
        let tool = Tool(
            name: "create_event",
            description: "Create a calendar event",
            parameters: [
                "title": ToolParam(type: "string", description: "Event title"),
                "start": ToolParam(type: "string", description: "Start time ISO8601"),
                "duration": ToolParam(type: "integer", description: "Duration in minutes")
            ],
            required: ["title", "start"]
        )

        #expect(tool.name == "create_event")
        #expect(tool.parameters.count == 3)
        #expect(tool.required.count == 2)
        #expect(tool.parameters["title"]?.type == "string")
        #expect(tool.parameters["duration"]?.type == "integer")
    }

    // MARK: - ToolParam Tests

    @Test func toolParamDefaultType() {
        let param = ToolParam(description: "A parameter")

        #expect(param.type == "string")
        #expect(param.description == "A parameter")
    }

    @Test func toolParamWithType() {
        let intParam = ToolParam(type: "integer", description: "An integer")
        let boolParam = ToolParam(type: "boolean", description: "A boolean")
        let numParam = ToolParam(type: "number", description: "A number")

        #expect(intParam.type == "integer")
        #expect(boolParam.type == "boolean")
        #expect(numParam.type == "number")
    }

    // MARK: - ToolCall Tests

    @Test func toolCallCreation() {
        let call = ToolCall(
            id: "call_123",
            name: "create_event",
            arguments: ["title": "Meeting", "start": "2024-01-01T10:00:00Z"]
        )

        #expect(call.id == "call_123")
        #expect(call.name == "create_event")
        #expect(call.arguments["title"] as? String == "Meeting")
        #expect(call.arguments.count == 2)
    }

    // MARK: - ToolResult Tests

    @Test func toolResultSuccess() {
        let result = ToolResult(callId: "call_123", content: "Event created")

        #expect(result.callId == "call_123")
        #expect(result.content == "Event created")
        #expect(result.isError == false)
    }

    @Test func toolResultError() {
        let result = ToolResult(callId: "call_456", content: "Permission denied", isError: true)

        #expect(result.callId == "call_456")
        #expect(result.content == "Permission denied")
        #expect(result.isError == true)
    }

    // MARK: - OpenAI Format Conversion Tests

    @Test func toolToOpenAIFormat() {
        let tool = Tool(
            name: "list_events",
            description: "List calendar events",
            parameters: [
                "start_date": ToolParam(type: "string", description: "Start date"),
                "end_date": ToolParam(type: "string", description: "End date")
            ],
            required: ["start_date"]
        )

        let openAI = tool.toOpenAI()

        #expect(openAI["type"] as? String == "function")

        let function = openAI["function"] as? [String: Any]
        #expect(function != nil)
        #expect(function?["name"] as? String == "list_events")
        #expect(function?["description"] as? String == "List calendar events")

        let parameters = function?["parameters"] as? [String: Any]
        #expect(parameters?["type"] as? String == "object")

        let required = parameters?["required"] as? [String]
        #expect(required?.contains("start_date") == true)

        let properties = parameters?["properties"] as? [String: Any]
        #expect(properties?.count == 2)
    }

    @Test func emptyToolToOpenAI() {
        let tool = Tool(name: "simple", description: "Simple tool")
        let openAI = tool.toOpenAI()

        let function = openAI["function"] as? [String: Any]
        let parameters = function?["parameters"] as? [String: Any]
        let properties = parameters?["properties"] as? [String: Any]
        let required = parameters?["required"] as? [String]

        #expect(properties?.isEmpty == true)
        #expect(required?.isEmpty == true)
    }

    // MARK: - Claude Format Conversion Tests

    @Test func toolToClaudeFormat() {
        let tool = Tool(
            name: "delete_event",
            description: "Delete a calendar event",
            parameters: [
                "event_id": ToolParam(type: "string", description: "Event ID to delete")
            ],
            required: ["event_id"]
        )

        let claude = tool.toClaude()

        #expect(claude["name"] as? String == "delete_event")
        #expect(claude["description"] as? String == "Delete a calendar event")

        let inputSchema = claude["input_schema"] as? [String: Any]
        #expect(inputSchema?["type"] as? String == "object")

        let properties = inputSchema?["properties"] as? [String: Any]
        #expect(properties?.count == 1)

        let required = inputSchema?["required"] as? [String]
        #expect(required?.contains("event_id") == true)
    }

    @Test func emptyToolToClaude() {
        let tool = Tool(name: "ping", description: "Ping tool")
        let claude = tool.toClaude()

        let inputSchema = claude["input_schema"] as? [String: Any]
        let properties = inputSchema?["properties"] as? [String: Any]
        let required = inputSchema?["required"] as? [String]

        #expect(properties?.isEmpty == true)
        #expect(required?.isEmpty == true)
    }

    // MARK: - MCPTool to Tool Conversion Tests

    @Test func mcpToolToToolConversion() {
        let mcpTool = MCPTool(
            name: "create_reminder",
            description: "Create a reminder",
            parameters: [
                MCPParameter(name: "title", type: "string", description: "Reminder title", required: true),
                MCPParameter(name: "notes", type: "string", description: "Additional notes", required: false)
            ]
        )

        let tool = mcpTool.toTool()

        #expect(tool.name == "create_reminder")
        #expect(tool.description == "Create a reminder")
        #expect(tool.parameters.count == 2)
        #expect(tool.required.count == 1)
        #expect(tool.required.contains("title"))
        #expect(!tool.required.contains("notes"))
        #expect(tool.parameters["title"]?.type == "string")
    }

    @Test func mcpToolWithNoParameters() {
        let mcpTool = MCPTool(name: "list_calendars", description: "List all calendars")
        let tool = mcpTool.toTool()

        #expect(tool.name == "list_calendars")
        #expect(tool.parameters.isEmpty)
        #expect(tool.required.isEmpty)
    }

    // MARK: - Format Consistency Tests

    @Test func openAIAndClaudeHaveMatchingContent() {
        let tool = Tool(
            name: "search",
            description: "Search for items",
            parameters: [
                "query": ToolParam(type: "string", description: "Search query"),
                "limit": ToolParam(type: "integer", description: "Max results")
            ],
            required: ["query"]
        )

        let openAI = tool.toOpenAI()
        let claude = tool.toClaude()

        // Both should have the same tool name
        let openAIFunction = openAI["function"] as? [String: Any]
        #expect(openAIFunction?["name"] as? String == claude["name"] as? String)

        // Both should have the same description
        #expect(openAIFunction?["description"] as? String == claude["description"] as? String)

        // Both should have the same required fields
        let openAIParams = openAIFunction?["parameters"] as? [String: Any]
        let claudeSchema = claude["input_schema"] as? [String: Any]

        let openAIRequired = openAIParams?["required"] as? [String] ?? []
        let claudeRequired = claudeSchema?["required"] as? [String] ?? []

        #expect(Set(openAIRequired) == Set(claudeRequired))
    }
}
