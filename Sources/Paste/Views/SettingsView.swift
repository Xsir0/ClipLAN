import AppKit
import Foundation
import PasteCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: ClipboardAppModel

    @AppStorage(PasteSettingsKeys.maxEntries) private var maxEntries = 10_000
    @AppStorage(PasteSettingsKeys.maxEntryMB) private var maxEntryMB = 50
    @AppStorage(PasteSettingsKeys.autoPaste) private var autoPaste = true
    @AppStorage(PasteSettingsKeys.syncEnabled) private var syncEnabled = true
    @AppStorage(PasteSettingsKeys.syncDiscoverable) private var syncDiscoverable = true
    @AppStorage(PasteSettingsKeys.syncPairingCode) private var syncPairingCode = ""
    @AppStorage(PasteSettingsKeys.deviceName) private var deviceName = Host.current().localizedName ?? "Mac"
    @AppStorage(PasteSettingsKeys.hotKeyPreset) private var hotKeyPreset = HotKeyPreset.commandShiftV.rawValue
    @AppStorage(PasteSettingsKeys.launchAtLogin) private var launchAtLogin = false
    @AppStorage("ClipLAN.selectedSettingsSection") private var selectedSectionRaw = SettingsSection.general.rawValue

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            VStack(spacing: 0) {
                sectionHeader
                Divider()
                sectionBody
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 740, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            launchAtLogin = LaunchAtLoginManager.isEnabled
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                PasteLogoMark(size: 24)
                Text("ClipLAN")
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.bottom, 12)

            ForEach(SettingsSection.allCases) { section in
                SettingsSidebarButton(
                    section: section,
                    isSelected: selectedSection == section
                ) {
                    selectedSectionRaw = section.rawValue
                }
            }

            Spacer()
        }
        .padding(16)
        .frame(width: 164)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.70))
    }

    private var sectionHeader: some View {
        ZStack {
            WindowDragArea()

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(selectedSection.title)
                        .font(.system(size: 17, weight: .semibold))
                    Text(selectedSection.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 20)
            .allowsHitTesting(false)
        }
        .frame(height: 62)
        .background(.bar)
    }

    @ViewBuilder
    private var sectionBody: some View {
        ScrollView {
            VStack(spacing: 16) {
                switch selectedSection {
                case .general:
                    generalSettings
                case .sync:
                    syncSettings
                }
            }
            .padding(20)
        }
    }

    private var generalSettings: some View {
        VStack(spacing: 16) {
            SettingsGroup {
                SettingsRow(icon: "keyboard", title: "Shortcut") {
                    Picker("", selection: $hotKeyPreset) {
                        ForEach(HotKeyPreset.allCases) { preset in
                            Text(preset.title).tag(preset.rawValue)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                    .onChange(of: hotKeyPreset) { _, _ in
                        NotificationCenter.default.post(name: HotKeySettingsNotification.changed, object: nil)
                    }
                }

                SettingsDivider()

                SettingsRow(icon: "clock.arrow.circlepath", title: "History Limit") {
                    NumericStepper(value: $maxEntries, range: 100...100_000, step: 100)
                }

                SettingsDivider()

                SettingsRow(icon: "externaldrive", title: "Max Item Size") {
                    NumericStepper(value: $maxEntryMB, range: 1...512, step: 1, suffix: "MB")
                }
            }

            SettingsGroup {
                SettingsRow(icon: "command", title: "Auto Paste") {
                    Toggle("", isOn: $autoPaste)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(icon: "power", title: "Launch at Login") {
                    Toggle("", isOn: launchAtLoginBinding)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(icon: "accessibility", title: "Accessibility") {
                    Button {
                        _ = PasteExecutor.accessibilityTrusted(prompt: true)
                    } label: {
                        Label("Request", systemImage: "lock.open")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }
        }
    }

    private var syncSettings: some View {
        VStack(spacing: 16) {
            SyncOverviewCard(
                isEnabled: syncEnabled,
                isDiscoverable: syncDiscoverable,
                status: model.syncStatus,
                deviceName: deviceName,
                deviceID: model.deviceID,
                peerCount: model.peers.count
            )

            SettingsGroup {
                SettingsRow(icon: "network", title: "LAN Sync") {
                    Toggle("", isOn: $syncEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingsDivider()

                SettingsRow(icon: "dot.radiowaves.left.and.right", title: "Discoverable") {
                    Toggle("", isOn: $syncDiscoverable)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

            SettingsGroup {
                SettingsRow(icon: "desktopcomputer", title: "Device Name") {
                    TextField("", text: $deviceName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }

                SettingsDivider()

                SettingsRow(icon: "key", title: "Pairing Code") {
                    SecureField("", text: $syncPairingCode)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)
                }

                SettingsDivider()

                SettingsRow(icon: "checkmark.circle", title: "Sync Settings") {
                    Button {
                        model.restartServices()
                    } label: {
                        Label("Apply", systemImage: "checkmark")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }

            DiscoveredPeersSection(
                peers: model.peers,
                isSyncEnabled: syncEnabled,
                syncStatus: model.syncStatus
            )
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { newValue in
                do {
                    try LaunchAtLoginManager.setEnabled(newValue)
                    launchAtLogin = newValue
                    model.statusMessage = newValue ? "Launch at login enabled" : "Launch at login disabled"
                } catch {
                    launchAtLogin = LaunchAtLoginManager.isEnabled
                    model.statusMessage = error.localizedDescription
                }
            }
        )
    }

    private var selectedSection: SettingsSection {
        SettingsSection(rawValue: selectedSectionRaw) ?? .general
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case sync

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .sync: "Sync"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Shortcut, history, startup"
        case .sync: "Local network and pairing"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .sync: "network"
        }
    }
}

private struct SettingsSidebarButton: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(section.title, systemImage: section.systemImage)
                .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .white : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct SyncOverviewCard: View {
    let isEnabled: Bool
    let isDiscoverable: Bool
    let status: String
    let deviceName: String
    let deviceID: String
    let peerCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isEnabled ? Color.accentColor : Color.secondary)
                    .frame(width: 44, height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill((isEnabled ? Color.accentColor : Color.secondary).opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 5) {
                    Text("LAN Sync")
                        .font(.system(size: 16, weight: .semibold))
                    Text(status)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer()

                HStack(spacing: 8) {
                    SettingsBadge(
                        title: isEnabled ? "Enabled" : "Off",
                        systemImage: isEnabled ? "checkmark.circle.fill" : "pause.circle",
                        tint: isEnabled ? .green : .secondary
                    )
                    SettingsBadge(
                        title: isDiscoverable ? "Discoverable" : "Hidden",
                        systemImage: isDiscoverable ? "dot.radiowaves.left.and.right" : "eye.slash",
                        tint: isDiscoverable ? Color.accentColor : .secondary
                    )
                }
            }

            HStack(spacing: 12) {
                SettingsInfoTile(
                    icon: "desktopcomputer",
                    title: "This Mac",
                    value: deviceName,
                    detail: "ID \(String(deviceID.prefix(8)))"
                )
                SettingsInfoTile(
                    icon: "network",
                    title: "Discovered",
                    value: "\(peerCount)",
                    detail: peerCount == 1 ? "paired device" : "paired devices"
                )
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct DiscoveredPeersSection: View {
    let peers: [PeerDevice]
    let isSyncEnabled: Bool
    let syncStatus: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Discovered Devices", systemImage: "display.2")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("\(peers.count)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(.quaternary, in: Capsule())
            }

            if peers.isEmpty {
                EmptyPeersView(isSyncEnabled: isSyncEnabled, syncStatus: syncStatus)
            } else {
                VStack(spacing: 10) {
                    ForEach(peers) { peer in
                        PeerDeviceCard(peer: peer)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct PeerDeviceCard: View {
    let peer: PeerDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack(alignment: .bottomTrailing) {
                    Image(systemName: "macbook.and.iphone")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 38, height: 38)
                        .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))

                    Circle()
                        .fill(peer.isConnected ? Color.green : Color.secondary)
                        .frame(width: 9, height: 9)
                        .overlay(Circle().stroke(Color(nsColor: .controlBackgroundColor), lineWidth: 2))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(peer.name)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text(peer.addressDisplay)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                SettingsBadge(
                    title: peer.isConnected ? "Online" : "Offline",
                    systemImage: peer.isConnected ? "checkmark.circle.fill" : "xmark.circle",
                    tint: peer.isConnected ? .green : .secondary
                )
            }

            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    PeerMetadataTile(icon: "network", title: "IP / Port", value: peer.addressDisplay)
                    PeerMetadataTile(icon: "number", title: "Device ID", value: peer.shortID)
                }

                HStack(spacing: 8) {
                    PeerMetadataTile(icon: "dot.radiowaves.left.and.right", title: "Bonjour", value: peer.serviceDisplay)
                    PeerMetadataTile(icon: "clock", title: "Last Seen", value: lastSeenText)
                }

                HStack(spacing: 8) {
                    PeerMetadataTile(icon: "arrow.triangle.2.circlepath", title: "Interface", value: peer.interfaceName ?? "Auto")
                    PeerMetadataTile(icon: "point.3.connected.trianglepath.dotted", title: "Endpoint", value: peer.endpointDescription ?? "Resolved")
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private var lastSeenText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: peer.lastSeenAt, relativeTo: Date())
    }
}

private struct EmptyPeersView: View {
    let isSyncEnabled: Bool
    let syncStatus: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: isSyncEnabled ? "network.slash" : "pause.circle")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 42, height: 42)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 4) {
                Text(isSyncEnabled ? "No paired LAN devices found" : "LAN sync is turned off")
                    .font(.system(size: 13, weight: .semibold))
                Text(isSyncEnabled ? "Same network, matching pairing code, and Discoverable enabled are required." : syncStatus)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct PeerMetadataTile: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
        .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct SettingsInfoTile: View {
    let icon: String
    let title: String
    let value: String
    let detail: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 24, height: 24)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detail)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct SettingsBadge: View {
    let title: String
    let systemImage: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 11, weight: .semibold))
            .labelStyle(.titleAndIcon)
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

private struct SettingsGroup<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct SettingsRow<Accessory: View>: View {
    let icon: String
    let title: String
    let accessory: Accessory

    init(icon: String, title: String, @ViewBuilder accessory: () -> Accessory) {
        self.icon = icon
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 26, height: 26)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))

            Text(title)
                .font(.system(size: 13, weight: .medium))

            Spacer(minLength: 16)

            accessory
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Divider()
            .padding(.leading, 52)
    }
}

private struct NumericStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    var suffix: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(displayValue)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .trailing)

            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
                .frame(width: 58)
        }
    }

    private var displayValue: String {
        let formatted = value.formatted(.number)
        if let suffix {
            return "\(formatted) \(suffix)"
        }
        return formatted
    }
}
