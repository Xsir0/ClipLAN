import PasteCore
import SwiftUI

struct EntryListView: View {
    @ObservedObject var model: ClipboardAppModel

    var body: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(16)

            Divider()

            if model.filteredEntries.isEmpty {
                ContentUnavailableView("No Items", systemImage: "doc.on.clipboard")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(model.filteredEntries) { entry in
                            EntryRowView(
                                entry: entry,
                                isSelected: model.selectedID == entry.id,
                                peers: model.peers,
                                onSelect: { model.selectedID = entry.id },
                                onPaste: { model.paste(entry) },
                                onPin: { model.togglePinned(entry) },
                                onFavorite: { model.toggleFavorite(entry) },
                                onDelete: { model.delete(entry) },
                                onSend: { peer in model.send(entry, to: peer) }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .background(.background)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $model.query)
                .textFieldStyle(.plain)
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct EntryRowView: View {
    let entry: ClipboardEntry
    let isSelected: Bool
    let peers: [PeerDevice]
    let onSelect: () -> Void
    let onPaste: () -> Void
    let onPin: () -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void
    let onSend: (PeerDevice) -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: entry.type.systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(isSelected ? .white : .indigo)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.preview.isEmpty ? entry.type.displayName : entry.preview)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(2)
                        .foregroundStyle(isSelected ? .white : .primary)

                    HStack(spacing: 8) {
                        Text(entry.type.displayName)
                        if let sourceApp = entry.sourceApp, !sourceApp.isEmpty {
                            Text(sourceApp)
                        }
                        Text(entry.createdAt, style: .relative)
                        if entry.needsPayload {
                            Label("Remote", systemImage: "icloud.and.arrow.down")
                                .labelStyle(.titleAndIcon)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.72) : .secondary)
                    .lineLimit(1)
                }

                Spacer(minLength: 8)

                VStack(spacing: 8) {
                    if entry.isPinned {
                        Image(systemName: "pin.fill")
                    }
                    if entry.isFavorite {
                        Image(systemName: "star.fill")
                    }
                }
                .font(.caption)
                .foregroundStyle(isSelected ? .white : .secondary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Paste", action: onPaste)
            Button(entry.isPinned ? "Unpin" : "Pin", action: onPin)
            Button(entry.isFavorite ? "Unfavorite" : "Favorite", action: onFavorite)
            Menu("Send To") {
                if peers.isEmpty {
                    Text("No LAN peers")
                } else {
                    ForEach(peers) { peer in
                        Button(peer.name) {
                            onSend(peer)
                        }
                    }
                }
            }
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var rowBackground: some ShapeStyle {
        isSelected ? AnyShapeStyle(Color.indigo) : AnyShapeStyle(Color.secondary.opacity(0.08))
    }
}
