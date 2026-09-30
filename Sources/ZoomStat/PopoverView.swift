import SwiftUI
import ZoomStatCore

struct PopoverView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.openSettings) private var openSettings

    private static let timeFormat: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f
    }()

    var body: some View {
        let s = model.stats
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ZoomStat").font(.headline)
                Spacer()
                HealthLabel(health: model.health)
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 6)

            ProfileSwitcher().padding(.horizontal, 14).padding(.bottom, 6)

            if let notice = notice(s) {
                NoticeView(text: notice.0, action: notice.1, actionTitle: notice.2)
                    .padding(.horizontal, 14).padding(.bottom, 6)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 3) {
                section("Connection")
                row("Zoom Meeting", s.meetingActive ? "Connected" : (s.zoomRunning ? "Not in meeting" : "Zoom not running"))
                row("Data Center", s.dataCenter.map { c in s.dataCenterDetail.map { "\(c) · \($0)" } ?? c })
                row("Network", [s.networkType, s.connectionType].compactMap { $0 }.joined(separator: " · ").nilIfEmpty)

                // What you send is the primary view.
                section("Sending")
                row("Bandwidth", Fmt.rate(s.bandwidthSend))
                if audioSending(s) {
                    row("Audio Latency", Fmt.ms(s.audio.latencySend))
                    row("Audio Jitter", Fmt.ms(s.audio.jitterSend))
                    row("Audio Loss", Fmt.loss(s.audio.packetLossSendAverage, s.audio.packetLossSendMax))
                } else {
                    row("Audio", s.meetingActive ? "Not sending" : nil)
                }
                row("Video", Fmt.stream(s.video.sendWidth, s.video.sendHeight, s.video.fpsSend))
                if s.video.sendWidth != nil || s.video.latencySend != nil {
                    row("Video Latency", Fmt.ms(s.video.latencySend))
                    row("Video Jitter", Fmt.ms(s.video.jitterSend))
                    row("Video Loss", Fmt.loss(s.video.packetLossSendAverage, s.video.packetLossSendMax))
                }
                if s.screenShare.sendWidth != nil || s.screenShare.fpsSend != nil {
                    row("Screen Share", Fmt.stream(s.screenShare.sendWidth, s.screenShare.sendHeight, s.screenShare.fpsSend))
                    row("Share Latency", Fmt.ms(s.screenShare.latencySend))
                    row("Share Loss", Fmt.loss(s.screenShare.packetLossSendAverage, s.screenShare.packetLossSendMax))
                }

                // Receiving is secondary: collapsed by default.
                disclosure("Receiving", isOpen: $model.settings.showReceiving)
                if model.settings.showReceiving {
                    row("Bandwidth", Fmt.rate(s.bandwidthReceive))
                    row("Audio Latency", Fmt.ms(s.audio.latencyReceive))
                    row("Audio Jitter", Fmt.ms(s.audio.jitterReceive))
                    row("Audio Loss", Fmt.loss(s.audio.packetLossReceiveAverage, s.audio.packetLossReceiveMax))
                    row("Video", Fmt.stream(s.video.receiveWidth, s.video.receiveHeight, s.video.fpsReceive))
                    row("Video Latency", Fmt.ms(s.video.latencyReceive))
                    row("Video Loss", Fmt.loss(s.video.packetLossReceiveAverage, s.video.packetLossReceiveMax))
                    if s.screenShare.receiveWidth != nil || s.screenShare.fpsReceive != nil {
                        row("Screen Share", Fmt.stream(s.screenShare.receiveWidth, s.screenShare.receiveHeight, s.screenShare.fpsReceive))
                    }
                }

                section("System")
                row("Zoom CPU", Fmt.pct(s.cpuZoom, digits: 0))
                row("System CPU", Fmt.pct(s.cpuSystem, digits: 0))
                row("Zoom Memory", Fmt.bytes(s.memoryZoom))
                row("System Memory", Fmt.bytes(s.memorySystem))

                Divider().gridCellColumns(2).padding(.vertical, 4)
                row("Last Updated", Self.timeFormat.string(from: s.timestamp))
            }
            .padding(.horizontal, 14)

            Divider().padding(.top, 8)

            VStack(spacing: 0) {
                MenuRow(title: "Open Zoom Statistics", enabled: s.zoomRunning) { model.openZoomStatistics() }
                MenuRow(title: model.isLogging ? "Stop Logging" : "Start Logging") { model.toggleLogging() }
                MenuRow(title: "Settings…") {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                Divider().padding(.vertical, 4)
                MenuRow(title: "Quit ZoomStat") { NSApp.terminate(nil) }
            }
            .padding(.horizontal, 5).padding(.vertical, 5)
        }
        .frame(width: 310)
    }

    // MARK: Pieces

    @ViewBuilder
    private func section(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .gridCellColumns(2)
            .padding(.top, 7)
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value ?? Fmt.dash)
                .monospacedDigit()
                .foregroundStyle(value == nil || value == Fmt.dash ? .tertiary : .primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 12))
    }

    @ViewBuilder
    private func disclosure(_ title: String, isOpen: Binding<Bool>) -> some View {
        Button { isOpen.wrappedValue.toggle() } label: {
            HStack(spacing: 4) {
                Text(title).font(.system(size: 11, weight: .semibold))
                Image(systemName: isOpen.wrappedValue ? "chevron.down" : "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 7)
    }

    /// Zoom reports "--" for every audio send value while you are muted.
    private func audioSending(_ s: ZoomStats) -> Bool {
        s.audio.latencySend != nil || s.audio.jitterSend != nil || s.audio.packetLossSendAverage != nil
    }

    /// Shows receive only when send is missing, "send / receive" otherwise.
    private func sendRecv(_ send: Double?, _ recv: Double?, _ f: (Double?) -> String) -> String? {
        switch (send, recv) {
        case (nil, nil): return nil
        case (nil, _): return f(recv)
        case (_, nil): return "\(f(send)) ↑"
        default: return "\(f(send)) ↑  \(f(recv)) ↓"
        }
    }

    private func notice(_ s: ZoomStats) -> (String, (() -> Void)?, String?)? {
        if !s.accessibilityGranted {
            return ("ZoomStat needs Accessibility access to read Zoom's Statistics panel.", model.openAccessibilitySettings, "Open Privacy Settings")
        }
        if !s.zoomRunning { return ("Zoom is not running.", nil, nil) }
        if s.meetingActive && !s.statisticsWindowAvailable {
            return ("Zoom's Statistics panel is closed, so only system values are shown.",
                    { model.openZoomStatistics(minimized: true) }, "Read Statistics in Background")
        }
        return nil
    }
}

struct HealthLabel: View {
    let health: ConnectionHealth
    var color: Color {
        switch health {
        case .healthy: .green
        case .degraded: .yellow
        case .poor: .red
        case .unavailable: .secondary
        }
    }
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(health.rawValue).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

struct NoticeView: View {
    let text: String
    let action: (() -> Void)?
    let actionTitle: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let action, let actionTitle {
                Button(actionTitle, action: action).controlSize(.small)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
    }
}

/// A full-width, menu-style row button.
struct MenuRow: View {
    let title: String
    var enabled = true
    let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 9).padding(.vertical, 3)
                .foregroundStyle(hover && enabled ? AnyShapeStyle(Color.white)
                                 : AnyShapeStyle(enabled ? HierarchicalShapeStyle.primary : .tertiary))
                .background(RoundedRectangle(cornerRadius: 4).fill(hover && enabled ? Color.accentColor : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hover = $0 }
    }
}

struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    var body: some View {
        if let t = model.menuBarText {
            if model.health == .poor {
                Label(t, systemImage: "exclamationmark.triangle").labelStyle(.titleAndIcon)
            } else {
                Text(t).monospacedDigit()
            }
        } else {
            Image(systemName: model.menuBarSymbol)
        }
    }
}

/// Quick switch between menu bar profiles (e.g. Normal / DJ).
struct ProfileSwitcher: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        let profiles = model.settings.menuBarProfiles
        if profiles.count > 1 {
            HStack(spacing: 8) {
                Text("Menu bar").font(.system(size: 11)).foregroundStyle(.secondary)
                if profiles.count <= 3 {
                    picker(profiles).pickerStyle(.segmented)
                } else {
                    picker(profiles).pickerStyle(.menu)
                }
            }
        }
    }

    private func picker(_ profiles: [MenuBarProfile]) -> some View {
        Picker("Menu bar", selection: Binding(get: { model.settings.activeProfile.id },
                                              set: { model.selectProfile($0) })) {
            ForEach(profiles) { Text($0.name).tag($0.id) }
        }
        .labelsHidden()
        .controlSize(.small)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
