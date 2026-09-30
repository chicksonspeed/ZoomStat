import Foundation

/// In-memory rolling history for the current meeting (cleared when a meeting ends).
public final class MeetingHistory {
    public private(set) var samples: [ZoomStats] = []
    public let capacity: Int
    private var inMeeting = false
    public init(capacity: Int = 7200) { self.capacity = capacity }

    public func append(_ s: ZoomStats) {
        if s.meetingActive && !inMeeting { samples.removeAll() }
        inMeeting = s.meetingActive
        guard s.meetingActive else { return }
        samples.append(s)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
    }
}

public struct LogFormats: OptionSet, Codable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let csv = LogFormats(rawValue: 1)
    public static let json = LogFormats(rawValue: 2)
}

/// Writes technical statistics only — the model carries no names, chat or media.
/// One CSV and/or JSON Lines file per meeting in ~/Library/Application Support/ZoomStat/Logs.
public final class StatsLogger {
    public static var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ZoomStat/Logs", isDirectory: true)
    }

    public var formats: LogFormats = [.csv]
    public private(set) var isLogging = false
    public private(set) var currentFiles: [URL] = []
    private var csv: FileHandle?
    private var json: FileHandle?
    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e
    }()

    public init() {}

    public func start() { isLogging = true }

    public func stop() { isLogging = false; closeFiles() }

    public func record(_ s: ZoomStats) {
        guard isLogging else { return }
        guard s.meetingActive else { closeFiles(); return }   // one file set per meeting
        if csv == nil && json == nil { openFiles(at: s.timestamp) }
        if let csv { csv.write(Data((Self.csvRow(s) + "\n").utf8)) }
        if let json, var d = try? encoder.encode(s) { d.append(0x0A); json.write(d) }
    }

    private func openFiles(at date: Date) {
        let dir = Self.directory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd_HHmmss"; f.locale = Locale(identifier: "en_US_POSIX")
        let base = "meeting_\(f.string(from: date))"
        currentFiles = []
        if formats.contains(.csv) {
            let url = dir.appendingPathComponent(base + ".csv")
            FileManager.default.createFile(atPath: url.path, contents: Data((Self.csvHeader + "\n").utf8))
            csv = try? FileHandle(forWritingTo: url); csv?.seekToEndOfFile(); currentFiles.append(url)
        }
        if formats.contains(.json) {
            let url = dir.appendingPathComponent(base + ".jsonl")
            FileManager.default.createFile(atPath: url.path, contents: nil)
            json = try? FileHandle(forWritingTo: url); currentFiles.append(url)
        }
    }

    private func closeFiles() {
        try? csv?.close(); try? json?.close(); csv = nil; json = nil
    }

    static let columns: [(String, (ZoomStats) -> String)] = {
        func d(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "" }
        func i(_ v: Int?) -> String { v.map(String.init) ?? "" }
        func u(_ v: UInt64?) -> String { v.map(String.init) ?? "" }
        func s(_ v: String?) -> String {
            guard let v else { return "" }
            return v.contains(",") || v.contains("\"") ? "\"" + v.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : v
        }
        let iso = ISO8601DateFormatter()
        var c: [(String, (ZoomStats) -> String)] = [
            ("timestamp", { iso.string(from: $0.timestamp) }),
            ("cpu_zoom", { d($0.cpuZoom) }), ("cpu_system", { d($0.cpuSystem) }),
            ("mem_zoom_bytes", { u($0.memoryZoom) }), ("mem_system_bytes", { u($0.memorySystem) }),
            ("bw_send_kbps", { d($0.bandwidthSend) }), ("bw_recv_kbps", { d($0.bandwidthReceive) }),
        ]
        for (p, k) in [("audio", \ZoomStats.audio), ("video", \ZoomStats.video), ("share", \ZoomStats.screenShare)] {
            c += [
                ("\(p)_latency_send_ms", { d($0[keyPath: k].latencySend) }), ("\(p)_latency_recv_ms", { d($0[keyPath: k].latencyReceive) }),
                ("\(p)_jitter_send_ms", { d($0[keyPath: k].jitterSend) }), ("\(p)_jitter_recv_ms", { d($0[keyPath: k].jitterReceive) }),
                ("\(p)_loss_send_avg", { d($0[keyPath: k].packetLossSendAverage) }), ("\(p)_loss_send_max", { d($0[keyPath: k].packetLossSendMax) }),
                ("\(p)_loss_recv_avg", { d($0[keyPath: k].packetLossReceiveAverage) }), ("\(p)_loss_recv_max", { d($0[keyPath: k].packetLossReceiveMax) }),
            ]
            if p == "audio" {
                c += [("audio_freq_send_khz", { d($0.audio.frequencySend) }), ("audio_freq_recv_khz", { d($0.audio.frequencyReceive) })]
            } else {
                c += [
                    ("\(p)_send_res", { st in Fmt.res(st[keyPath: k].sendWidth, st[keyPath: k].sendHeight).map { $0.replacingOccurrences(of: "×", with: "x") } ?? "" }),
                    ("\(p)_recv_res", { st in Fmt.res(st[keyPath: k].receiveWidth, st[keyPath: k].receiveHeight).map { $0.replacingOccurrences(of: "×", with: "x") } ?? "" }),
                    ("\(p)_fps_send", { d($0[keyPath: k].fpsSend) }), ("\(p)_fps_recv", { d($0[keyPath: k].fpsReceive) }),
                ]
            }
        }
        c += [("data_center", { s($0.dataCenter) }), ("network_type", { s($0.networkType) }),
              ("connection_type", { s($0.connectionType) }), ("zoom_version", { s($0.zoomVersion) })]
        return c
    }()

    public static var csvHeader: String { columns.map(\.0).joined(separator: ",") }
    public static func csvRow(_ s: ZoomStats) -> String { columns.map { $0.1(s) }.joined(separator: ",") }
}
