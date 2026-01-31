import Foundation
import os.log

class PersistenceController {
    static let shared = PersistenceController()

    private let logger = Logger(subsystem: "com.aihelper.persistence", category: "Persistence")
    private let fileManager = FileManager.default
    private var conversationsDirectory: URL {
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("conversations")
    }

    init() {
        // Ensure conversations directory exists
        try? fileManager.createDirectory(at: conversationsDirectory, withIntermediateDirectories: true)
        logger.info("Persistence initialized at \(self.conversationsDirectory.path)")
    }

    // MARK: - Conversation Management

    func saveConversation(id: UUID, messages: [ChatMessage]) {
        let fileURL = conversationsDirectory.appendingPathComponent("\(id.uuidString).json")

        let data = ConversationData(id: id, messages: messages, updatedAt: Date())

        do {
            let encoded = try JSONEncoder().encode(data)
            try encoded.write(to: fileURL)
            logger.info("Saved conversation \(id.uuidString)")
        } catch {
            logger.error("Failed to save conversation: \(error.localizedDescription)")
        }
    }

    func loadConversation(id: UUID) -> [ChatMessage]? {
        let fileURL = conversationsDirectory.appendingPathComponent("\(id.uuidString).json")

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let conversation = try JSONDecoder().decode(ConversationData.self, from: data)
            logger.info("Loaded conversation \(id.uuidString) with \(conversation.messages.count) messages")
            return conversation.messages
        } catch {
            logger.error("Failed to load conversation: \(error.localizedDescription)")
            return nil
        }
    }

    func loadMostRecentConversation() -> (UUID, [ChatMessage])? {
        do {
            let files = try fileManager.contentsOfDirectory(at: conversationsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])

            let sorted = files
                .filter { $0.pathExtension == "json" }
                .compactMap { url -> (URL, Date)? in
                    let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                    return date.map { (url, $0) }
                }
                .sorted { $0.1 > $1.1 }

            guard let mostRecent = sorted.first else {
                return nil
            }

            let data = try Data(contentsOf: mostRecent.0)
            let conversation = try JSONDecoder().decode(ConversationData.self, from: data)
            return (conversation.id, conversation.messages)
        } catch {
            logger.error("Failed to load recent conversation: \(error.localizedDescription)")
            return nil
        }
    }

    func createNewConversation() -> UUID {
        let id = UUID()
        saveConversation(id: id, messages: [])
        return id
    }

    func deleteConversation(id: UUID) {
        let fileURL = conversationsDirectory.appendingPathComponent("\(id.uuidString).json")
        try? fileManager.removeItem(at: fileURL)
        logger.info("Deleted conversation \(id.uuidString)")
    }

    func listConversations() -> [(id: UUID, updatedAt: Date, messageCount: Int)] {
        do {
            let files = try fileManager.contentsOfDirectory(at: conversationsDirectory, includingPropertiesForKeys: [.contentModificationDateKey])

            return files
                .filter { $0.pathExtension == "json" }
                .compactMap { url -> (UUID, Date, Int)? in
                    guard let data = try? Data(contentsOf: url),
                          let conversation = try? JSONDecoder().decode(ConversationData.self, from: data) else {
                        return nil
                    }
                    return (conversation.id, conversation.updatedAt, conversation.messages.count)
                }
                .sorted { $0.1 > $1.1 }
        } catch {
            logger.error("Failed to list conversations: \(error.localizedDescription)")
            return []
        }
    }
}

// MARK: - Data Models

struct ConversationData: Codable {
    let id: UUID
    var messages: [ChatMessage]
    var updatedAt: Date
}
