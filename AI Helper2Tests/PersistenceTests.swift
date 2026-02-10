//
//  PersistenceTests.swift
//  AI Helper2Tests
//
//  Tests for JSON-based conversation persistence
//

import Testing
import Foundation
@testable import AI_Helper2

struct PersistenceTests {

    // Use a fresh PersistenceController instance (uses app's documents directory in simulator)
    // Each test uses unique conversation IDs to avoid interference

    // MARK: - Create and Load

    @Test func createNewConversation() {
        let persistence = PersistenceController()
        let id = persistence.createNewConversation()

        // Should be loadable (empty messages)
        let messages = persistence.loadConversation(id: id)
        #expect(messages != nil)
        #expect(messages?.isEmpty == true)

        // Clean up
        persistence.deleteConversation(id: id)
    }

    @Test func saveAndLoadConversation() {
        let persistence = PersistenceController()
        let id = UUID()

        let messages = [
            ChatMessage(content: "Hello", isUser: true),
            ChatMessage(content: "Hi there!", isUser: false)
        ]

        persistence.saveConversation(id: id, messages: messages)

        let loaded = persistence.loadConversation(id: id)
        #expect(loaded != nil)
        #expect(loaded?.count == 2)
        #expect(loaded?[0].content == "Hello")
        #expect(loaded?[0].isUser == true)
        #expect(loaded?[1].content == "Hi there!")
        #expect(loaded?[1].isUser == false)

        // Clean up
        persistence.deleteConversation(id: id)
    }

    @Test func loadNonExistentConversation() {
        let persistence = PersistenceController()
        let fakeID = UUID()

        let result = persistence.loadConversation(id: fakeID)
        #expect(result == nil)
    }

    // MARK: - Update Conversation

    @Test func updateExistingConversation() {
        let persistence = PersistenceController()
        let id = UUID()

        // Save initial
        let initial = [ChatMessage(content: "First", isUser: true)]
        persistence.saveConversation(id: id, messages: initial)

        // Update with more messages
        let updated = [
            ChatMessage(content: "First", isUser: true),
            ChatMessage(content: "Reply", isUser: false),
            ChatMessage(content: "Follow up", isUser: true)
        ]
        persistence.saveConversation(id: id, messages: updated)

        let loaded = persistence.loadConversation(id: id)
        #expect(loaded?.count == 3)
        #expect(loaded?[2].content == "Follow up")

        // Clean up
        persistence.deleteConversation(id: id)
    }

    // MARK: - Delete

    @Test func deleteConversation() {
        let persistence = PersistenceController()
        let id = UUID()

        persistence.saveConversation(id: id, messages: [
            ChatMessage(content: "To be deleted", isUser: true)
        ])

        // Verify exists
        #expect(persistence.loadConversation(id: id) != nil)

        // Delete
        persistence.deleteConversation(id: id)

        // Verify gone
        #expect(persistence.loadConversation(id: id) == nil)
    }

    @Test func deleteNonExistentConversationDoesNotCrash() {
        let persistence = PersistenceController()
        // Should not crash
        persistence.deleteConversation(id: UUID())
    }

    // MARK: - List Conversations

    @Test func listConversations() {
        let persistence = PersistenceController()
        let id1 = UUID()
        let id2 = UUID()

        persistence.saveConversation(id: id1, messages: [
            ChatMessage(content: "Conv 1", isUser: true)
        ])
        persistence.saveConversation(id: id2, messages: [
            ChatMessage(content: "Conv 2 msg 1", isUser: true),
            ChatMessage(content: "Conv 2 msg 2", isUser: false)
        ])

        let list = persistence.listConversations()

        // Should contain our conversations (may contain others from parallel tests)
        let ourConvs = list.filter { $0.id == id1 || $0.id == id2 }
        #expect(ourConvs.count == 2)

        let conv1 = ourConvs.first { $0.id == id1 }
        let conv2 = ourConvs.first { $0.id == id2 }
        #expect(conv1?.messageCount == 1)
        #expect(conv2?.messageCount == 2)

        // Clean up
        persistence.deleteConversation(id: id1)
        persistence.deleteConversation(id: id2)
    }

    // MARK: - Most Recent Conversation

    @Test func loadMostRecentConversation() throws {
        let persistence = PersistenceController()
        let oldID = UUID()
        let newID = UUID()

        // Save an older conversation
        persistence.saveConversation(id: oldID, messages: [
            ChatMessage(content: "Old", isUser: true)
        ])

        // Small delay to ensure different modification times
        Thread.sleep(forTimeInterval: 0.1)

        // Save a newer conversation
        persistence.saveConversation(id: newID, messages: [
            ChatMessage(content: "New", isUser: true)
        ])

        let result = persistence.loadMostRecentConversation()
        #expect(result != nil)

        // The most recent should be our newest conversation
        if let (id, messages) = result {
            #expect(id == newID)
            #expect(messages[0].content == "New")
        }

        // Clean up
        persistence.deleteConversation(id: oldID)
        persistence.deleteConversation(id: newID)
    }

    // MARK: - Empty Messages

    @Test func saveEmptyConversation() {
        let persistence = PersistenceController()
        let id = UUID()

        persistence.saveConversation(id: id, messages: [])

        let loaded = persistence.loadConversation(id: id)
        #expect(loaded != nil)
        #expect(loaded?.isEmpty == true)

        // Clean up
        persistence.deleteConversation(id: id)
    }

    // MARK: - ConversationData Codable

    @Test func conversationDataCodable() throws {
        let messages = [
            ChatMessage(content: "Test", isUser: true),
            ChatMessage(content: "Response", isUser: false)
        ]

        let original = ConversationData(
            id: UUID(),
            messages: messages,
            updatedAt: Date()
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ConversationData.self, from: data)

        #expect(decoded.id == original.id)
        #expect(decoded.messages.count == 2)
        #expect(decoded.messages[0].content == "Test")
        #expect(decoded.messages[1].content == "Response")
    }
}
