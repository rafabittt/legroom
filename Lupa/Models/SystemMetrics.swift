import Foundation
import AppKit
import Darwin
import CoreWLAN
import SystemConfiguration

// MARK: - CPU

/// CPU usage from the kernel's accumulated ticks (host_cpu_load_info), like
/// Activity Monitor: the difference between two readings gives the user,
/// system, and idle share of the interval.
struct CPUSample: Equatable {
    let user: Double     // 0…1
    let system: Double
    var busy: Double { user + system }
    var idle: Double { max(0, 1 - busy) }
}

final class CPUMonitor {
    private var last: host_cpu_load_info?
    private(set) var history: [CPUSample] = []
    static let historyLength = 60

    static let chipName: String = {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return String(localized: "Processor") }
        var buf = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        return String(cString: buf)
    }()
    static let coreCount = ProcessInfo.processInfo.activeProcessorCount

    private func read() -> host_cpu_load_info? {
        var info = host_cpu_load_info()
        var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        return r == KERN_SUCCESS ? info : nil
    }

    /// Reads and returns the sample for the interval since the last call (nil on the first).
    func tick() -> CPUSample? {
        guard let now = read() else { return nil }
        defer { last = now }
        guard let prev = last else { return nil }
        func d(_ i: Int) -> Double {
            let a = withUnsafeBytes(of: now.cpu_ticks) { $0.load(fromByteOffset: i * 4, as: UInt32.self) }
            let b = withUnsafeBytes(of: prev.cpu_ticks) { $0.load(fromByteOffset: i * 4, as: UInt32.self) }
            return Double(a &- b)
        }
        let user = d(Int(CPU_STATE_USER)) + d(Int(CPU_STATE_NICE))
        let sys = d(Int(CPU_STATE_SYSTEM))
        let idle = d(Int(CPU_STATE_IDLE))
        let total = user + sys + idle
        guard total > 0 else { return nil }
        let s = CPUSample(user: user / total, system: sys / total)
        history.append(s)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
        return s
    }

    static var uptime: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

// MARK: - Processes

/// A process visible to the user, via `ps`. Only regular apps (with a Dock icon)
/// get the quit button; system processes are shown but never touched.
struct ProcessInfoRow: Identifiable, Equatable {
    let pid: Int32
    let name: String
    let cpu: Double        // %
    let memory: Int64      // bytes (RSS)
    let isApp: Bool
    var id: Int32 { pid }

    var icon: NSImage? {
        guard let app = NSRunningApplication(processIdentifier: pid), let url = app.bundleURL else { return nil }
        return NSWorkspace.shared.icon(forFile: url.path)
    }

    /// Quits with a normal quit request (the app may still ask whether to save).
    func quit() { NSRunningApplication(processIdentifier: pid)?.terminate() }

    /// Processes grouped by app: helpers ("Google Chrome Helper (Renderer)",
    /// "Claude Helper") add up into the owning app, as Activity Monitor does in its
    /// per-app view. Anything that doesn't belong to an open app shows as a system process.
    static func top(byCPU: Bool, limit: Int = 6) -> [ProcessInfoRow] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-Aceo", "pid=,pcpu=,rss=,comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        let myBundle = Bundle.main.bundleIdentifier

        // open regular apps, from longest to shortest name (prefix matching)
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != myBundle }
            .compactMap { a -> (pid: Int32, name: String)? in a.localizedName.map { (a.processIdentifier, $0) } }
            .sorted { $0.name.count > $1.name.count }

        struct Acc { var cpu = 0.0; var mem: Int64 = 0; var name = ""; var isApp = false }
        var byKey: [Int32: Acc] = [:]
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let cpu = Double(parts[1]), let rssKB = Int64(parts[2]) else { continue }
            if pid == me { continue }
            let comm = String(parts[3])
            if let b = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier, b == myBundle { continue }
            var key = pid, name = comm, isApp = false
            if let app = apps.first(where: { $0.pid == pid }) {
                key = app.pid; name = app.name; isApp = true
            } else if let owner = apps.first(where: { comm.hasPrefix($0.name) }) {
                key = owner.pid; name = owner.name; isApp = true
            }
            var acc = byKey[key] ?? Acc()
            acc.cpu += cpu; acc.mem += rssKB * 1024; acc.name = name; acc.isApp = isApp
            byKey[key] = acc
        }
        var rows = byKey.map { ProcessInfoRow(pid: $0.key, name: $0.value.name, cpu: $0.value.cpu, memory: $0.value.mem, isApp: $0.value.isApp) }
        rows.sort { byCPU ? $0.cpu > $1.cpu : $0.memory > $1.memory }
        return Array(rows.prefix(limit))
    }
}

// MARK: - Swap

struct SwapUsage {
    let used: UInt64
    let total: UInt64
    static func read() -> SwapUsage? {
        var x = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &x, &size, nil, 0) == 0 else { return nil }
        return SwapUsage(used: x.xsu_used, total: x.xsu_total)
    }
}

// MARK: - Network

/// Bytes received/sent by the primary interface (getifaddrs), sampled to give
/// the instantaneous speed; Wi‑Fi via CoreWLAN when available.
struct NetworkSample: Equatable {
    let downBytesPerSec: Double
    let upBytesPerSec: Double
}

struct NetTotals: Equatable {
    let received: UInt64
    let sent: UInt64
}

struct WiFiInfo: Equatable {
    let interface: String
    let ssid: String?
    let rssi: Int?
    let transmitRateMbps: Double?
    let security: String?
    let channel: Int?
}

final class NetworkMonitor {
    private var last: (date: Date, interface: String, inBytes: UInt64, outBytes: UInt64)?
    private(set) var history: [NetworkSample] = []
    private(set) var totalIn: UInt64 = 0
    private(set) var totalOut: UInt64 = 0
    static let historyLength = 60

    /// Name of the default route's interface (en0, en1…), or en0 if it can't be determined.
    static func primaryInterface() -> String {
        if let store = SCDynamicStoreCreate(nil, "Legroom" as CFString, nil, nil),
           let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
           let name = dict["PrimaryInterface"] as? String { return name }
        return "en0"
    }

    /// Interface counters (sysctl NET_RT_IFLIST2). For third-party apps macOS hands
    /// out these numbers truncated to 32 bits, so they wrap back to zero every 4 GB
    /// of traffic: `tick` handles the wraparound and `systemTotals` gives the real total.
    private func readBytes(interface: String) -> (UInt64, UInt64)? {
        let index = if_nametoindex(interface)
        guard index != 0 else { return nil }
        var mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, Int32(index)]
        var len = 0
        guard sysctl(&mib, 6, nil, &len, nil, 0) == 0, len > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: len)
        guard sysctl(&mib, 6, &buf, &len, nil, 0) == 0 else { return nil }
        return buf.withUnsafeBytes { raw -> (UInt64, UInt64)? in
            var offset = 0
            while offset + MemoryLayout<if_msghdr>.size <= len {
                let header = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr.self)
                let length = Int(header.ifm_msglen)
                guard length > 0 else { break }
                if Int32(header.ifm_type) == RTM_IFINFO2, offset + MemoryLayout<if_msghdr2>.size <= len {
                    let info = raw.loadUnaligned(fromByteOffset: offset, as: if_msghdr2.self)
                    if UInt32(info.ifm_index) == index { return (info.ifm_data.ifi_ibytes, info.ifm_data.ifi_obytes) }
                }
                offset += length
            }
            return nil
        }
    }

    func tick() -> NetworkSample? {
        let iface = Self.primaryInterface()
        guard let (inB, outB) = readBytes(interface: iface) else { last = nil; return nil }
        totalIn = inB; totalOut = outB
        let now = Date()
        defer { last = (now, iface, inB, outB) }
        // No sample when it can't be compared with the previous reading: the interface
        // changed (Wi‑Fi to Ethernet, VPN) or too much time passed (the Mac slept).
        guard let l = last, l.interface == iface else { return nil }
        let dt = now.timeIntervalSince(l.date)
        guard dt > 0.1, dt < 30,
              let down = Self.delta(from: l.inBytes, to: inB),
              let up = Self.delta(from: l.outBytes, to: outB) else { return nil }
        let s = NetworkSample(downBytesPerSec: Double(down) / dt, upBytesPerSec: Double(up) / dt)
        // A counter that reset for another reason (interface recreated) looks like a
        // wraparound and would produce an absurd spike; no interface exceeds 2.5 GB/s.
        guard s.downBytesPerSec < Self.maxPlausibleRate, s.upBytesPerSec < Self.maxPlausibleRate else { return nil }
        history.append(s)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
        return s
    }

    static let maxPlausibleRate = 2.5e9

    /// Difference between two counter readings. If it went backwards and fit in
    /// 32 bits, it wrapped around; otherwise there's no way to know how much passed.
    static func delta(from old: UInt64, to new: UInt64) -> UInt64? {
        if new >= old { return new - old }
        guard old <= UInt64(UInt32.max) else { return nil }
        return new + (UInt64(UInt32.max) + 1) - old
    }

    /// Total received/sent since the Mac started, from the system's netstat, which
    /// sees the full counter. Runs off the main thread.
    static func systemTotals() -> (received: UInt64, sent: UInt64)? {
        let iface = primaryInterface()
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/netstat")
        task.arguments = ["-ibn", "-I", iface]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        // Link-layer line: Name Mtu <Link#n> [Address] Ipkts Ierrs Ibytes Opkts Oerrs Obytes Coll
        for line in text.split(separator: "\n") where line.contains("<Link#") {
            let f = line.split(separator: " ")
            guard f.count >= 10, f[0] == Substring(iface),
                  let received = UInt64(f[f.count - 5]), let sent = UInt64(f[f.count - 2]) else { continue }
            return (received, sent)
        }
        return nil
    }

    static func wifi() -> WiFiInfo? {
        let iface = primaryInterface()
        guard let w = CWWiFiClient.shared().interface(withName: iface) ?? CWWiFiClient.shared().interface() else { return nil }
        guard w.powerOn() else { return nil }
        let sec: String? = {
            switch w.security() {
            case .none: return String(localized: "Open network")
            case .WEP: return "WEP"
            case .wpaPersonal, .wpaPersonalMixed: return String(localized: "WPA Personal")
            case .wpa2Personal: return String(localized: "WPA2 Personal")
            case .personal: return String(localized: "WPA Personal")
            case .wpa3Personal, .wpa3Transition: return String(localized: "WPA3 Personal")
            case .wpaEnterprise, .wpa2Enterprise, .wpa3Enterprise, .wpaEnterpriseMixed, .enterprise: return String(localized: "Enterprise")
            default: return nil
            }
        }()
        return WiFiInfo(interface: w.interfaceName ?? iface, ssid: w.ssid(), rssi: w.rssiValue() == 0 ? nil : w.rssiValue(),
                        transmitRateMbps: w.transmitRate() > 0 ? w.transmitRate() : nil, security: sec, channel: w.wlanChannel()?.channelNumber)
    }
}

/// On-demand speed test (Cloudflare's public endpoints): downloads one block,
/// uploads another, and measures the latency of a small request. Nothing runs on its own.
enum SpeedTest {
    struct Result: Equatable {
        let downloadMbps: Double
        let uploadMbps: Double
        let latencyMs: Double
        let finished: Date
    }

    static func run() async throws -> Result {
        let session = URLSession(configuration: .ephemeral)
        // latency
        var t0 = Date()
        let (_, _) = try await session.data(from: URL(string: "https://speed.cloudflare.com/__down?bytes=0")!)
        let latency = Date().timeIntervalSince(t0) * 1000
        // download: 40 MB
        t0 = Date()
        let (down, _) = try await session.data(from: URL(string: "https://speed.cloudflare.com/__down?bytes=40000000")!)
        let dt = max(0.001, Date().timeIntervalSince(t0))
        let downMbps = Double(down.count) * 8 / dt / 1_000_000
        // upload: 12 MB of random bytes
        var req = URLRequest(url: URL(string: "https://speed.cloudflare.com/__up")!)
        req.httpMethod = "POST"
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        let payload = Data((0..<12_000_000).map { _ in UInt8.random(in: 0...255) })
        t0 = Date()
        _ = try await session.upload(for: req, from: payload)
        let ut = max(0.001, Date().timeIntervalSince(t0))
        let upMbps = Double(payload.count) * 8 / ut / 1_000_000
        return Result(downloadMbps: downMbps, uploadMbps: upMbps, latencyMs: latency, finished: Date())
    }
}

extension Format {
    static func mbps(_ v: Double) -> String { v >= 100 ? "\(v.rounded().safeInt) Mb/s" : "\((v.isFinite ? v : 0).formatted(.number.precision(.fractionLength(1)))) Mb/s" }
    static func rate(_ bytesPerSec: Double) -> String { bytes(Int64(max(0, bytesPerSec).safeInt)) + "/s" }
    static func percent(_ f: Double) -> String { "\((f * 100).rounded().safeInt)%" }
    static func uptime(_ t: TimeInterval) -> String {
        let secs = max(0, t).safeInt
        let d = secs / 86_400, h = (secs % 86_400) / 3600, m = (secs % 3600) / 60
        if d > 0 { return String(localized: "\(d) d \(h) h") }
        if h > 0 { return String(localized: "\(h) h \(m) min") }
        return String(localized: "\(m) min")
    }
}
