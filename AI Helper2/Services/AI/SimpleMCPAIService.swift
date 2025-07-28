import Foundation

class SimpleMCPAIService: ObservableObject {
    private let aiService = AIService()
    private let mcpManager = SimpleMCPManager()
    
    init() {
        // Initialize calendar integration
        let calendarServer = SimpleCalendarMCPServer()
        mcpManager.enableCalendarIntegration(calendarServer)
    }
    
    func sendMessage(_ message: String, configuration: APIConfiguration) async throws -> String {
        // Check if message contains calendar creation request
        if containsCalendarRequest(message) && mcpManager.isCalendarEnabled {
            return try await handleCalendarRequest(message, configuration: configuration)
        }
        
        // Regular AI response
        return try await aiService.sendMessage(message, configuration: configuration)
    }
    
    private func containsCalendarRequest(_ message: String) -> Bool {
        let keywords = ["create event", "schedule", "meeting", "appointment", "calendar", "remind me on"]
        let lowercaseMessage = message.lowercased()
        return keywords.contains { lowercaseMessage.contains($0) }
    }
    
    private func handleCalendarRequest(_ message: String, configuration: APIConfiguration) async throws -> String {
        // Use AI to extract event details with current context
        let now = Date()
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        
        let extractionPrompt = """
        Current context for date/time parsing:
        - Today's date: \(dateFormatter.string(from: now)) (\(dayFormatter.string(from: now)))
        - Current time: \(timeFormatter.string(from: now))
        
        Extract calendar event details from this message: "\(message)"
        
        Please provide:
        - title: brief event title
        - date: date mentioned (use today's date if none specified or relative terms like "tomorrow", "next week")
        - time: time mentioned (use current time + 1 hour if none specified)
        - duration: how long the event should be (default 1 hour)
        - notes: any additional details
        
        For relative dates:
        - "today" = \(dateFormatter.string(from: now))
        - "tomorrow" = \(dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: 1, to: now) ?? now))
        - "next week" = \(dateFormatter.string(from: Calendar.current.date(byAdding: .weekOfYear, value: 1, to: now) ?? now))
        
        Respond in this exact format:
        TITLE: [event title]
        DATE: [YYYY-MM-DD]
        TIME: [HH:MM]
        DURATION: [number of hours]
        NOTES: [additional details or none]
        """
        
        let aiResponse = try await aiService.sendMessageWithoutContext(extractionPrompt, configuration: configuration)
        let eventDetails = parseEventDetails(from: aiResponse)
        
        // Create calendar event using MCP
        do {
            let startDate = combineDateTime(date: eventDetails.date, time: eventDetails.time)
            let endDate = startDate.addingTimeInterval(TimeInterval(eventDetails.duration * 3600))
            
            let result = try await mcpManager.createCalendarEvent(
                title: eventDetails.title,
                startDate: startDate,
                endDate: endDate,
                notes: eventDetails.notes.isEmpty ? nil : eventDetails.notes
            )
            
            if result.isError {
                return "I tried to create the calendar event but encountered an error: \(result.message)"
            } else {
                return "✅ \(result.message)"
            }
            
        } catch {
            return "I couldn't create the calendar event: \(error.localizedDescription)"
        }
    }
    
    private func parseEventDetails(from response: String) -> EventDetails {
        var title = "New Event"
        var date = Date()
        var time = Date()
        var duration = 1.0
        var notes = ""
        
        let lines = response.components(separatedBy: .newlines)
        
        for line in lines {
            if line.hasPrefix("TITLE:") {
                title = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("DATE:") {
                let dateString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if let parsedDate = parseDate(dateString) {
                    date = parsedDate
                }
            } else if line.hasPrefix("TIME:") {
                let timeString = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if let parsedTime = parseTime(timeString) {
                    time = parsedTime
                }
            } else if line.hasPrefix("DURATION:") {
                let durationString = String(line.dropFirst(9)).trimmingCharacters(in: .whitespaces)
                if let parsedDuration = Double(durationString.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) {
                    duration = parsedDuration
                }
            } else if line.hasPrefix("NOTES:") {
                notes = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
                if notes.lowercased() == "none" {
                    notes = ""
                }
            }
        }
        
        return EventDetails(title: title, date: date, time: time, duration: duration, notes: notes)
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: dateString)
    }
    
    private func parseTime(_ timeString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.date(from: timeString)
    }
    
    private func combineDateTime(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)
        
        var combined = DateComponents()
        combined.year = dateComponents.year
        combined.month = dateComponents.month
        combined.day = dateComponents.day
        combined.hour = timeComponents.hour
        combined.minute = timeComponents.minute
        
        return calendar.date(from: combined) ?? Date()
    }
}

struct EventDetails {
    let title: String
    let date: Date
    let time: Date
    let duration: Double
    let notes: String
}