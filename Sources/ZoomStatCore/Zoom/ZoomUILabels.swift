import Foundation

/// Every Zoom-version / Zoom-language dependent string lives here.
/// Verified against Zoom Workplace 6.5.7 (60598), English UI.
/// If a Zoom update renames something, this is the only file that should change.
public struct ZoomUILabels: Sendable {
    public var bundleIdentifier = "us.zoom.xos"

    // Windows
    public var settingsWindowTitle = "Settings"
    public var meetingWindowTitles = ["Zoom Meeting", "Zoom Webinar"]
    public var settingsMenuItemPrefixes = ["Settings", "Preferences"]

    // Settings sidebar
    public var categoryListDescription = "Category List"
    public var statisticsCategory = "Statistics"

    // Statistics tabs (AX role "Tab", matched by title prefix)
    public var tabRole = "Tab"
    public var tabOverall = "Overall"
    public var tabAudio = "Audio"
    public var tabVideo = "Video"
    public var tabScreenShare = "Screen sharing"
    public var selectedSuffix = ", Selected"

    // Overall tab
    public var cpu = "CPU"
    public var memory = "Memory"
    public var zoomRow = "Zoom"
    public var overallRow = "Overall"
    public var bandwidth = "Bandwidth:"
    public var networkType = "Network type:"
    public var proxy = "Proxy:"
    public var connectionType = "Connection type:"
    public var dataCenter = "Data Center:"
    public var encryption = "Encryption:"
    public var version = "Version"

    // Media tabs (label followed by Send, Receive cells)
    public var mediaHeader = "Item name"
    public var frequency = "Frequency"
    public var latency = "Latency"
    public var jitter = "Jitter"
    public var packetLoss = "Packet loss"   // prefix of "Packet loss - average(max)"
    public var resolution = "Resolution"
    public var fps = "Frames per second"
    public var bitrate = "Bitrate"          // not present in 6.5.7; parsed if it appears

    /// Text Zoom shows for "no value".
    public var emptyValues: Set<String> = ["--", "-", ""]

    public init() {}
    public static let english = ZoomUILabels()
}
