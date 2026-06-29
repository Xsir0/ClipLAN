import AppKit
import Combine
import Foundation
import PasteCore

@MainActor
final class ClipboardAppModel: ObservableObject {
    @Published var entries: [ClipboardEntry] = []
    @Published var filter: EntryFilter = .all
    @Published var query: String = "" {
        didSet {
            refresh()
        }
    }
    @Published var selectedID: ClipboardEntry.ID?
    @Published var statusMessage = "Ready"
    @Published var syncStatus = "LAN sync stopped"
    @Published var peers: [PeerDevice] = []
    @Published private var floatingMediaPreviews: [ClipboardEntry.ID: FloatingMediaPreview] = [:]
    @Published var floatingQuery: String = "" {
        didSet {
            resetFloatingSelection()
        }
    }

    let deviceID: String

    private let payloadStore: PayloadStore
    private let store: ClipboardStore
    private let reader: ClipboardReader
    private let monitor: ClipboardMonitor
    private let pasteExecutor: PasteExecutor
    private let ocrService: ImageOCRService
    private let lanSync = LANSyncService()
    private let syncPayloadCache: SyncPayloadCache
    private var cancellables = Set<AnyCancellable>()
    private var started = false
    private var pasteTargetApplication: NSRunningApplication?
    private var queuedOCRHashes = Set<String>()
    private var shouldResetFloatingSelectionAfterLoad = false
    private var queuedFloatingPreviewIDs = Set<ClipboardEntry.ID>()
    private static let previewableImageExtensions: Set<String> = [
        "avif", "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp"
    ]
    private static let previewableVideoExtensions: Set<String> = [
        "avi", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "webm"
    ]

    var filteredEntries: [ClipboardEntry] {
        entries.filter { filter.includes($0) }
    }

    var floatingEntries: [ClipboardEntry] {
        let trimmed = floatingQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Array(entries.prefix(8))
        }

        let needle = trimmed.lowercased()
        return Array(
            entries
                .filter { entry in
                    entry.preview.lowercased().contains(needle)
                    || entry.ocrText?.lowercased().contains(needle) == true
                    || entry.sourceApp?.lowercased().contains(needle) == true
                    || entry.type.displayName.lowercased().contains(needle)
                }
                .prefix(8)
        )
    }

    var selectedEntry: ClipboardEntry? {
        if let selectedID, let entry = entries.first(where: { $0.id == selectedID }) {
            return entry
        }
        return entries.first
    }

    init() {
        do {
            let payloadStore = try PayloadStore()
            let store = try ClipboardStore()
            let deviceID = DeviceIdentity.current()
            self.payloadStore = payloadStore
            self.store = store
            self.deviceID = deviceID
            self.reader = ClipboardReader(payloadStore: payloadStore)
            self.monitor = ClipboardMonitor(reader: reader, deviceID: deviceID)
            self.pasteExecutor = PasteExecutor(payloadStore: payloadStore)
            self.ocrService = ImageOCRService()
            self.syncPayloadCache = SyncPayloadCache(payloadStore: payloadStore)
        } catch {
            fatalError("Failed to initialize ClipLAN: \(error.localizedDescription)")
        }

        Task { @MainActor [weak self] in
            self?.start()
        }
        FloatingPanelController.shared.bind(model: self)
    }

    func start() {
        guard !started else {
            return
        }
        started = true

        monitor.onCapture = { [weak self] entry in
            Task { @MainActor in
                await self?.recordLocal(entry)
            }
        }
        monitor.onSkip = { [weak self] message in
            self?.statusMessage = message
        }

        lanSync.onReceivedEntry = { [weak self] received in
            Task { @MainActor in
                await self?.recordRemote(received)
            }
        }
        lanSync.payloadProvider = { [weak self] contentHash in
            self?.syncPayloadCache.providedPayload(for: contentHash)
        }

        lanSync.$peers
            .receive(on: RunLoop.main)
            .sink { [weak self] peers in self?.peers = peers }
            .store(in: &cancellables)

        lanSync.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] status in self?.syncStatus = status }
            .store(in: &cancellables)

        refresh()
        restartServices()
    }

    func restartServices() {
        let settings = PasteRuntimeSettings.current()
        monitor.start(maxBytes: settings.maxEntryBytes)
        lanSync.start(
            configuration: LANSyncConfiguration(
                isEnabled: settings.syncEnabled,
                isDiscoverable: settings.syncDiscoverable,
                deviceID: deviceID,
                deviceName: settings.deviceName,
                pairingCode: settings.syncPairingCode
            )
        )
    }

    func refresh() {
        Task { @MainActor in
            await loadEntries()
        }
    }

    func paste(_ entry: ClipboardEntry?) {
        guard let entry else {
            return
        }

        if entry.needsPayload {
            statusMessage = "Requesting payload from LAN peer..."
            lanSync.requestPayload(contentHash: entry.contentHash, from: entry.remoteDeviceID)
            return
        }

        let settings = PasteRuntimeSettings.current()
        let canAutoPaste = !settings.autoPaste || PasteExecutor.accessibilityTrusted(prompt: settings.autoPaste)

        do {
            let targetApplication = pasteTargetApplication
            if settings.autoPaste && canAutoPaste && targetApplication != nil {
                closeMainWindows()
            }
            try pasteExecutor.paste(
                entry,
                autoPaste: settings.autoPaste && canAutoPaste,
                targetApplication: targetApplication
            )
            statusMessage = settings.autoPaste && canAutoPaste ? "Pasted" : "Copied to clipboard"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func prepareForHotKeyActivation() {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            pasteTargetApplication = frontmost
        }

        floatingQuery = ""
        resetFloatingSelection()
        shouldResetFloatingSelectionAfterLoad = true
    }

    func selectPreviousEntry() {
        moveSelection(delta: -1)
    }

    func selectNextEntry() {
        moveSelection(delta: 1)
    }

    func selectPreviousFloatingEntry() {
        moveSelection(delta: -1, entries: floatingEntries)
    }

    func selectNextFloatingEntry() {
        moveSelection(delta: 1, entries: floatingEntries)
    }

    func togglePinned(_ entry: ClipboardEntry) {
        Task { @MainActor in
            do {
                try await store.setPinned(id: entry.id, isPinned: !entry.isPinned)
                await loadEntries()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func toggleFavorite(_ entry: ClipboardEntry) {
        Task { @MainActor in
            do {
                try await store.setFavorite(id: entry.id, isFavorite: !entry.isFavorite)
                await loadEntries()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func delete(_ entry: ClipboardEntry) {
        Task { @MainActor in
            do {
                if let payloadPath = try await store.deleteEntry(id: entry.id) {
                    payloadStore.deletePayload(relativePath: payloadPath)
                }
                await loadEntries()
            } catch {
                statusMessage = error.localizedDescription
            }
        }
    }

    func send(_ entry: ClipboardEntry, to peer: PeerDevice) {
        do {
            let payload = try payloadData(for: entry)
            lanSync.broadcast(entry: entry, payload: payload, activate: true, to: peer.id)
            statusMessage = "Sent to \(peer.name)"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    func requestPayload(_ entry: ClipboardEntry) {
        lanSync.requestPayload(contentHash: entry.contentHash, from: entry.remoteDeviceID)
        statusMessage = "Requesting payload from LAN peer..."
    }

    func fullText(for entry: ClipboardEntry) -> String {
        guard let data = try? payloadData(for: entry) else {
            return entry.preview
        }
        return String(data: data, encoding: .utf8) ?? entry.preview
    }

    func image(for entry: ClipboardEntry) -> NSImage? {
        guard entry.type == .image, let data = try? payloadData(for: entry) else {
            return nil
        }
        return NSImage(data: data)
    }

    func fileURLs(for entry: ClipboardEntry) -> [URL] {
        guard entry.type == .file else {
            return []
        }
        return fullText(for: entry)
            .split(separator: "\n")
            .compactMap { URL(string: String($0)) }
    }

    func mediaPreviewURL(for entry: ClipboardEntry) -> URL? {
        fileURLs(for: entry).first { url in
            Self.isPreviewableMediaURL(url)
        }
    }

    func isVideoPreviewURL(_ url: URL) -> Bool {
        Self.previewableVideoExtensions.contains(url.pathExtension.lowercased())
    }

    func floatingMediaPreview(for entry: ClipboardEntry) -> FloatingMediaPreview? {
        floatingMediaPreviews[entry.id]
    }

    func loadFloatingMediaPreview(for entry: ClipboardEntry) async {
        guard floatingMediaPreviews[entry.id] == nil, !queuedFloatingPreviewIDs.contains(entry.id) else {
            return
        }

        queuedFloatingPreviewIDs.insert(entry.id)
        defer {
            queuedFloatingPreviewIDs.remove(entry.id)
        }

        if entry.type == .image {
            guard let image = image(for: entry) else {
                return
            }
            floatingMediaPreviews[entry.id] = FloatingMediaPreview(image: image, kind: .clipboardImage)
            return
        }

        guard entry.type == .file, let url = mediaPreviewURL(for: entry) else {
            return
        }

        let kind: FloatingMediaKind = isVideoPreviewURL(url) ? .fileVideo : .fileImage
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = await FloatingMediaThumbnailer.shared.thumbnail(
            for: url,
            size: CGSize(width: 276, height: 228),
            scale: scale
        ) else {
            return
        }

        guard !Task.isCancelled else {
            return
        }
        floatingMediaPreviews[entry.id] = FloatingMediaPreview(image: image, kind: kind)
    }

    private func recordLocal(_ entry: ClipboardEntry) async {
        do {
            let mutation = try await store.upsert(entry, maxEntries: PasteRuntimeSettings.current().maxEntries)
            await loadEntries()
            scheduleOCRIfNeeded(for: mutation.entry)

            if let payload = try? payloadData(for: mutation.entry) {
                lanSync.broadcast(entry: mutation.entry, payload: payload)
            }
            statusMessage = mutation.inserted ? "Captured \(entry.type.displayName)" : "Updated existing item"
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func recordRemote(_ received: ReceivedClipboardEntry) async {
        do {
            var entry = received.entry
            if let payloadData = received.payloadData {
                let payloadPath = try payloadStore.savePayload(
                    data: payloadData,
                    hash: entry.contentHash,
                    type: entry.type
                )
                entry.payloadPath = payloadPath
                entry.byteSize = payloadData.count
            }

            let mutation = try await store.upsert(entry, maxEntries: PasteRuntimeSettings.current().maxEntries)
            await loadEntries()
            scheduleOCRIfNeeded(for: mutation.entry)

            if received.activate {
                if mutation.entry.needsPayload {
                    lanSync.requestPayload(contentHash: mutation.entry.contentHash, from: mutation.entry.remoteDeviceID)
                } else {
                    try pasteExecutor.copyToPasteboard(mutation.entry)
                    statusMessage = "Received from LAN"
                }
            }
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func loadEntries() async {
        do {
            let loaded = try await store.fetchEntries(query: query, limit: 200)
            entries = loaded
            if shouldResetFloatingSelectionAfterLoad {
                shouldResetFloatingSelectionAfterLoad = false
                resetFloatingSelection()
            } else if selectedID == nil || !loaded.contains(where: { $0.id == selectedID }) {
                selectedID = filteredEntries.first?.id
            }
            pruneFloatingMediaPreviews(validEntryIDs: Set(loaded.map(\.id)))
            updatePayloadCache(loaded)
            scheduleVisibleOCRIfNeeded(loaded)
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func payloadData(for entry: ClipboardEntry) throws -> Data? {
        guard let payloadPath = entry.payloadPath else {
            return nil
        }
        return try payloadStore.loadPayload(relativePath: payloadPath)
    }

    private func updatePayloadCache(_ entries: [ClipboardEntry]) {
        syncPayloadCache.update(entries)
    }

    private func resetFloatingSelection() {
        selectedID = floatingEntries.first?.id
    }

    private func pruneFloatingMediaPreviews(validEntryIDs: Set<ClipboardEntry.ID>) {
        floatingMediaPreviews = floatingMediaPreviews.filter { validEntryIDs.contains($0.key) }
        queuedFloatingPreviewIDs = queuedFloatingPreviewIDs.filter { validEntryIDs.contains($0) }
    }

    private func scheduleVisibleOCRIfNeeded(_ entries: [ClipboardEntry]) {
        for entry in entries.prefix(12) where entry.type == .image {
            scheduleOCRIfNeeded(for: entry)
        }
    }

    private func scheduleOCRIfNeeded(for entry: ClipboardEntry) {
        guard
            entry.type == .image,
            entry.ocrText?.isEmpty ?? true,
            let payloadPath = entry.payloadPath,
            !queuedOCRHashes.contains(entry.contentHash)
        else {
            return
        }

        queuedOCRHashes.insert(entry.contentHash)
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let data = try self.payloadStore.loadPayload(relativePath: payloadPath)
                let recognizedText = try await self.ocrService.recognizeText(in: data)
                guard !recognizedText.isEmpty else {
                    return
                }

                _ = try await self.store.updateOCRText(contentHash: entry.contentHash, ocrText: recognizedText)
                await self.loadEntries()
                self.statusMessage = "Image OCR indexed"
            } catch {
                self.statusMessage = "Image OCR skipped: \(error.localizedDescription)"
            }
        }
    }

    private func moveSelection(delta: Int, entries: [ClipboardEntry]? = nil) {
        let visibleEntries = entries ?? filteredEntries
        guard !visibleEntries.isEmpty else {
            selectedID = nil
            return
        }

        guard
            let currentID = selectedID,
            let index = visibleEntries.firstIndex(where: { $0.id == currentID })
        else {
            selectedID = visibleEntries.first?.id
            return
        }

        let nextIndex = (index + delta + visibleEntries.count) % visibleEntries.count
        selectedID = visibleEntries[nextIndex].id
    }

    private func closeMainWindows() {
        for window in NSApp.windows where window.title == "ClipLAN" {
            window.orderOut(nil)
        }
    }

    private static func isPreviewableMediaURL(_ url: URL) -> Bool {
        guard url.isFileURL else {
            return false
        }

        let pathExtension = url.pathExtension.lowercased()
        return previewableImageExtensions.contains(pathExtension) || previewableVideoExtensions.contains(pathExtension)
    }
}
