import Foundation
import SwiftUI

// MARK: - Processing Status

enum ProcessingStatus: Equatable {
    case idle
    case loadingTools
    case thinkingStep(Int)
    case callingTool(String)
    case processingToolResult(String)
    case generatingResponse
    case completed
    case error(String)

    var displayText: String {
        switch self {
        case .idle:
            return ""
        case .loadingTools:
            return "Loading tools..."
        case .thinkingStep(let step):
            return "Thinking (Step \(step))..."
        case .callingTool(let toolName):
            return "Calling \(toolName)..."
        case .processingToolResult(let toolName):
            return "Processing \(toolName)..."
        case .generatingResponse:
            return "Generating response..."
        case .completed:
            return "Done"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    var isError: Bool {
        guard case .error = self else { return false }
        return true
    }
}

// MARK: - Process Tracker (Dynamic UI)

/// Tracks the entire processing workflow for dynamic UI display
class ProcessTracker: ObservableObject {
    @Published var iterations: [ProcessIteration] = []
    @Published var currentPhase: ProcessPhase = .idle
    @Published var toolsLoaded: [String] = []

    func reset() {
        iterations.removeAll()
        currentPhase = .idle
        toolsLoaded.removeAll()
    }

    func setToolsLoaded(_ tools: [String]) {
        toolsLoaded = tools
    }

    func startIteration(_ number: Int) {
        let iteration = ProcessIteration(number: number)
        iterations.append(iteration)
        currentPhase = .thinking
    }

    func addToolCall(name: String, isCalendar: Bool) {
        guard var last = iterations.last else { return }
        let toolCall = ToolCallRecord(name: name, isCalendar: isCalendar)
        last.toolCalls.append(toolCall)
        iterations[iterations.count - 1] = last
        currentPhase = .callingTool(name)
    }

    func completeToolCall(name: String, success: Bool, message: String) {
        guard var last = iterations.last,
              let idx = last.toolCalls.lastIndex(where: { $0.name == name && $0.status == .running }) else { return }
        last.toolCalls[idx].status = success ? .success : .failed
        last.toolCalls[idx].resultPreview = String(message.prefix(100))
        last.toolCalls[idx].endTime = Date()
        iterations[iterations.count - 1] = last
        currentPhase = .processingResult(name)
    }

    func completeIteration() {
        guard var last = iterations.last else { return }
        last.endTime = Date()
        iterations[iterations.count - 1] = last
    }

    func setCompleted() {
        currentPhase = .completed
    }

    func setError(_ message: String) {
        currentPhase = .error(message)
    }
}

enum ProcessPhase: Equatable {
    case idle
    case loadingTools
    case thinking
    case callingTool(String)
    case processingResult(String)
    case completed
    case error(String)
}

struct ProcessIteration: Identifiable {
    let id = UUID()
    let number: Int
    var toolCalls: [ToolCallRecord] = []
    let startTime = Date()
    var endTime: Date?

    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }
}

struct ToolCallRecord: Identifiable {
    let id = UUID()
    let name: String
    let isCalendar: Bool
    var status: ToolCallStatus = .running
    var resultPreview: String = ""
    let startTime = Date()
    var endTime: Date?

    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }

    var icon: String {
        isCalendar ? "calendar" : "checkmark.circle"
    }

    var statusIcon: String {
        switch status {
        case .running: return "arrow.trianglehead.2.clockwise"
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var statusColor: Color {
        switch status {
        case .running: return DS.Colors.accent
        case .success: return DS.Colors.success
        case .failed: return DS.Colors.error
        }
    }
}

enum ToolCallStatus {
    case running
    case success
    case failed
}

// MARK: - Process Update Events (for SimpleAIService callbacks)

enum ProcessUpdate {
    case toolsLoaded([String])
    case iterationStarted(Int)
    case toolCallStarted(name: String, isCalendar: Bool)
    case toolCallCompleted(name: String, success: Bool, message: String)
    case iterationCompleted
    case completed
    case error(String)
}

// MARK: - Pending Action (Confirmation for delete/update)

struct PendingAction: Identifiable {
    let id = UUID()
    let type: PendingActionType
    let toolName: String
    let arguments: [String: Any]
    let title: String
    let details: String
    let isCalendar: Bool

    var icon: String {
        switch type {
        case .delete: return "trash"
        case .update: return "pencil"
        case .complete: return "checkmark.circle"
        }
    }

    var color: Color {
        switch type {
        case .delete: return DS.Colors.error
        case .update: return DS.Colors.warning
        case .complete: return DS.Colors.success
        }
    }

    var actionText: String {
        switch type {
        case .delete: return "Delete"
        case .update: return "Update"
        case .complete: return "Complete"
        }
    }
}

enum PendingActionType {
    case delete
    case update
    case complete
}
