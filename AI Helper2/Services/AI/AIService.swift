import Foundation
import UIKit

class AIService: ObservableObject {
    private let urlSession = URLSession.shared
    
    func sendMessage(_ message: String, configuration: APIConfiguration) async throws -> String {
        let messageWithContext = addCommonContext(to: message)
        
        switch configuration.provider {
        case .openai:
            return try await sendOpenAIMessage(messageWithContext, configuration: configuration)
        case .claude:
            return try await sendClaudeMessage(messageWithContext, configuration: configuration)
        }
    }
    
    // Internal method for system prompts that already have context
    func sendMessageWithoutContext(_ message: String, configuration: APIConfiguration) async throws -> String {
        switch configuration.provider {
        case .openai:
            return try await sendOpenAIMessage(message, configuration: configuration)
        case .claude:
            return try await sendClaudeMessage(message, configuration: configuration)
        }
    }
    
    private func addCommonContext(to message: String) -> String {
        let now = Date()
        let calendar = Calendar.current
        let timeZone = TimeZone.current
        
        // Full date and time
        let fullDateFormatter = DateFormatter()
        fullDateFormatter.dateStyle = .full
        fullDateFormatter.timeStyle = .short
        
        // ISO format for easy parsing
        let isoDateFormatter = DateFormatter()
        isoDateFormatter.dateFormat = "yyyy-MM-dd"
        
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "EEEE"
        
        // Calculate relative dates
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: now) ?? now
        
        // Device/app context
        let locale = Locale.current
        let deviceModel = UIDevice.current.model
        
        let context = """
        Current context:
        - Current date and time: \(fullDateFormatter.string(from: now))
        - Today: \(isoDateFormatter.string(from: now)) (\(dayFormatter.string(from: now)))
        - Current time: \(timeFormatter.string(from: now))
        - Tomorrow: \(isoDateFormatter.string(from: tomorrow)) (\(dayFormatter.string(from: tomorrow)))
        - Next week (same day): \(isoDateFormatter.string(from: nextWeek))
        - Time zone: \(timeZone.identifier) (\(timeZone.abbreviation(for: now) ?? ""))
        - Week of year: \(calendar.component(.weekOfYear, from: now))
        - Device: \(deviceModel)
        - Locale: \(locale.identifier)
        
        User message: \(message)
        """
        
        return context
    }
    
    private func sendOpenAIMessage(_ message: String, configuration: APIConfiguration) async throws -> String {
        let url = URL(string: "\(configuration.provider.baseURL)/chat/completions")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestBody: [String: Any] = [
            "model": configuration.model,
            "messages": [
                ["role": "user", "content": message]
            ],
            "max_tokens": configuration.maxTokens,
            "temperature": configuration.temperature
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AIServiceError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIServiceError.invalidResponse
        }
        
        return content
    }
    
    private func sendClaudeMessage(_ message: String, configuration: APIConfiguration) async throws -> String {
        let url = URL(string: "\(configuration.provider.baseURL)/messages")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let requestBody: [String: Any] = [
            "model": configuration.model,
            "max_tokens": configuration.maxTokens,
            "temperature": configuration.temperature,
            "messages": [
                ["role": "user", "content": message]
            ]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await urlSession.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw AIServiceError.invalidResponse
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let firstContent = content.first,
              let text = firstContent["text"] as? String else {
            throw AIServiceError.invalidResponse
        }
        
        return text
    }
}

enum AIServiceError: Error, LocalizedError {
    case invalidResponse
    case noAPIKey
    case networkError
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from AI service"
        case .noAPIKey:
            return "API key is required"
        case .networkError:
            return "Network error occurred"
        }
    }
}