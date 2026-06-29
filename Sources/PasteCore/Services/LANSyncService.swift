import Combine
import Darwin
import Foundation
import Network

public struct LANSyncConfiguration: Sendable {
    public var isEnabled: Bool
    public var isDiscoverable: Bool
    public var deviceID: String
    public var deviceName: String
    public var pairingCode: String
    public var maxInlinePayloadBytes: Int

    public init(
        isEnabled: Bool,
        isDiscoverable: Bool = true,
        deviceID: String,
        deviceName: String,
        pairingCode: String,
        maxInlinePayloadBytes: Int = 2 * 1024 * 1024
    ) {
        self.isEnabled = isEnabled
        self.isDiscoverable = isDiscoverable
        self.deviceID = deviceID
        self.deviceName = deviceName
        self.pairingCode = pairingCode
        self.maxInlinePayloadBytes = maxInlinePayloadBytes
    }

    var keyHash: String {
        let seed = pairingCode.trimmingCharacters(in: .whitespacesAndNewlines)
        return ContentHasher.sha256Hex(seed.isEmpty ? "local-paste-default-lan" : seed)
    }
}

public struct ReceivedClipboardEntry: Sendable {
    public var entry: ClipboardEntry
    public var payloadData: Data?
    public var activate: Bool

    public init(entry: ClipboardEntry, payloadData: Data?, activate: Bool) {
        self.entry = entry
        self.payloadData = payloadData
        self.activate = activate
    }
}

public struct ProvidedSyncPayload: Sendable {
    public var entry: ClipboardEntry
    public var data: Data

    public init(entry: ClipboardEntry, data: Data) {
        self.entry = entry
        self.data = data
    }
}

public final class LANSyncService: ObservableObject {
    @Published public private(set) var peers: [PeerDevice] = []
    @Published public private(set) var status: String = "LAN sync stopped"

    public var onReceivedEntry: ((ReceivedClipboardEntry) -> Void)?
    public var payloadProvider: ((String) -> ProvidedSyncPayload?)?

    private let serviceType = "_cliplan._tcp"
    private let queue = DispatchQueue(label: "app.cliplan.lan-sync", qos: .utility)
    private var configuration: LANSyncConfiguration?
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connections: [UUID: PeerConnection] = [:]
    private var connectingEndpoints: Set<String> = []
    private var resolvers: [UUID: BonjourServiceResolver] = [:]

    public init() {}

    public func start(configuration: LANSyncConfiguration) {
        queue.async { [self] in
            self.stopLocked()
            self.configuration = configuration

            guard configuration.isEnabled else {
                self.publishStatus("LAN sync disabled")
                return
            }

            do {
                if configuration.isDiscoverable {
                    let listener = try NWListener(using: .tcp)
                    listener.service = NWListener.Service(
                        name: configuration.deviceName,
                        type: self.serviceType
                    )
                    listener.newConnectionHandler = { [weak self] connection in
                        self?.queue.async {
                            self?.setup(connection: connection, endpointKey: nil)
                        }
                    }
                    listener.stateUpdateHandler = { [weak self] state in
                        self?.handleListenerState(state)
                    }
                    listener.start(queue: self.queue)
                    self.listener = listener
                }

                let browser = NWBrowser(
                    for: .bonjour(type: self.serviceType, domain: nil),
                    using: .tcp
                )
                browser.browseResultsChangedHandler = { [weak self] results, _ in
                    self?.queue.async {
                        self?.connect(to: results)
                    }
                }
                browser.start(queue: self.queue)
                self.browser = browser

                self.publishStatus(configuration.isDiscoverable ? "LAN sync listening" : "LAN sync hidden")
            } catch {
                self.publishStatus("LAN sync failed: \(error.localizedDescription)")
            }
        }
    }

    public func stop() {
        queue.async {
            self.stopLocked()
            self.publishStatus("LAN sync stopped")
        }
    }

    public func broadcast(entry: ClipboardEntry, payload: Data?, activate: Bool = false, to peerID: String? = nil) {
        queue.async {
            guard let configuration = self.configuration, configuration.isEnabled else {
                return
            }

            let payloadForMessage: Data?
            if let payload, payload.count <= configuration.maxInlinePayloadBytes {
                payloadForMessage = payload
            } else {
                payloadForMessage = nil
            }

            let envelope = self.envelope(
                kind: activate ? .push : .entry,
                entry: entry,
                payload: payloadForMessage,
                activate: activate
            )

            for peer in self.readyPeers(peerID: peerID) {
                self.send(envelope, to: peer)
            }
        }
    }

    public func requestPayload(contentHash: String, from peerID: String? = nil) {
        queue.async {
            let envelope = self.envelope(kind: .requestPayload, requestHash: contentHash)
            for peer in self.readyPeers(peerID: peerID) {
                self.send(envelope, to: peer)
            }
        }
    }

    private func stopLocked() {
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
        resolvers.values.forEach { $0.cancel() }
        resolvers.removeAll()
        connections.values.forEach { $0.connection.cancel() }
        connections.removeAll()
        connectingEndpoints.removeAll()
        publishPeers()
    }

    private func handleListenerState(_ state: NWListener.State) {
        switch state {
        case .ready:
            publishStatus("LAN sync ready")
        case .failed(let error):
            publishStatus("LAN listener failed: \(error.localizedDescription)")
        case .cancelled:
            publishStatus("LAN sync stopped")
        default:
            break
        }
    }

    private func connect(to results: Set<NWBrowser.Result>) {
        for result in results {
            let key = result.endpoint.debugDescription
            guard !connectingEndpoints.contains(key) else {
                continue
            }

            connectingEndpoints.insert(key)
            let connection = NWConnection(to: result.endpoint, using: .tcp)
            setup(connection: connection, endpointKey: key)
        }
    }

    private func setup(connection: NWConnection, endpointKey: String?) {
        let peer = PeerConnection(
            connection: connection,
            endpointKey: endpointKey,
            endpointInfo: Self.endpointInfo(for: connection.endpoint)
        )
        connections[peer.id] = peer

        connection.stateUpdateHandler = { [weak self, weak peer] state in
            guard let self, let peer else {
                return
            }
            self.queue.async {
                self.handleConnectionState(state, peer: peer)
            }
        }

        connection.start(queue: queue)
        startEndpointResolutionIfNeeded(for: peer)
        receive(on: peer)
    }

    private func handleConnectionState(_ state: NWConnection.State, peer: PeerConnection) {
        switch state {
        case .ready:
            send(envelope(kind: .hello), to: peer)
        case .failed, .cancelled:
            remove(peer)
        default:
            break
        }
    }

    private func receive(on peer: PeerConnection) {
        peer.connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self, weak peer] data, _, isComplete, error in
            guard let self, let peer else {
                return
            }

            self.queue.async {
                if let data, !data.isEmpty {
                    peer.buffer.append(data)
                    self.processBuffer(for: peer)
                }

                if error != nil || isComplete {
                    self.remove(peer)
                } else {
                    self.receive(on: peer)
                }
            }
        }
    }

    private func processBuffer(for peer: PeerConnection) {
        while let newline = peer.buffer.firstIndex(of: 0x0A) {
            let line = peer.buffer[..<newline]
            peer.buffer.removeSubrange(...newline)

            guard !line.isEmpty else {
                continue
            }

            do {
                let envelope = try SyncCoders.decoder.decode(SyncEnvelope.self, from: Data(line))
                handle(envelope, from: peer)
            } catch {
                publishStatus("LAN decode error: \(error.localizedDescription)")
            }
        }
    }

    private func handle(_ envelope: SyncEnvelope, from peer: PeerConnection) {
        guard let configuration else {
            return
        }

        guard envelope.keyHash == configuration.keyHash else {
            peer.connection.cancel()
            remove(peer)
            return
        }

        if envelope.deviceID == configuration.deviceID {
            peer.connection.cancel()
            remove(peer)
            return
        }

        switch envelope.kind {
        case .hello:
            peer.peer = PeerDevice(
                id: envelope.deviceID,
                name: envelope.deviceName,
                ipAddress: peer.endpointInfo.ipAddress,
                port: peer.endpointInfo.port,
                serviceName: peer.endpointInfo.serviceName,
                serviceType: peer.endpointInfo.serviceType,
                serviceDomain: peer.endpointInfo.serviceDomain,
                interfaceName: peer.endpointInfo.interfaceName,
                endpointDescription: peer.endpointInfo.endpointDescription,
                lastSeenAt: Date(),
                isConnected: true
            )
            publishPeers()
        case .entry, .push, .payload:
            updateLastSeen(for: peer)
            guard var entry = envelope.entry else {
                return
            }

            entry.isRemote = true
            entry.remoteDeviceID = envelope.deviceID
            entry.payloadPath = nil

            let payload = envelope.payloadBase64.flatMap { Data(base64Encoded: $0) }
            let received = ReceivedClipboardEntry(
                entry: entry,
                payloadData: payload,
                activate: envelope.activate ?? (envelope.kind == .push)
            )
            DispatchQueue.main.async {
                self.onReceivedEntry?(received)
            }
        case .requestPayload:
            updateLastSeen(for: peer)
            guard
                let requestHash = envelope.requestHash,
                let provided = payloadProvider?(requestHash)
            else {
                return
            }
            send(
                self.envelope(kind: .payload, entry: provided.entry, payload: provided.data, activate: false),
                to: peer
            )
        }
    }

    private func send(_ envelope: SyncEnvelope, to peer: PeerConnection) {
        do {
            var data = try SyncCoders.encoder.encode(envelope)
            data.append(0x0A)
            peer.connection.send(content: data, completion: .contentProcessed { [weak self] error in
                if let error {
                    self?.publishStatus("LAN send failed: \(error.localizedDescription)")
                }
            })
        } catch {
            publishStatus("LAN encode error: \(error.localizedDescription)")
        }
    }

    private func readyPeers(peerID: String?) -> [PeerConnection] {
        connections.values.filter { peer in
            guard let knownPeer = peer.peer else {
                return false
            }
            if let peerID {
                return knownPeer.id == peerID
            }
            return true
        }
    }

    private func remove(_ peer: PeerConnection) {
        connections[peer.id] = nil
        resolvers.removeValue(forKey: peer.id)?.cancel()
        if let endpointKey = peer.endpointKey {
            connectingEndpoints.remove(endpointKey)
        }
        publishPeers()
    }

    private func updateLastSeen(for peer: PeerConnection) {
        guard var knownPeer = peer.peer else {
            return
        }

        knownPeer.lastSeenAt = Date()
        knownPeer.isConnected = true
        peer.peer = knownPeer
    }

    private func refreshPeerEndpointDetails(for peer: PeerConnection) {
        guard var knownPeer = peer.peer else {
            return
        }

        knownPeer.ipAddress = peer.endpointInfo.ipAddress
        knownPeer.port = peer.endpointInfo.port
        knownPeer.serviceName = peer.endpointInfo.serviceName
        knownPeer.serviceType = peer.endpointInfo.serviceType
        knownPeer.serviceDomain = peer.endpointInfo.serviceDomain
        knownPeer.interfaceName = peer.endpointInfo.interfaceName
        knownPeer.endpointDescription = peer.endpointInfo.endpointDescription
        peer.peer = knownPeer
    }

    private func publishPeers() {
        let peers = connections.values
            .compactMap(\.peer)
            .reduce(into: [String: PeerDevice]()) { partial, peer in
                partial[peer.id] = peer
            }
            .values
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        DispatchQueue.main.async {
            self.peers = peers
        }
    }

    private func publishStatus(_ status: String) {
        DispatchQueue.main.async {
            self.status = status
        }
    }

    private func startEndpointResolutionIfNeeded(for peer: PeerConnection) {
        guard case let .service(name, type, domain, interface) = peer.connection.endpoint else {
            return
        }

        peer.endpointInfo.serviceName = name
        peer.endpointInfo.serviceType = type
        peer.endpointInfo.serviceDomain = domain
        peer.endpointInfo.interfaceName = interface?.name

        let peerID = peer.id
        let resolver = BonjourServiceResolver(
            name: name,
            type: type,
            domain: domain,
            fallbackInfo: peer.endpointInfo
        ) { [weak self] resolvedInfo in
            guard let self else {
                return
            }

            self.queue.async {
                self.resolvers.removeValue(forKey: peerID)

                guard let resolvedInfo, let peer = self.connections[peerID] else {
                    return
                }

                peer.endpointInfo.merge(resolvedInfo)
                self.refreshPeerEndpointDetails(for: peer)
                self.publishPeers()
            }
        }

        resolvers[peerID] = resolver
        resolver.start()
    }

    private static func endpointInfo(for endpoint: NWEndpoint) -> PeerEndpointInfo {
        var info = PeerEndpointInfo(endpointDescription: endpoint.debugDescription)

        switch endpoint {
        case let .hostPort(host, port):
            info.ipAddress = String(describing: host)
            info.port = port.rawValue
        case let .service(name, type, domain, interface):
            info.serviceName = name
            info.serviceType = type
            info.serviceDomain = domain
            info.interfaceName = interface?.name
        case let .url(url):
            info.endpointDescription = url.absoluteString
            info.ipAddress = url.host
            if let port = url.port {
                info.port = UInt16(port)
            }
        case let .unix(path):
            info.endpointDescription = path
        case let .opaque(value):
            info.endpointDescription = String(describing: value)
        @unknown default:
            break
        }

        return info
    }

    private func envelope(
        kind: SyncMessageKind,
        entry: ClipboardEntry? = nil,
        payload: Data? = nil,
        activate: Bool = false,
        requestHash: String? = nil
    ) -> SyncEnvelope {
        let configuration = configuration
        return SyncEnvelope(
            kind: kind,
            deviceID: configuration?.deviceID ?? "",
            deviceName: configuration?.deviceName ?? Host.current().localizedName ?? "Mac",
            keyHash: configuration?.keyHash ?? "",
            entry: entry,
            payloadBase64: payload?.base64EncodedString(),
            activate: activate,
            requestHash: requestHash,
            sentAt: Date()
        )
    }
}

private final class PeerConnection {
    let id = UUID()
    let connection: NWConnection
    let endpointKey: String?
    var endpointInfo: PeerEndpointInfo
    var buffer = Data()
    var peer: PeerDevice?

    init(connection: NWConnection, endpointKey: String?, endpointInfo: PeerEndpointInfo) {
        self.connection = connection
        self.endpointKey = endpointKey
        self.endpointInfo = endpointInfo
    }
}

private struct PeerEndpointInfo {
    var ipAddress: String?
    var port: UInt16?
    var serviceName: String?
    var serviceType: String?
    var serviceDomain: String?
    var interfaceName: String?
    var endpointDescription: String?

    mutating func merge(_ other: PeerEndpointInfo) {
        ipAddress = other.ipAddress ?? ipAddress
        port = other.port ?? port
        serviceName = other.serviceName ?? serviceName
        serviceType = other.serviceType ?? serviceType
        serviceDomain = other.serviceDomain ?? serviceDomain
        interfaceName = other.interfaceName ?? interfaceName
        endpointDescription = other.endpointDescription ?? endpointDescription
    }
}

private final class BonjourServiceResolver: NSObject, NetServiceDelegate {
    private let service: NetService
    private let fallbackInfo: PeerEndpointInfo
    private let completion: (PeerEndpointInfo?) -> Void
    private var didFinish = false

    init(
        name: String,
        type: String,
        domain: String,
        fallbackInfo: PeerEndpointInfo,
        completion: @escaping (PeerEndpointInfo?) -> Void
    ) {
        self.service = NetService(
            domain: domain.isEmpty ? "local." : domain,
            type: type.hasSuffix(".") ? type : "\(type).",
            name: name
        )
        self.fallbackInfo = fallbackInfo
        self.completion = completion
        super.init()
    }

    func start() {
        DispatchQueue.main.async { [weak self] in
            guard let self else {
                return
            }

            self.service.delegate = self
            self.service.schedule(in: .main, forMode: .common)
            self.service.resolve(withTimeout: 4)
        }
    }

    func cancel() {
        DispatchQueue.main.async { [weak self] in
            self?.cleanup()
        }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        var resolved = fallbackInfo
        if let bestAddress = Self.bestAddress(from: sender.addresses ?? []) {
            resolved.ipAddress = bestAddress.host
            resolved.port = bestAddress.port
        }
        resolved.serviceName = sender.name
        resolved.serviceType = sender.type
        resolved.serviceDomain = sender.domain
        finish(resolved)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        finish(nil)
    }

    private func finish(_ info: PeerEndpointInfo?) {
        guard !didFinish else {
            return
        }

        didFinish = true
        cleanup()
        completion(info)
    }

    private func cleanup() {
        service.stop()
        service.remove(from: .main, forMode: .common)
        service.delegate = nil
    }

    private static func bestAddress(from addresses: [Data]) -> (host: String, port: UInt16)? {
        let parsed = addresses.compactMap(address)
        return parsed.first { !$0.host.contains(":") } ?? parsed.first
    }

    private static func address(from data: Data) -> (host: String, port: UInt16)? {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return nil
            }

            let socketAddress = baseAddress.assumingMemoryBound(to: sockaddr.self)
            var hostBuffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            var portBuffer = [CChar](repeating: 0, count: Int(NI_MAXSERV))
            let result = getnameinfo(
                socketAddress,
                socklen_t(rawBuffer.count),
                &hostBuffer,
                socklen_t(hostBuffer.count),
                &portBuffer,
                socklen_t(portBuffer.count),
                NI_NUMERICHOST | NI_NUMERICSERV
            )

            guard result == 0, let port = UInt16(String(cString: portBuffer)) else {
                return nil
            }

            return (String(cString: hostBuffer), port)
        }
    }
}

private enum SyncMessageKind: String, Codable {
    case hello
    case entry
    case push
    case requestPayload
    case payload
}

private struct SyncEnvelope: Codable {
    var kind: SyncMessageKind
    var deviceID: String
    var deviceName: String
    var keyHash: String
    var entry: ClipboardEntry?
    var payloadBase64: String?
    var activate: Bool?
    var requestHash: String?
    var sentAt: Date
}
