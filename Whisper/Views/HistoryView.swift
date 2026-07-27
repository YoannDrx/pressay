import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyService = HistoryService.shared
    @AppStorage(Constants.historyRetentionDaysKey) private var retentionDays = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Historique")
                    .font(.headline)
                Spacer()
                if !historyService.entries.isEmpty {
                    Button("Tout effacer") {
                        historyService.clearAll()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            if historyService.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Aucune transcription")
                        .foregroundStyle(.secondary)
                    Text("Les transcriptions s'effacent après \(retentionLabel)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(historyService.entries) { entry in
                            HistoryEntryView(entry: entry) {
                                historyService.delete(entry)
                            }
                        }
                    }
                    .padding()
                }
            }
        }
        .frame(width: 350, height: 400)
    }

    private var retentionLabel: String {
        retentionDays == 1 ? "24 h" : "\(retentionDays) jours"
    }
}

struct HistoryEntryView: View {
    let entry: TranscriptionEntry
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(timeAgo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isHovering {
                    Button {
                        // Copier dans le presse-papiers
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.text, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
            }

            Text(entry.text)
                .font(.system(size: 12))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
        .onHover { isHovering = $0 }
    }

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: entry.date, relativeTo: Date())
    }
}

#Preview {
    HistoryView()
}
