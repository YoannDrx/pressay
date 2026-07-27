import AppKit
import SwiftUI

@MainActor
final class TextPreviewController: NSObject, ObservableObject, TextPreviewPresenting {
    static let shared = TextPreviewController()

    @Published private(set) var preview: TextPreview?
    @Published var draft = ""

    private var panel: NSPanel?
    private var applyHandler: ((String) -> Void)?
    private var cancelHandler: (() -> Void)?
    private var isResolving = false

    func show(
        _ preview: TextPreview,
        onApply: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        isResolving = false
        self.preview = preview
        draft = preview.proposedText
        applyHandler = onApply
        cancelHandler = onCancel

        let panel = panel ?? makePanel()
        self.panel = panel
        panel.center()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    func hide() {
        panel?.orderOut(nil)
        preview = nil
        draft = ""
        applyHandler = nil
        cancelHandler = nil
        isResolving = false
    }

    func apply() {
        guard !isResolving else { return }
        let cleanDraft = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanDraft.isEmpty else { return }
        isResolving = true
        let handler = applyHandler
        hide()
        handler?(cleanDraft)
    }

    func cancel() {
        guard !isResolving else { return }
        isResolving = true
        let handler = cancelHandler
        hide()
        handler?()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 500),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.title = "Aperçu Pressay"
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.minSize = NSSize(width: 620, height: 400)
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: TextPreviewView(controller: self))
        return panel
    }
}

extension TextPreviewController: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cancel()
        return false
    }
}

private struct TextPreviewView: View {
    @ObservedObject var controller: TextPreviewController

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            comparison
            Divider()
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onExitCommand(perform: controller.cancel)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 34, height: 34)
                .background(.purple.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(controller.preview?.modeName ?? "Transformation")
                    .font(.system(size: 14, weight: .semibold))
                Text(contextDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Label("Cloud", systemImage: "cloud")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.orange.opacity(0.1), in: Capsule())
                .accessibilityLabel("Traitement dans le cloud")
        }
        .padding(18)
    }

    private var comparison: some View {
        HStack(spacing: 0) {
            textColumn(
                title: "ORIGINAL",
                text: controller.preview?.originalText ?? "",
                editable: false,
                isProposed: false
            )
            Divider()
            textColumn(
                title: controller.preview?.isReadOnly == true
                    ? "FINAL"
                    : "PROPOSITION",
                text: controller.draft,
                editable: controller.preview?.isReadOnly != true,
                isProposed: true
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func textColumn(
        title: String,
        text: String,
        editable: Bool,
        isProposed: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            if editable {
                if shouldShowCompactDiff {
                    ScrollView {
                        Text(diffText(text, isProposed: true))
                            .font(.system(size: 11))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .frame(maxHeight: 74)
                    .padding(8)
                    .background(
                        .secondary.opacity(0.05),
                        in: RoundedRectangle(cornerRadius: 9)
                    )
                    .accessibilityLabel("Diff des changements proposés")
                }
                TextEditor(text: $controller.draft)
                    .font(.system(size: 12))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                    .accessibilityLabel("Proposition modifiable")
                    .accessibilityHint(
                        "Commande Entrée applique la proposition"
                    )
            } else {
                ScrollView {
                    Text(diffText(text, isProposed: isProposed))
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(9)
                }
                .background(.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityLabel(
                    title == "ORIGINAL"
                        ? "Texte original en lecture seule"
                        : "Texte final en lecture seule"
                )
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack {
            Text("Le texte sélectionné est traité comme donnée, jamais comme instruction.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            if controller.preview?.isReadOnly == true {
                Button("Fermer", action: controller.cancel)
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
            } else {
                Button("Annuler", action: controller.cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Appliquer", action: controller.apply)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint(
                        "Applique la proposition à la cible d’origine"
                    )
                Button("", action: controller.apply)
                    .keyboardShortcut(.defaultAction)
                    .labelsHidden()
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
        }
        .padding(16)
    }

    private var contextDescription: String {
        guard let preview = controller.preview else { return "" }
        let sources = preview.contextManifest.isEmpty
            ? "aucun contexte"
            : preview.contextManifest.joined(separator: ", ")
        return "\(preview.providerIdentifier) · contexte transmis : \(sources)"
    }

    private var shouldShowCompactDiff: Bool {
        guard let preview = controller.preview else { return false }
        return preview.originalText != controller.draft
            && max(preview.originalText.count, controller.draft.count) <= 1_200
    }

    private func diffText(
        _ fallback: String,
        isProposed: Bool
    ) -> AttributedString {
        guard shouldShowCompactDiff,
              let preview = controller.preview else {
            return AttributedString(fallback)
        }
        return WordDiffRenderer.render(
            original: preview.originalText,
            proposed: controller.draft,
            proposedSide: isProposed
        )
    }
}

private enum WordDiffRenderer {
    private enum Change {
        case unchanged(String)
        case removed(String)
        case added(String)
    }

    static func render(
        original: String,
        proposed: String,
        proposedSide: Bool
    ) -> AttributedString {
        let changes = diff(tokens(original), tokens(proposed))
        var output = AttributedString()
        for change in changes {
            switch change {
            case .unchanged(let value):
                output += AttributedString(value)
            case .removed(let value) where !proposedSide:
                let prefix = NSWorkspace.shared
                    .accessibilityDisplayShouldDifferentiateWithoutColor
                    ? "−"
                    : ""
                var part = AttributedString(prefix + value)
                part.foregroundColor = .red
                part.backgroundColor = .red.opacity(0.12)
                part.strikethroughStyle = .single
                output += part
            case .added(let value) where proposedSide:
                let prefix = NSWorkspace.shared
                    .accessibilityDisplayShouldDifferentiateWithoutColor
                    ? "+"
                    : ""
                var part = AttributedString(prefix + value)
                part.foregroundColor = .green
                part.backgroundColor = .green.opacity(0.12)
                part.underlineStyle = .single
                output += part
            default:
                break
            }
        }
        return output
    }

    private static func tokens(_ text: String) -> [String] {
        let pattern = #"\s+|[\p{L}\p{N}_]+|[^\s\p{L}\p{N}_]+"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }
        let range = NSRange(text.startIndex..., in: text)
        return expression.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private static func diff(_ left: [String], _ right: [String]) -> [Change] {
        var lengths = Array(
            repeating: Array(repeating: 0, count: right.count + 1),
            count: left.count + 1
        )
        if !left.isEmpty, !right.isEmpty {
            for leftIndex in stride(from: left.count - 1, through: 0, by: -1) {
                for rightIndex in stride(
                    from: right.count - 1,
                    through: 0,
                    by: -1
                ) {
                    lengths[leftIndex][rightIndex] =
                        left[leftIndex] == right[rightIndex]
                        ? lengths[leftIndex + 1][rightIndex + 1] + 1
                        : max(
                            lengths[leftIndex + 1][rightIndex],
                            lengths[leftIndex][rightIndex + 1]
                        )
                }
            }
        }

        var changes: [Change] = []
        var leftIndex = 0
        var rightIndex = 0
        while leftIndex < left.count || rightIndex < right.count {
            if leftIndex < left.count,
               rightIndex < right.count,
               left[leftIndex] == right[rightIndex] {
                changes.append(.unchanged(left[leftIndex]))
                leftIndex += 1
                rightIndex += 1
            } else if rightIndex < right.count,
                      leftIndex == left.count
                        || lengths[leftIndex][rightIndex + 1]
                            >= lengths[leftIndex + 1][rightIndex] {
                changes.append(.added(right[rightIndex]))
                rightIndex += 1
            } else {
                changes.append(.removed(left[leftIndex]))
                leftIndex += 1
            }
        }
        return changes
    }
}
