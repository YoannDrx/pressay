import AppKit
import SwiftUI

enum HUDState: Equatable {
    case listening
    case transcribing
    case success
    case cancelled

    var title: String {
        switch self {
        case .listening: return "J’écoute…"
        case .transcribing: return "Transcription…"
        case .success: return "Texte inséré"
        case .cancelled: return "Annulé"
        }
    }

    var icon: String {
        switch self {
        case .listening: return "waveform"
        case .transcribing: return "ellipsis"
        case .success: return "checkmark"
        case .cancelled: return "xmark"
        }
    }

    var color: Color {
        switch self {
        case .listening: return .red
        case .transcribing: return .blue
        case .success: return .green
        case .cancelled: return .secondary
        }
    }
}

@MainActor
final class StatusHUDController: ObservableObject {
    static let shared = StatusHUDController()

    @Published private(set) var state: HUDState = .listening
    @Published private(set) var detail: String?
    @Published private(set) var listeningStartedAt: Date?
    @Published private(set) var audioLevel: Float = 0
    @Published var isUndoAvailable = false
    @Published private(set) var canRetranscribe = false
    @Published private(set) var canCompareRawAndFinal = false
    var onCancel: (() -> Void)?
    var onUndo: (() -> Void)?
    private var onCopy: (() -> Void)?
    private var onRetranscribe: (() -> Void)?
    private var onCompareRawAndFinal: (() -> Void)?
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(
        _ state: HUDState,
        detail: String? = nil,
        autoHide: Bool = false
    ) {
        hideTask?.cancel()
        self.state = state
        self.detail = detail
        if state == .listening {
            listeningStartedAt = Date()
            isUndoAvailable = false
        } else if state == .success || state == .cancelled {
            listeningStartedAt = nil
        }

        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()

        if autoHide {
            hideTask = Task { [weak self] in
                let delay: Duration = self?.state == .success
                    ? .seconds(5)
                    : .milliseconds(900)
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    func updateAudioLevel(_ level: Float) {
        audioLevel = max(0, min(1, level))
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
    }

    func configureResultActions(
        canRetranscribe: Bool,
        canCompareRawAndFinal: Bool,
        onCopy: @escaping () -> Void,
        onRetranscribe: @escaping () -> Void,
        onCompareRawAndFinal: @escaping () -> Void
    ) {
        self.canRetranscribe = canRetranscribe
        self.canCompareRawAndFinal = canCompareRawAndFinal
        self.onCopy = onCopy
        self.onRetranscribe = onRetranscribe
        self.onCompareRawAndFinal = onCompareRawAndFinal
    }

    func copyResult() {
        onCopy?()
    }

    func retranscribeResult() {
        onRetranscribe?()
    }

    func compareRawAndFinalResult() {
        onCompareRawAndFinal?()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 430, height: 60),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: StatusHUDView(controller: self))
        return panel
    }

    private func position(_ panel: NSPanel) {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: min(max(pointer.x + 14, visible.minX + 8), visible.maxX - panel.frame.width - 8),
            y: min(max(pointer.y - panel.frame.height - 18, visible.minY + 8), visible.maxY - panel.frame.height - 8)
        )
        panel.setFrameOrigin(origin)
    }

    func elapsedText(at date: Date) -> String {
        guard let listeningStartedAt else { return "" }
        let elapsed = max(0, Int(date.timeIntervalSince(listeningStartedAt)))
        return String(format: "%02d:%02d", elapsed / 60, elapsed % 60)
    }
}

extension StatusHUDController: HUDPresenting {}

private struct StatusHUDView: View {
    @ObservedObject var controller: StatusHUDController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor)
    private var differentiateWithoutColor

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(controller.state.color.opacity(0.16))
                    .frame(width: 30, height: 30)
                Image(systemName: controller.state.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(controller.state.color)
                    .symbolEffect(
                        .pulse,
                        isActive: !reduceMotion
                            && controller.state == .transcribing
                    )
                    .symbolEffect(
                        .variableColor.iterative,
                        isActive: !reduceMotion
                            && controller.state == .listening
                    )
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(controller.state.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if controller.state == .listening {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(controller.elapsedText(at: context.date))
                        }
                    }
                    if let detail = controller.detail {
                        Text(detail)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.secondary)

                if controller.state == .listening {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(.secondary.opacity(0.16))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(controller.state.color)
                                    .frame(
                                        width: max(
                                            2,
                                            proxy.size.width * CGFloat(controller.audioLevel)
                                        )
                                    )
                            }
                    }
                    .frame(height: 2)
                    .accessibilityElement()
                    .accessibilityLabel("Niveau du microphone")
                    .accessibilityValue(
                        "\(Int(controller.audioLevel * 100)) pour cent"
                    )
                }
            }
            Spacer(minLength: 0)
            if controller.state == .success {
                HStack(spacing: 7) {
                    Button("Copier", action: controller.copyResult)
                        .accessibilityHint(
                            "Copie le résultat visible dans le presse-papiers"
                        )
                    if controller.canRetranscribe {
                        Button("Retranscrire", action: controller.retranscribeResult)
                            .accessibilityHint(
                                "Relance la transcription depuis l’audio temporaire"
                            )
                    }
                    if controller.canCompareRawAndFinal {
                        Button("Brut/Final", action: controller.compareRawAndFinalResult)
                            .accessibilityLabel(
                                "Comparer la transcription brute et le texte final"
                            )
                    }
                    if controller.isUndoAvailable {
                        Button("Annuler") {
                            controller.onUndo?()
                        }
                        .accessibilityLabel("Annuler la dernière insertion")
                    }
                }
                .font(.system(size: 9, weight: .semibold))
                .buttonStyle(.plain)
            } else if controller.state == .listening || controller.state == .transcribing {
                Button {
                    controller.onCancel?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(.primary.opacity(0.07), in: Circle())
                }
                .buttonStyle(.plain)
                .help("Annuler")
                .accessibilityLabel(
                    controller.state == .listening
                        ? "Annuler l’enregistrement"
                        : "Annuler la transcription"
                )
            }
        }
        .padding(.horizontal, 12)
        .frame(width: 430, height: 60)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(
                    differentiateWithoutColor
                        ? Color.primary.opacity(0.5)
                        : Color.white.opacity(0.14),
                    lineWidth: differentiateWithoutColor ? 1.5 : 0.5
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pressay. \(controller.state.title)")
    }
}
