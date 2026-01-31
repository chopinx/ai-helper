import Foundation
import AVFoundation
import os.log

class WhisperTranscriptionService {
    private let logger = Logger(subsystem: "com.aihelper.voice", category: "WhisperTranscription")

    func transcribe(audioURL: URL, apiKey: String) async throws -> String {
        logger.info("Starting Whisper transcription...")

        let url = URL(string: "https://api.openai.com/v1/audio/transcriptions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // Add model field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"model\"\r\n\r\n".data(using: .utf8)!)
        body.append("whisper-1\r\n".data(using: .utf8)!)

        // Add audio file
        let audioData = try Data(contentsOf: audioURL)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(audioData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let startTime = CFAbsoluteTimeGetCurrent()
        let (data, response) = try await URLSession.shared.data(for: request)
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        guard let httpResponse = response as? HTTPURLResponse else {
            throw WhisperError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            logger.error("Whisper API error: \(errorMessage)")
            throw WhisperError.apiError(errorMessage)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = json["text"] as? String else {
            throw WhisperError.parseError
        }

        logger.info("Whisper transcription complete - Duration: \(String(format: "%.2f", duration))s")
        return text
    }
}

enum WhisperError: LocalizedError {
    case invalidResponse
    case apiError(String)
    case parseError
    case recordingFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from Whisper API"
        case .apiError(let msg): return "Whisper API error: \(msg)"
        case .parseError: return "Failed to parse transcription"
        case .recordingFailed: return "Failed to record audio"
        }
    }
}
