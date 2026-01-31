import Foundation
import os.log

class StreamingService: NSObject, URLSessionDataDelegate {
    private let logger = Logger(subsystem: "com.aihelper.streaming", category: "StreamingService")

    private var onChunk: ((String) -> Void)?
    private var onComplete: ((Result<Void, Error>) -> Void)?
    private var buffer = ""
    private var session: URLSession?

    func streamOpenAI(
        messages: [[String: Any]],
        configuration: APIConfiguration,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        self.onChunk = onChunk
        self.onComplete = onComplete
        self.buffer = ""

        let url = URL(string: "https://api.openai.com/v1/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": configuration.model,
            "messages": messages,
            "max_tokens": configuration.maxTokens,
            "temperature": configuration.temperature,
            "stream": true
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session?.dataTask(with: request)
        task?.resume()

        logger.info("Started OpenAI streaming request")
    }

    func streamClaude(
        messages: [[String: Any]],
        configuration: APIConfiguration,
        onChunk: @escaping (String) -> Void,
        onComplete: @escaping (Result<Void, Error>) -> Void
    ) {
        self.onChunk = onChunk
        self.onComplete = onComplete
        self.buffer = ""

        let url = URL(string: "https://api.anthropic.com/v1/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(configuration.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": configuration.model,
            "max_tokens": configuration.maxTokens,
            "messages": messages,
            "stream": true
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session?.dataTask(with: request)
        task?.resume()

        logger.info("Started Claude streaming request")
    }

    func cancel() {
        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard let text = String(data: data, encoding: .utf8) else { return }
        buffer += text

        // Process SSE lines
        while let lineEnd = buffer.firstIndex(of: "\n") {
            let line = String(buffer[..<lineEnd])
            buffer = String(buffer[buffer.index(after: lineEnd)...])
            processSSELine(line)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        DispatchQueue.main.async { [weak self] in
            if let error = error {
                self?.onComplete?(.failure(error))
            } else {
                self?.onComplete?(.success(()))
            }
            self?.session = nil
        }
        logger.info("Streaming complete")
    }

    private func processSSELine(_ line: String) {
        guard line.hasPrefix("data: ") else { return }
        let jsonString = String(line.dropFirst(6))

        if jsonString == "[DONE]" { return }

        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        // OpenAI format
        if let choices = json["choices"] as? [[String: Any]],
           let delta = choices.first?["delta"] as? [String: Any],
           let content = delta["content"] as? String {
            DispatchQueue.main.async { [weak self] in
                self?.onChunk?(content)
            }
        }

        // Claude format
        if let type = json["type"] as? String, type == "content_block_delta",
           let delta = json["delta"] as? [String: Any],
           let text = delta["text"] as? String {
            DispatchQueue.main.async { [weak self] in
                self?.onChunk?(text)
            }
        }
    }
}
