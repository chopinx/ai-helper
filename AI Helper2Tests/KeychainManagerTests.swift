//
//  KeychainManagerTests.swift
//  AI Helper2Tests
//
//  Tests for secure API key storage using Keychain
//

import Foundation
import Testing
@testable import AI_Helper2

struct KeychainManagerTests {

    // Use a test-specific provider name to avoid interfering with real keys
    private let testProvider = "test-provider-\(UUID().uuidString.prefix(8))"

    // MARK: - Save and Retrieve Tests

    @Test func saveAndRetrieveAPIKey() throws {
        let keychain = KeychainManager.shared
        let testKey = "sk-test-key-123456"

        // Clean up before test
        try? keychain.deleteAPIKey(for: testProvider)

        // Save
        try keychain.saveAPIKey(testKey, for: testProvider)

        // Retrieve
        let retrieved = keychain.getAPIKey(for: testProvider)
        #expect(retrieved == testKey)

        // Clean up after test
        try keychain.deleteAPIKey(for: testProvider)
    }

    @Test func retrieveNonExistentKey() {
        let keychain = KeychainManager.shared
        let nonExistentProvider = "non-existent-\(UUID().uuidString)"

        let retrieved = keychain.getAPIKey(for: nonExistentProvider)
        #expect(retrieved == nil)
    }

    @Test func hasAPIKeyWhenExists() throws {
        let keychain = KeychainManager.shared
        let testKey = "sk-test-exists"

        // Clean up before test
        try? keychain.deleteAPIKey(for: testProvider)

        // Initially should not exist
        #expect(keychain.hasAPIKey(for: testProvider) == false)

        // Save
        try keychain.saveAPIKey(testKey, for: testProvider)

        // Now should exist
        #expect(keychain.hasAPIKey(for: testProvider) == true)

        // Clean up
        try keychain.deleteAPIKey(for: testProvider)
    }

    // MARK: - Update Tests

    @Test func updateExistingKey() throws {
        let keychain = KeychainManager.shared
        let originalKey = "sk-original-key"
        let updatedKey = "sk-updated-key"

        // Clean up before test
        try? keychain.deleteAPIKey(for: testProvider)

        // Save original
        try keychain.saveAPIKey(originalKey, for: testProvider)
        #expect(keychain.getAPIKey(for: testProvider) == originalKey)

        // Update (save new key)
        try keychain.saveAPIKey(updatedKey, for: testProvider)
        #expect(keychain.getAPIKey(for: testProvider) == updatedKey)

        // Clean up
        try keychain.deleteAPIKey(for: testProvider)
    }

    // MARK: - Delete Tests

    @Test func deleteExistingKey() throws {
        let keychain = KeychainManager.shared
        let testKey = "sk-to-delete"

        // Clean up before test
        try? keychain.deleteAPIKey(for: testProvider)

        // Save
        try keychain.saveAPIKey(testKey, for: testProvider)
        #expect(keychain.hasAPIKey(for: testProvider) == true)

        // Delete
        try keychain.deleteAPIKey(for: testProvider)
        #expect(keychain.hasAPIKey(for: testProvider) == false)
        #expect(keychain.getAPIKey(for: testProvider) == nil)
    }

    @Test func deleteNonExistentKeyDoesNotThrow() throws {
        let keychain = KeychainManager.shared
        let nonExistentProvider = "delete-non-existent-\(UUID().uuidString)"

        // Should not throw for non-existent key
        try keychain.deleteAPIKey(for: nonExistentProvider)
    }

    // MARK: - Multiple Providers Tests

    @Test func separateKeysPerProvider() throws {
        let keychain = KeychainManager.shared
        let openaiKey = "sk-openai-key"
        let claudeKey = "sk-claude-key"
        let openaiProvider = "OpenAI-test-\(UUID().uuidString.prefix(8))"
        let claudeProvider = "Claude-test-\(UUID().uuidString.prefix(8))"

        // Clean up
        try? keychain.deleteAPIKey(for: openaiProvider)
        try? keychain.deleteAPIKey(for: claudeProvider)

        // Save different keys for different providers
        try keychain.saveAPIKey(openaiKey, for: openaiProvider)
        try keychain.saveAPIKey(claudeKey, for: claudeProvider)

        // Verify they are stored separately
        #expect(keychain.getAPIKey(for: openaiProvider) == openaiKey)
        #expect(keychain.getAPIKey(for: claudeProvider) == claudeKey)

        // Verify updating one doesn't affect the other
        let newOpenaiKey = "sk-openai-updated"
        try keychain.saveAPIKey(newOpenaiKey, for: openaiProvider)

        #expect(keychain.getAPIKey(for: openaiProvider) == newOpenaiKey)
        #expect(keychain.getAPIKey(for: claudeProvider) == claudeKey) // Unchanged

        // Clean up
        try keychain.deleteAPIKey(for: openaiProvider)
        try keychain.deleteAPIKey(for: claudeProvider)
    }

    // MARK: - Special Characters Tests

    @Test func handleSpecialCharactersInKey() throws {
        let keychain = KeychainManager.shared
        let specialKey = "sk-test_key+with/special=chars!@#$%^&*()"

        // Clean up
        try? keychain.deleteAPIKey(for: testProvider)

        // Save key with special characters
        try keychain.saveAPIKey(specialKey, for: testProvider)

        // Retrieve and verify
        let retrieved = keychain.getAPIKey(for: testProvider)
        #expect(retrieved == specialKey)

        // Clean up
        try keychain.deleteAPIKey(for: testProvider)
    }

    @Test func handleEmptyKey() throws {
        let keychain = KeychainManager.shared

        // Clean up
        try? keychain.deleteAPIKey(for: testProvider)

        // Save empty key
        try keychain.saveAPIKey("", for: testProvider)

        // Retrieve - empty string is valid
        let retrieved = keychain.getAPIKey(for: testProvider)
        #expect(retrieved == "")

        // Clean up
        try keychain.deleteAPIKey(for: testProvider)
    }
}
