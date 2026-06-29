import PasteCore
import SwiftUI

struct EntryDetailView: View {
    @ObservedObject var model: ClipboardAppModel
    let entry: ClipboardEntry?

    var body: some View {
        Group {
            if let entry {
                detail(for: entry)
            } else {
                ContentUnavailableView("No Selection", systemImage: "sidebar.right")
            }
        }
        .background(.background)
    }

    private func detail(for entry: ClipboardEntry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            header(entry)
                .padding(24)

            Divider()

            preview(entry)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)

            Divider()

            actions(entry)
                .padding(16)
        }
    }

    private func header(_ entry: ClipboardEntry) -> some View {
        HStack(spacing: 16) {
            Image(systemName: entry.type.systemImage)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.indigo)
                .frame(width: 44, height: 44)
                .background(.indigo.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.type.displayName)
                    .font(.title3.weight(.semibold))
                HStack(spacing: 8) {
                    if let sourceApp = entry.sourceApp {
                        Text(sourceApp)
                    }
                    Text(ByteCountFormatter.string(fromByteCount: Int64(entry.byteSize), countStyle: .file))
                    Text(entry.createdAt, style: .date)
                    Text(entry.createdAt, style: .time)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    @ViewBuilder
    private func preview(_ entry: ClipboardEntry) -> some View {
        if entry.needsPayload {
            VStack(spacing: 16) {
                Image(systemName: "icloud.and.arrow.down")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Button("Fetch Payload") {
                    model.requestPayload(entry)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if entry.type == .image, let image = model.image(for: entry) {
            VStack(alignment: .leading, spacing: 16) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let ocrText = entry.ocrText, !ocrText.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recognized Text")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(ocrText)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .lineLimit(4)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        } else if entry.type == .file {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.fileURLs(for: entry), id: \.absoluteString) { url in
                        Label(url.path, systemImage: "doc")
                            .font(.system(size: 14))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ScrollView {
                Text(model.fullText(for: entry))
                    .font(.system(size: 16, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func actions(_ entry: ClipboardEntry) -> some View {
        HStack(spacing: 8) {
            Button {
                model.paste(entry)
            } label: {
                Label("Paste", systemImage: "arrow.down.doc")
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)

            Button {
                model.togglePinned(entry)
            } label: {
                Label(entry.isPinned ? "Unpin" : "Pin", systemImage: entry.isPinned ? "pin.slash" : "pin")
            }

            Button {
                model.toggleFavorite(entry)
            } label: {
                Label(entry.isFavorite ? "Unfavorite" : "Favorite", systemImage: entry.isFavorite ? "star.slash" : "star")
            }

            Menu {
                if model.peers.isEmpty {
                    Text("No LAN peers")
                } else {
                    ForEach(model.peers) { peer in
                        Button(peer.name) {
                            model.send(entry, to: peer)
                        }
                    }
                }
            } label: {
                Label("Send", systemImage: "paperplane")
            }

            Spacer()

            Button(role: .destructive) {
                model.delete(entry)
            } label: {
                Image(systemName: "trash")
            }
            .help("Delete")
        }
    }
}
