//
//  ProcessTrackerTests.swift
//  AI Helper2Tests
//
//  Tests for ProcessTracker state management
//

import Testing
import Foundation
@testable import AI_Helper2

struct ProcessTrackerTests {

    // MARK: - Initial State

    @Test func initialState() {
        let tracker = ProcessTracker()

        #expect(tracker.iterations.isEmpty)
        #expect(tracker.currentPhase == .idle)
        #expect(tracker.toolsLoaded.isEmpty)
    }

    // MARK: - Reset

    @Test func resetClearsState() {
        let tracker = ProcessTracker()
        tracker.setToolsLoaded(["tool1", "tool2"])
        tracker.startIteration(1)
        tracker.currentPhase = .thinking

        tracker.reset()

        #expect(tracker.iterations.isEmpty)
        #expect(tracker.currentPhase == .idle)
        #expect(tracker.toolsLoaded.isEmpty)
    }

    // MARK: - Tools Loaded

    @Test func setToolsLoaded() {
        let tracker = ProcessTracker()
        let tools = ["create_event", "list_events", "create_reminder"]

        tracker.setToolsLoaded(tools)

        #expect(tracker.toolsLoaded.count == 3)
        #expect(tracker.toolsLoaded.contains("create_event"))
        #expect(tracker.toolsLoaded.contains("list_events"))
        #expect(tracker.toolsLoaded.contains("create_reminder"))
    }

    // MARK: - Iteration Management

    @Test func startIteration() {
        let tracker = ProcessTracker()

        tracker.startIteration(1)

        #expect(tracker.iterations.count == 1)
        #expect(tracker.iterations[0].number == 1)
        #expect(tracker.iterations[0].toolCalls.isEmpty)
        #expect(tracker.currentPhase == .thinking)
    }

    @Test func multipleIterations() {
        let tracker = ProcessTracker()

        tracker.startIteration(1)
        tracker.startIteration(2)
        tracker.startIteration(3)

        #expect(tracker.iterations.count == 3)
        #expect(tracker.iterations[0].number == 1)
        #expect(tracker.iterations[1].number == 2)
        #expect(tracker.iterations[2].number == 3)
    }

    @Test func completeIteration() {
        let tracker = ProcessTracker()
        tracker.startIteration(1)

        #expect(tracker.iterations[0].endTime == nil)

        tracker.completeIteration()

        #expect(tracker.iterations[0].endTime != nil)
    }

    @Test func completeIterationWithNoIterationsDoesNothing() {
        let tracker = ProcessTracker()
        // Should not crash
        tracker.completeIteration()
        #expect(tracker.iterations.isEmpty)
    }

    // MARK: - Tool Calls

    @Test func addToolCall() {
        let tracker = ProcessTracker()
        tracker.startIteration(1)

        tracker.addToolCall(name: "create_event", isCalendar: true)

        #expect(tracker.iterations[0].toolCalls.count == 1)
        #expect(tracker.iterations[0].toolCalls[0].name == "create_event")
        #expect(tracker.iterations[0].toolCalls[0].isCalendar == true)
        #expect(tracker.iterations[0].toolCalls[0].status == .running)
        #expect(tracker.currentPhase == .callingTool("create_event"))
    }

    @Test func addToolCallWithoutIterationDoesNothing() {
        let tracker = ProcessTracker()
        // Should not crash when no iteration exists
        tracker.addToolCall(name: "test", isCalendar: false)
        #expect(tracker.iterations.isEmpty)
    }

    @Test func completeToolCallSuccess() {
        let tracker = ProcessTracker()
        tracker.startIteration(1)
        tracker.addToolCall(name: "list_events", isCalendar: true)

        tracker.completeToolCall(name: "list_events", success: true, message: "Found 3 events")

        let toolCall = tracker.iterations[0].toolCalls[0]
        #expect(toolCall.status == .success)
        #expect(toolCall.resultPreview == "Found 3 events")
        #expect(toolCall.endTime != nil)
        #expect(tracker.currentPhase == .processingResult("list_events"))
    }

    @Test func completeToolCallFailure() {
        let tracker = ProcessTracker()
        tracker.startIteration(1)
        tracker.addToolCall(name: "create_event", isCalendar: true)

        tracker.completeToolCall(name: "create_event", success: false, message: "Permission denied")

        let toolCall = tracker.iterations[0].toolCalls[0]
        #expect(toolCall.status == .failed)
        #expect(toolCall.resultPreview == "Permission denied")
    }

    @Test func completeToolCallTruncatesLongMessages() {
        let tracker = ProcessTracker()
        tracker.startIteration(1)
        tracker.addToolCall(name: "list_events", isCalendar: true)

        let longMessage = String(repeating: "A", count: 200)
        tracker.completeToolCall(name: "list_events", success: true, message: longMessage)

        let preview = tracker.iterations[0].toolCalls[0].resultPreview
        #expect(preview.count == 100) // Truncated to 100 chars
    }

    @Test func multipleToolCallsInOneIteration() {
        let tracker = ProcessTracker()
        tracker.startIteration(1)

        tracker.addToolCall(name: "list_events", isCalendar: true)
        tracker.completeToolCall(name: "list_events", success: true, message: "OK")

        tracker.addToolCall(name: "create_event", isCalendar: true)
        tracker.completeToolCall(name: "create_event", success: true, message: "Created")

        #expect(tracker.iterations[0].toolCalls.count == 2)
        #expect(tracker.iterations[0].toolCalls[0].name == "list_events")
        #expect(tracker.iterations[0].toolCalls[1].name == "create_event")
    }

    // MARK: - Phase Transitions

    @Test func setCompleted() {
        let tracker = ProcessTracker()
        tracker.setCompleted()
        #expect(tracker.currentPhase == .completed)
    }

    @Test func setError() {
        let tracker = ProcessTracker()
        tracker.setError("Something went wrong")
        #expect(tracker.currentPhase == .error("Something went wrong"))
    }

    // MARK: - Full Workflow

    @Test func fullWorkflow() {
        let tracker = ProcessTracker()

        // Load tools
        tracker.setToolsLoaded(["list_events", "create_event"])
        #expect(tracker.toolsLoaded.count == 2)

        // Iteration 1: list events
        tracker.startIteration(1)
        #expect(tracker.currentPhase == .thinking)

        tracker.addToolCall(name: "list_events", isCalendar: true)
        #expect(tracker.currentPhase == .callingTool("list_events"))

        tracker.completeToolCall(name: "list_events", success: true, message: "2 events found")
        #expect(tracker.currentPhase == .processingResult("list_events"))

        tracker.completeIteration()

        // Iteration 2: create event
        tracker.startIteration(2)
        tracker.addToolCall(name: "create_event", isCalendar: true)
        tracker.completeToolCall(name: "create_event", success: true, message: "Event created")
        tracker.completeIteration()

        tracker.setCompleted()

        #expect(tracker.iterations.count == 2)
        #expect(tracker.currentPhase == .completed)
    }

    // MARK: - ProcessPhase Equatable

    @Test func processPhaseEquatable() {
        #expect(ProcessPhase.idle == ProcessPhase.idle)
        #expect(ProcessPhase.thinking == ProcessPhase.thinking)
        #expect(ProcessPhase.callingTool("a") == ProcessPhase.callingTool("a"))
        #expect(ProcessPhase.callingTool("a") != ProcessPhase.callingTool("b"))
        #expect(ProcessPhase.error("x") == ProcessPhase.error("x"))
        #expect(ProcessPhase.completed == ProcessPhase.completed)
    }

    // MARK: - ProcessIteration Tests

    @Test func processIterationDuration() {
        let tracker = ProcessTracker()
        tracker.startIteration(1)

        // Duration should be non-negative (endTime is nil so it uses Date())
        #expect(tracker.iterations[0].duration >= 0)

        tracker.completeIteration()
        #expect(tracker.iterations[0].duration >= 0)
    }

    // MARK: - ToolCallRecord Tests

    @Test func toolCallRecordIcon() {
        let calendarRecord = ToolCallRecord(name: "create_event", isCalendar: true)
        let reminderRecord = ToolCallRecord(name: "create_reminder", isCalendar: false)

        #expect(calendarRecord.icon == "calendar")
        #expect(reminderRecord.icon == "checkmark.circle")
    }

    @Test func toolCallRecordStatusIcon() {
        var record = ToolCallRecord(name: "test", isCalendar: false)
        #expect(record.statusIcon == "arrow.trianglehead.2.clockwise") // running

        record.status = .success
        #expect(record.statusIcon == "checkmark.circle.fill")

        record.status = .failed
        #expect(record.statusIcon == "xmark.circle.fill")
    }

    @Test func toolCallRecordDuration() {
        let record = ToolCallRecord(name: "test", isCalendar: false)

        // Before completion, duration is from startTime to now
        #expect(record.duration >= 0)
    }
}
