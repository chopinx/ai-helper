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

        let optionalNames = ["new_title", "new_due_date", "new_notes", "new_priority", "new_recurrence"]
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
        #expect(paramsByName["new_recurrence"]?.type == "string")
    }

    @Test func updateReminderToolParameterCount() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()
        let updateTool = tools.first { $0.name == "update_reminder" }

        #expect(updateTool?.parameters.count == 6)
    }

    @Test func updateReminderToToolConversion() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()
        let updateTool = tools.first { $0.name == "update_reminder" }

        let tool = updateTool?.toTool()
        #expect(tool != nil)
        #expect(tool?.name == "update_reminder")
        #expect(tool?.required == ["title"])
        #expect(tool?.parameters.count == 6)
        #expect(tool?.parameters["new_priority"]?.type == "integer")
    }

    // MARK: - get_reminder_lists Tool Tests

    @Test func getReminderListsToolExists() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()
        let toolNames = tools.map { $0.name }

        #expect(toolNames.contains("get_reminder_lists"))
    }

    @Test func getReminderListsToolHasNoParameters() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "get_reminder_lists" }

        #expect(tool != nil)
        #expect(tool?.parameters.isEmpty == true)
    }

    // MARK: - uncomplete_reminder Tool Tests

    @Test func uncompleteReminderToolExists() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()
        let toolNames = tools.map { $0.name }

        #expect(toolNames.contains("uncomplete_reminder"))
    }

    @Test func uncompleteReminderToolHasRequiredTitleParameter() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "uncomplete_reminder" }

        #expect(tool != nil)
        #expect(tool?.parameters.count == 1)
        let titleParam = tool?.parameters.first { $0.name == "title" }
        #expect(titleParam != nil)
        #expect(titleParam?.type == "string")
        #expect(titleParam?.required == true)
    }

    // MARK: - create_reminder list and recurrence params

    @Test func createReminderToolHasListParameter() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "create_reminder" }

        let listParam = tool?.parameters.first { $0.name == "list" }
        #expect(listParam != nil)
        #expect(listParam?.type == "string")
        #expect(listParam?.required == false)
    }

    @Test func createReminderToolHasRecurrenceParameter() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "create_reminder" }

        let param = tool?.parameters.first { $0.name == "recurrence" }
        #expect(param != nil)
        #expect(param?.type == "string")
        #expect(param?.required == false)
    }

    @Test func createReminderToolParameterCount() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "create_reminder" }

        #expect(tool?.parameters.count == 6)
    }

    // MARK: - list_reminders list param

    @Test func listRemindersToolHasListParameter() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "list_reminders" }

        let listParam = tool?.parameters.first { $0.name == "list" }
        #expect(listParam != nil)
        #expect(listParam?.type == "string")
        #expect(listParam?.required == false)
    }

    @Test func listRemindersToolParameterCount() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "list_reminders" }

        #expect(tool?.parameters.count == 2)
    }

    // MARK: - Total tool count

    @Test func reminderServerTotalToolCount() async throws {
        let server = RemindersMCPServer()
        let tools = try await server.listTools()

        #expect(tools.count == 10)
    }
}
