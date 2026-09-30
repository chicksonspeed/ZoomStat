import Foundation

public enum ConnectionHealth: String, Codable, Sendable, CaseIterable {
    case healthy = "Healthy", degraded = "Degraded", poor = "Poor", unavailable = "Unavailable"
}

/// A pair of limits: at/above `degraded` → Degraded, at/above `poor` → Poor.
/// For "lower is worse" metrics (FPS) the comparison is inverted.
public struct Limit: Codable, Equatable, Sendable {
    public var degraded: Double
    public var poor: Double
    public var enabled: Bool
    public init(degraded: Double, poor: Double, enabled: Bool = true) {
        self.degraded = degraded; self.poor = poor; self.enabled = enabled
    }
}

/// Thresholds are data supplied by the app's settings; the core ships none of its own.
public struct HealthThresholds: Codable, Equatable, Sendable {
    public var latencyMs: Limit
    public var jitterMs: Limit
    public var packetLossPercent: Limit
    public var videoFPS: Limit          // lower is worse
    public init(latencyMs: Limit, jitterMs: Limit, packetLossPercent: Limit, videoFPS: Limit) {
        self.latencyMs = latencyMs; self.jitterMs = jitterMs
        self.packetLossPercent = packetLossPercent; self.videoFPS = videoFPS
    }
}

/// Which side of the call quality is judged on.
public enum QualityDirection: String, Codable, CaseIterable, Sendable {
    case send, receive, both
    public var title: String {
        switch self { case .send: "What I send"; case .receive: "What I receive"; case .both: "Both directions" }
    }
}

/// Worst-case metric values for a direction (nil when Zoom reports nothing).
public struct DirectionalMetrics: Sendable {
    public var latency: Double?, jitter: Double?, loss: Double?, fps: Double?

    public init(_ s: ZoomStats, _ d: QualityDirection) {
        let send = d != .receive, recv = d != .send
        func pick(_ a: Double?, _ b: Double?) -> [Double?] { (send ? [a] : []) + (recv ? [b] : []) }
        let media = [s.audio, s.video, s.screenShare]
        latency = media.flatMap { pick($0.latencySend, $0.latencyReceive) }.compactMap { $0 }.max()
        jitter = media.flatMap { pick($0.jitterSend, $0.jitterReceive) }.compactMap { $0 }.max()
        loss = media.flatMap { pick($0.packetLossSendAverage, $0.packetLossReceiveAverage) }.compactMap { $0 }.max()
        // Frame rate: lowest active video stream in the chosen direction.
        fps = pick(s.video.fpsSend, s.video.fpsReceive).compactMap { $0 }.filter { $0 > 0 }.min()
    }
}

public enum HealthEvaluator {
    public static func evaluate(_ s: ZoomStats, _ t: HealthThresholds, direction: QualityDirection = .both) -> ConnectionHealth {
        guard s.zoomRunning, s.meetingActive else { return .unavailable }
        let m = DirectionalMetrics(s, direction)
        let latency = m.latency, jitter = m.jitter, loss = m.loss, fps = m.fps

        var levels: [ConnectionHealth] = []
        func higherIsWorse(_ v: Double?, _ l: Limit) {
            guard l.enabled, let v else { return }
            levels.append(v >= l.poor ? .poor : v >= l.degraded ? .degraded : .healthy)
        }
        higherIsWorse(latency, t.latencyMs)
        higherIsWorse(jitter, t.jitterMs)
        higherIsWorse(loss, t.packetLossPercent)
        if t.videoFPS.enabled, let fps, fps > 0 {
            levels.append(fps <= t.videoFPS.poor ? .poor : fps <= t.videoFPS.degraded ? .degraded : .healthy)
        }
        if levels.isEmpty { return .unavailable }
        if levels.contains(.poor) { return .poor }
        if levels.contains(.degraded) { return .degraded }
        return .healthy
    }
}
