import Foundation
import ZoomStatCore

/// One value that can be shown in the menu bar.
enum MenuBarItem: String, Codable, CaseIterable, Identifiable {
    // Audio
    case audioLatencySend, audioLatencyReceive, audioJitterSend, audioJitterReceive
    case audioLossSend, audioLossReceive, audioPeakLoss
    // Video
    case videoSendResolution, videoSendFPS, videoSendStream
    case videoReceiveResolution, videoReceiveFPS
    case videoLatencySend, videoLatencyReceive, videoJitterSend, videoLossSend, videoLossReceive
    // Screen sharing
    case shareSendStream, shareReceiveStream
    // Network
    case bandwidthSend, bandwidthReceive, dataCenter
    // System
    case zoomCPU, systemCPU, zoomMemory
    // Status
    case health

    var id: String { rawValue }

    enum Group: String, CaseIterable { case audio = "Audio", video = "Video", share = "Screen Sharing", network = "Network", system = "System", status = "Status" }

    var group: Group {
        switch self {
        case .audioLatencySend, .audioLatencyReceive, .audioJitterSend, .audioJitterReceive,
             .audioLossSend, .audioLossReceive, .audioPeakLoss: .audio
        case .videoSendResolution, .videoSendFPS, .videoSendStream, .videoReceiveResolution, .videoReceiveFPS,
             .videoLatencySend, .videoLatencyReceive, .videoJitterSend, .videoLossSend, .videoLossReceive: .video
        case .shareSendStream, .shareReceiveStream: .share
        case .bandwidthSend, .bandwidthReceive, .dataCenter: .network
        case .zoomCPU, .systemCPU, .zoomMemory: .system
        case .health: .status
        }
    }

    var title: String {
        switch self {
        case .audioLatencySend: "Send latency"
        case .audioLatencyReceive: "Receive latency"
        case .audioJitterSend: "Send jitter"
        case .audioJitterReceive: "Receive jitter"
        case .audioLossSend: "Send packet loss"
        case .audioLossReceive: "Receive packet loss"
        case .audioPeakLoss: "Peak packet loss"
        case .videoSendResolution: "Send resolution"
        case .videoSendFPS: "Send frame rate"
        case .videoSendStream: "Send resolution @ fps"
        case .videoReceiveResolution: "Receive resolution"
        case .videoReceiveFPS: "Receive frame rate"
        case .videoLatencySend: "Send latency"
        case .videoLatencyReceive: "Receive latency"
        case .videoJitterSend: "Send jitter"
        case .videoLossSend: "Send packet loss"
        case .videoLossReceive: "Receive packet loss"
        case .shareSendStream: "Send resolution @ fps"
        case .shareReceiveStream: "Receive resolution @ fps"
        case .bandwidthSend: "Bandwidth send"
        case .bandwidthReceive: "Bandwidth receive"
        case .dataCenter: "Data center"
        case .zoomCPU: "Zoom CPU"
        case .systemCPU: "System CPU"
        case .zoomMemory: "Zoom memory"
        case .health: "Connection status"
        }
    }

    /// Compact prefix used when labels are on. ↑ = send, ↓ = receive.
    var shortLabel: String {
        switch self {
        case .audioLatencySend, .audioJitterSend, .audioLossSend: "A↑"
        case .audioLatencyReceive, .audioJitterReceive, .audioLossReceive: "A↓"
        case .audioPeakLoss: "A peak"
        case .videoSendResolution, .videoSendFPS, .videoSendStream, .videoLatencySend, .videoJitterSend, .videoLossSend: "V↑"
        case .videoReceiveResolution, .videoReceiveFPS, .videoLatencyReceive, .videoLossReceive: "V↓"
        case .shareSendStream: "S↑"
        case .shareReceiveStream: "S↓"
        case .bandwidthSend: "↑"
        case .bandwidthReceive: "↓"
        case .dataCenter: ""
        case .zoomCPU: "Zoom"
        case .systemCPU: "CPU"
        case .zoomMemory: "Zoom"
        case .health: ""
        }
    }

    /// Compact value, or nil when Zoom reports nothing (shown as "—").
    func value(_ s: ZoomStats, health: ConnectionHealth, compact: Bool = false) -> String? {
        let sp = compact ? "" : " "
        func ms(_ v: Double?) -> String? { v.map { "\(Int($0.rounded()))\(sp)ms" } }
        func pct(_ v: Double?) -> String? { v.map { $0 < 10 ? String(format: "%.1f%%", $0) : "\(Int($0.rounded()))%" } }
        func fps(_ v: Double?) -> String? { v.map { "\(Int($0.rounded()))\(sp)fps" } }
        func res(_ w: Int?, _ h: Int?) -> String? {
            guard let w, let h else { return nil }
            return compact ? "\(h)p" : "\(w)×\(h)"
        }
        func rate(_ k: Double?) -> String? {
            guard let k else { return nil }
            guard compact else { return Fmt.rate(k) }
            return k >= 1000 ? String(format: "%.1fM", k / 1000) : "\(Int(k.rounded()))k"
        }
        func stream(_ w: Int?, _ h: Int?, _ f: Double?) -> String? {
            let r = res(w, h), f = fps(f)
            switch (r, f) {
            case let (r?, f?): return "\(r) \(f)"
            default: return r ?? f
            }
        }
        let a = s.audio, v = s.video, sh = s.screenShare
        switch self {
        case .audioLatencySend: return ms(a.latencySend)
        case .audioLatencyReceive: return ms(a.latencyReceive)
        case .audioJitterSend: return ms(a.jitterSend)
        case .audioJitterReceive: return ms(a.jitterReceive)
        case .audioLossSend: return pct(a.packetLossSendAverage)
        case .audioLossReceive: return pct(a.packetLossReceiveAverage)
        case .audioPeakLoss: return pct(a.packetLossMax)
        case .videoSendResolution: return res(v.sendWidth, v.sendHeight)
        case .videoSendFPS: return fps(v.fpsSend)
        case .videoSendStream: return stream(v.sendWidth, v.sendHeight, v.fpsSend)
        case .videoReceiveResolution: return res(v.receiveWidth, v.receiveHeight)
        case .videoReceiveFPS: return fps(v.fpsReceive)
        case .videoLatencySend: return ms(v.latencySend)
        case .videoLatencyReceive: return ms(v.latencyReceive)
        case .videoJitterSend: return ms(v.jitterSend)
        case .videoLossSend: return pct(v.packetLossSendAverage)
        case .videoLossReceive: return pct(v.packetLossReceiveAverage)
        case .shareSendStream: return stream(sh.sendWidth, sh.sendHeight, sh.fpsSend)
        case .shareReceiveStream: return stream(sh.receiveWidth, sh.receiveHeight, sh.fpsReceive)
        case .bandwidthSend: return rate(s.bandwidthSend)
        case .bandwidthReceive: return rate(s.bandwidthReceive)
        case .dataCenter: return s.dataCenter
        case .zoomCPU: return s.cpuZoom.map { "\(Int($0.rounded()))%" }
        case .systemCPU: return s.cpuSystem.map { "\(Int($0.rounded()))%" }
        case .zoomMemory: return s.memoryZoom.map { Fmt.bytes($0) }
        case .health: return health == .unavailable ? nil : health.rawValue
        }
    }
}

/// A named set of menu bar values the user can switch between (e.g. "Normal", "DJ").
struct MenuBarProfile: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var items: [MenuBarItem]
    var showLabels = true
    /// Short formats ("923k", "360p", "26fps") so the item fits next to the notch.
    var compact = true

    static let normal = MenuBarProfile(name: "Normal", items: [.bandwidthSend, .videoSendResolution, .videoSendFPS])
    static let dj = MenuBarProfile(name: "DJ", items: [.audioLatencySend, .audioJitterSend, .audioLossSend])

    /// Compact: "↑923k · V↑360p 26fps". Items sharing a label are grouped under it.
    func text(_ s: ZoomStats, health: ConnectionHealth) -> String? {
        guard !items.isEmpty else { return nil }
        var groups: [(label: String, values: [String])] = []
        for item in items {
            let v = item.value(s, health: health, compact: compact) ?? Fmt.dash
            let label = showLabels ? item.shortLabel : ""
            if showLabels, !label.isEmpty, let last = groups.last, last.label == label {
                groups[groups.count - 1].values.append(v)
            } else {
                groups.append((label, [v]))
            }
        }
        let inner = compact ? " " : " · "
        let labelGap = compact ? "" : " "
        return groups.map { g in
            let body = g.values.joined(separator: inner)
            return g.label.isEmpty ? body : "\(g.label)\(labelGap)\(body)"
        }.joined(separator: " · ")
    }

    init(id: UUID = UUID(), name: String, items: [MenuBarItem], showLabels: Bool = true, compact: Bool = true) {
        self.id = id; self.name = name; self.items = items; self.showLabels = showLabels; self.compact = compact
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "Profile"
        items = (try? c.decode([MenuBarItem].self, forKey: .items)) ?? []
        showLabels = (try? c.decode(Bool.self, forKey: .showLabels)) ?? true
        compact = (try? c.decode(Bool.self, forKey: .compact)) ?? true
    }
}
