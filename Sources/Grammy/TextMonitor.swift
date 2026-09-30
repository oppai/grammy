import AppKit
import ApplicationServices

struct FocusedText {
    let element: AXUIElement
    let pid: pid_t
    let bundleID: String?
    let isElectron: Bool
    let text: String

    /// Where to anchor the suggestion panel: caret if available, otherwise the field itself.
    var anchorRect: CGRect? {
        AX.caretRect(element) ?? AX.frame(element)
    }
}

/// Polls the focused text field of the frontmost app and reports edits.
/// Polling (rather than AXObserver) is used because Electron apps like Slack
/// do not reliably emit AXValueChanged notifications.
final class TextMonitor {
    var isEligible: (String?) -> Bool = { _ in false }
    var debounceSeconds: () -> TimeInterval = { 1.2 }
    var onChange: () -> Void = {}
    var onSettled: (FocusedText) -> Void = { _ in }
    var onFocusLost: () -> Void = {}

    private var timer: Timer?
    private var lastElement: AXUIElement?
    private var lastText: String?
    private var settleWork: DispatchWorkItem?
    private var manualAXEnabledPIDs = Set<pid_t>()
    private var electronCache: [String: Bool] = [:]

    var currentText: String? { lastText }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        reset()
    }

    /// Reads the focused field right now, ignoring the eligibility filter (used by "check now").
    func snapshotNow() -> FocusedText? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != getpid() else { return nil }
        return snapshot(of: app)
    }

    private func poll() {
        guard AX.isTrusted else { return diagnose("AX not trusted") }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else {
            return diagnose("frontmost is Grammy or none")
        }
        guard isEligible(app.bundleIdentifier) else {
            return diagnose("not monitored: \(app.bundleIdentifier ?? "nil")")
        }
        guard let snap = snapshot(of: app) else { return reset() }

        let sameElement = lastElement.map { CFEqual($0, snap.element) } ?? false
        guard !sameElement || snap.text != lastText else { return }

        lastElement = snap.element
        lastText = snap.text
        Log.monitor.debug("text changed: length=\(snap.text.count)")
        onChange()
        scheduleSettle(snap)
    }

    private func snapshot(of app: NSRunningApplication) -> FocusedText? {
        let pid = app.processIdentifier
        let electron = isElectron(app)
        if electron, !manualAXEnabledPIDs.contains(pid) {
            AX.enableManualAccessibility(pid: pid)
            manualAXEnabledPIDs.insert(pid)
        }
        guard let element = AX.focusedElement(pid: pid) else {
            diagnose("\(app.bundleIdentifier ?? "?") electron=\(electron): no focused element")
            return nil
        }
        let role = AX.string(element, kAXRoleAttribute) ?? "nil"
        let subrole = AX.string(element, kAXSubroleAttribute) ?? "nil"
        let valueType = AX.copy(element, kAXValueAttribute).map { String(describing: CFCopyTypeIDDescription(CFGetTypeID($0))) } ?? "nil"
        guard AX.isEditableText(element) else {
            diagnose("\(app.bundleIdentifier ?? "?") electron=\(electron): not editable role=\(role) subrole=\(subrole) value=\(valueType)")
            return nil
        }
        guard let text = AX.value(element) else {
            diagnose("\(app.bundleIdentifier ?? "?") electron=\(electron): no string value role=\(role) value=\(valueType)")
            return nil
        }
        diagnose("\(app.bundleIdentifier ?? "?") electron=\(electron): OK role=\(role) subrole=\(subrole)")
        return FocusedText(element: element, pid: pid, bundleID: app.bundleIdentifier, isElectron: electron, text: text)
    }

    private func scheduleSettle(_ snap: FocusedText) {
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.lastText == snap.text else { return }
            self.onSettled(snap)
        }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceSeconds(), execute: work)
    }

    private var lastDiagnosis = ""

    /// Logs only when the reason changes, so polling doesn't flood the log.
    private func diagnose(_ message: String) {
        guard message != lastDiagnosis else { return }
        lastDiagnosis = message
        Log.monitor.info("\(message, privacy: .public)")
    }

    private func reset() {
        settleWork?.cancel()
        settleWork = nil
        guard lastElement != nil else { return }
        lastElement = nil
        lastText = nil
        onFocusLost()
    }

    private func isElectron(_ app: NSRunningApplication) -> Bool {
        let key = app.bundleIdentifier ?? "\(app.processIdentifier)"
        if let cached = electronCache[key] { return cached }
        let framework = app.bundleURL?.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        let result = framework.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        electronCache[key] = result
        return result
    }
}

enum TextHeuristics {
    static let maxLength = 4000

    /// Only English-ish text is worth sending; pure Japanese messages are skipped.
    static func looksLikeEnglish(_ text: String) -> Bool {
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let latin = letters.filter { $0.isASCII }
        guard latin.count >= 6, text.contains(" ") else { return false }
        return Double(latin.count) / Double(letters.count) >= 0.3
    }
}
