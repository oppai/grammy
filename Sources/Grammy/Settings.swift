import Foundation

enum ClaudeModel: String, CaseIterable, Identifiable {
    case opus55 = "claude-opus-5-5"
    case sonnet55 = "claude-sonnet-5-5"
    case haiku45 = "claude-haiku-4-5"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .opus55: return "Claude Opus 5.5（高品質）"
        case .sonnet55: return "Claude Sonnet 5.5（バランス）"
        case .haiku45: return "Claude Haiku 4.5（高速・低コスト）"
        }
    }
}

enum Provider: String, CaseIterable, Identifiable {
    case litellm
    case anthropic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .litellm: return "OpenAI 互換（LiteLLM など）"
        case .anthropic: return "Anthropic API（直接）"
        }
    }
}

final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    static let slackBundleID = "com.tinyspeck.slackmacgap"
    /// Any OpenAI-compatible chat completions endpoint works here (OpenAI itself, a LiteLLM proxy, ...).
    static let defaultLiteLLMURL = "https://api.openai.com/v1/chat/completions"

    private let defaults = UserDefaults.standard

    @Published var isEnabled: Bool {
        didSet { defaults.set(isEnabled, forKey: "isEnabled") }
    }
    @Published var provider: Provider {
        didSet { defaults.set(provider.rawValue, forKey: "provider") }
    }
    @Published var litellmURL: String {
        didSet { defaults.set(litellmURL, forKey: "litellmURL") }
    }
    /// Model name as registered on the LiteLLM proxy.
    @Published var litellmModel: String {
        didSet { defaults.set(litellmModel, forKey: "litellmModel") }
    }
    @Published var model: String {
        didSet { defaults.set(model, forKey: "model") }
    }
    @Published var monitorAllApps: Bool {
        didSet { defaults.set(monitorAllApps, forKey: "monitorAllApps") }
    }
    /// Comma-separated bundle identifiers of apps to monitor.
    @Published var bundleIDsText: String {
        didSet { defaults.set(bundleIDsText, forKey: "bundleIDsText") }
    }
    /// Seconds of typing inactivity before a check is sent.
    @Published var debounceSeconds: Double {
        didSet { defaults.set(debounceSeconds, forKey: "debounceSeconds") }
    }

    private init() {
        defaults.register(defaults: [
            "isEnabled": true,
            "provider": Provider.litellm.rawValue,
            "litellmURL": AppSettings.defaultLiteLLMURL,
            "litellmModel": "",
            "model": ClaudeModel.opus55.rawValue,
            "monitorAllApps": false,
            "bundleIDsText": AppSettings.slackBundleID,
            "debounceSeconds": 1.2,
        ])
        isEnabled = defaults.bool(forKey: "isEnabled")
        provider = Provider(rawValue: defaults.string(forKey: "provider") ?? "") ?? .litellm
        litellmURL = defaults.string(forKey: "litellmURL") ?? AppSettings.defaultLiteLLMURL
        litellmModel = defaults.string(forKey: "litellmModel") ?? ""
        model = defaults.string(forKey: "model") ?? ClaudeModel.opus55.rawValue
        monitorAllApps = defaults.bool(forKey: "monitorAllApps")
        bundleIDsText = defaults.string(forKey: "bundleIDsText") ?? AppSettings.slackBundleID
        debounceSeconds = defaults.double(forKey: "debounceSeconds")
    }

    var monitoredBundleIDs: Set<String> {
        Set(bundleIDsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    func isMonitored(_ bundleID: String?) -> Bool {
        guard isEnabled, let bundleID, bundleID != Bundle.main.bundleIdentifier else { return false }
        return monitorAllApps || monitoredBundleIDs.contains(bundleID)
    }

    var apiKey: String? {
        if let key = CredentialStore.readAPIKey(for: provider), !key.isEmpty { return key }
        let envNames = provider == .litellm ? ["LITELLM_API_KEY", "OPENAI_API_KEY"] : ["ANTHROPIC_API_KEY"]
        for name in envNames {
            if let key = ProcessInfo.processInfo.environment[name], !key.isEmpty { return key }
        }
        return nil
    }

    /// Builds a checker for the current settings, or nil if the API key is missing.
    func makeChecker() throws -> GrammarChecker? {
        guard let apiKey else { return nil }
        switch provider {
        case .anthropic:
            return ClaudeClient(model: model, apiKey: apiKey)
        case .litellm:
            let model = litellmModel.trimmingCharacters(in: .whitespaces)
            guard !model.isEmpty else {
                throw CheckError.invalidResponse("モデルが未選択です。設定画面でモデルを選んでください。")
            }
            return LiteLLMClient(endpoint: try litellmEndpoint(), model: model, apiKey: apiKey)
        }
    }

    func litellmEndpoint() throws -> URL {
        try LiteLLMClient.chatURL(from: litellmURL)
    }
}

/// Stores API keys in ~/Library/Application Support/Grammy/credentials.json (mode 0600).
/// Used instead of the Keychain because an ad-hoc signed app gets a new identity on every
/// build, which makes the Keychain re-prompt for access over and over.
enum CredentialStore {
    private static var cache: [String: String]?

    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Grammy", isDirectory: true)
            .appendingPathComponent("credentials.json")
    }

    private static func load() -> [String: String] {
        if let cache { return cache }
        let stored = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        cache = stored
        return stored
    }

    static func readAPIKey(for provider: Provider) -> String? {
        load()[provider.rawValue]
    }

    @discardableResult
    static func saveAPIKey(_ key: String, for provider: Provider) -> Bool {
        var stored = load()
        stored[provider.rawValue] = key.isEmpty ? nil : key
        let fm = FileManager.default
        let dir = fileURL.deletingLastPathComponent()
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let data = try JSONEncoder().encode(stored)
            // Create with 0600 up front so the key is never briefly world-readable.
            if !fm.fileExists(atPath: fileURL.path) {
                fm.createFile(atPath: fileURL.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            try data.write(to: fileURL)
            try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
            cache = stored
            return true
        } catch {
            return false
        }
    }
}
