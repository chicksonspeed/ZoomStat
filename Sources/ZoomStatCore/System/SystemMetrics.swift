import Foundation
import Darwin
import Network
import SystemConfiguration

/// Native, public-API metrics. Used as fallbacks when Zoom's panel is not readable.
public final class SystemMetrics {
    private var lastHost: (busy: UInt64, total: UInt64)?
    private var lastProc: (ns: UInt64, at: UInt64)?
    private var lastPID: pid_t?
    private let timebase: mach_timebase_info_data_t = { var t = mach_timebase_info_data_t(); mach_timebase_info(&t); return t }()
    private let cores = Double(ProcessInfo.processInfo.activeProcessorCount)
    private let pathMonitor = NWPathMonitor()
    private var path: NWPath?
    private let lock = NSLock()

    public init() {
        pathMonitor.pathUpdateHandler = { [weak self] p in
            self?.lock.lock(); self?.path = p; self?.lock.unlock()
        }
        pathMonitor.start(queue: DispatchQueue(label: "ZoomStat.path"))
    }

    deinit { pathMonitor.cancel() }

    /// Forget deltas (after sleep/wake or a Zoom restart) so the next reading is not skewed.
    public func reset() { lastHost = nil; lastProc = nil }

    // MARK: CPU

    public func systemCPU() -> Double? {
        var count: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &info, &infoCount) == KERN_SUCCESS,
              let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride)) }
        var busy: UInt64 = 0, total: UInt64 = 0
        for cpu in 0..<Int(count) {
            let base = cpu * Int(CPU_STATE_MAX)
            let user = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)]))
            let sys = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)]))
            let nice = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            let idle = UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)]))
            busy += user + sys + nice; total += user + sys + nice + idle
        }
        defer { lastHost = (busy, total) }
        guard let last = lastHost, total > last.total, busy >= last.busy else { return nil }
        return Double(busy - last.busy) / Double(total - last.total) * 100
    }

    /// CPU of Zoom (main process + helpers), as % of the whole machine like Zoom's panel.
    public func processCPU(pid: pid_t) -> Double? {
        if pid != lastPID { lastProc = nil; lastPID = pid }
        let pids = [pid] + childPIDs(pid)
        var ns: UInt64 = 0
        for p in pids { if let r = rusage(p) { ns += (r.ri_user_time + r.ri_system_time) * UInt64(timebase.numer) / UInt64(timebase.denom) } }
        let now = mach_absolute_time() * UInt64(timebase.numer) / UInt64(timebase.denom)
        defer { lastProc = (ns, now) }
        guard let last = lastProc, now > last.at, ns >= last.ns else { return nil }
        return Double(ns - last.ns) / Double(now - last.at) / cores * 100
    }

    public func processMemory(pid: pid_t) -> UInt64? {
        let pids = [pid] + childPIDs(pid)
        let values = pids.compactMap { rusage($0)?.ri_phys_footprint }
        return values.isEmpty ? nil : values.reduce(0, +)
    }

    private func rusage(_ pid: pid_t) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let rc = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        return rc == 0 ? info : nil
    }

    private func childPIDs(_ pid: pid_t) -> [pid_t] {
        var buf = [pid_t](repeating: 0, count: 64)
        let n = proc_listchildpids(pid, &buf, Int32(buf.count * MemoryLayout<pid_t>.size))
        return n > 0 ? Array(buf.prefix(Int(n))) : []
    }

    // MARK: Memory

    /// (used, total) bytes. "Used" follows Activity Monitor: app memory + wired + compressed.
    public func systemMemory() -> (UInt64, UInt64)? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let rc = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count) }
        }
        guard rc == KERN_SUCCESS else { return nil }
        let page = UInt64(vm_kernel_page_size)
        let total = ProcessInfo.processInfo.physicalMemory
        let app = UInt64(stats.internal_page_count) - min(UInt64(stats.internal_page_count), UInt64(stats.purgeable_count))
        let used = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return (min(used, total), total)
    }

    // MARK: Network

    public func networkType() -> String? {
        lock.lock(); let p = path; lock.unlock()
        guard let p, p.status == .satisfied else { return p == nil ? nil : "Offline" }
        if p.usesInterfaceType(.wiredEthernet) { return "Wired" }
        if p.usesInterfaceType(.wifi) { return "Wi-Fi" }
        if p.usesInterfaceType(.cellular) { return "Cellular" }
        return "Other"
    }

    /// Short description of the system proxy, or "None".
    public func proxy() -> String? {
        guard let d = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else { return nil }
        func on(_ k: String) -> Bool { (d[k] as? Int) == 1 }
        if on("ProxyAutoConfigEnable") { return "Auto (PAC)" }
        if on("HTTPSEnable"), let h = d["HTTPSProxy"] as? String { return "HTTPS \(h):\(d["HTTPSPort"] ?? "")" }
        if on("HTTPEnable"), let h = d["HTTPProxy"] as? String { return "HTTP \(h):\(d["HTTPPort"] ?? "")" }
        if on("SOCKSEnable"), let h = d["SOCKSProxy"] as? String { return "SOCKS \(h):\(d["SOCKSPort"] ?? "")" }
        return "None"
    }

    public static func zoomVersion(bundleURL: URL?) -> String? {
        guard let url = bundleURL, let info = Bundle(url: url)?.infoDictionary else { return nil }
        let short = info["CFBundleShortVersionString"] as? String
        let build = info["CFBundleVersion"] as? String
        switch (short, build) {
        case let (s?, b?) where s != b && !s.contains(b): return "\(s) (\(b))"
        case let (s?, _): return s
        default: return nil
        }
    }
}
