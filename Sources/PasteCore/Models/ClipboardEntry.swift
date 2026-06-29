import Foundation

public struct ClipboardEntry: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: String
    public var deviceID: String
    public var contentHash: String
    public var type: ClipboardContentType
    public var preview: String
    public var ocrText: String?
    public var sourceApp: String?
    public var payloadPath: String?
    public var byteSize: Int
    public var createdAt: Date
    public var updatedAt: Date
    public var isFavorite: Bool
    public var isPinned: Bool
    public var isRemote: Bool
    public var remoteDeviceID: String?

    public init(
        id: String = UUID().uuidString,
        deviceID: String,
        contentHash: String,
        type: ClipboardContentType,
        preview: String,
        ocrText: String? = nil,
        sourceApp: String?,
        payloadPath: String?,
        byteSize: Int,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isFavorite: Bool = false,
        isPinned: Bool = false,
        isRemote: Bool = false,
        remoteDeviceID: String? = nil
    ) {
        self.id = id
        self.deviceID = deviceID
        self.contentHash = contentHash
        self.type = type
        self.preview = preview
        self.ocrText = ocrText
        self.sourceApp = sourceApp
        self.payloadPath = payloadPath
        self.byteSize = byteSize
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isFavorite = isFavorite
        self.isPinned = isPinned
        self.isRemote = isRemote
        self.remoteDeviceID = remoteDeviceID
    }

    public var needsPayload: Bool {
        payloadPath == nil
    }
}
