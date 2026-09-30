import Foundation

public enum AlertMetric: String, Codable, CaseIterable, Sendable, Identifiable {
    case latency, jitter, packetLoss, lowVideoFPS, zoomCPU, systemCPU, memoryPressure
    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .latency: "High latency"
        case .jitter: "High jitter"
        case .packetLoss: "Packet loss"
        case .lowVideoFPS: "Low video frame rate"
        case .zoomCPU: "High Zoom CPU"
        case .systemCPU: "High system CPU"
        case .memoryPressure: "High memory use"
        }
    }

    public var unit: String {
        switch self {
        case .latency, .jitter: "ms"
        case .lowVideoFPS: "fps"
        case .packetLoss, .zoomCPU, .systemCPU, .memoryPressure: "%"
        }
    }

    public var lowerIsWorse: Bool { self == .lowVideoFPS }

    public func value(_ s: ZoomStats, direction: QualityDirection = .both) -> Double? {
        let m = DirectionalMetrics(s, direction)
        return switch self {
        case .latency: m.latency
        case .jitter: m.jitter
        case .packetLoss: m.loss
        case .lowVideoFPS: m.fps
        case .zoomCPU: s.cpuZoom
        case .systemCPU: s.cpuSystem
        case .memoryPressure:
            s.memoryTotal.flatMap { t -> Double? in
                guard t > 0, let u = s.memorySystem else { return nil }
                return Double(u) / Double(t) * 100
            }
        }
    }
}

public struct AlertRule: Codable, Equatable, Sendable, Identifiable {
    public var metric: AlertMetric
    public var enabled: Bool
    public var threshold: Double
    /// Condition must hold continuously this long before notifying.
    public var sustainSeconds: Double
    public var id: AlertMetric { metric }
    public init(metric: AlertMetric, enabled: Bool, threshold: Double, sustainSeconds: Double) {
        self.metric = metric; self.enabled = enabled; self.threshold = threshold; self.sustainSeconds = sustainSeconds
    }
}

public struct FiredAlert: Sendable {
    public var rule: AlertRule
    public var value: Double
}

/// Fires once per sustained episode; re-arms after the condition clears.
public final class AlertEngine {
    private var since: [AlertMetric: Date] = [:]
    private var fired: Set<AlertMetric> = []
    public init() {}

    public func reset() { since = [:]; fired = [] }

    public func evaluate(_ s: ZoomStats, rules: [AlertRule], direction: QualityDirection = .both) -> [FiredAlert] {
        guard s.meetingActive || [.zoomCPU, .systemCPU, .memoryPressure].contains(where: { m in rules.contains { $0.metric == m && $0.enabled } }) else {
            reset(); return []
        }
        var out: [FiredAlert] = []
        for r in rules {
            let meetingMetric = ![.zoomCPU, .systemCPU, .memoryPressure].contains(r.metric)
            guard r.enabled, !(meetingMetric && !s.meetingActive), let v = r.metric.value(s, direction: direction) else {
                since[r.metric] = nil; fired.remove(r.metric); continue
            }
            let bad = r.metric.lowerIsWorse ? v < r.threshold : v > r.threshold
            if !bad { since[r.metric] = nil; fired.remove(r.metric); continue }
            let start = since[r.metric] ?? s.timestamp
            since[r.metric] = start
            if !fired.contains(r.metric), s.timestamp.timeIntervalSince(start) >= r.sustainSeconds {
                fired.insert(r.metric)
                out.append(FiredAlert(rule: r, value: v))
            }
        }
        return out
    }
}
