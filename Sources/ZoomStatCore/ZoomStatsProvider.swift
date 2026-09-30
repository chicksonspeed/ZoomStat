import Foundation

public protocol ZoomStatsProvider: AnyObject {
    func start()
    func stop()
    var latestStats: ZoomStats { get }
    /// Called on the main queue whenever `latestStats` changes.
    var onUpdate: ((ZoomStats) -> Void)? { get set }
    /// Brings up Zoom's own Statistics panel (optional capability).
    func openZoomStatistics(minimized: Bool)
}

public extension ZoomStatsProvider {
    func openZoomStatistics(minimized: Bool) {}
}

/// Thread-safe box used by providers that sample on a background queue.
final class StatsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value = ZoomStats()
    var stats: ZoomStats {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}

/// Deterministic fake data for UI work and previews.
public final class MockZoomStatsProvider: ZoomStatsProvider {
    public var onUpdate: ((ZoomStats) -> Void)?
    public private(set) var latestStats = ZoomStats()
    private var timer: Timer?
    private var tick = 0.0

    public init() {}

    public func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.step() }
        step()
    }

    public func stop() { timer?.invalidate(); timer = nil }

    private func step() {
        tick += 1
        var s = ZoomStats()
        s.zoomRunning = true; s.meetingActive = true; s.statisticsWindowAvailable = true
        s.cpuZoom = 9; s.cpuSystem = 40 + 10 * sin(tick / 5)
        s.memoryZoom = 1_900_000_000; s.memorySystem = 30_000_000_000; s.memoryTotal = 36 * 1_073_741_824
        s.bandwidthSend = 940; s.bandwidthReceive = 4989
        s.audio.frequencyReceive = 48; s.audio.latencyReceive = 44 + 20 * sin(tick / 7)
        s.audio.jitterReceive = 1; s.audio.packetLossReceiveAverage = 2.8; s.audio.packetLossReceiveMax = 11.4
        s.video.latencySend = 40; s.video.latencyReceive = 40
        s.video.sendWidth = 640; s.video.sendHeight = 360; s.video.receiveWidth = 640; s.video.receiveHeight = 360
        s.video.fpsSend = 26; s.video.fpsReceive = 17
        s.video.packetLossReceiveAverage = 0; s.video.packetLossReceiveMax = 0
        s.dataCenter = "FRA"; s.dataCenterDetail = "Germany"; s.networkType = "Wired"
        s.connectionType = "Cloud"; s.encryption = "AES-256-GCM"; s.zoomVersion = "6.5.7 (60598)"
        latestStats = s
        onUpdate?(s)
    }
}
