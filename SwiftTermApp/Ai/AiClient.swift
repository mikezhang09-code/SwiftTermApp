//
//  AiClient.swift
//  SwiftTermApp
//
//  Minimal HTTP layer for the configured AI providers.  For now this only
//  implements connectivity testing (list models / tiny ping) used by the
//  "Test" button in the AI settings; chat/completion calls build on top of
//  the same request plumbing in a later step.
//

import Foundation

enum AiClientError: LocalizedError {
    case badUrl (String)
    case emptyKey
    case http (Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .badUrl (let url):
            return "Invalid base URL: \(url)"
        case .emptyKey:
            return "No API key configured"
        case .http (let code, let body):
            let detail = body.isEmpty ? "" : ": \(body.prefix (200))"
            switch code {
            case 401, 403: return "Authentication failed (HTTP \(code))\(detail)"
            case 429: return "Rate limited (HTTP 429)\(detail)"
            default: return "HTTP \(code)\(detail)"
            }
        case .badResponse:
            return "Unexpected response from the server"
        }
    }
}

/// Outcome of a provider connectivity test
struct AiTestResult {
    var summary: String
    /// Set when the configured model was not found in the endpoint's model list
    var warning: String?
}

struct AiClient {
    var config: AiProviderConfig
    var apiKey: String

    /// Joins the base URL with a path, tolerating trailing slashes
    func endpoint (_ path: String) -> URL? {
        var base = config.baseUrl
        while base.hasSuffix ("/") {
            base = String (base.dropLast ())
        }
        return URL (string: base + path)
    }

    // URLSession.data(for:) requires iOS 15, the app still targets 14.7
    func fetchData (for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await withCheckedThrowingContinuation { cont in
            let task = URLSession.shared.dataTask (with: request) { data, response, error in
                if let error = error {
                    cont.resume (throwing: error)
                    return
                }
                guard let data = data, let http = response as? HTTPURLResponse else {
                    cont.resume (throwing: AiClientError.badResponse)
                    return
                }
                cont.resume (returning: (data, http))
            }
            task.resume ()
        }
    }

    /// Validates key + endpoint + network by listing the endpoint's models.
    /// Cost-free: no tokens are consumed except in the Anthropic-compatible
    /// fallback (1 output token) for proxies that lack /v1/models.
    func test () async throws -> AiTestResult {
        guard !apiKey.isEmpty else { throw AiClientError.emptyKey }
        switch config.kind {
        case .anthropic:
            return try await testAnthropic ()
        case .openai:
            return try await testOpenAi ()
        case .gemini:
            return try await testGemini ()
        }
    }

    func modelListResult (ids: [String], matches: (String) -> Bool) -> AiTestResult {
        var result = AiTestResult (summary: "OK — \(ids.count) models available")
        if !ids.isEmpty && !ids.contains (where: matches) {
            result.warning = "Configured model “\(config.model)” was not in the list — double-check the model name"
        }
        return result
    }

    func testAnthropic () async throws -> AiTestResult {
        guard let url = endpoint ("/v1/models") else { throw AiClientError.badUrl (config.baseUrl) }
        var request = URLRequest (url: url)
        request.setValue (apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue ("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let (data, http) = try await fetchData (for: request)
        if http.statusCode == 404 || http.statusCode == 405 {
            // Anthropic-compatible proxies often only implement /v1/messages
            return try await testAnthropicMessagePing ()
        }
        guard http.statusCode == 200 else {
            throw AiClientError.http (http.statusCode, String (bytes: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject (with: data) as? [String: Any],
              let list = json ["data"] as? [[String: Any]] else {
            throw AiClientError.badResponse
        }
        let ids = list.compactMap { $0 ["id"] as? String }
        return modelListResult (ids: ids) { $0 == config.model }
    }

    func testAnthropicMessagePing () async throws -> AiTestResult {
        guard let url = endpoint ("/v1/messages") else { throw AiClientError.badUrl (config.baseUrl) }
        var request = URLRequest (url: url)
        request.httpMethod = "POST"
        request.setValue (apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue ("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue ("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": 1,
            "messages": [["role": "user", "content": "ping"]]
        ]
        request.httpBody = try JSONSerialization.data (withJSONObject: body)
        let (data, http) = try await fetchData (for: request)
        guard http.statusCode == 200 else {
            throw AiClientError.http (http.statusCode, String (bytes: data, encoding: .utf8) ?? "")
        }
        return AiTestResult (summary: "OK — endpoint accepted a message for “\(config.model)”")
    }

    func testOpenAi () async throws -> AiTestResult {
        guard let url = endpoint ("/models") else { throw AiClientError.badUrl (config.baseUrl) }
        var request = URLRequest (url: url)
        request.setValue ("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, http) = try await fetchData (for: request)
        guard http.statusCode == 200 else {
            throw AiClientError.http (http.statusCode, String (bytes: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject (with: data) as? [String: Any],
              let list = json ["data"] as? [[String: Any]] else {
            throw AiClientError.badResponse
        }
        let ids = list.compactMap { $0 ["id"] as? String }
        return modelListResult (ids: ids) { $0 == config.model }
    }

    // MARK: - Streaming chat

    /// Builds the streaming request and the provider-specific extractor that
    /// turns one SSE event payload into a text delta (nil = not a text event)
    func chatRequest (system: String, user: String) throws -> (URLRequest, (Data) -> String?) {
        guard !apiKey.isEmpty else { throw AiClientError.emptyKey }
        switch config.kind {
        case .anthropic:
            guard let url = endpoint ("/v1/messages") else { throw AiClientError.badUrl (config.baseUrl) }
            var request = URLRequest (url: url)
            request.httpMethod = "POST"
            request.setValue (apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue ("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.setValue ("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": config.model,
                "max_tokens": 4096,
                "stream": true,
                "system": system,
                "messages": [["role": "user", "content": user]]
            ]
            request.httpBody = try JSONSerialization.data (withJSONObject: body)
            return (request, { data in
                guard let json = try? JSONSerialization.jsonObject (with: data) as? [String: Any],
                      json ["type"] as? String == "content_block_delta",
                      let delta = json ["delta"] as? [String: Any],
                      delta ["type"] as? String == "text_delta" else { return nil }
                return delta ["text"] as? String
            })
        case .openai:
            guard let url = endpoint ("/chat/completions") else { throw AiClientError.badUrl (config.baseUrl) }
            var request = URLRequest (url: url)
            request.httpMethod = "POST"
            request.setValue ("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue ("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "model": config.model,
                "stream": true,
                "messages": [
                    ["role": "system", "content": system],
                    ["role": "user", "content": user]
                ]
            ]
            request.httpBody = try JSONSerialization.data (withJSONObject: body)
            return (request, { data in
                guard let json = try? JSONSerialization.jsonObject (with: data) as? [String: Any],
                      let choices = json ["choices"] as? [[String: Any]],
                      let delta = choices.first? ["delta"] as? [String: Any] else { return nil }
                return delta ["content"] as? String
            })
        case .gemini:
            guard let url = endpoint ("/models/\(config.model):streamGenerateContent?alt=sse") else {
                throw AiClientError.badUrl (config.baseUrl)
            }
            var request = URLRequest (url: url)
            request.httpMethod = "POST"
            request.setValue (apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.setValue ("application/json", forHTTPHeaderField: "Content-Type")
            let body: [String: Any] = [
                "systemInstruction": ["parts": [["text": system]]],
                "contents": [["role": "user", "parts": [["text": user]]]]
            ]
            request.httpBody = try JSONSerialization.data (withJSONObject: body)
            return (request, { data in
                guard let json = try? JSONSerialization.jsonObject (with: data) as? [String: Any],
                      let candidates = json ["candidates"] as? [[String: Any]],
                      let content = candidates.first? ["content"] as? [String: Any],
                      let parts = content ["parts"] as? [[String: Any]] else { return nil }
                let text = parts.compactMap { $0 ["text"] as? String }.joined ()
                return text.isEmpty ? nil : text
            })
        }
    }

    /// Starts a streaming chat call; deltas and completion arrive on the main queue
    func chat (system: String, user: String, onDelta: @escaping (String) -> Void, onDone: @escaping (Result<Void, Error>) -> Void) -> AiChatStream? {
        do {
            let (request, extract) = try chatRequest (system: system, user: user)
            let stream = AiChatStream (request: request, extract: extract, onDelta: onDelta, onDone: onDone)
            stream.start ()
            return stream
        } catch {
            onDone (.failure (error))
            return nil
        }
    }

    func testGemini () async throws -> AiTestResult {
        guard let url = endpoint ("/models") else { throw AiClientError.badUrl (config.baseUrl) }
        var request = URLRequest (url: url)
        request.setValue (apiKey, forHTTPHeaderField: "x-goog-api-key")
        let (data, http) = try await fetchData (for: request)
        guard http.statusCode == 200 else {
            throw AiClientError.http (http.statusCode, String (bytes: data, encoding: .utf8) ?? "")
        }
        guard let json = try? JSONSerialization.jsonObject (with: data) as? [String: Any],
              let list = json ["models"] as? [[String: Any]] else {
            throw AiClientError.badResponse
        }
        // Gemini model names come back as "models/gemini-..."
        let ids = list.compactMap { $0 ["name"] as? String }
        return modelListResult (ids: ids) { $0 == config.model || $0 == "models/\(config.model)" }
    }
}

/// Reads a server-sent-events response and forwards text deltas.
/// Delegate-based because URLSession.bytes(for:) requires iOS 15;
/// callbacks are delivered on the main queue.
final class AiChatStream: NSObject, URLSessionDataDelegate {
    let request: URLRequest
    let extract: (Data) -> String?
    let onDelta: (String) -> Void
    let onDone: (Result<Void, Error>) -> Void

    var session: URLSession!
    var task: URLSessionDataTask?
    var buffer = Data ()
    var httpStatus = 200
    var errorBody = Data ()
    var finished = false

    init (request: URLRequest, extract: @escaping (Data) -> String?, onDelta: @escaping (String) -> Void, onDone: @escaping (Result<Void, Error>) -> Void) {
        self.request = request
        self.extract = extract
        self.onDelta = onDelta
        self.onDone = onDone
        super.init ()
        let queue = OperationQueue.main
        session = URLSession (configuration: .default, delegate: self, delegateQueue: queue)
    }

    func start () {
        task = session.dataTask (with: request)
        task?.resume ()
    }

    func cancel () {
        finished = true
        task?.cancel ()
        session.invalidateAndCancel ()
    }

    public func urlSession (_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        if let http = response as? HTTPURLResponse {
            httpStatus = http.statusCode
        }
        completionHandler (.allow)
    }

    public func urlSession (_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        if httpStatus != 200 {
            errorBody.append (data)
            return
        }
        buffer.append (data)
        processBuffer ()
    }

    func processBuffer () {
        // SSE: events are lines, "data: {json}" carries the payload
        while let newline = buffer.firstIndex (of: UInt8 (ascii: "\n")) {
            let lineData = buffer.subdata (in: buffer.startIndex..<newline)
            buffer.removeSubrange (buffer.startIndex...newline)
            guard var line = String (bytes: lineData, encoding: .utf8) else { continue }
            if line.hasSuffix ("\r") {
                line = String (line.dropLast ())
            }
            guard line.hasPrefix ("data:") else { continue }
            var payload = String (line.dropFirst (5))
            if payload.hasPrefix (" ") {
                payload = String (payload.dropFirst ())
            }
            if payload == "[DONE]" { continue }
            if let delta = extract (Data (payload.utf8)), !delta.isEmpty {
                onDelta (delta)
            }
        }
    }

    public func urlSession (_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if finished { return }
        finished = true
        defer { self.session.finishTasksAndInvalidate () }
        if let error = error {
            onDone (.failure (error))
            return
        }
        if httpStatus != 200 {
            onDone (.failure (AiClientError.http (httpStatus, String (bytes: errorBody, encoding: .utf8) ?? "")))
            return
        }
        onDone (.success (()))
    }
}
