//
//  ReasonActModelsTests.swift
//  AI Helper2Tests
//
//  Tests for ReasonActStep
//

import Testing
import Foundation
@testable import AI_Helper2

struct ReasonActModelsTests {

    // MARK: - ReasonActStep Tests

    @Test func reasonActStepCreation() {
        let step = ReasonActStep(
            stepNumber: 1,
            assistantMessage: "I'll check your calendar",
            toolExecutions: []
        )

        #expect(step.stepNumber == 1)
        #expect(step.assistantMessage == "I'll check your calendar")
        #expect(step.toolExecutions.isEmpty)
    }

    @Test func reasonActStepWithToolExecutions() {
        let executions = [
            ReasonActStep.ToolExecution(
                toolName: "list_events",
                arguments: ["start_date": "2026-02-01"],
                result: "Found 3 events",
                isError: false,
                duration: 0.5
            ),
            ReasonActStep.ToolExecution(
                toolName: "create_event",
                arguments: ["title": "Meeting", "start_date": "2026-02-01 10:00"],
                result: "Event created",
                isError: false,
                duration: 0.8
            )
        ]

        let step = ReasonActStep(
            stepNumber: 1,
            assistantMessage: "Creating meeting",
            toolExecutions: executions
        )

        #expect(step.toolExecutions.count == 2)
    }

    // MARK: - ToolExecution Tests

    @Test func toolExecutionStatusIconSuccess() {
        let exec = ReasonActStep.ToolExecution(
            toolName: "list_events",
            arguments: [:],
            result: "OK",
            isError: false,
            duration: 0.1
        )

        #expect(exec.statusIcon == "\u{2705}") // checkmark
    }

    @Test func toolExecutionStatusIconError() {
        let exec = ReasonActStep.ToolExecution(
            toolName: "create_event",
            arguments: [:],
            result: "Failed",
            isError: true,
            duration: 0.1
        )

        #expect(exec.statusIcon == "\u{274C}") // cross mark
    }

    @Test func toolExecutionDurationString() {
        let exec = ReasonActStep.ToolExecution(
            toolName: "test",
            arguments: [:],
            result: "",
            isError: false,
            duration: 1.234
        )

        #expect(exec.durationString == "1.23s")
    }

    @Test func toolExecutionDurationStringZero() {
        let exec = ReasonActStep.ToolExecution(
            toolName: "test",
            arguments: [:],
            result: "",
            isError: false,
            duration: 0.0
        )

        #expect(exec.durationString == "0.00s")
    }

    @Test func toolExecutionArgumentsStringWithValidJSON() {
        let exec = ReasonActStep.ToolExecution(
            toolName: "create_event",
            arguments: ["title": "Meeting"],
            result: "",
            isError: false,
            duration: 0.1
        )

        let argsString = exec.argumentsString
        // Should be valid JSON containing the key and value
        #expect(argsString.contains("title"))
        #expect(argsString.contains("Meeting"))
    }

    @Test func toolExecutionArgumentsStringEmpty() {
        let exec = ReasonActStep.ToolExecution(
            toolName: "test",
            arguments: [:],
            result: "",
            isError: false,
            duration: 0.1
        )

        #expect(exec.argumentsString == "{}")
    }

}
