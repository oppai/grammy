import AppKit
import Carbon.HIToolbox

/// Glues together: text monitoring → LLM check → suggestion panel → apply.
final class Coordinator {
    private let settings = AppSettings.shared
    private let monitor = TextMonitor()
    private let panel = SuggestionPanelController()

    private var task: Task<Void, Never>?
    private var cache: [String: GrammarResult] = [:]
    private var dismissed = Set<String>()
    private var pending: (target: FocusedText, result: GrammarResult)?
    private lazy var applyHotKey = HotKey(id: 1, keyCode: kVK_Return, modifiers: controlKey | optionKey) { [weak self] in
        // Give the user a beat to release ⌃⌥ so they don't combine with the synthetic ⌘A/⌘V.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self?.applyPending() }
    }

    var onCheckingChanged: (Bool) -> Void = { _ in }

    func start() {
        monitor.isEligible = { [weak self] in self?.settings.isMonitored($0) ?? false }
        monitor.debounceSeconds = { [weak self] in self?.settings.debounceSeconds ?? 1.2 }
        monitor.onChange = { [weak self] in self?.reset() }
        monitor.onFocusLost = { [weak self] in self?.reset() }
        monitor.onSettled = { [weak self] in self?.check($0, force: false) }
        panel.model.onApply = { [weak self] in self?.applyPending() }
        panel.model.onDismiss = { [weak self] in self?.dismiss() }
        monitor.start()
    }

    /// `--debug-panel`: show a canned suggestion at the mouse so panel rendering can be checked in isolation.
    func showDebugPanel() {
        let sample = "I has went to the meeting."
        let result = GrammarResult(hasIssues: true, correctedText: "I went to the meeting.",
                                   issues: [GrammarIssue(original: "has went", replacement: "went", explanation: "過去形にします")])
        let mouse = NSEvent.mouseLocation
        panel.show(.suggestion(result, WordDiff.attributed(from: sample, to: result.correctedText)),
                   near: CGRect(origin: mouse, size: .zero))
    }

    /// Manual trigger from the menu: checks whatever field is focused, bypassing heuristics.
    func checkNow() {
        guard let target = monitor.snapshotNow() else {
            NSSound.beep()
            return
        }
        check(target, force: true)
    }

    private func key(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func check(_ target: FocusedText, force: Bool) {
        let text = key(target.text)
        Log.check.info("settled: length=\(text.count) english=\(TextHeuristics.looksLikeEnglish(text)) force=\(force)")
        guard !text.isEmpty, text.count <= TextHeuristics.maxLength else { return }
        guard force || (TextHeuristics.looksLikeEnglish(text) && !dismissed.contains(text)) else {
            Log.check.info("skipped: not English-like or dismissed")
            return
        }
        Log.check.info("anchor: \(String(describing: target.anchorRect), privacy: .public)")

        if let cached = cache[text] {
            present(cached, for: target, quietIfClean: !force)
            return
        }
        let checker: GrammarChecker
        do {
            guard let made = try settings.makeChecker() else {
                panel.show(.error("\(settings.provider.label) の API キーが未設定です。メニューバーの Grammy → 設定… から登録してください。"),
                           near: target.anchorRect)
                return
            }
            checker = made
        } catch {
            panel.show(.error(error.localizedDescription), near: target.anchorRect)
            return
        }

        panel.show(.checking, near: target.anchorRect)
        onCheckingChanged(true)
        task?.cancel()
        task = Task { @MainActor [weak self] in
            defer { self?.onCheckingChanged(false) }
            do {
                let start = Date()
                let result = try await checker.check(text: target.text)
                Log.check.info("latency: \(String(format: "%.1f", Date().timeIntervalSince(start)), privacy: .public)s")
                guard let self, !Task.isCancelled else { return }
                Log.check.info("result: has_issues=\(result.hasIssues) issues=\(result.issues.count)")
                self.remember(result, for: text)
                // Drop stale results if the user kept typing while we waited.
                guard force || self.monitor.currentText == target.text else { return }
                self.present(result, for: target, quietIfClean: false)
            } catch {
                guard let self, !Task.isCancelled, !Self.isCancellation(error) else { return }
                Log.check.error("check failed: \(error.localizedDescription, privacy: .public)")
                self.panel.show(.error(error.localizedDescription), near: target.anchorRect)
            }
        }
    }

    private func present(_ result: GrammarResult, for target: FocusedText, quietIfClean: Bool) {
        guard result.hasIssues, key(result.correctedText) != key(target.text) else {
            pending = nil
            applyHotKey.unregister()
            if quietIfClean { panel.hide() } else { panel.show(.ok, near: target.anchorRect, autoHideAfter: 1.2) }
            return
        }
        pending = (target, result)
        let diff = WordDiff.attributed(from: target.text, to: result.correctedText)
        panel.show(.suggestion(result, diff), near: target.anchorRect)
        applyHotKey.register()
    }

    private func applyPending() {
        guard let (target, result) = pending else { return }
        // Only overwrite if the field still holds exactly what we checked.
        guard AX.value(target.element) == target.text else {
            reset()
            return
        }
        remember(.clean(result.correctedText), for: key(result.correctedText))
        reset()
        TextReplacer.replaceAll(in: target, with: result.correctedText)
    }

    private func dismiss() {
        if let pending { dismissed.insert(key(pending.target.text)) }
        reset()
    }

    private func reset() {
        task?.cancel()
        task = nil
        pending = nil
        applyHotKey.unregister()
        panel.hide()
    }

    private func remember(_ result: GrammarResult, for text: String) {
        if cache.count > 200 { cache.removeAll() }
        cache[text] = result
    }

    private static func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }
}
