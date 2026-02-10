//
//  CalendarMCPServerTests.swift
//  AI Helper2Tests
//
//  Tests for CalendarMCPServer tool definitions
//

import Testing
@testable import AI_Helper2

struct CalendarMCPServerTests {

    // MARK: - Total tool count

    @Test func calendarServerTotalToolCount() async throws {
        let server = CalendarMCPServer()
        let tools = try await server.listTools()

        #expect(tools.count == 8)
    }

    // MARK: - create_event new params (location, alert_minutes, recurrence)

    @Test func createEventToolHasLocationParameter() async throws {
        let server = CalendarMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "create_event" }

        let param = tool?.parameters.first { $0.name == "location" }
        #expect(param != nil)
        #expect(param?.type == "string")
        #expect(param?.required == false)
    }

    @Test func createEventToolHasAlertMinutesParameter() async throws {
        let server = CalendarMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "create_event" }

        let param = tool?.parameters.first { $0.name == "alert_minutes" }
        #expect(param != nil)
        #expect(param?.type == "integer")
        #expect(param?.required == false)
    }

    @Test func createEventToolHasRecurrenceParameter() async throws {
        let server = CalendarMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "create_event" }

        let param = tool?.parameters.first { $0.name == "recurrence" }
        #expect(param != nil)
        #expect(param?.type == "string")
        #expect(param?.required == false)
    }

    @Test func createEventToolParameterCount() async throws {
        let server = CalendarMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "create_event" }

        // title, start_date, end_date, notes, location, alert_minutes, recurrence
        #expect(tool?.parameters.count == 7)
    }

    @Test func createEventToolRequiredParams() async throws {
        let server = CalendarMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "create_event" }

        let converted = tool?.toTool()
        #expect(converted?.required.sorted() == ["end_date", "start_date", "title"])
    }

    // MARK: - update_event new params (new_location, new_alert_minutes, new_recurrence)

    @Test func updateEventToolHasNewLocationParameter() async throws {
        let server = CalendarMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "update_event" }

        let param = tool?.parameters.first { $0.name == "new_location" }
        #expect(param != nil)
        #expect(param?.type == "string")
        #expect(param?.required == false)
    }

    @Test func updateEventToolHasNewAlertMinutesParameter() async throws {
        let server = CalendarMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "update_event" }

        let param = tool?.parameters.first { $0.name == "new_alert_minutes" }
        #expect(param != nil)
        #expect(param?.type == "integer")
        #expect(param?.required == false)
    }

    @Test func updateEventToolHasNewRecurrenceParameter() async throws {
        let server = CalendarMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "update_event" }

        let param = tool?.parameters.first { $0.name == "new_recurrence" }
        #expect(param != nil)
        #expect(param?.type == "string")
        #expect(param?.required == false)
    }

    @Test func updateEventToolParameterCount() async throws {
        let server = CalendarMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "update_event" }

        // event_title, new_title, new_notes, new_start_date, new_end_date, new_location, new_alert_minutes, new_recurrence
        #expect(tool?.parameters.count == 8)
    }

    @Test func updateEventToolRequiredParams() async throws {
        let server = CalendarMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "update_event" }

        let converted = tool?.toTool()
        #expect(converted?.required == ["event_title"])
    }

    // MARK: - get_free_slots Tool Tests

    @Test func getFreeSlotsToolExists() async throws {
        let server = CalendarMCPServer()
        let tools = try await server.listTools()
        let toolNames = tools.map { $0.name }

        #expect(toolNames.contains("get_free_slots"))
    }

    @Test func getFreeSlotsToolHasCorrectDescription() async throws {
        let server = CalendarMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "get_free_slots" }

        #expect(tool != nil)
        #expect(tool?.description.contains("free time slots") == true)
    }

    @Test func getFreeSlotsToolHasRequiredDateParameter() async throws {
        let server = CalendarMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "get_free_slots" }

        let param = tool?.parameters.first { $0.name == "date" }
        #expect(param != nil)
        #expect(param?.type == "string")
        #expect(param?.required == true)
    }

    @Test func getFreeSlotsToolHasOptionalMinDurationParameter() async throws {
        let server = CalendarMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "get_free_slots" }

        let param = tool?.parameters.first { $0.name == "min_duration" }
        #expect(param != nil)
        #expect(param?.type == "integer")
        #expect(param?.required == false)
    }

    @Test func getFreeSlotsToolParameterCount() async throws {
        let server = CalendarMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "get_free_slots" }

        #expect(tool?.parameters.count == 2)
    }

    @Test func getFreeSlotsToToolConversion() async throws {
        let server = CalendarMCPServer()
        let tools = try await server.listTools()
        let tool = tools.first { $0.name == "get_free_slots" }

        let converted = tool?.toTool()
        #expect(converted != nil)
        #expect(converted?.name == "get_free_slots")
        #expect(converted?.required == ["date"])
        #expect(converted?.parameters.count == 2)
    }

    // MARK: - parseRecurrence Tests

    @Test func parseRecurrenceDaily() {
        let rule = parseRecurrence("daily")
        #expect(rule != nil)
        #expect(rule?.frequency == .daily)
        #expect(rule?.interval == 1)
    }

    @Test func parseRecurrenceWeekly() {
        let rule = parseRecurrence("weekly")
        #expect(rule != nil)
        #expect(rule?.frequency == .weekly)
    }

    @Test func parseRecurrenceMonthly() {
        let rule = parseRecurrence("Monthly")
        #expect(rule != nil)
        #expect(rule?.frequency == .monthly)
    }

    @Test func parseRecurrenceYearly() {
        let rule = parseRecurrence("YEARLY")
        #expect(rule != nil)
        #expect(rule?.frequency == .yearly)
    }

    @Test func parseRecurrenceInvalid() {
        let rule = parseRecurrence("biweekly")
        #expect(rule == nil)
    }
}
