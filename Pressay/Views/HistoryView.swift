import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum HistoryFilter: String, CaseIterable, Identifiable {
    case all
    case favorites
    case derived

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "Tout"
        case .favorites: "Favoris"
        case .derived: "Retraité"
        }
    }
}

struct HistoryView: View {
    @ObservedObject var historyService = HistoryService.shared
    @ObservedObject private var reprocessor = HistoryReprocessingService.shared
    @ObservedObject private var modes = ModeStore.shared
    @AppStorage(Constants.historyRetentionDaysKey) private var retentionDays = 1
    @State private var searchText = ""
    @State private var filter: HistoryFilter = .all
    @State private var pendingDeletion = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if historyService.entries.isEmpty {
                emptyState
            } else if filteredEntries.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 9) {
                        ForEach(filteredEntries) { entry in
                            HistoryEntryView(
                                entry: entry,
                                modes: modes.visibleModes,
                                onFavorite: { historyService.toggleFavorite(entry) },
                                onTagsChanged: { historyService.updateTags($0, for: entry) },
                                onReprocess: { mode in
                                    Task { await reprocessor.reprocess(entry, with: mode) }
                                },
                                onDelete: { historyService.delete(entry) }
                            )
                        }
                    }
                    .padding()
                }
            }

            if reprocessor.isProcessing || reprocessor.lastMessage != nil {
                Divider()
                HStack(spacing: 8) {
                    if reprocessor.isProcessing { ProgressView().controlSize(.small) }
                    Image(systemName: reprocessor.lastError == nil ? "wand.and.stars" : "exclamationmark.triangle")
                        .foregroundStyle(reprocessor.lastError == nil ? .blue : .orange)
                    Text(reprocessor.lastError ?? reprocessor.lastMessage ?? "")
                        .font(.caption)
                        .lineLimit(2)
                    Spacer()
                    Button("Fermer") { reprocessor.clearMessage() }
                        .buttonStyle(.plain)
                        .font(.caption)
                }
                .padding(10)
            }
        }
        .frame(minWidth: 560, idealWidth: 680, minHeight: 480, idealHeight: 620)
        .confirmationDialog(
            "Effacer tout l’historique ?",
            isPresented: $pendingDeletion
        ) {
            Button("Tout effacer", role: .destructive) { historyService.clearAll() }
        } message: {
            Text("Cette suppression retire définitivement l’historique local chiffré.")
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack {
                Label("Historique", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Text("\(historyService.entries.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Markdown…") { exportMarkdown() }
                    Button("JSON…") { exportJSON() }
                } label: {
                    Label("Exporter", systemImage: "square.and.arrow.up")
                }
                .disabled(historyService.entries.isEmpty)
                Button("Tout effacer", role: .destructive) { pendingDeletion = true }
                    .disabled(historyService.entries.isEmpty)
            }

            HStack(spacing: 8) {
                TextField("Rechercher dans le texte, les tags ou le fournisseur", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Picker("Filtre", selection: $filter) {
                    ForEach(HistoryFilter.allCases) { item in
                        Text(item.label).tag(item)
                    }
                }
                .labelsHidden()
                .frame(width: 120)
            }
        }
        .padding()
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "Aucune transcription",
            systemImage: "clock.arrow.circlepath",
            description: Text("Les transcriptions s’effacent après \(retentionLabel).")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var filteredEntries: [TranscriptionEntry] {
        historyService.entries.filter { entry in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = true
            case .favorites: matchesFilter = entry.isFavorite
            case .derived: matchesFilter = entry.parentEntryID != nil
            }
            guard matchesFilter else { return false }
            let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            let searchable = [
                entry.text,
                entry.rawText,
                entry.applicationBundleIdentifier ?? "",
                entry.transcriptionProvider ?? "",
                entry.processingProvider ?? "",
                entry.tags.joined(separator: " ")
            ].joined(separator: " ")
            return searchable.localizedCaseInsensitiveContains(query)
        }
    }

    private var retentionLabel: String {
        retentionDays == 1 ? "24 h" : "\(retentionDays) jours"
    }

    private func exportMarkdown() {
        save(
            data: Data(historyService.markdownExport().utf8),
            suggestedName: "pressay-history.md",
            contentType: UTType(filenameExtension: "md") ?? .plainText
        )
    }

    private func exportJSON() {
        guard let data = try? historyService.jsonExport() else { return }
        save(data: data, suggestedName: "pressay-history.json", contentType: .json)
    }

    private func save(data: Data, suggestedName: String, contentType: UTType) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [contentType]
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }
}

private struct HistoryEntryView: View {
    let entry: TranscriptionEntry
    let modes: [ModeDefinition]
    let onFavorite: () -> Void
    let onTagsChanged: ([String]) -> Void
    let onReprocess: (ModeDefinition) -> Void
    let onDelete: () -> Void

    @State private var showsTags = false
    @State private var tagText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(entry.date, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let provider = entry.processingProvider ?? entry.transcriptionProvider {
                    Text(provider)
                        .font(.caption2.monospaced())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.09), in: Capsule())
                }
                if entry.parentEntryID != nil {
                    Label("Retraité", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                        .font(.caption2)
                        .foregroundStyle(.purple)
                }
                Spacer()
                Button(action: onFavorite) {
                    Image(systemName: entry.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(entry.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .help(entry.isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
                Menu {
                    Button("Copier") { TextInjector.shared.copyToPasteboard(entry.text) }
                    Menu("Retraiter avec") {
                        ForEach(modes.filter { $0.cleaningLevel != .faithful }) { mode in
                            Button(mode.name) { onReprocess(mode) }
                        }
                    }
                    Button("Modifier les tags…") {
                        tagText = entry.tags.joined(separator: ", ")
                        showsTags = true
                    }
                    Divider()
                    Button("Supprimer", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            Text(entry.text)
                .font(.system(size: 13))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            if entry.rawText != entry.text {
                DisclosureGroup("Voir la transcription brute") {
                    Text(entry.rawText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                }
                .font(.caption)
            }

            if !entry.tags.isEmpty {
                HStack(spacing: 5) {
                    ForEach(entry.tags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
        .background(.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .popover(isPresented: $showsTags) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tags").font(.headline)
                TextField("projet, client, idée", text: $tagText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 260)
                    .onSubmit(saveTags)
                HStack {
                    Spacer()
                    Button("Annuler") { showsTags = false }
                    Button("Enregistrer", action: saveTags)
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    private func saveTags() {
        onTagsChanged(tagText.split(separator: ",").map(String.init))
        showsTags = false
    }
}

#Preview {
    HistoryView()
}
