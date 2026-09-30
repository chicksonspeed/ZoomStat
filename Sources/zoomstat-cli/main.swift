import Foundation
import ZoomStatCore

// zoomstat-cli — proof of concept. Prints Zoom statistics about once per second.
//   --once          print one sample and exit
//   --json          JSON output
//   --interval N    seconds between samples (default 1)
//   --open          open Zoom Settings → Statistics (minimized) first
//   --no-cycle      do not rotate Statistics tabs
//   --mock          use MockZoomStatsProvider
//   --log           also write CSV + JSON Lines to ~/Library/Application Support/ZoomStat/Logs

let args = CommandLine.arguments
func flag(_ f: String) -> Bool { args.contains(f) }
func value(_ f: String) -> String? { args.firstIndex(of: f).flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil } }

setvbuf(stdout, nil, _IOLBF, 0)
var config = ProviderConfiguration()
config.refreshInterval = Double(value("--interval") ?? "") ?? 1
config.cycleTabs = !flag("--no-cycle")
config.cycleTabsWhenVisible = true   // CLI is a diagnostic tool: always rotate

func yesNo(_ b: Bool) -> String { b ? "Yes" : "No" }

func render(_ s: ZoomStats) -> String {
    if flag("--json") {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]
        return String(data: try! e.encode(s), encoding: .utf8)!
    }
    let a = s.audio, v = s.video, sh = s.screenShare
    var o = """
    ── \(ISO8601DateFormatter().string(from: s.timestamp))
    Zoom running: \(yesNo(s.zoomRunning))   Meeting active: \(yesNo(s.meetingActive))   Statistics panel: \(s.statisticsWindowAvailable ? "readable" : "not open")\(s.accessibilityGranted ? "" : "   (Accessibility NOT granted)")

    Data center: \(s.dataCenter ?? Fmt.dash)\(s.dataCenterDetail.map { " (\($0))" } ?? "")
    Network: \(s.networkType ?? Fmt.dash)   Connection: \(s.connectionType ?? Fmt.dash)   Proxy: \(s.proxy ?? Fmt.dash)
    Encryption: \(s.encryption ?? Fmt.dash)   Zoom: \(s.zoomVersion ?? Fmt.dash)

    Bandwidth:  send \(Fmt.rate(s.bandwidthSend))   receive \(Fmt.rate(s.bandwidthReceive))

    Audio:      send / receive
      Frequency  \(Fmt.khz(a.frequencySend)) / \(Fmt.khz(a.frequencyReceive))
      Latency    \(Fmt.ms(a.latencySend)) / \(Fmt.ms(a.latencyReceive))
      Jitter     \(Fmt.ms(a.jitterSend)) / \(Fmt.ms(a.jitterReceive))
      Loss       \(Fmt.loss(a.packetLossSendAverage, a.packetLossSendMax)) / \(Fmt.loss(a.packetLossReceiveAverage, a.packetLossReceiveMax))

    Video:
      Send       \(Fmt.stream(v.sendWidth, v.sendHeight, v.fpsSend))
      Receive    \(Fmt.stream(v.receiveWidth, v.receiveHeight, v.fpsReceive))
      Latency    \(Fmt.ms(v.latencySend)) / \(Fmt.ms(v.latencyReceive))
      Jitter     \(Fmt.ms(v.jitterSend)) / \(Fmt.ms(v.jitterReceive))
      Loss       \(Fmt.loss(v.packetLossSendAverage, v.packetLossSendMax)) / \(Fmt.loss(v.packetLossReceiveAverage, v.packetLossReceiveMax))
      Bitrate    \(Fmt.rate(v.bitrateSend)) / \(Fmt.rate(v.bitrateReceive))

    """
    if sh.hasAnyValue {
        o += """
        Screen sharing:
          Send       \(Fmt.stream(sh.sendWidth, sh.sendHeight, sh.fpsSend))
          Receive    \(Fmt.stream(sh.receiveWidth, sh.receiveHeight, sh.fpsReceive))
          Latency    \(Fmt.ms(sh.latencySend)) / \(Fmt.ms(sh.latencyReceive))

        """
    }
    o += """
    System:
      Zoom CPU     \(Fmt.pct(s.cpuZoom, digits: 0))     System CPU     \(Fmt.pct(s.cpuSystem, digits: 0))
      Zoom memory  \(Fmt.bytes(s.memoryZoom))   System memory  \(Fmt.bytes(s.memorySystem)) of \(Fmt.bytes(s.memoryTotal))
    """
    return o
}

if flag("--mock") {
    let p = MockZoomStatsProvider()
    p.onUpdate = { print(render($0)) }
    p.start()
    RunLoop.main.run()
}

let provider = AccessibilityZoomStatsProvider(configuration: config)
if flag("--open") {
    provider.openZoomStatistics(minimized: true)
    Thread.sleep(forTimeInterval: 2)
}
if flag("--once") {
    // Rotate through all tabs once so every section is populated.
    var s = provider.sampleNow()
    let rounds = s.statisticsWindowAvailable ? 8 : 0
    for _ in 0..<rounds { Thread.sleep(forTimeInterval: config.refreshInterval); s = provider.sampleNow() }
    print(render(s))
    exit(0)
}
let logger = StatsLogger()
if flag("--log") { logger.formats = [.csv, .json]; logger.start() }
provider.onUpdate = { s in
    logger.record(s)
    print(render(s))
}
signal(SIGINT) { _ in exit(0) }
provider.start()
RunLoop.main.run()
