import Foundation

/// Client for any OpenAI-compatible /v1/chat/completions endpoint (OpenAI, a LiteLLM proxy, ...).
final class LiteLLMClient: GrammarChecker {
    private let endpoint: URL
    private let model: String
    private let apiKey: String

    /// Models (per proxy URL) that rejected `reasoning_effort`; remembered for the app's lifetime.
    private static var effortUnsupported = Set<String>()
    /// Some local servers put the entire answer in reasoning_content for `low`.
    private static var noReasoningRequired = Set<String>()

    private enum EmptyContent: Error { case response }

    init(endpoint: URL, model: String, apiKey: String) {
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
    }

    func check(text: String) async throws -> GrammarResult {
        let key = endpoint.absoluteString + "|" + model
        do {
            if Self.noReasoningRequired.contains(key) {
                return try await send(text: text, reasoningEffort: "none")
            }
            if Self.effortUnsupported.contains(key) {
                return try await send(text: text, reasoningEffort: nil)
            }
            do {
                // Grammar fixes don't need deep reasoning; low effort cuts latency substantially.
                return try await send(text: text, reasoningEffort: "low")
            } catch EmptyContent.response {
                // LM Studio may put a structured reply only in reasoning_content.
                // Request a final answer in content rather than treating reasoning as output.
                do {
                    let result = try await send(text: text, reasoningEffort: "none")
                    Self.noReasoningRequired.insert(key)
                    return result
                } catch CheckError.http(400, _) {
                    return try await send(text: text, reasoningEffort: nil)
                }
            } catch CheckError.http(400, let message) {
                Log.check.info("reasoning_effort rejected, retrying without: \(message, privacy: .public)")
                Self.effortUnsupported.insert(key)
                return try await send(text: text, reasoningEffort: nil)
            }
        } catch EmptyContent.response {
            throw CheckError.invalidResponse("モデルの回答（content）が空です。モデル設定を確認してください。")
        }
    }

    private func send(text: String, reasoningEffort: String?) async throws -> GrammarResult {
        var body: [String: Any] = [
            "model": model,
            "max_completion_tokens": 8000,
            "messages": [
                ["role": "system", "content": GrammarPrompt.systemPrompt],
                ["role": "user", "content": GrammarPrompt.userMessage(text)],
            ],
            // LiteLLM translates this into the provider's native structured output.
            "response_format": [
                "type": "json_schema",
                "json_schema": ["name": "grammar_result", "schema": GrammarPrompt.schema, "strict": true],
            ],
        ]
        if let reasoningEffort { body["reasoning_effort"] = reasoningEffort }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await checkerSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8) ?? ""
            throw CheckError.http(status, message)
        }

        let completion = try JSONDecoder().decode(ChatCompletion.self, from: data)
        guard let choice = completion.choices.first else {
            throw CheckError.invalidResponse("choices が空です")
        }
        switch choice.finishReason {
        case "content_filter": throw CheckError.refusal
        case "length": throw CheckError.truncated
        default: break
        }
        guard let content = choice.message.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw EmptyContent.response
        }
        return try GrammarResult.decode(fromReply: Self.stripCodeFence(content))
    }

    /// Lists model names available on the proxy via its OpenAI-compatible /v1/models endpoint.
    static func listModels(endpoint: URL, apiKey: String) async throws -> [String] {
        var request = URLRequest(url: modelsURL(for: endpoint))
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "authorization")

        let (data, response) = try await checkerSession.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(APIErrorEnvelope.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8) ?? ""
            throw CheckError.http(status, message)
        }
        let list = try JSONDecoder().decode(ModelList.self, from: data)
        return Array(Set(list.data.map(\.id))).sorted()
    }

    /// Accept a full endpoint or an HTTP(S) server URL, including local servers.
    static func chatURL(from input: String) throws -> URL {
        guard var components = URLComponents(string: input.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else {
            throw CheckError.invalidResponse("エンドポイントには http:// または https:// で始まる URL を指定してください。")
        }
        components.scheme = scheme
        let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.isEmpty {
            components.path = "/v1/chat/completions"
        } else if path == "v1" || path.hasSuffix("/v1") {
            components.path = "/" + path + "/chat/completions"
        }
        guard let url = components.url else {
            throw CheckError.invalidResponse("エンドポイント URL が不正です。")
        }
        return url
    }

    /// ".../v1/chat/completions" → ".../v1/models"
    static func modelsURL(for endpoint: URL) -> URL {
        var base = endpoint
        if base.lastPathComponent == "completions" { base.deleteLastPathComponent() }
        if base.lastPathComponent == "chat" { base.deleteLastPathComponent() }
        return base.appendingPathComponent("models")
    }

    /// Some routes return JSON wrapped in ```json fences despite response_format.
    private static func stripCodeFence(_ content: String) -> String {
        var s = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("```") else { return s }
        if let newline = s.firstIndex(of: "\n") { s = String(s[s.index(after: newline)...]) }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct ModelList: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

private struct ChatCompletion: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case message
            case finishReason = "finish_reason"
        }
    }

    let choices: [Choice]
}
