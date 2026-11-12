import Foundation

/// The Mac's temperatures, read from the sensors macOS publishes through IOHID
/// (the same path apps like Stats use). There's no public API for this: the
/// functions are resolved at runtime and, if they're missing (Intel Mac or a
/// future macOS version), everything becomes nil and the temperature disappears
/// from the screen.
///
/// - Chip: average of the "tdie" sensors (points inside the M chip).
/// - Battery and SSD when the Mac publishes those sensors.
struct ThermalReading: Equatable {
    var chip: Double?
    var chipMax: Double?
    var battery: Double?
    var ssd: Double?
    var state: ProcessInfo.ThermalState

    /// How macOS rates the heat right now (this is what decides whether to throttle).
    var stateLabel: String {
        switch state {
        case .nominal: return String(localized: "Normal temperature")
        case .fair: return String(localized: "A bit warm")
        case .serious: return String(localized: "Hot: the Mac is slowing down")
        case .critical: return String(localized: "Very hot: the Mac is slowing down a lot")
        @unknown default: return String(localized: "Normal temperature")
        }
    }
}

enum Thermal {
    private typealias CreateFn = @convention(c) (CFAllocator?) -> Unmanaged<AnyObject>?
    private typealias SetMatchFn = @convention(c) (AnyObject, CFDictionary) -> Int32
    private typealias CopyServicesFn = @convention(c) (AnyObject) -> Unmanaged<CFArray>?
    private typealias CopyPropertyFn = @convention(c) (AnyObject, CFString) -> Unmanaged<CFTypeRef>?
    private typealias CopyEventFn = @convention(c) (AnyObject, Int64, Int32, Int64) -> Unmanaged<AnyObject>?
    private typealias GetFloatFn = @convention(c) (AnyObject, UInt32) -> Double

    private struct API {
        let copyServices: CopyServicesFn
        let copyProperty: CopyPropertyFn
        let copyEvent: CopyEventFn
        let getFloat: GetFloatFn
        let client: AnyObject
    }

    private static let temperatureEvent: Int64 = 15   // kIOHIDEventTypeTemperature

    nonisolated(unsafe) private static let api: API? = {
        guard let h = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let c = dlsym(h, "IOHIDEventSystemClientCreate"),
              let m = dlsym(h, "IOHIDEventSystemClientSetMatching"),
              let s = dlsym(h, "IOHIDEventSystemClientCopyServices"),
              let p = dlsym(h, "IOHIDServiceClientCopyProperty"),
              let e = dlsym(h, "IOHIDServiceClientCopyEvent"),
              let f = dlsym(h, "IOHIDEventGetFloatValue") else { return nil }
        let create = unsafeBitCast(c, to: CreateFn.self)
        guard let client = create(kCFAllocatorDefault)?.takeRetainedValue() else { return nil }
        // temperature sensors: Apple usage page 0xff00, usage 5
        _ = unsafeBitCast(m, to: SetMatchFn.self)(client, ["PrimaryUsagePage": 0xff00, "PrimaryUsage": 5] as CFDictionary)
        return API(copyServices: unsafeBitCast(s, to: CopyServicesFn.self),
                   copyProperty: unsafeBitCast(p, to: CopyPropertyFn.self),
                   copyEvent: unsafeBitCast(e, to: CopyEventFn.self),
                   getFloat: unsafeBitCast(f, to: GetFloatFn.self),
                   client: client)
    }()

    private static let lock = NSLock()

    /// Reads all sensors now. Cheap (a few ms); can run off the main thread.
    static func read() -> ThermalReading {
        var out = ThermalReading(state: ProcessInfo.processInfo.thermalState)
        guard let api else { return out }
        lock.lock(); defer { lock.unlock() }
        guard let services = api.copyServices(api.client)?.takeRetainedValue() as? [AnyObject] else { return out }
        var die: [Double] = [], battery: [Double] = [], ssd: [Double] = []
        for s in services {
            guard let name = api.copyProperty(s, "Product" as CFString)?.takeRetainedValue() as? String,
                  let event = api.copyEvent(s, temperatureEvent, 0, 0)?.takeRetainedValue() else { continue }
            let t = api.getFloat(event, UInt32(temperatureEvent << 16))
            guard t > 0, t < 130 else { continue }   // discard nonsensical readings
            let n = name.lowercased()
            if n.contains("tdie") { die.append(t) }
            else if n.contains("battery") { battery.append(t) }
            else if n.contains("nand") { ssd.append(t) }
        }
        if !die.isEmpty { out.chip = die.reduce(0, +) / Double(die.count); out.chipMax = die.max() }
        if !battery.isEmpty { out.battery = battery.max() }
        if !ssd.isEmpty { out.ssd = ssd.max() }
        return out
    }
}

extension Format {
    static func celsius(_ t: Double) -> String { "\(Int(t.rounded())) °C" }
}
