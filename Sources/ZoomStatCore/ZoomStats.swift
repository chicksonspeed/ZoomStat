import Foundation

/// Send/receive statistics for one media type (audio, video, screen sharing).
/// Every value is optional: nil means "not reported / unavailable", never zero.
public struct MediaStats: Codable, Equatable, Sendable {
    public var frequencySend: Double?        // kHz (audio only)
    public var frequencyReceive: Double?     // kHz (audio only)
    public var latencySend: Double?          // ms
    public var latencyReceive: Double?       // ms
    public var jitterSend: Double?           // ms
    public var jitterReceive: Double?        // ms
    public var packetLossSendAverage: Double?     // %
    public var packetLossSendMax: Double?         // %
    public var packetLossReceiveAverage: Double?  // %
    public var packetLossReceiveMax: Double?      // %
    public var sendWidth: Int?
    public var sendHeight: Int?
    public var receiveWidth: Int?
    public var receiveHeight: Int?
    public var fpsSend: Double?
    public var fpsReceive: Double?
    public var bitrateSend: Double?          // kb/s — not exposed by Zoom 6.5
    public var bitrateReceive: Double?       // kb/s — not exposed by Zoom 6.5

    public init() {}

    /// Largest of the send/receive averages (what the UI calls "Packet Loss").
    public var packetLossAverage: Double? { maxOf(packetLossSendAverage, packetLossReceiveAverage) }
    public var packetLossMax: Double? { maxOf(packetLossSendMax, packetLossReceiveMax) }

    public var hasAnyValue: Bool {
        [latencySend, latencyReceive, jitterSend, jitterReceive, packetLossSendAverage,
         packetLossReceiveAverage, fpsSend, fpsReceive, frequencySend, frequencyReceive]
            .contains { $0 != nil } || sendWidth != nil || receiveWidth != nil
    }
}

func maxOf(_ a: Double?, _ b: Double?) -> Double? {
    switch (a, b) {
    case let (x?, y?): return max(x, y)
    case let (x?, nil): return x
    case let (nil, y?): return y
    default: return nil
    }
}

public struct ZoomStats: Codable, Equatable, Sendable {
    public var timestamp: Date = Date()

    public var zoomRunning = false
    public var meetingActive = false
    /// True when the values came from Zoom's own Statistics panel.
    public var statisticsWindowAvailable = false
    /// False when ZoomStat lacks Accessibility permission.
    public var accessibilityGranted = true

    public var cpuZoom: Double?          // % of whole machine
    public var cpuSystem: Double?        // %
    public var memoryZoom: UInt64?       // bytes
    public var memorySystem: UInt64?     // bytes used
    public var memoryTotal: UInt64?      // bytes

    public var bandwidthSend: Double?    // kb/s
    public var bandwidthReceive: Double? // kb/s

    public var audio = MediaStats()
    public var video = MediaStats()
    public var screenShare = MediaStats()

    public var dataCenter: String?        // e.g. "AMS"
    public var dataCenterDetail: String?  // e.g. "Netherlands"
    public var networkType: String?
    public var connectionType: String?
    public var proxy: String?
    public var encryption: String?
    public var zoomVersion: String?

    public init() {}

    public static let unavailable = ZoomStats()
}
