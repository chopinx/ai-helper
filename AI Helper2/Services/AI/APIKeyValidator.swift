import Foundation
import os.log

enum APIKeyValidationResult {
    case valid
    case invalid(String)
    case networkError(String)
}

class APIKeyValidator {
    private let logger = Logger(subsystem: "com.aihelper.validation", category: "APIKeyValidator")

    func validate(apiKey: String, provider: AIProvider) async -> APIKeyValidationResult {
        guard !apiKey.isEmpty else {
            return .invalid("API key is empty")
        }

        logger.info("🔑 Validating \(provider.rawValue) API key...")

        switch provider {
        case .openai:
            return await validateOpenAI(apiKey: apiKey)
        case .claude:
            return await validateClaude(apiKey: apiKey)
        }
    }

    private func validateOpenAI(apiKey: String) async -> APIKeyValidationResult {
        let url = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .networkError("Invalid response")
            }

            switch httpResponse.statusCode {
            case 200:
                logger.info("✅ OpenAI API key valid")
                return .valid
            case 401:
                logger.warning("❌ OpenAI API key invalid")
                return .invalid("Invalid API key")
            case 429:
                logger.warning("⚠️ OpenAI rate limited, assuming valid")
                return .valid
            default:
                return .invalid("Unexpected status: \(httpResponse.statusCode)")
            }
        } catch {
            logger.error("❌ OpenAI validation error: \(error.localizedDescription)")
            return .networkError(error.localizedDescription)
        }
    }

    private func validateClaude(apiKey: String) async -> APIKeyValidationResult {
        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 10

        let body: [String: Any] = [
            "model": "claude-haiku-4-5",
            "max_tokens": 1,
            "messages": [["role": "user", "content": "hi"]]
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .networkError("Invalid response")
            }

            switch httpResponse.statusCode {
            case 200:
                logger.info("✅ Claude API key valid")
                return .valid
            case 401:
                logger.warning("❌ Claude API key invalid")
                return .invalid("Invalid API key")
            case 429:
                logger.warning("⚠️ Claude rate limited, assuming valid")
                return .valid
            default:
                return .invalid("Unexpected status: \(httpResponse.statusCode)")
            }
        } catch {
            logger.error("❌ Claude validation error: \(error.localizedDescription)")
            return .networkError(error.localizedDescription)
        }
    }
}
