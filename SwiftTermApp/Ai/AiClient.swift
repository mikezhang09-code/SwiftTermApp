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
