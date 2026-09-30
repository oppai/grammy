import AppKit
import SwiftUI

final class SuggestionViewModel: ObservableObject {
    enum Phase {
        case checking
        case suggestion(GrammarResult, AttributedString)
        case ok
        case error(String)
    }

    @Published var phase: Phase = .checking
    var onApply: () -> Void = {}
    var onDismiss: () -> Void = {}
}

struct SuggestionView: View {
    @ObservedObject var model: SuggestionViewModel

    var body: some View {
        content
            .padding(12)
            .frame(width: 400, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.separator))
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("チェック中…").foregroundStyle(.secondary)
            }
        case .ok:
            Label("問題なさそうです", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .error(message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Spacer()
                    Button("閉じる") { model.onDismiss() }
                }
            }
        case let .suggestion(result, diff):
            suggestion(result, diff: diff)
        }
    }

    private func suggestion(_ result: GrammarResult, diff: AttributedString) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("改善案", systemImage: "sparkles").font(.headline)
                Spacer()
                Button { model.onDismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
            }

            Text(diff)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))

            ForEach(result.issues.prefix(5)) { issue in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(issue.original).strikethrough().foregroundStyle(.red)
                        Image(systemName: "arrow.right").font(.caption).foregroundStyle(.secondary)
                        Text(issue.replacement).foregroundStyle(.green)
                    }
                    Text(issue.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Spacer()
                Button("無視") { model.onDismiss() }
                Button("適用  ⌃⌥↩") { model.onApply() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    // Let a single click on a button work even though the panel never becomes key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// Floating, non-activating panel so the user's focus stays in Slack.
final class SuggestionPanelController {
    let model = SuggestionViewModel()
    private var hideWork: DispatchWorkItem?

    private lazy var hostingView: NSHostingView<SuggestionView> = {
        let view = FirstMouseHostingView(rootView: SuggestionView(model: model))
        view.sizingOptions = [.intrinsicContentSize]
        return view
    }()

    private lazy var panel: NSPanel = {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: true)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = hostingView
        return panel
    }()

    var isVisible: Bool { panel.isVisible }

    func show(_ phase: SuggestionViewModel.Phase, near anchor: CGRect?, autoHideAfter delay: TimeInterval? = nil) {
        hideWork?.cancel()
        model.phase = phase
        hostingView.layoutSubtreeIfNeeded()
        let size = hostingView.fittingSize
        let frame = frame(for: size, near: anchor)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        Log.check.info("""
        panel: phase=\(String(describing: phase).prefix(20), privacy: .public) fitting=\(String(describing: size), privacy: .public) \
        frame=\(String(describing: frame), privacy: .public) visible=\(self.panel.isVisible) onScreen=\(self.panel.occlusionState.contains(.visible)) \
        screens=\(NSScreen.screens.map { String(describing: $0.frame) }.joined(separator: " "), privacy: .public)
        """)

        if let delay {
            let work = DispatchWorkItem { [weak self] in self?.hide() }
            hideWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }

    func hide() {
        hideWork?.cancel()
        panel.orderOut(nil)
    }

    private func frame(for size: CGSize, near anchor: CGRect?) -> CGRect {
        let fallbackPoint = NSEvent.mouseLocation
        let anchor = anchor ?? CGRect(origin: fallbackPoint, size: .zero)
        let screen = NSScreen.screens.first { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }
            ?? NSScreen.main ?? NSScreen.screens[0]
        let visible = screen.visibleFrame
        let gap: CGFloat = 6

        // Prefer below the caret; Slack's composer sits at the bottom, so usually this flips above.
        var origin = CGPoint(x: anchor.minX, y: anchor.minY - gap - size.height)
        if origin.y < visible.minY {
            origin.y = anchor.maxY + gap
        }
        origin.x = min(max(origin.x, visible.minX + gap), visible.maxX - size.width - gap)
        origin.y = min(max(origin.y, visible.minY + gap), visible.maxY - size.height - gap)
        return CGRect(origin: origin, size: size)
    }
}
