import ApplicationServices
import AppKit

/// Version-dependent knowledge of Zoom's window/AX layout. Used by
/// AccessibilityZoomStatsProvider; nothing else should touch Zoom's AX tree.
public final class ZoomStatisticsWindow {
    public let labels: ZoomUILabels
    public init(labels: ZoomUILabels = .english) { self.labels = labels }

    public struct Snapshot {
        public var zoomPID: pid_t?
        public var meetingWindowOpen = false
        public var statisticsVisible = false   // Settings window showing the Statistics category
        public var windowMinimized = false
        /// Zoom is frontmost and the Settings window is its main window: the user is looking at it.
        public var userViewing = false
        public var selectedTab: StatisticsTab?
        public var tokens: [String] = []
    }

    public func zoomApp() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: labels.bundleIdentifier)
            .first { !$0.isTerminated }
    }

    func appElement(_ pid: pid_t) -> AXUIElement {
        let e = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(e, 0.5)   // never block on a busy Zoom
        return e
    }

    func settingsWindow(_ app: AXUIElement) -> AXUIElement? {
        AX.windows(app).first { AX.title($0) == labels.settingsWindowTitle }
    }

    func tabs(in window: AXUIElement) -> [(StatisticsTab, AXUIElement, Bool)] {
        let map: [(String, StatisticsTab)] = [(labels.tabOverall, .overall), (labels.tabAudio, .audio),
                                               (labels.tabVideo, .video), (labels.tabScreenShare, .screenShare)]
        let elems = AX.findAll(window, maxDepth: 6) { AX.role($0) == self.labels.tabRole }
        return elems.compactMap { e in
            guard let t = AX.title(e), let m = map.first(where: { t.hasPrefix($0.0) }) else { return nil }
            return (m.1, e, t.hasSuffix(labels.selectedSuffix))
        }
    }

    /// Container holding the value texts: the scroll area that follows the tab strip.
    private func valueTexts(window: AXUIElement, tabElement: AXUIElement) -> [String] {
        // Tab strip lives in a scroll area; its parent holds [tab strip, values, buttons].
        guard let strip: AXUIElement = AX.attr(tabElement, kAXParentAttribute),
              let pane: AXUIElement = AX.attr(strip, kAXParentAttribute) else { return [] }
        return AX.children(pane).filter { !CFEqual($0, strip) }.flatMap { AX.leafTexts($0) }
    }

    public func snapshot() -> Snapshot {
        var s = Snapshot()
        guard let app = zoomApp() else { return s }
        s.zoomPID = app.processIdentifier
        let ax = appElement(app.processIdentifier)
        let wins = AX.windows(ax)
        s.meetingWindowOpen = wins.contains { w in
            guard let t = AX.title(w) else { return false }
            return labels.meetingWindowTitles.contains(t)
        }
        guard let win = wins.first(where: { AX.title($0) == labels.settingsWindowTitle }) else { return s }
        s.windowMinimized = AX.attr(win, kAXMinimizedAttribute, as: Bool.self) ?? false
        s.userViewing = !s.windowMinimized && app.isActive && (AX.attr(win, kAXMainAttribute, as: Bool.self) ?? false)
        let t = tabs(in: win)
        guard let selected = t.first(where: { $0.2 }) ?? t.first else { return s }
        s.statisticsVisible = true
        s.selectedTab = selected.0
        s.tokens = valueTexts(window: win, tabElement: selected.1)
        return s
    }

    @discardableResult
    public func select(tab: StatisticsTab) -> Bool {
        guard let app = zoomApp() else { return false }
        let ax = appElement(app.processIdentifier)
        guard let win = settingsWindow(ax),
              let e = tabs(in: win).first(where: { $0.0 == tab }) else { return false }
        return AX.press(e.1)
    }

    /// Opens Zoom Settings → Statistics through Zoom's own menu. Explicit user action only.
    @discardableResult
    public func open(minimize: Bool) -> Bool {
        guard let app = zoomApp() else { return false }
        let ax = appElement(app.processIdentifier)
        if settingsWindow(ax) == nil {
            guard let menuBar: AXUIElement = AX.attr(ax, kAXMenuBarAttribute) else { return false }
            let appMenus = AX.children(menuBar).dropFirst().prefix(1)   // [Apple, <App>, …]
            let item = appMenus.lazy.compactMap { m -> AXUIElement? in
                AX.find(m, maxDepth: 3) { e in
                    AX.role(e) == kAXMenuItemRole as String &&
                    self.labels.settingsMenuItemPrefixes.contains { (AX.title(e) ?? "").hasPrefix($0) }
                }
            }.first
            guard let item, AX.press(item) else { return false }
            for _ in 0..<20 where settingsWindow(ax) == nil { Thread.sleep(forTimeInterval: 0.1) }
        }
        guard let win = settingsWindow(ax) else { return false }
        if let table = AX.find(win, maxDepth: 5, { AX.desc($0) == self.labels.categoryListDescription }) {
            for row in AX.children(table) where AX.role(row) == kAXRowRole as String {
                if let cell = AX.children(row).first, (AX.desc(cell) ?? "").hasPrefix(labels.statisticsCategory) {
                    AX.set(row, kAXSelectedAttribute, kCFBooleanTrue)
                }
            }
        }
        if minimize {
            Thread.sleep(forTimeInterval: 0.3)
            AX.set(win, kAXMinimizedAttribute, kCFBooleanTrue)
        } else {
            AX.set(win, kAXMainAttribute, kCFBooleanTrue)
            app.activate()
        }
        return true
    }
}
