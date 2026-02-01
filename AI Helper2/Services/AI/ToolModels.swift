import Foundation

// MARK: - LLM-Friendly Tool Interface

/// Universal tool definition that works with any LLM (OpenAI, Claude, etc.)
struct Tool {
    let name: String
    let description: String
    let parameters: [String: ToolParam]
    let required: [String]

    init(name: String, description: String, parameters: [String: ToolParam] = [:], required: [String] = []) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.required = required
    }
}

struct ToolParam {
    let type: String        // "string", "integer", "boolean", "number"
    let description: String

    init(type: String = "string", description: String) {
        self.type = type
        self.description = description
    }
}

/// Tool call from LLM response
struct ToolCall {
    let id: String
    let name: String
    let arguments: [String: Any]
}

/// Result of tool execution
struct ToolResult {
    let callId: String
    let content: String
    let isError: Bool

    init(callId: String, content: String, isError: Bool = false) {
        self.callId = callId
        self.content = content
        self.isError = isError
    }
}

// MARK: - Tool Provider Protocol

protocol ToolProvider {
    var name: String { get }
    func listTools() async throws -> [Tool]
    func execute(name: String, arguments: [String: Any]) async throws -> String
}

// MARK: - OpenAI Format Conversion

extension Tool {
    func toOpenAI() -> [String: Any] {
        var properties: [String: [String: String]] = [:]
        for (key, param) in parameters {
            properties[key] = [
                "type": param.type,
                "description": param.description
            ]
        }

        return [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required
                ]
            ]
        ]
    }
}

// MARK: - Claude Format Conversion

extension Tool {
    func toClaude() -> [String: Any] {
        var properties: [String: [String: String]] = [:]
        for (key, param) in parameters {
            properties[key] = [
                "type": param.type,
                "description": param.description
            ]
        }

        return [
            "name": name,
            "description": description,
            "input_schema": [
                "type": "object",
                "properties": properties,
                "required": required
            ]
        ]
    }
}

// MARK: - Convert MCPTool to Tool

extension MCPTool {
    func toTool() -> Tool {
        var params: [String: ToolParam] = [:]
        var requiredParams: [String] = []

        for param in parameters {
            params[param.name] = ToolParam(type: param.type, description: param.description)
            if param.required {
                requiredParams.append(param.name)
            }
        }

        return Tool(
            name: name,
            description: description,
            parameters: params,
            required: requiredParams
        )
    }
}
