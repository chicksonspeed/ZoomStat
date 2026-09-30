import XCTest
@testable import ZoomStatCore

/// Token lists captured from Zoom 6.5.7 (research/fixtures/ax_*.txt).
final class ParserTests: XCTestCase {
    let p = StatisticsPanelParser()

    func testOverall() {
        let t = ["CPU", "Zoom", "7%", "Overall", "88% (Medium)", "2.4GHz  Cores: 11", "Memory", "Zoom", "1.91 GB",
                 "Overall", "28.83 GB (High)", "36.00 GB", "Bandwidth:", "838 kb/s (send)   1930 kb/s (receive)",
                 "Network type:", "Wired", "Proxy:", "--", "Connection type:", "Cloud", "Data Center:",
                 "You are connected to Zoom Global Network via data centers in the Netherlands (AMS)",
                 "Encryption:", "AES-256-GCM", "Version", "6.5.7 (60598)"]
        var s = ZoomStats()
        XCTAssertTrue(p.apply(tokens: t, tab: .overall, to: &s))
        XCTAssertEqual(s.cpuZoom, 7); XCTAssertEqual(s.cpuSystem, 88)
        XCTAssertEqual(s.memoryZoom, UInt64(1.91 * 1_073_741_824))
        XCTAssertEqual(s.memoryTotal, 36 * 1_073_741_824)
        XCTAssertEqual(s.bandwidthSend, 838); XCTAssertEqual(s.bandwidthReceive, 1930)
        XCTAssertEqual(s.networkType, "Wired"); XCTAssertNil(s.proxy)
        XCTAssertEqual(s.connectionType, "Cloud"); XCTAssertEqual(s.dataCenter, "AMS")
        XCTAssertEqual(s.dataCenterDetail, "Netherlands"); XCTAssertEqual(s.encryption, "AES-256-GCM")
        XCTAssertEqual(s.zoomVersion, "6.5.7 (60598)")
    }

    func testOverallNotReady() {
        var s = ZoomStats()
        XCTAssertFalse(p.apply(tokens: ["CPU", "Memory", "Bandwidth:"], tab: .overall, to: &s))
    }

    func testAudio() {
        let t = ["Item name", "Send", "Receive", "Frequency", "--", "48 KHz", "Latency", "--", "26 ms",
                 "Jitter", "--", "2 ms", "Packet loss - average(max)", "--", "0.0%  (0.0%)"]
        var s = ZoomStats()
        XCTAssertTrue(p.apply(tokens: t, tab: .audio, to: &s))
        XCTAssertNil(s.audio.frequencySend); XCTAssertEqual(s.audio.frequencyReceive, 48)
        XCTAssertNil(s.audio.latencySend); XCTAssertEqual(s.audio.latencyReceive, 26)
        XCTAssertEqual(s.audio.jitterReceive, 2)
        XCTAssertEqual(s.audio.packetLossReceiveAverage, 0); XCTAssertEqual(s.audio.packetLossReceiveMax, 0)
        XCTAssertNil(s.audio.packetLossSendAverage)
    }

    func testVideo() {
        let t = ["Item name", "Send", "Receive", "Latency", "28 ms", "26 ms", "Jitter", "2 ms", "0 ms",
                 "Packet loss - average(max)", "2.8% (11.4%)", "0.0% (0.0%)", "Resolution", "640x360", "1280x720",
                 "Frames per second", "26 fps", "25 fps"]
        var s = ZoomStats()
        XCTAssertTrue(p.apply(tokens: t, tab: .video, to: &s))
        XCTAssertEqual(s.video.latencySend, 28); XCTAssertEqual(s.video.jitterReceive, 0)
        XCTAssertEqual(s.video.packetLossSendAverage, 2.8); XCTAssertEqual(s.video.packetLossSendMax, 11.4)
        XCTAssertEqual(s.video.packetLossAverage, 2.8)
        XCTAssertEqual(s.video.sendWidth, 640); XCTAssertEqual(s.video.receiveHeight, 720)
        XCTAssertEqual(s.video.fpsSend, 26); XCTAssertEqual(s.video.fpsReceive, 25)
        XCTAssertNil(s.video.bitrateSend)
    }

    func testShareAllEmpty() {
        let t = ["Item name", "Send", "Receive", "Latency", "--", "--", "Jitter", "--", "--",
                 "Packet loss - average(max)", "--", "--", "Resolution", "--", "--", "Frames per second", "--", "--"]
        var s = ZoomStats()
        XCTAssertTrue(p.apply(tokens: t, tab: .screenShare, to: &s))
        XCTAssertFalse(s.screenShare.hasAnyValue)
    }

    func testUnits() {
        XCTAssertEqual(StatisticsPanelParser.rates("1.2 Mb/s (send) 900 kb/s (receive)"), [1200, 900])
        XCTAssertEqual(StatisticsPanelParser.bytes("512 MB"), 512 * 1_048_576)
    }

    func testHealthAndAlerts() {
        var s = ZoomStats(); s.zoomRunning = true; s.meetingActive = true
        s.audio.latencyReceive = 44; s.audio.packetLossReceiveAverage = 2.8
        let t = HealthThresholds(latencyMs: Limit(degraded: 150, poor: 300), jitterMs: Limit(degraded: 30, poor: 60),
                                 packetLossPercent: Limit(degraded: 2, poor: 5), videoFPS: Limit(degraded: 15, poor: 8))
        XCTAssertEqual(HealthEvaluator.evaluate(s, t), .degraded)

        let engine = AlertEngine()
        let rule = AlertRule(metric: .packetLoss, enabled: true, threshold: 2, sustainSeconds: 10)
        s.timestamp = Date(timeIntervalSince1970: 0)
        XCTAssertTrue(engine.evaluate(s, rules: [rule]).isEmpty)
        s.timestamp = Date(timeIntervalSince1970: 11)
        XCTAssertEqual(engine.evaluate(s, rules: [rule]).count, 1)
        s.timestamp = Date(timeIntervalSince1970: 20)
        XCTAssertTrue(engine.evaluate(s, rules: [rule]).isEmpty)   // fires once per episode
    }

    func testDirection() {
        var s = ZoomStats(); s.zoomRunning = true; s.meetingActive = true
        s.audio.latencySend = 40; s.audio.latencyReceive = 400
        s.video.fpsSend = 25; s.video.fpsReceive = 5
        let t = HealthThresholds(latencyMs: Limit(degraded: 150, poor: 300), jitterMs: Limit(degraded: 30, poor: 60),
                                 packetLossPercent: Limit(degraded: 2, poor: 5), videoFPS: Limit(degraded: 15, poor: 8))
        XCTAssertEqual(HealthEvaluator.evaluate(s, t, direction: .send), .healthy)
        XCTAssertEqual(HealthEvaluator.evaluate(s, t, direction: .receive), .poor)
        XCTAssertEqual(AlertMetric.latency.value(s, direction: .send), 40)
    }
}
