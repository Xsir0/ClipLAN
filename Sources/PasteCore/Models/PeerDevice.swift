import Foundation

public struct PeerDevice: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var ipAddress: String?
    public var port: UInt16?
    public var serviceName: String?
    public var serviceType: String?
    public var serviceDomain: String?
    public var interfaceName: String?
    public var endpointDescription: String?
    public var lastSeenAt: Date
    public var isConnected: Bool

    public init(
        id: String,
        name: String,
        ipAddress: String? = nil,
        port: UInt16? = nil,
        serviceName: String? = nil,
        serviceType: String? = nil,
        serviceDomain: String? = nil,
        interfaceName: String? = nil,
        endpointDescription: String? = nil,
        lastSeenAt: Date = Date(),
        isConnected: Bool = true
    ) {
        self.id = id
        self.name = name
        self.ipAddress = ipAddress
        self.port = port
        self.serviceName = serviceName
        self.serviceType = serviceType
        self.serviceDomain = serviceDomain
        self.interfaceName = interfaceName
        self.endpointDescription = endpointDescription
        self.lastSeenAt = lastSeenAt
        self.isConnected = isConnected
    }

    public var shortID: String {
        String(id.prefix(8))
    }

    public var addressDisplay: String {
        if let ipAddress, let port {
            return "\(ipAddress):\(port)"
        }
        if let ipAddress {
            return ipAddress
        }
        if let serviceName {
            let domain: String
            if let serviceDomain, !serviceDomain.isEmpty {
                domain = serviceDomain
            } else {
                domain = "local."
            }
            return "\(serviceName).\(domain)"
        }
        return endpointDescription ?? "Resolving"
    }

    public var serviceDisplay: String {
        guard let serviceName else {
            return "Direct connection"
        }
        let type = serviceType ?? "_cliplan._tcp"
        return "\(serviceName) \(type)"
    }
}
