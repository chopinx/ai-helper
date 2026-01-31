import Foundation

// MARK: - Reason-Act Models

/// Represents a single step in the Reason-Act loop
struct ReasonActStep: Identifiable {
    let id = UUID()
    let stepNumber: Int
    let assistantMessage: String
    let toolExecutions: [ToolExecution]
    
    struct ToolExecution: Identifiable {
        let id = UUID()
        let toolName: String
        let arguments: [String: Any]
        let result: String
        let isError: Bool
        let duration: TimeInterval
        
        var argumentsString: String {
            guard let data = try? JSONSerialization.data(withJSONObject: arguments),
                  let string = String(data: data, encoding: .utf8) else {
                return "{}"
            }
            return string
        }
        
        var statusIcon: String {
            return isError ? "❌" : "✅"
        }
        
        var durationString: String {
            return String(format: "%.2fs", duration)
        }
    }
}

// MARK: - Error Types

enum ReasonActError: Error, LocalizedError {
    case consecutiveErrors(String)
    case maxStepsReached
    case toolHandlerNotConfigured
    case contextCompressionFailed
    
    var errorDescription: String? {
        switch self {
        case .consecutiveErrors(let message):
            return "Consecutive errors occurred: \(message)"
        case .maxStepsReached:
            return "Maximum reasoning steps reached"
        case .toolHandlerNotConfigured:
            return "Tool handler not configured"
        case .contextCompressionFailed:
            return "Context compression failed"
        }
    }
}