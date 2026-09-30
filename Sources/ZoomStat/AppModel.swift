import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications
import ZoomStatCore

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var stats = ZoomStats()
    @Published private(set) var health: ConnectionHealth = .unavailable
    @Published var settings: AppSettings {
        didSet { if settings != oldValue { settingsChanged(from: oldValue) } }
    }
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    let provider: ZoomStatsProvider
    let history = MeetingHistory()
    private let logger = StatsLogger()
    private let alerts = AlertEngine()
    private var wakeObserver: NSObjectProtocol?

    var isLogging: Bool { settings.loggingEnabled }

    init(provider: ZoomStatsProvider? = nil) {
        let s = AppSettings.load()
        settings = s
        if let provider {
            self.provider = provider
        } else if ProcessInfo.processInfo.arguments.contains("--mock") {
            self.provider = MockZoomStatsProvider()
        } else {
            self.provider = AccessibilityZoomStatsProvider(configuration: s.providerConfiguration)
        }
        logger.formats = s.logFormats
        if s.loggingEnabled { logger.start() }

        self.provider.onUpdate = { [weak self] st in self?.receive(st) }
        self.provider.start()

        // Ask once for Accessibility; macOS shows its own prompt.
        _ = AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)

        // Diagnostics: `ZoomStat --snapshot out.png` renders the popover after a few samples and quits.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let path = args[i + 1]
            NSLog("ZoomStat: snapshot scheduled")
            DispatchQueue.main.asyncAfter(deadline: .now() + 12) { self.writeSnapshot(to: path) }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.alerts.reset() }
        }
    }

    private func receive(_ s: ZoomStats) {
        stats = s
        health = HealthEvaluator.evaluate(s, settings.thresholds, direction: settings.qualityDirection)
        history.append(s)
        logger.record(s)
        guard settings.notificationsEnabled else { return }
        for fired in alerts.evaluate(s, rules: settings.alertRules, direction: settings.qualityDirection) { notify(fired) }
    }

    private func settingsChanged(from old: AppSettings) {
        settings.save()
        if let p = provider as? AccessibilityZoomStatsProvider,
           old.providerConfiguration != settings.providerConfiguration {
            p.configuration = settings.providerConfiguration
        }
        logger.formats = settings.logFormats
        if settings.loggingEnabled != old.loggingEnabled || settings.logFormats != old.logFormats {
            logger.stop()
            if settings.loggingEnabled { logger.start() }
        }
        if settings.notificationsEnabled && !old.notificationsEnabled { requestNotificationPermission() }
        if settings.alertRules != old.alertRules || settings.qualityDirection != old.qualityDirection { alerts.reset() }
        if settings.qualityDirection != old.qualityDirection { health = HealthEvaluator.evaluate(stats, settings.thresholds, direction: settings.qualityDirection) }
    }

    // MARK: Actions

    func toggleLogging() { settings.loggingEnabled.toggle() }

    func openZoomStatistics(minimized: Bool = false) { provider.openZoomStatistics(minimized: minimized) }

    func revealLogs() {
        let dir = StatsLogger.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(dir)
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("ZoomStat: launch at login failed: \(error.localizedDescription)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: Notifications

    private func requestNotificationPermission() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func notify(_ a: FiredAlert) {
        guard Bundle.main.bundleIdentifier != nil else { return }   // not running as .app
        let c = UNMutableNotificationContent()
        c.title = a.rule.metric.title
        let v = a.rule.metric.unit == "%" ? String(format: "%.1f%%", a.value) : "\(Int(a.value.rounded())) \(a.rule.metric.unit)"
        c.body = "\(v) for more than \(Int(a.rule.sustainSeconds)) s"
        let req = UNNotificationRequest(identifier: "zoomstat.\(a.rule.metric.rawValue)", content: c, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func writeSnapshot(to path: String) {
        NSLog("ZoomStat: writing snapshot")
        for p in settings.menuBarProfiles {
            NSLog("ZoomStat: menu bar [\(p.name)] \(p.text(stats, health: health) ?? "(icon)")")
        }
        for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            let view = PopoverView().environmentObject(self)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, scheme)
            let r = ImageRenderer(content: view)
            r.scale = 2
            if let img = r.nsImage, let tiff = img.tiffRepresentation,
               let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                let url = URL(fileURLWithPath: path).deletingPathExtension().appendingPathExtension("\(name).png")
                do { try png.write(to: url) } catch { NSLog("ZoomStat: \(error)") }
            } else {
                NSLog("ZoomStat: renderer returned no image")
            }
        }
        NSApp.terminate(nil)
    }

    // MARK: Menu bar text

    var menuBarText: String? {
        guard stats.meetingActive else { return nil }
        return settings.activeProfile.text(stats, health: health)
    }

    func selectProfile(_ id: UUID) { settings.activeProfileID = id }

    var menuBarSymbol: String {
        if !stats.zoomRunning { return "video.slash" }
        if !stats.meetingActive { return "video" }
        switch health {
        case .poor: return "exclamationmark.triangle"
        case .degraded: return "video.badge.ellipsis"
        default: return "video.fill"
        }
    }
}
