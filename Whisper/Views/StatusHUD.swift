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
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(_ state: HUDState, autoHide: Bool = false) {
        hideTask?.cancel()
        self.state = state

        let panel = panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()

        if autoHide {
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        hideTask = nil
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 164, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
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
}

private struct StatusHUDView: View {
    @ObservedObject var controller: StatusHUDController

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(controller.state.color.opacity(0.16))
                    .frame(width: 30, height: 30)
                Image(systemName: controller.state.icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(controller.state.color)
                    .symbolEffect(.pulse, isActive: controller.state == .transcribing)
                    .symbolEffect(.variableColor.iterative, isActive: controller.state == .listening)
            }

            Text(controller.state.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: 164, height: 52)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 0.5)
        )
    }
}
