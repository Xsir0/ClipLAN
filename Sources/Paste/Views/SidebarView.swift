import PasteCore
import SwiftUI

struct SidebarView: View {
    @ObservedObject var model: ClipboardAppModel
    var onOpenSettings: () -> Void

    var body: some View {
        List(selection: $model.filter) {
            Section("Library") {
                ForEach(EntryFilter.allCases) { filter in
                    Label(filter.title, systemImage: filter.systemImage)
                        .tag(filter)
                }
            }

            Section("Devices") {
                if model.peers.isEmpty {
                    Label("No LAN peers", systemImage: "network.slash")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.peers) { peer in
                        Label(peer.name, systemImage: "desktopcomputer")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                Button(action: onOpenSettings) {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Settings")

                Divider()

                Text(model.syncStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }
}
