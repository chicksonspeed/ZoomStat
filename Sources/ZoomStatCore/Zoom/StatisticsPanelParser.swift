import Foundation

public enum StatisticsTab: String, CaseIterable, Codable, Sendable {
    case overall, audio, video, screenShare
}

/// Converts the flattened text of Zoom's Statistics panel into `ZoomStats` fields.
/// Label-driven: independent of AX nesting (Zoom mixes grouped and flat rows).
public struct StatisticsPanelParser: Sendable {
    public var labels: ZoomUILabels
    public init(labels: ZoomUILabels = .english) { self.labels = labels }

    /// Returns false when the panel had labels but no values yet (right after a tab switch).
    @discardableResult
    public func apply(tokens raw: [String], tab: StatisticsTab, to stats: inout ZoomStats) -> Bool {
        let tokens = raw.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        switch tab {
        case .overall: return applyOverall(tokens, &stats)
        case .audio: return applyMedia(tokens, &stats.audio)
        case .video: return applyMedia(tokens, &stats.video)
        case .screenShare: return applyMedia(tokens, &stats.screenShare)
        }
    }

    // MARK: Overall

    private func applyOverall(_ t: [String], _ s: inout ZoomStats) -> Bool {
        var section = ""
        var found = false
        var i = 0
        func next() -> String? { i + 1 < t.count ? t[i + 1] : nil }
        while i < t.count {
            let tok = t[i]
            switch tok {
            case labels.cpu, labels.memory:
                section = tok
            case labels.zoomRow, labels.overallRow:
                guard let v = next(), !isLabel(v) else { break }
                found = true
                if section == labels.cpu {
                    if tok == labels.zoomRow { s.cpuZoom = Self.number(v) } else { s.cpuSystem = Self.number(v) }
                } else if section == labels.memory {
                    if tok == labels.zoomRow { s.memoryZoom = Self.bytes(v) } else {
                        s.memorySystem = Self.bytes(v)
                        // The token after the overall memory value is the installed total.
                        if i + 2 < t.count, let total = Self.bytes(t[i + 2]), !isLabel(t[i + 2]) { s.memoryTotal = total }
                    }
                }
                i += 1
            case labels.bandwidth:
                if let v = next() {
                    let rates = Self.rates(v)
                    if rates.count >= 2 { s.bandwidthSend = rates[0]; s.bandwidthReceive = rates[1]; found = true }
                    i += 1
                }
            case labels.networkType: s.networkType = text(next()); i += 1
            case labels.proxy: s.proxy = text(next()); i += 1
            case labels.connectionType: s.connectionType = text(next()); i += 1
            case labels.encryption: s.encryption = text(next()); i += 1
            case labels.version: if let v = text(next()) { s.zoomVersion = v }; i += 1
            case labels.dataCenter:
                if let v = text(next()) {
                    let (code, detail) = Self.dataCenter(v)
                    s.dataCenter = code ?? v
                    s.dataCenterDetail = detail
                }
                i += 1
            default: break
            }
            i += 1
        }
        return found
    }

    private func isLabel(_ s: String) -> Bool {
        [labels.cpu, labels.memory, labels.zoomRow, labels.overallRow, labels.bandwidth, labels.networkType,
         labels.proxy, labels.connectionType, labels.dataCenter, labels.encryption, labels.version].contains(s)
    }

    private func text(_ v: String?) -> String? {
        guard let v, !labels.emptyValues.contains(v), !isLabel(v) else { return nil }
        return v
    }

    // MARK: Media tabs

    private func applyMedia(_ t: [String], _ m: inout MediaStats) -> Bool {
        var found = false
        var fresh = MediaStats()
        func pair(_ label: (String) -> Bool) -> (String?, String?)? {
            guard let idx = t.firstIndex(where: label) else { return nil }
            let a = idx + 1 < t.count ? t[idx + 1] : nil
            let b = idx + 2 < t.count ? t[idx + 2] : nil
            return (clean(a), clean(b))
        }
        if let (a, b) = pair({ $0 == labels.frequency }) {
            fresh.frequencySend = a.flatMap(Self.number); fresh.frequencyReceive = b.flatMap(Self.number)
        }
        if let (a, b) = pair({ $0 == labels.latency }) {
            fresh.latencySend = a.flatMap(Self.number); fresh.latencyReceive = b.flatMap(Self.number)
        }
        if let (a, b) = pair({ $0 == labels.jitter }) {
            fresh.jitterSend = a.flatMap(Self.number); fresh.jitterReceive = b.flatMap(Self.number)
        }
        if let (a, b) = pair({ $0.hasPrefix(labels.packetLoss) }) {
            let sa = a.map(Self.numbers) ?? [], rb = b.map(Self.numbers) ?? []
            fresh.packetLossSendAverage = sa.first; fresh.packetLossSendMax = sa.count > 1 ? sa[1] : nil
            fresh.packetLossReceiveAverage = rb.first; fresh.packetLossReceiveMax = rb.count > 1 ? rb[1] : nil
        }
        if let (a, b) = pair({ $0 == labels.resolution }) {
            if let r = a.flatMap(Self.resolution) { fresh.sendWidth = r.0; fresh.sendHeight = r.1 }
            if let r = b.flatMap(Self.resolution) { fresh.receiveWidth = r.0; fresh.receiveHeight = r.1 }
        }
        if let (a, b) = pair({ $0 == labels.fps }) {
            fresh.fpsSend = a.flatMap(Self.number); fresh.fpsReceive = b.flatMap(Self.number)
        }
        if let (a, b) = pair({ $0.hasPrefix(labels.bitrate) }) {
            fresh.bitrateSend = a.flatMap { Self.rates($0).first ?? Self.number($0) }
            fresh.bitrateReceive = b.flatMap { Self.rates($0).first ?? Self.number($0) }
        }
        // Table present (header or any row label) → the tab is valid even if every cell is "--".
        found = t.contains(labels.mediaHeader) && t.contains(labels.latency)
        if found { m = fresh }
        return found
    }

    private func clean(_ v: String?) -> String? {
        guard let v, !labels.emptyValues.contains(v) else { return nil }
        let rowLabels = [labels.frequency, labels.latency, labels.jitter, labels.resolution, labels.fps]
        if rowLabels.contains(v) || v.hasPrefix(labels.packetLoss) { return nil }
        return v
    }

    // MARK: Value parsing (static so tests can use them)

    static let numberRegex = try! NSRegularExpression(pattern: #"[-+]?\d+(?:[.,]\d+)?"#)

    public static func numbers(_ s: String) -> [Double] {
        let ns = s as NSString
        return numberRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap {
            Double(ns.substring(with: $0.range).replacingOccurrences(of: ",", with: "."))
        }
    }

    public static func number(_ s: String) -> Double? { numbers(s).first }

    /// "1.91 GB" → bytes (binary units, matching Zoom's "36.00 GB" for a 36 GB Mac).
    public static func bytes(_ s: String) -> UInt64? {
        guard let n = number(s) else { return nil }
        let u = s.uppercased()
        let mult: Double
        if u.contains("TB") { mult = pow(1024, 4) }
        else if u.contains("GB") { mult = pow(1024, 3) }
        else if u.contains("MB") { mult = pow(1024, 2) }
        else if u.contains("KB") { mult = 1024 }
        else { return nil }
        return UInt64(n * mult)
    }

    static let rateRegex = try! NSRegularExpression(pattern: #"([\d.,]+)\s*([kKmMgG])?b(?:ps|/s)"#)

    /// "838 kb/s (send)   1930 kb/s (receive)" → [838, 1930] in kb/s.
    public static func rates(_ s: String) -> [Double] {
        let ns = s as NSString
        return rateRegex.matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            guard let v = Double(ns.substring(with: m.range(at: 1)).replacingOccurrences(of: ",", with: ".")) else { return nil }
            let unit = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)).lowercased() : ""
            switch unit {
            case "m": return v * 1000
            case "g": return v * 1_000_000
            case "k": return v
            default: return v / 1000
            }
        }
    }

    public static func resolution(_ s: String) -> (Int, Int)? {
        let parts = s.split(whereSeparator: { $0 == "x" || $0 == "×" || $0 == "X" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) else { return nil }
        return (w, h)
    }

    /// "…via data centers in the Netherlands (AMS)" → ("AMS", "Netherlands")
    public static func dataCenter(_ s: String) -> (String?, String?) {
        guard let open = s.range(of: "(", options: .backwards),
              let close = s.range(of: ")", options: .backwards), open.upperBound <= close.lowerBound else { return (nil, nil) }
        let code = String(s[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespaces)
        var detail: String?
        let head = s[..<open.lowerBound]
        if let r = head.range(of: " in ", options: .backwards) {
            var d = String(head[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            if d.hasPrefix("the ") { d.removeFirst(4) }
            detail = d.isEmpty ? nil : d
        }
        return (code.isEmpty ? nil : code, detail)
    }
}
