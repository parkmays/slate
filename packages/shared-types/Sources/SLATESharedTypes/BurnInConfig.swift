// SLATE — Proxy burn-in settings (persisted on WatchFolder)
// Core Image rendering consumes these RGBA components in IngestDaemon.

import Foundation

public enum BurnInPosition: String, Codable, Sendable, CaseIterable {
    case topLeft
    case topCenter
    case bottomLeft
    case bottomCenter
}

/// Per-project proxy burn-in (off by default). Colors are linear RGBA 0…1 for Codable persistence.
public struct BurnInConfig: Codable, Sendable, Equatable {
    public var enabled: Bool
    public var position: BurnInPosition
    public var fontSize: Double
    public var textColorRed: Double
    public var textColorGreen: Double
    public var textColorBlue: Double
    public var textColorAlpha: Double
    public var backgroundColorRed: Double
    public var backgroundColorGreen: Double
    public var backgroundColorBlue: Double
    public var backgroundColorAlpha: Double

    public init(
        enabled: Bool = false,
        position: BurnInPosition = .bottomCenter,
        fontSize: Double = 28,
        textColorRed: Double = 1,
        textColorGreen: Double = 1,
        textColorBlue: Double = 1,
        textColorAlpha: Double = 1,
        backgroundColorRed: Double = 0,
        backgroundColorGreen: Double = 0,
        backgroundColorBlue: Double = 0,
        backgroundColorAlpha: Double = 0.55
    ) {
        self.enabled = enabled
        self.position = position
        self.fontSize = fontSize
        self.textColorRed = textColorRed
        self.textColorGreen = textColorGreen
        self.textColorBlue = textColorBlue
        self.textColorAlpha = textColorAlpha
        self.backgroundColorRed = backgroundColorRed
        self.backgroundColorGreen = backgroundColorGreen
        self.backgroundColorBlue = backgroundColorBlue
        self.backgroundColorAlpha = backgroundColorAlpha
    }
}
