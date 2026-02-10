//
//  ModelsTests.swift
//  AI Helper2Tests
//
//  Tests for core data models, enums, and structs
//

import Testing
import Foundation
@testable import AI_Helper2

struct ModelsTests {

    // MARK: - AIProvider Tests

    @Test func aiProviderBaseURLs() {
        #expect(AIProvider.openai.baseURL == "https://api.openai.com/v1")
        #expect(AIProvider.claude.baseURL == "https://api.anthropic.com/v1")
    }

    @Test func aiProviderAvailableModels() {
        let openaiModels = AIProvider.openai.availableModels
        #expect(openaiModels.contains("gpt-4o"))
        #expect(openaiModels.contains("gpt-4o-mini"))
        #expect(openaiModels.contains("gpt-3.5-turbo"))

        let claudeModels = AIProvider.claude.availableModels
        #expect(claudeModels.contains("claude-3-5-sonnet-20241022"))
        #expect(claudeModels.contains("claude-3-5-haiku-20241022"))
        #expect(claudeModels.contains("claude-3-opus-20240229"))
    }

    @Test func aiProviderDefaultModel() {
        #expect(AIProvider.openai.defaultModel == "gpt-4o-mini")
        #expect(AIProvider.claude.defaultModel == "claude-3-5-haiku-20241022")
    }

    @Test func aiProviderDefaultModelIsInAvailableModels() {
        #expect(AIProvider.openai.availableModels.contains(AIProvider.openai.defaultModel))
        #expect(AIProvider.claude.availableModels.contains(AIProvider.claude.defaultModel))
    }

    @Test func aiProviderSupportsToolCalling() {
        #expect(AIProvider.openai.supportsToolCalling == true)
        #expect(AIProvider.claude.supportsToolCalling == true)
    }

    @Test func aiProviderCodable() throws {
        let provider = AIProvider.openai
        let data = try JSONEncoder().encode(provider)
        let decoded = try JSONDecoder().decode(AIProvider.self, from: data)
        #expect(decoded == provider)
    }

    @Test func aiProviderRawValues() {
        #expect(AIProvider.openai.rawValue == "OpenAI")
        #expect(AIProvider.claude.rawValue == "Claude")
    }

    @Test func aiProviderCaseIterable() {
        let allCases = AIProvider.allCases
        #expect(allCases.count == 2)
        #expect(allCases.contains(.openai))
        #expect(allCases.contains(.claude))
    }

    // MARK: - MaxTokensOption Tests

    @Test func maxTokensOptionRawValues() {
        #expect(MaxTokensOption.low.rawValue == 500)
        #expect(MaxTokensOption.medium.rawValue == 1000)
        #expect(MaxTokensOption.high.rawValue == 2000)
        #expect(MaxTokensOption.veryHigh.rawValue == 4000)
    }

    @Test func maxTokensOptionDisplayNames() {
        #expect(MaxTokensOption.low.displayName == "500 (Short)")
        #expect(MaxTokensOption.medium.displayName == "1000 (Medium)")
        #expect(MaxTokensOption.high.displayName == "2000 (Long)")
        #expect(MaxTokensOption.veryHigh.displayName == "4000 (Very Long)")
    }

    @Test func maxTokensOptionCaseIterable() {
        #expect(MaxTokensOption.allCases.count == 4)
    }

    // MARK: - APIConfiguration Tests

    @Test func apiConfigurationDefaults() {
        let config = APIConfiguration()

        #expect(config.provider == .openai)
        #expect(config.apiKey == "")
        #expect(config.model == AIProvider.openai.defaultModel)
        #expect(config.maxTokens == 1000)
        #expect(config.temperature == 0.7)
        #expect(config.enableMCP == true)
    }

    @Test func apiConfigurationCustomValues() {
        let config = APIConfiguration(
            provider: .claude,
            apiKey: "test-key",
            model: "claude-3-opus-20240229",
            maxTokens: 2000,
            temperature: 0.5,
            enableMCP: false
        )

        #expect(config.provider == .claude)
        #expect(config.apiKey == "test-key")
        #expect(config.model == "claude-3-opus-20240229")
        #expect(config.maxTokens == 2000)
        #expect(config.temperature == 0.5)
        #expect(config.enableMCP == false)
    }

    @Test func apiConfigurationEmptyModelUsesDefault() {
        let config = APIConfiguration(provider: .claude, model: "")
        #expect(config.model == AIProvider.claude.defaultModel)
    }

    @Test func apiConfigurationCodableExcludesAPIKey() throws {
        let config = APIConfiguration(
            provider: .openai,
            apiKey: "secret-key-should-not-be-encoded",
            model: "gpt-4o",
            maxTokens: 1000,
            temperature: 0.7,
            enableMCP: true
        )

        // Encode
        let data = try JSONEncoder().encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        // apiKey should NOT be in the encoded data
        #expect(json?["apiKey"] == nil)

        // Other fields should be present
        #expect(json?["provider"] as? String == "OpenAI")
        #expect(json?["model"] as? String == "gpt-4o")
        #expect(json?["maxTokens"] as? Int == 1000)

        // Decode back - apiKey should be empty
        let decoded = try JSONDecoder().decode(APIConfiguration.self, from: data)
        #expect(decoded.apiKey == "")
        #expect(decoded.provider == .openai)
        #expect(decoded.model == "gpt-4o")
        #expect(decoded.maxTokens == 1000)
    }

    // MARK: - ChatMessage Tests

    @Test func chatMessageCreation() {
        let msg = ChatMessage(content: "Hello", isUser: true)

        #expect(msg.content == "Hello")
        #expect(msg.isUser == true)
        #expect(msg.id != UUID()) // Has a unique ID
    }

    @Test func chatMessageCodable() throws {
        let original = ChatMessage(content: "Test message", isUser: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.content == original.content)
        #expect(decoded.isUser == original.isUser)
    }

    // MARK: - PromptCategory Tests

    @Test func promptCategoryColors() {
        #expect(PromptCategory.calendar.color == "blue")
        #expect(PromptCategory.productivity.color == "green")
        #expect(PromptCategory.creative.color == "purple")
        #expect(PromptCategory.analysis.color == "orange")
        #expect(PromptCategory.learning.color == "red")
    }

    @Test func promptCategoryCaseIterable() {
        #expect(PromptCategory.allCases.count == 5)
    }

    @Test func promptCategoryCodable() throws {
        let category = PromptCategory.calendar
        let data = try JSONEncoder().encode(category)
        let decoded = try JSONDecoder().decode(PromptCategory.self, from: data)
        #expect(decoded == category)
    }

    // MARK: - ProcessingStatus Tests

    @Test func processingStatusDisplayText() {
        #expect(ProcessingStatus.idle.displayText == "")
        #expect(ProcessingStatus.loadingTools.displayText == "Loading tools...")
        #expect(ProcessingStatus.thinkingStep(2).displayText == "Thinking (Step 2)...")
        #expect(ProcessingStatus.callingTool("create_event").displayText == "Calling create_event...")
        #expect(ProcessingStatus.processingToolResult("list_events").displayText == "Processing list_events...")
        #expect(ProcessingStatus.generatingResponse.displayText == "Generating response...")
        #expect(ProcessingStatus.completed.displayText == "Done")
        #expect(ProcessingStatus.error("Something failed").displayText == "Error: Something failed")
    }

    @Test func processingStatusIcon() {
        #expect(ProcessingStatus.idle.icon == "")
        #expect(ProcessingStatus.loadingTools.icon == "wrench.and.screwdriver")
        #expect(ProcessingStatus.thinkingStep(1).icon == "brain")
        #expect(ProcessingStatus.callingTool("test").icon == "hammer")
        #expect(ProcessingStatus.processingToolResult("test").icon == "gearshape")
        #expect(ProcessingStatus.generatingResponse.icon == "text.bubble")
        #expect(ProcessingStatus.completed.icon == "checkmark.circle")
        #expect(ProcessingStatus.error("err").icon == "exclamationmark.triangle")
    }

    @Test func processingStatusIsActive() {
        // Inactive states
        #expect(ProcessingStatus.idle.isActive == false)
        #expect(ProcessingStatus.completed.isActive == false)
        #expect(ProcessingStatus.error("err").isActive == false)

        // Active states
        #expect(ProcessingStatus.loadingTools.isActive == true)
        #expect(ProcessingStatus.thinkingStep(1).isActive == true)
        #expect(ProcessingStatus.callingTool("test").isActive == true)
        #expect(ProcessingStatus.processingToolResult("test").isActive == true)
        #expect(ProcessingStatus.generatingResponse.isActive == true)
    }

    @Test func processingStatusStepNumber() {
        #expect(ProcessingStatus.thinkingStep(3).stepNumber == 3)
        #expect(ProcessingStatus.idle.stepNumber == nil)
        #expect(ProcessingStatus.callingTool("test").stepNumber == nil)
    }

    @Test func processingStatusIsError() {
        #expect(ProcessingStatus.error("fail").isError == true)
        #expect(ProcessingStatus.idle.isError == false)
        #expect(ProcessingStatus.completed.isError == false)
    }

    @Test func processingStatusEquatable() {
        #expect(ProcessingStatus.idle == ProcessingStatus.idle)
        #expect(ProcessingStatus.thinkingStep(1) == ProcessingStatus.thinkingStep(1))
        #expect(ProcessingStatus.thinkingStep(1) != ProcessingStatus.thinkingStep(2))
        #expect(ProcessingStatus.error("a") == ProcessingStatus.error("a"))
        #expect(ProcessingStatus.error("a") != ProcessingStatus.error("b"))
    }

    // MARK: - PendingAction Tests

    @Test func pendingActionDeleteProperties() {
        let action = PendingAction(
            type: .delete,
            toolName: "delete_event",
            arguments: ["title": "Meeting"],
            title: "Meeting",
            details: "Delete this event",
            isCalendar: true
        )

        #expect(action.icon == "trash")
        #expect(action.actionText == "Delete")
    }

    @Test func pendingActionUpdateProperties() {
        let action = PendingAction(
            type: .update,
            toolName: "update_event",
            arguments: [:],
            title: "Meeting",
            details: "",
            isCalendar: true
        )

        #expect(action.icon == "pencil")
        #expect(action.actionText == "Update")
    }

    @Test func pendingActionCompleteProperties() {
        let action = PendingAction(
            type: .complete,
            toolName: "complete_reminder",
            arguments: [:],
            title: "Task",
            details: "",
            isCalendar: false
        )

        #expect(action.icon == "checkmark.circle")
        #expect(action.actionText == "Complete")
    }

    // MARK: - AIError Tests

    @Test func aiErrorDescriptions() {
        #expect(AIError.invalidResponse.errorDescription == "Invalid response from AI")
        #expect(AIError.apiError("test error").errorDescription == "test error")
        #expect(AIError.noAPIKey.errorDescription == "API key not configured")
    }

    // MARK: - SuggestedPrompt Tests

    @Test func suggestedPromptCreation() {
        let prompt = SuggestedPrompt(
            title: "Test",
            prompt: "Test prompt",
            category: .productivity,
            icon: "star"
        )

        #expect(prompt.title == "Test")
        #expect(prompt.prompt == "Test prompt")
        #expect(prompt.category == .productivity)
        #expect(prompt.icon == "star")
    }

    @Test func suggestedPromptCodable() throws {
        let original = SuggestedPrompt(
            title: "Test",
            prompt: "Do something",
            category: .calendar,
            icon: "calendar"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SuggestedPrompt.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.title == original.title)
        #expect(decoded.prompt == original.prompt)
        #expect(decoded.category == original.category)
        #expect(decoded.icon == original.icon)
    }
}
