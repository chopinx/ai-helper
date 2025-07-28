import Foundation

enum AIProvider: String, CaseIterable, Codable {
    case openai = "OpenAI"
    case claude = "Claude"
    
    var baseURL: String {
        switch self {
        case .openai:
            return "https://api.openai.com/v1"
        case .claude:
            return "https://api.anthropic.com/v1"
        }
    }
    
    var availableModels: [String] {
        switch self {
        case .openai:
            return [
                "gpt-4o",
                "gpt-4o-mini",
                "gpt-4-turbo",
                "gpt-4",
                "gpt-3.5-turbo",
                "gpt-3.5-turbo-16k"
            ]
        case .claude:
            return [
                "claude-3-5-sonnet-20241022",
                "claude-3-5-haiku-20241022",
                "claude-3-opus-20240229",
                "claude-3-sonnet-20240229",
                "claude-3-haiku-20240307"
            ]
        }
    }
    
    var defaultModel: String {
        switch self {
        case .openai:
            return "gpt-3.5-turbo"
        case .claude:
            return "claude-3-haiku-20240307"
        }
    }
}

enum MaxTokensOption: Int, CaseIterable {
    case low = 500
    case medium = 1000
    case high = 2000
    case veryHigh = 4000
    
    var displayName: String {
        switch self {
        case .low:
            return "500 (Short)"
        case .medium:
            return "1000 (Medium)"
        case .high:
            return "2000 (Long)"
        case .veryHigh:
            return "4000 (Very Long)"
        }
    }
}

struct APIConfiguration: Codable {
    var provider: AIProvider
    var apiKey: String
    var model: String
    var maxTokens: Int
    var temperature: Double
    
    init(provider: AIProvider = .openai, apiKey: String = "", model: String = "", maxTokens: Int = 1000, temperature: Double = 0.7) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model.isEmpty ? provider.defaultModel : model
        self.maxTokens = maxTokens
        self.temperature = temperature
    }
}

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let content: String
    let isUser: Bool
    let timestamp: Date
    
    init(content: String, isUser: Bool) {
        self.id = UUID()
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
    }
}

class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var currentMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var apiConfiguration: APIConfiguration = APIConfiguration()
    
    private let userDefaults = UserDefaults.standard
    private let configKey = "APIConfiguration"
    
    init() {
        loadConfiguration()
    }
    
    func saveConfiguration() {
        if let encoded = try? JSONEncoder().encode(apiConfiguration) {
            userDefaults.set(encoded, forKey: configKey)
        }
    }
    
    func loadConfiguration() {
        if let data = userDefaults.data(forKey: configKey),
           let config = try? JSONDecoder().decode(APIConfiguration.self, from: data) {
            apiConfiguration = config
        }
    }
}