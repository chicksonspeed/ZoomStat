import Foundation
import ZoomStatCore

struct AppSettings: Codable, Equatable {
    var refreshInterval: Double = 1
    var menuBarProfiles: [MenuBarProfile] = [.normal, .dj]
    var activeProfileID: UUID? = nil

    var activeProfile: MenuBarProfile {
        menuBarProfiles.first { $0.id == activeProfileID } ?? menuBarProfiles.first ?? .normal
    }

    // Zoom Statistics window handling
    var cycleTabs = true
    var cycleTabsWhenVisible = false
    var autoOpenStatistics = false

    var thresholds = HealthThresholds(
        latencyMs: Limit(degraded: 150, poor: 300),
        jitterMs: Limit(degraded: 30, poor: 60),
        packetLossPercent: Limit(degraded: 2, poor: 5),
        videoFPS: Limit(degraded: 15, poor: 8)
    )

    var showReceiving = false
    var qualityDirection: QualityDirection = .send

    var loggingEnabled = false
    var logCSV = true
    var logJSON = false

    var notificationsEnabled = false
    var alertRules: [AlertRule] = [
        AlertRule(metric: .latency, enabled: true, threshold: 300, sustainSeconds: 15),
        AlertRule(metric: .jitter, enabled: true, threshold: 60, sustainSeconds: 15),
        AlertRule(metric: .packetLoss, enabled: true, threshold: 5, sustainSeconds: 15),
        AlertRule(metric: .lowVideoFPS, enabled: false, threshold: 10, sustainSeconds: 20),
        AlertRule(metric: .zoomCPU, enabled: false, threshold: 50, sustainSeconds: 30),
        AlertRule(metric: .systemCPU, enabled: false, threshold: 90, sustainSeconds: 30),
        AlertRule(metric: .memoryPressure, enabled: false, threshold: 95, sustainSeconds: 60),
    ]

    var providerConfiguration: ProviderConfiguration {
        var c = ProviderConfiguration()
        c.refreshInterval = refreshInterval
        c.cycleTabs = cycleTabs
        c.cycleTabsWhenVisible = cycleTabsWhenVisible
        c.autoOpenStatistics = autoOpenStatistics
        return c
    }

    var logFormats: LogFormats {
        var f: LogFormats = []
        if logCSV { f.insert(.csv) }
        if logJSON { f.insert(.json) }
        return f.isEmpty ? [.csv] : f
    }

    // MARK: Persistence (tolerant of fields added in later versions)

    private static let key = "ZoomStat.settings"

    static func load() -> AppSettings {
        guard let d = UserDefaults.standard.data(forKey: key),
              let s = try? JSONDecoder().decode(AppSettings.self, from: d) else { return AppSettings() }
        return s
    }

    func save() {
        if let d = try? JSONEncoder().encode(self) { UserDefaults.standard.set(d, forKey: Self.key) }
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        refreshInterval = (try? c.decode(Double.self, forKey: .refreshInterval)) ?? d.refreshInterval
        menuBarProfiles = (try? c.decode([MenuBarProfile].self, forKey: .menuBarProfiles)) ?? d.menuBarProfiles
        if menuBarProfiles.isEmpty { menuBarProfiles = d.menuBarProfiles }
        activeProfileID = try? c.decode(UUID.self, forKey: .activeProfileID)
        cycleTabs = (try? c.decode(Bool.self, forKey: .cycleTabs)) ?? d.cycleTabs
        cycleTabsWhenVisible = (try? c.decode(Bool.self, forKey: .cycleTabsWhenVisible)) ?? d.cycleTabsWhenVisible
        autoOpenStatistics = (try? c.decode(Bool.self, forKey: .autoOpenStatistics)) ?? d.autoOpenStatistics
        thresholds = (try? c.decode(HealthThresholds.self, forKey: .thresholds)) ?? d.thresholds
        showReceiving = (try? c.decode(Bool.self, forKey: .showReceiving)) ?? d.showReceiving
        qualityDirection = (try? c.decode(QualityDirection.self, forKey: .qualityDirection)) ?? d.qualityDirection
        loggingEnabled = (try? c.decode(Bool.self, forKey: .loggingEnabled)) ?? d.loggingEnabled
        logCSV = (try? c.decode(Bool.self, forKey: .logCSV)) ?? d.logCSV
        logJSON = (try? c.decode(Bool.self, forKey: .logJSON)) ?? d.logJSON
        notificationsEnabled = (try? c.decode(Bool.self, forKey: .notificationsEnabled)) ?? d.notificationsEnabled
        let rules = (try? c.decode([AlertRule].self, forKey: .alertRules)) ?? []
        alertRules = d.alertRules.map { def in rules.first { $0.metric == def.metric } ?? def }
    }
}
