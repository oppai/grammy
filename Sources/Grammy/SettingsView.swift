import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var apiKeyInput = ""
    @State private var keyStatus = ""
    @State private var trusted = AX.isTrusted
    @State private var litellmModels: [String] = []
    @State private var loadingModels = false
    @State private var modelsMessage: String?

    /// Keep the saved model selectable even if the proxy no longer lists it.
    private var modelChoices: [String] {
        litellmModels.contains(settings.litellmModel) ? litellmModels : [settings.litellmModel] + litellmModels
    }

    var body: some View {
        Form {
            Section("AI プロバイダ") {
                Picker("接続先", selection: $settings.provider) {
                    ForEach(Provider.allCases) { Text($0.label).tag($0) }
                }
                switch settings.provider {
                case .litellm:
                    HStack {
                        TextField("エンドポイント URL", text: $settings.litellmURL)
                        Button("既定に戻す") { settings.litellmURL = AppSettings.defaultLiteLLMURL }
                            .disabled(settings.litellmURL == AppSettings.defaultLiteLLMURL)
                    }
                    Text("OpenAI 互換の /v1/chat/completions なら何でも指定できます（例: LiteLLM プロキシ）。既定は OpenAI です。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        if litellmModels.isEmpty {
                            TextField("モデル名", text: $settings.litellmModel, prompt: Text("↻ で一覧を取得するか、モデル名を入力"))
                        } else {
                            Picker("モデル", selection: $settings.litellmModel) {
                                ForEach(modelChoices, id: \.self) { Text($0.isEmpty ? "選択してください" : $0).tag($0) }
                            }
                        }
                        Button {
                            Task { await fetchModels() }
                        } label: {
                            if loadingModels {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .help("エンドポイントからモデル一覧を取得")
                        .disabled(loadingModels)
                    }
                    Text(modelsMessage ?? "エンドポイントで使えるモデルから選択します。")
                        .font(.caption)
                        .foregroundStyle(modelsMessage == nil ? .secondary : Color.orange)
                case .anthropic:
                    Picker("モデル", selection: $settings.model) {
                        ForEach(ClaudeModel.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                }
                SecureField("API キー", text: $apiKeyInput, prompt: Text(settings.provider == .litellm ? "sk-..." : "sk-ant-..."))
                HStack {
                    Text("状態: \(keyStatus)").foregroundStyle(.secondary)
                    Spacer()
                    Button("削除") {
                        CredentialStore.saveAPIKey("", for: settings.provider)
                        refreshKeyStatus()
                    }
                    Button("保存") {
                        let key = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        keyStatus = CredentialStore.saveAPIKey(key, for: settings.provider) ? "保存済み" : "保存に失敗しました"
                        apiKeyInput = ""
                        if settings.provider == .litellm { Task { await fetchModels() } }
                    }
                    .disabled(apiKeyInput.isEmpty)
                }
                Text("入力中のテキストは選択したプロバイダ経由でモデルに送信されます。社外秘の内容を扱うチャンネルでは無効にしてください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ConnectionTestSection()

            Section("監視対象") {
                Toggle("すべてのアプリで有効にする", isOn: $settings.monitorAllApps)
                TextField("Bundle ID（カンマ区切り）", text: $settings.bundleIDsText)
                    .disabled(settings.monitorAllApps)
                Text("既定値: \(AppSettings.slackBundleID)（Slack）")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("動作") {
                LabeledContent("入力が止まってから") {
                    HStack {
                        Slider(value: $settings.debounceSeconds, in: 0.5...3.0, step: 0.1)
                        Text(String(format: "%.1f 秒", settings.debounceSeconds))
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            }

            Section("権限") {
                HStack {
                    Label(trusted ? "アクセシビリティ: 許可済み" : "アクセシビリティ: 未許可",
                          systemImage: trusted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(trusted ? .green : .red)
                    Spacer()
                    Button("システム設定を開く") { AX.openAccessibilitySettings() }
                }
                if !trusted {
                    HStack {
                        Text("システム設定でオンなのに未許可のままなら、古いビルドの許可が残っています。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("リセットして再許可") { AX.resetAndRequestTrust() }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshKeyStatus)
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            trusted = AX.isTrusted
        }
        .onChange(of: settings.provider) { refreshKeyStatus() }
        .onChange(of: settings.litellmURL) {
            // A different endpoint serves a different model list.
            litellmModels = []
            modelsMessage = nil
        }
        .task(id: settings.provider) {
            if settings.provider == .litellm, litellmModels.isEmpty, settings.apiKey != nil {
                await fetchModels()
            }
        }
        .frame(minWidth: 520, idealWidth: 520, minHeight: 480, idealHeight: 720)
    }
}

private extension SettingsView {
    func refreshKeyStatus() {
        keyStatus = CredentialStore.readAPIKey(for: settings.provider) == nil ? "未設定" : "保存済み"
    }

    @MainActor
    func fetchModels() async {
        guard let apiKey = settings.apiKey else {
            modelsMessage = "モデル一覧の取得には API キーが必要です。"
            return
        }
        loadingModels = true
        defer { loadingModels = false }
        do {
            let models = try await LiteLLMClient.listModels(endpoint: try settings.litellmEndpoint(), apiKey: apiKey)
            litellmModels = models
            modelsMessage = models.isEmpty ? "利用できるモデルがありません。" : nil
        } catch {
            modelsMessage = "モデル一覧を取得できませんでした: \(error.localizedDescription)"
        }
    }
}

final class SettingsWindowController {
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Grammy 設定"
            window.styleMask = [.titled, .closable, .resizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
