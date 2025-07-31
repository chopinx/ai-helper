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
                "gpt-4o",              // ✅ Tool calling supported
                "gpt-4o-mini",         // ✅ Tool calling supported
                "gpt-4-turbo",         // ✅ Tool calling supported
                "gpt-4",               // ✅ Tool calling supported
                "gpt-3.5-turbo",       // ✅ Tool calling supported
                "gpt-3.5-turbo-16k"    // ✅ Tool calling supported
            ]
        case .claude:
            return [
                "claude-3-5-sonnet-20241022",  // ✅ Tool calling supported
                "claude-3-5-haiku-20241022",   // ✅ Tool calling supported
                "claude-3-opus-20240229",      // ✅ Tool calling supported
                "claude-3-sonnet-20240229",    // ✅ Tool calling supported
                "claude-3-haiku-20240307"      // ✅ Tool calling supported
            ]
        }
    }
    
    var defaultModel: String {
        switch self {
        case .openai:
            return "gpt-4o-mini"  // Default to a model with tool calling support
        case .claude:
            return "claude-3-5-haiku-20241022"  // Default to newest model with tool calling
        }
    }
    
    /// Check if the current model supports tool calling
    var supportsToolCalling: Bool {
        // All current models in availableModels support tool calling
        return availableModels.contains(where: { $0 == defaultModel })
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
    var enableMCP: Bool
    
    init(provider: AIProvider = .openai, apiKey: String = "", model: String = "", maxTokens: Int = 1000, temperature: Double = 0.7, enableMCP: Bool = true) {
        self.provider = provider
        self.apiKey = apiKey
        self.model = model.isEmpty ? provider.defaultModel : model
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.enableMCP = enableMCP
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
    @Published var showMCPDetails: Bool = false
    
    private let aiService = AIService()
    private let mcpAIService = MCPAIService()
    private let userDefaults = UserDefaults.standard
    private let configKey = "APIConfiguration"
    
    var mcpManager: MCPManager {
        return mcpAIService.mcpManager
    }
    
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
    
    func sendMessage() async {
        guard !currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !apiConfiguration.apiKey.isEmpty else { return }
        
        let userMessage = ChatMessage(content: currentMessage, isUser: true)
        
        await MainActor.run {
            messages.append(userMessage)
            isLoading = true
        }
        
        let messageToSend = currentMessage
        
        await MainActor.run {
            currentMessage = ""
        }
        
        do {
            let response: String
            if apiConfiguration.enableMCP {
                // Get recent conversation history for context (last 5 messages)
                let recentHistory = messages.suffix(5).map { $0.content }
                response = try await mcpAIService.sendMessage(messageToSend, conversationHistory: Array(recentHistory), configuration: apiConfiguration)
            } else {
                response = try await aiService.sendMessage(messageToSend, configuration: apiConfiguration)
            }
            
            let aiMessage = ChatMessage(content: response, isUser: false)
            
            await MainActor.run {
                messages.append(aiMessage)
                isLoading = false
            }
        } catch {
            let errorMessage = ChatMessage(content: "Error: \(error.localizedDescription)", isUser: false)
            await MainActor.run {
                messages.append(errorMessage)
                isLoading = false
            }
        }
    }
}