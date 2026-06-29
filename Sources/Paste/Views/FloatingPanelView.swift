import AppKit
import PasteCore
import SwiftUI

struct FloatingPanelView: View {
    @ObservedObject var model: ClipboardAppModel
    var onPaste: (ClipboardEntry) -> Void

    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 10) {
            searchField

            if model.floatingEntries.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 10) {
                            ForEach(model.floatingEntries) { entry in
                                FloatingEntryTile(
                                    model: model,
                                    entry: entry,
                                    isSelected: entry.id == model.selectedID
                                )
                                .id(entry.id)
                                .onTapGesture {
                                    model.selectedID = entry.id
                                    onPaste(entry)
                                }
                            }
                        }
                        .padding(.horizontal, 2)
                    }
                    .onChange(of: model.selectedID) { _, selectedID in
                        guard let selectedID else {
                            return
                        }
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(selectedID, anchor: .center)
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(.white.opacity(0.18), lineWidth: 1)
        )
        .onAppear {
            searchFocused = true
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search clipboard", text: $model.floatingQuery)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(.system(size: 15))

            if !model.floatingQuery.isEmpty {
                Button {
                    model.floatingQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text("No matching clips")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 114, maxHeight: .infinity)
    }
}

private struct FloatingEntryTile: View {
    @ObservedObject var model: ClipboardAppModel
    let entry: ClipboardEntry
    let isSelected: Bool

    var body: some View {
        Group {
            if let preview = model.immediateFloatingMediaPreview(for: entry) {
                mediaTile(preview)
            } else {
                textTile
            }
        }
        .frame(width: 138, height: 114, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(borderColor, lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            Task { @MainActor in
                await model.loadFloatingMediaPreview(for: entry)
            }
        }
        .task(id: entry.id) {
            await model.loadFloatingMediaPreview(for: entry)
        }
    }

    private var textTile: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: entry.type.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 22, height: 22)

                Spacer(minLength: 0)

                if entry.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? .white.opacity(0.80) : .secondary)
                }
            }

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? .white : .primary)
                .lineLimit(3)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                Text(entry.type.displayName)
                Text("·")
                Text(entry.createdAt, style: .relative)
            }
            .font(.system(size: 11))
            .foregroundStyle(isSelected ? .white.opacity(0.72) : .secondary)
            .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(tileBackground, in: RoundedRectangle(cornerRadius: 8))
    }

    private func mediaTile(_ preview: FloatingMediaPreview) -> some View {
        ZStack(alignment: .bottomLeading) {
            Image(nsImage: preview.image)
                .resizable()
                .scaledToFill()
                .frame(width: 138, height: 114)
                .clipped()

            if preview.kind == .fileVideo {
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(.black.opacity(0.42), in: Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: mediaIconName(for: preview.kind))
                        .font(.system(size: 12, weight: .semibold))
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text(entry.type.displayName)
                    Text("·")
                    Text(entry.createdAt, style: .relative)
                }
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .foregroundStyle(.primary)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.regularMaterial)
        }
        .background(Color.secondary.opacity(0.08))
    }

    private var title: String {
        let trimmed = entry.preview.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? entry.type.displayName : trimmed
    }

    private var iconColor: some ShapeStyle {
        isSelected ? AnyShapeStyle(Color.white) : AnyShapeStyle(Color.indigo)
    }

    private var tileBackground: some ShapeStyle {
        isSelected ? AnyShapeStyle(Color.indigo) : AnyShapeStyle(Color.secondary.opacity(0.08))
    }

    private var borderColor: Color {
        if model.immediateFloatingMediaPreview(for: entry) != nil, isSelected {
            return .indigo
        }
        return isSelected ? Color.white.opacity(0.18) : Color.primary.opacity(0.04)
    }

    private func mediaIconName(for kind: FloatingMediaKind) -> String {
        kind == .fileVideo ? "play.rectangle.fill" : "photo.fill"
    }
}
