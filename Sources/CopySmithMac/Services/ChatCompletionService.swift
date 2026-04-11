import Foundation

// MARK: - Internal error types

private struct RetryableHTTPError: Error {
    let statusCode: Int
    let retryAfter: TimeInterval?
}

// MARK: - SSE Parser

enum SSEParser {
    /// Strip `data: ` prefix and return the payload, or nil for empty/done lines.
    static func payload(from raw: String) -> String? {
        var line = raw
        if line.hasPrefix("data: ") { line = String(line.dropFirst(6)) }
        line = line.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, line != "[DONE]" else { return nil }
        return line
    }

    static func isDone(_ raw: String) -> Bool {
        var line = raw
        if line.hasPrefix("data: ") { line = String(line.dropFirst(6)) }
        return line.trimmingCharacters(in: .whitespaces) == "[DONE]"
    }

    /// Extract `choices[0].delta.content` from an OpenAI-compatible chunk payload.
    static func extractContent(from payload: String) -> String? {
        guard
            let data = payload.data(using: .utf8),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = json["choices"] as? [[String: Any]],
            let first = choices.first,
            let delta = first["delta"] as? [String: Any],
            let content = delta["content"] as? String
        else { return nil }
        return content
    }
}

// MARK: - Service

struct ChatCompletionService: LLMService {
    let endpoint: URL
    let timeout: TimeInterval

    init(
        endpoint: URL = URL(string: "http://localhost:2276/v1/chat/completions")!,
        timeout: TimeInterval = 20
    ) {
        self.endpoint = endpoint
        self.timeout = timeout
    }

    func stream(prompt: String) -> AsyncThrowingStream<String, Error> {
        .taskBacked { continuation in
            try await self.withRetry(maxAttempts: 3) {
                try await self.performRequest(prompt: prompt) { chunk in
                    continuation.yield(chunk)
                }
            }
        }
    }

    // MARK: Private

    private func performRequest(
        prompt: String,
        onChunk: @Sendable (String) async -> Void
    ) async throws {
        var request = URLRequest(url: endpoint, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "messages": [["role": "user", "content": prompt]],
            "stream": true
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = timeout
        config.timeoutIntervalForResource = timeout * 5
        let session = URLSession(configuration: config)

        let (bytes, response) = try await session.bytes(for: request)

        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 || http.statusCode >= 500 {
                let retryAfter = (http.allHeaderFields["Retry-After"] as? String)
                    .flatMap(TimeInterval.init)
                throw RetryableHTTPError(statusCode: http.statusCode, retryAfter: retryAfter)
            }
            if http.statusCode != 200 {
                throw ChatError.apiError("HTTP \(http.statusCode)")
            }
        }

        for try await line in bytes.lines {
            try Task.checkCancellation()
            if SSEParser.isDone(line) { break }
            if let payload = SSEParser.payload(from: line),
               let content = SSEParser.extractContent(from: payload) {
                await onChunk(content)
            }
        }
    }

    private func withRetry(maxAttempts: Int, operation: () async throws -> Void) async throws {
        var attempt = 0
        var delay: TimeInterval = 1.5

        while true {
            do {
                try await operation()
                return
            } catch let err as RetryableHTTPError {
                attempt += 1
                if attempt >= maxAttempts {
                    throw ChatError.apiError("API request failed: HTTP \(err.statusCode)")
                }
                let wait = err.retryAfter ?? min(delay, 10)
                delay = min(delay * 2, 10)
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            } catch is CancellationError {
                throw CancellationError()
            } catch let err as ChatError {
                throw err
            } catch {
                attempt += 1
                if attempt >= maxAttempts {
                    throw ChatError.networkError("Network error: \(error.localizedDescription)")
                }
                let wait = min(delay, 10)
                delay = min(delay * 2, 10)
                try await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
        }
    }
}
