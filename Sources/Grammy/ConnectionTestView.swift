import AppKit
import SwiftUI

/// Sends a sample sentence through the configured provider and verifies the reply
/// parses into `GrammarResult` and actually flags the planted mistakes.
struct ConnectionTestSection: View {
    @ObservedObject var settings = AppSettings.shared
    @State private var sample = "I has went to the meeting yesterday and it were very helpful for our team."
    @State private var running = false
    @State private var outcome: Outcome?

    private enum Outcome {
        case success(GrammarResult, elapsed: TimeInterval, sample: String)
        case failure(message: String, raw: String?)
    }

    var body: some View {
        Section("接続テスト") {
            TextField("テスト文", text: $sample, axis: .vertical)
                .lineLimit(2...4)
            HStack {
                Text("接続先: \(settings.provider.label) / \(modelName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if running { ProgressView().controlSize(.small) }
                Button("テスト実行") { Task { await run() } }
                    .disabled(running || sample.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let outcome { result(outcome) }
        }
    }

    private var modelName: String {
        settings.provider == .litellm ? settings.litellmModel : settings.model
    }

    @ViewBuilder
    private func result(_ outcome: Outcome) -> some View {
        switch outcome {
        case let .success(result, elapsed, sample):
            VStack(alignment: .leading, spacing: 6) {
                check(true, "JSON を解釈できました（\(String(format: "%.1f", elapsed)) 秒）")
                check(true, "has_issues: \(result.hasIssues) / issues: \(result.issues.count) 件")
                let changed = result.correctedText != sample
                check(result.hasIssues == changed,
                      result.hasIssues == changed
                          ? "has_issues と corrected_text の内容が一致しています"
                          : "has_issues と corrected_text の内容が食い違っています")
                Text(WordDiff.attributed(from: sample, to: result.correctedText))
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                ForEach(result.issues) { issue in
                    Text("• \(issue.original) → \(issue.replacement): \(issue.explanation)")
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case let .failure(message, raw):
            VStack(alignment: .leading, spacing: 6) {
                check(false, message)
                if let raw {
                    Text("モデルの生の応答:").font(.caption).foregroundStyle(.secondary)
                    Text(raw)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .lineLimit(12)
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
                    Button("応答をコピー") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(raw, forType: .string)
                    }
                }
            }
        }
    }

    private func check(_ ok: Bool, _ text: String) -> some View {
        Label(text, systemImage: ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
            .foregroundStyle(ok ? .green : .red)
            .fixedSize(horizontal: false, vertical: true)
    }

    @MainActor
    private func run() async {
        running = true
        defer { running = false }
        let text = sample
        do {
            guard let checker = try settings.makeChecker() else {
                outcome = .failure(message: "\(settings.provider.label) の API キーが未設定です", raw: nil)
                return
            }
            let start = Date()
            let result = try await checker.check(text: text)
            outcome = .success(result, elapsed: Date().timeIntervalSince(start), sample: text)
        } catch let CheckError.malformedJSON(reason, raw) {
            outcome = .failure(message: "JSON が形式と一致しません: \(reason)", raw: raw)
        } catch {
            outcome = .failure(message: error.localizedDescription, raw: nil)
        }
    }
}
