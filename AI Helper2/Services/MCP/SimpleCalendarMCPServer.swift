import Foundation
import EventKit

class SimpleCalendarMCPServer: SimpleMCPServer {
    private let eventStore = EKEventStore()
    private var isAuthorized = false
    
    func initialize() async throws {
        try await requestCalendarAccess()
    }
    
    func listTools() async throws -> [SimpleMCPTool] {
        return [
            SimpleMCPTool(
                name: "create_event",
                description: "Create a new calendar event"
            )
        ]
    }
    
    func callTool(name: String, arguments: [String : Any]) async throws -> SimpleMCPResult {
        guard isAuthorized else {
            throw SimpleMCPError.permissionDenied("Calendar access not granted")
        }
        
        switch name {
        case "create_event":
            return try await createEvent(arguments: arguments)
        default:
            throw SimpleMCPError.toolNotFound(name)
        }
    }
    
    private func requestCalendarAccess() async throws {
        let status = EKEventStore.authorizationStatus(for: .event)
        
        switch status {
        case .fullAccess, .authorized:
            isAuthorized = true
        case .notDetermined:
            if #available(iOS 17.0, *) {
                let granted = try await eventStore.requestFullAccessToEvents()
                isAuthorized = granted
                if !granted {
                    throw SimpleMCPError.permissionDenied("Calendar access denied by user")
                }
            } else {
                let granted = try await eventStore.requestAccess(to: .event)
                isAuthorized = granted
                if !granted {
                    throw SimpleMCPError.permissionDenied("Calendar access denied by user")
                }
            }
        case .denied, .restricted:
            throw SimpleMCPError.permissionDenied("Calendar access is denied or restricted")
        case .writeOnly:
            throw SimpleMCPError.permissionDenied("Calendar access is write-only, need full access")
        @unknown default:
            throw SimpleMCPError.permissionDenied("Unknown calendar access status")
        }
    }
    
    private func createEvent(arguments: [String: Any]) async throws -> SimpleMCPResult {
        guard let title = arguments["title"] as? String,
              let startDateString = arguments["start_date"] as? String,
              let endDateString = arguments["end_date"] as? String else {
            throw SimpleMCPError.invalidArguments("Missing required fields: title, start_date, end_date")
        }
        
        let dateFormatter = ISO8601DateFormatter()
        guard let startDate = dateFormatter.date(from: startDateString),
              let endDate = dateFormatter.date(from: endDateString) else {
            throw SimpleMCPError.invalidArguments("Invalid date format. Use ISO 8601 format.")
        }
        
        let event = EKEvent(eventStore: eventStore)
        event.title = title
        event.startDate = startDate
        event.endDate = endDate
        event.notes = arguments["notes"] as? String
        event.calendar = eventStore.defaultCalendarForNewEvents
        
        do {
            try eventStore.save(event, span: .thisEvent)
            return SimpleMCPResult(
                message: "Calendar event '\(title)' created successfully for \(DateFormatter.localizedString(from: startDate, dateStyle: .medium, timeStyle: .short))",
                isError: false
            )
        } catch {
            throw SimpleMCPError.operationFailed("Failed to create event: \(error.localizedDescription)")
        }
    }
}