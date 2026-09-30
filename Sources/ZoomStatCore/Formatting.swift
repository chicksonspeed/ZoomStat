import Foundation

/// Display helpers shared by the CLI and the app. nil → "—".
public enum Fmt {
    public static let dash = "—"

    public static func ms(_ v: Double?) -> String { v.map { "\(Int($0.rounded())) ms" } ?? dash }
    public static func pct(_ v: Double?, digits: Int = 1) -> String {
        guard let v else { return dash }
        return digits == 0 || v == v.rounded() && v >= 10 ? "\(Int(v.rounded()))%" : String(format: "%.\(digits)f%%", v)
    }
    public static func fps(_ v: Double?) -> String { v.map { "\(Int($0.rounded())) fps" } ?? dash }
    public static func khz(_ v: Double?) -> String { v.map { String(format: $0 == $0.rounded() ? "%.0f kHz" : "%.1f kHz", $0) } ?? dash }

    public static func rate(_ kbps: Double?) -> String {
        guard let k = kbps else { return dash }
        return k >= 1000 ? String(format: "%.1f Mb/s", k / 1000) : "\(Int(k.rounded())) kb/s"
    }

    public static func bytes(_ b: UInt64?) -> String {
        guard let b else { return dash }
        let gb = Double(b) / 1_073_741_824
        return gb >= 1 ? String(format: "%.2f GB", gb) : String(format: "%.0f MB", Double(b) / 1_048_576)
    }

    public static func res(_ w: Int?, _ h: Int?) -> String? {
        guard let w, let h else { return nil }
        return "\(w)×\(h)"
    }

    /// "640×360 @ 26 fps"
    public static func stream(_ w: Int?, _ h: Int?, _ f: Double?) -> String {
        switch (res(w, h), f) {
        case let (r?, f?): return "\(r) @ \(Int(f.rounded())) fps"
        case let (r?, nil): return r
        case let (nil, f?): return "\(Int(f.rounded())) fps"
        default: return dash
        }
    }

    public static func loss(_ avg: Double?, _ max: Double?) -> String {
        guard let avg else { return dash }
        if let max, max > avg { return "\(pct(avg)) (max \(pct(max)))" }
        return pct(avg)
    }
}
