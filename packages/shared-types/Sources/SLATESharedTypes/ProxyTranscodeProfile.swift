import Foundation

public struct ProxyTranscodeProfile: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var scaleDivisor: Int
    public var codec: String
    public var bitrateBps: Int
    public var watermarkOpacity: Double

    public init(
        id: String = UUID().uuidString,
        name: String,
        scaleDivisor: Int,
        codec: String = "h264",
        bitrateBps: Int,
        watermarkOpacity: Double
    ) {
        self.id = id
        self.name = name
        self.scaleDivisor = max(1, scaleDivisor)
        self.codec = codec
        self.bitrateBps = max(500_000, bitrateBps)
        self.watermarkOpacity = min(max(0, watermarkOpacity), 1)
    }

    public static let slateDefault = ProxyTranscodeProfile(
        id: "default",
        name: "SLATE Default",
        scaleDivisor: 4,
        codec: "h264",
        bitrateBps: 8_000_000,
        watermarkOpacity: 0.85
    )
}
