import Foundation

class AIService: ObservableObject {
    private let urlSession = URLSession.shared
    
    func sendMessage(_ message: String, configuration: APIConfiguration) async throws -> String {
        switch configuration.provider {
        case .openai:
            return try await sendOpenAIMessage(message, configuration: configuration)
        case .claude:
            return try await sendClaudeMessage(message, configuration: configuration)
        }
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