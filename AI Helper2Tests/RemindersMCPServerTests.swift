//
//  RemindersMCPServerTests.swift
//  AI Helper2Tests
//
//  Tests for RemindersMCPServer tool definitions
//

import Testing
@testable import AI_Helper2

struct RemindersMCPServerTests {

    // MARK: - update_reminder Tool Tests

    @Test func updateReminderToolExists() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()
        let toolNames = tools.map { $0.name }

        #expect(toolNames.contains("update_reminder"))
    }

    @Test func updateReminderToolHasCorrectDescription() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()
        let updateTool = tools.first { $0.name == "update_reminder" }

        #expect(updateTool != nil)
        #expect(updateTool?.description == "Update an existing reminder's title, due date, notes, or priority")
    }

    @Test func updateReminderToolHasRequiredTitleParameter() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()
        let updateTool = tools.first { $0.name == "update_reminder" }

        let titleParam = updateTool?.parameters.first { $0.name == "title" }
        #expect(titleParam != nil)
        #expect(titleParam?.type == "string")
        #expect(titleParam?.required == true)
    }

    @Test func updateReminderToolHasOptionalParameters() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()
        let updateTool = tools.first { $0.name == "update_reminder" }

        let optionalNames = ["new_title", "new_due_date", "new_notes", "new_priority"]
        for name in optionalNames {
            let param = updateTool?.parameters.first { $0.name == name }
            #expect(param != nil, "Missing parameter: \(name)")
            #expect(param?.required == false, "Parameter \(name) should be optional")
        }
    }

    @Test func updateReminderToolParameterTypes() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()
        let updateTool = tools.first { $0.name == "update_reminder" }

        let params = updateTool?.parameters ?? []
        let paramsByName = Dictionary(uniqueKeysWithValues: params.map { ($0.name, $0) })

        #expect(paramsByName["title"]?.type == "string")
        #expect(paramsByName["new_title"]?.type == "string")
        #expect(paramsByName["new_due_date"]?.type == "string")
        #expect(paramsByName["new_notes"]?.type == "string")
        #expect(paramsByName["new_priority"]?.type == "integer")
    }

    @Test func updateReminderToolParameterCount() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()
        let updateTool = tools.first { $0.name == "update_reminder" }

        #expect(updateTool?.parameters.count == 5)
    }

    @Test func updateReminderToToolConversion() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()
        let updateTool = tools.first { $0.name == "update_reminder" }

        let tool = updateTool?.toTool()
        #expect(tool != nil)
        #expect(tool?.name == "update_reminder")
        #expect(tool?.required == ["title"])
        #expect(tool?.parameters.count == 5)
        #expect(tool?.parameters["new_priority"]?.type == "integer")
    }
}
