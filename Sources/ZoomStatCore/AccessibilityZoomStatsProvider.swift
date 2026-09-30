import Foundation
import AppKit

public struct ProviderConfiguration: Sendable, Equatable {
    public var refreshInterval: TimeInterval = 1.0
    /// Rotate Overall → Audio → Video → Screen sharing so every tab gets read.
    public var cycleTabs = true
    /// Also rotate while the user is working in the Statistics window (Zoom frontmost, window focused).
    public var cycleTabsWhenVisible = false
    public var includeScreenShareTab = true
    /// Open Statistics (minimized) automatically when a meeting starts.
    public var autoOpenStatistics = false
    public var useSystemFallbacks = true
    public init() {}
}

/// Reads Zoom's own Statistics panel through the Accessibility API (read-only apart
/// from selecting the panel's tabs) and fills gaps with native system metrics.
public final class AccessibilityZoomStatsProvider: ZoomStatsProvider {
    public var onUpdate: ((ZoomStats) -> Void)?
    public var latestStats: ZoomStats { box.stats }
    public var configuration: ProviderConfiguration {
        get { queue.sync { config } }
        set { queue.async { self.config = newValue; self.reschedule() } }
    }

    private let box = StatsBox()
    private let queue = DispatchQueue(label: "ZoomStat.provider", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var config: ProviderConfiguration
    private let window: ZoomStatisticsWindow
    private let parser: StatisticsPanelParser
    private let system = SystemMetrics()
    private let debug = ProcessInfo.processInfo.environment["ZOOMSTAT_DEBUG"] != nil

    // Panel values persist across ticks because only one tab is readable at a time.
    private var panel = ZoomStats()
    private var tabReadAt: [StatisticsTab: Date] = [:]
    private var notReadyCount = 0
    private var lastPID: pid_t?
    private var lastTick: Date?
    private var wasInMeeting = false

    public init(configuration: ProviderConfiguration = .init(), labels: ZoomUILabels = .english) {
        self.config = configuration
        self.window = ZoomStatisticsWindow(labels: labels)
        self.parser = StatisticsPanelParser(labels: labels)
    }

    deinit { timer?.cancel() }

    public func start() { queue.async { self.reschedule() } }

    public func stop() { queue.async { self.timer?.cancel(); self.timer = nil } }

    public func openZoomStatistics(minimized: Bool) {
        queue.async { _ = self.window.open(minimize: minimized) }
    }

    /// One synchronous sample (used by the CLI and tests).
    public func sampleNow() -> ZoomStats { queue.sync { tick(); return box.stats } }

    private func reschedule() {
        timer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        let ms = Int(max(0.25, config.refreshInterval) * 1000)
        t.schedule(deadline: .now(), repeating: .milliseconds(ms), leeway: .milliseconds(ms / 10))
        t.setEventHandler { [weak self] in self?.tick() }
        t.resume()
        timer = t
    }

    private var tabOrder: [StatisticsTab] {
        config.includeScreenShareTab ? [.overall, .audio, .video, .screenShare] : [.overall, .audio, .video]
    }

    private func staleAfter() -> TimeInterval {
        max(10, config.refreshInterval * Double(tabOrder.count) * 3)
    }

    private func tick() {
        let now = Date()
        if let last = lastTick, now.timeIntervalSince(last) > max(5, config.refreshInterval * 5) {
            system.reset()   // woke from sleep or stalled: drop CPU deltas
        }
        lastTick = now

        var out = ZoomStats()
        out.timestamp = now
        out.accessibilityGranted = AX.isTrusted(prompt: false)

        let snap = out.accessibilityGranted ? window.snapshot() : ZoomStatisticsWindow.Snapshot()
        let app = window.zoomApp()
        let pid = snap.zoomPID ?? app?.processIdentifier

        if pid != lastPID {   // Zoom quit/restarted
            panel = ZoomStats(); tabReadAt = [:]; system.reset(); lastPID = pid
        }

        guard let pid else {
            publish(out)
            return
        }
        out.zoomRunning = true

        // 1. Read whichever tab is currently shown.
        var ready = false
        if snap.statisticsVisible, let tab = snap.selectedTab {
            ready = parser.apply(tokens: snap.tokens, tab: tab, to: &panel)
            if ready { tabReadAt[tab] = now; notReadyCount = 0 } else { notReadyCount += 1 }
        }

        // 2. Expire values from tabs we have not seen recently.
        for tab in StatisticsTab.allCases {
            if let t = tabReadAt[tab], now.timeIntervalSince(t) > staleAfter() { clear(tab); tabReadAt[tab] = nil }
            if !snap.statisticsVisible, tabReadAt[tab] == nil { clear(tab) }
        }

        out.statisticsWindowAvailable = snap.statisticsVisible
        if snap.statisticsVisible || tabReadAt[.overall] != nil {
            copyPanel(into: &out)
        }
        let mediaSeen = out.audio.hasAnyValue || out.video.hasAnyValue || out.screenShare.hasAnyValue
        out.meetingActive = snap.meetingWindowOpen || mediaSeen

        // 3. Native fallbacks (always sampled so CPU deltas stay warm).
        let cpuZ = system.processCPU(pid: pid)
        let cpuS = system.systemCPU()
        if config.useSystemFallbacks {
            if out.cpuZoom == nil { out.cpuZoom = cpuZ }
            if out.cpuSystem == nil { out.cpuSystem = cpuS }
            if out.memoryZoom == nil { out.memoryZoom = system.processMemory(pid: pid) }
            if out.memorySystem == nil || out.memoryTotal == nil, let (used, total) = system.systemMemory() {
                if out.memorySystem == nil { out.memorySystem = used }
                if out.memoryTotal == nil { out.memoryTotal = total }
            }
            if out.networkType == nil { out.networkType = system.networkType() }
            if out.proxy == nil { out.proxy = system.proxy() }
            if out.zoomVersion == nil { out.zoomVersion = SystemMetrics.zoomVersion(bundleURL: app?.bundleURL) }
        }

        // 4. Auto-open on meeting start (opt-in).
        if out.meetingActive, !wasInMeeting, config.autoOpenStatistics, !snap.statisticsVisible, out.accessibilityGranted {
            _ = window.open(minimize: true)
        }
        wasInMeeting = out.meetingActive

        if debug {
            FileHandle.standardError.write(Data("tick tab=\(snap.selectedTab.map { "\($0)" } ?? "-") ready=\(ready) minimized=\(snap.windowMinimized) viewing=\(snap.userViewing) visible=\(snap.statisticsVisible) tokens=\(snap.tokens.count)\n".utf8))
        }

        // 5. Advance to the next tab once the current one has been read.
        if config.cycleTabs, snap.statisticsVisible, let cur = snap.selectedTab,
           !snap.userViewing || config.cycleTabsWhenVisible,
           ready || notReadyCount >= 3 {
            let order = tabOrder
            let idx = order.firstIndex(of: cur) ?? -1
            window.select(tab: order[(idx + 1) % order.count])
            notReadyCount = 0
        }

        publish(out)
    }

    private func clear(_ tab: StatisticsTab) {
        switch tab {
        case .audio: panel.audio = MediaStats()
        case .video: panel.video = MediaStats()
        case .screenShare: panel.screenShare = MediaStats()
        case .overall:
            let keep = panel
            panel = ZoomStats()
            panel.audio = keep.audio; panel.video = keep.video; panel.screenShare = keep.screenShare
        }
    }

    private func copyPanel(into out: inout ZoomStats) {
        out.cpuZoom = panel.cpuZoom; out.cpuSystem = panel.cpuSystem
        out.memoryZoom = panel.memoryZoom; out.memorySystem = panel.memorySystem; out.memoryTotal = panel.memoryTotal
        out.bandwidthSend = panel.bandwidthSend; out.bandwidthReceive = panel.bandwidthReceive
        out.audio = panel.audio; out.video = panel.video; out.screenShare = panel.screenShare
        out.dataCenter = panel.dataCenter; out.dataCenterDetail = panel.dataCenterDetail
        out.networkType = panel.networkType; out.connectionType = panel.connectionType
        out.proxy = panel.proxy; out.encryption = panel.encryption; out.zoomVersion = panel.zoomVersion
    }

    private func publish(_ s: ZoomStats) {
        box.stats = s
        if let cb = onUpdate { DispatchQueue.main.async { cb(s) } }
    }
}
