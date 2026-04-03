import Foundation
import CIOKit

// MARK: - IOReport Private API (same API used by iStats, Stats.app, etc.)

@_silgen_name("IOReportCopyChannelsInGroup")
private func IOReportCopyChannelsInGroup(
    _ group: NSString, _ subgroup: NSString?,
    _ a: UInt64, _ b: UInt64, _ c: UInt64
) -> Unmanaged<NSMutableDictionary>?

@_silgen_name("IOReportMergeChannels")
private func IOReportMergeChannels(
    _ a: NSMutableDictionary, _ b: NSMutableDictionary, _ c: CFTypeRef?
)

@_silgen_name("IOReportCreateSubscription")
private func IOReportCreateSubscription(
    _ a: AnyObject?, _ b: NSMutableDictionary,
    _ c: AutoreleasingUnsafeMutablePointer<NSMutableDictionary?>,
    _ d: UInt64, _ e: CFTypeRef?
) -> Unmanaged<AnyObject>?

@_silgen_name("IOReportCreateSamples")
private func IOReportCreateSamples(
    _ sub: AnyObject, _ ch: NSMutableDictionary, _ a: CFTypeRef?
) -> Unmanaged<NSDictionary>?

@_silgen_name("IOReportCreateSamplesDelta")
private func IOReportCreateSamplesDelta(
    _ prev: NSDictionary, _ cur: NSDictionary, _ a: CFTypeRef?
) -> Unmanaged<NSDictionary>?

@_silgen_name("IOReportChannelGetGroup")
private func IOReportChannelGetGroup(_ ch: NSDictionary) -> Unmanaged<NSString>?

@_silgen_name("IOReportChannelGetSubGroup")
private func IOReportChannelGetSubGroup(_ ch: NSDictionary) -> Unmanaged<NSString>?

@_silgen_name("IOReportChannelGetChannelName")
private func IOReportChannelGetChannelName(_ ch: NSDictionary) -> Unmanaged<NSString>?

@_silgen_name("IOReportSimpleGetIntegerValue")
private func IOReportSimpleGetIntegerValue(
    _ ch: NSDictionary, _ err: UnsafeMutablePointer<Int32>?
) -> Int64

@_silgen_name("IOReportStateGetCount")
private func IOReportStateGetCount(_ ch: NSDictionary) -> Int32

@_silgen_name("IOReportStateGetNameForIndex")
private func IOReportStateGetNameForIndex(
    _ ch: NSDictionary, _ i: Int32
) -> Unmanaged<NSString>?

@_silgen_name("IOReportStateGetResidency")
private func IOReportStateGetResidency(_ ch: NSDictionary, _ i: Int32) -> Int64

// MARK: - Service

/// Reads real-time CPU/GPU power and frequency via IOReport (no root required).
final class PowerMetricsService: @unchecked Sendable {
    struct Result {
        var powerReadings: [PowerReading] = []
        var frequencyReadings: [FrequencyReading] = []
    }

    private var subscription: AnyObject?
    private var subscribedChannels: NSMutableDictionary?
    private var previousSample: NSDictionary?
    private var previousTime: UInt64 = 0
    private var available = true

    // DVFS frequency tables from IORegistry (MHz, indexed by OPP index)
    private var dvfsTables: [Int: [Double]] = [:]
    private var gpuFreqTable: [Double] = []
    private var freqTablesLoaded = false

    init() {
        setupSubscription()
    }

    func sample() -> Result? {
        guard available,
              let sub = subscription,
              let channels = subscribedChannels else { return nil }

        guard let current = IOReportCreateSamples(sub, channels, nil)?
            .takeRetainedValue() else { return nil }

        let now = mach_absolute_time()
        let prev = previousSample
        let prevTime = previousTime

        previousSample = current
        previousTime = now

        guard let prev = prev, prevTime > 0 else {
            return nil // Need two samples to compute a delta
        }

        let elapsed = machToSeconds(now - prevTime)
        guard elapsed > 0.05 else { return nil }

        guard let delta = IOReportCreateSamplesDelta(prev, current, nil)?
            .takeRetainedValue() else { return nil }

        return parseDelta(delta, elapsed: elapsed)
    }

    // MARK: - Setup

    private func setupSubscription() {
        guard let energyCh = IOReportCopyChannelsInGroup(
            "Energy Model" as NSString, nil, 0, 0, 0
        )?.takeRetainedValue() else {
            available = false
            return
        }

        if let cpuCh = IOReportCopyChannelsInGroup(
            "CPU Stats" as NSString, nil, 0, 0, 0
        )?.takeRetainedValue() {
            IOReportMergeChannels(energyCh, cpuCh, nil)
        }

        if let gpuCh = IOReportCopyChannelsInGroup(
            "GPU Stats" as NSString, nil, 0, 0, 0
        )?.takeRetainedValue() {
            IOReportMergeChannels(energyCh, gpuCh, nil)
        }

        var subscribed: NSMutableDictionary?
        guard let sub = IOReportCreateSubscription(
            nil, energyCh, &subscribed, 0, nil
        )?.takeRetainedValue() else {
            available = false
            return
        }

        subscription = sub
        subscribedChannels = subscribed ?? energyCh
    }

    // MARK: - Delta Parsing

    private func parseDelta(_ delta: NSDictionary, elapsed: TimeInterval) -> Result {
        var result = Result()
        guard let channels = delta["IOReportChannels"] as? NSArray else { return result }

        // Load DVFS frequency tables on first call
        if !freqTablesLoaded {
            loadFrequencyTables()
            freqTablesLoaded = true
        }

        // --- Power: exact name allowlist for aggregate energy channels ---
        // "GPU Energy" is a bogus channel with huge values - must be excluded!
        let powerChannelMap: [String: String] = [
            "CPU Energy": "CPU",
            "GPU": "Graphics",
            "DRAM": "DRAM",
            "ANE": "ANE",
        ]
        var powerByName: [String: Double] = [:]
        var displayWatts: Double = 0

        // --- Frequency: OPP residency data ---
        var eClusterOPPs: [OPPResidency] = []
        var pClusterOPPs: [OPPResidency] = []
        var gpuOPPs: [OPPResidency] = []

        for case let ch as NSDictionary in channels {
            let group = IOReportChannelGetGroup(ch)?.takeUnretainedValue() as String? ?? ""
            let subGroup = IOReportChannelGetSubGroup(ch)?.takeUnretainedValue() as String? ?? ""
            let name = IOReportChannelGetChannelName(ch)?.takeUnretainedValue() as String? ?? ""
            let stateCount = IOReportStateGetCount(ch)

            // ---- Power (Energy Model, simple channels: stateCount < 0) ----
            if group == "Energy Model" && stateCount < 0 {
                var err: Int32 = 0
                let value = IOReportSimpleGetIntegerValue(ch, &err)
                guard err == 0 && value > 0 else { continue }

                // Energy delta is in mJ; power = mJ / 1e3 / seconds = watts
                let watts = Double(value) / 1000.0 / elapsed

                if let displayName = powerChannelMap[name] {
                    powerByName[displayName] = watts
                } else if name == "DISP" || name == "DISPEXT" {
                    displayWatts += watts
                }
            }

            // ---- CPU Frequency (Complex Performance States) ----
            if group == "CPU Stats"
                && subGroup == "CPU Complex Performance States"
                && stateCount > 0
                && (name == "ECPU" || name == "PCPU" || name == "PCPU1") {

                var opps: [OPPResidency] = []
                for i in 0..<stateCount {
                    let sName = IOReportStateGetNameForIndex(ch, i)?
                        .takeUnretainedValue() as String? ?? ""
                    let residency = IOReportStateGetResidency(ch, i)
                    guard residency > 0 else { continue }

                    // Parse "V{domain}P{index}" state names
                    if let oppIdx = parseOPPIndex(sName) {
                        opps.append(OPPResidency(oppIndex: oppIdx, residency: residency))
                    }
                }

                switch name {
                case "ECPU":
                    eClusterOPPs = opps
                case "PCPU", "PCPU1":
                    pClusterOPPs.append(contentsOf: opps)
                default:
                    break
                }
            }

            // ---- GPU Frequency (GPU Performance States) ----
            if group == "GPU Stats"
                && name == "GPUPH"
                && subGroup == "GPU Performance States"
                && stateCount > 0 {

                for i in 0..<stateCount {
                    let sName = IOReportStateGetNameForIndex(ch, i)?
                        .takeUnretainedValue() as String? ?? ""
                    let residency = IOReportStateGetResidency(ch, i)
                    guard residency > 0, sName != "OFF" else { continue }

                    // GPU states: "P1", "P2", ..., "P15"
                    if let gpuIdx = parseGPUStateIndex(sName) {
                        gpuOPPs.append(OPPResidency(oppIndex: gpuIdx, residency: residency))
                    }
                }
            }
        }

        // --- Build power readings ---
        let displayOrder: [String: Int] = [
            "CPU": 0, "Graphics": 1, "DRAM": 2, "ANE": 3, "Display": 4
        ]

        for (name, watts) in powerByName where watts > 0.001 {
            result.powerReadings.append(PowerReading(name: name, watts: watts))
        }
        if displayWatts > 0.001 {
            result.powerReadings.append(PowerReading(name: "Display", watts: displayWatts))
        }

        result.powerReadings.sort {
            (displayOrder[$0.name] ?? 99) < (displayOrder[$1.name] ?? 99)
        }

        let total = result.powerReadings.reduce(0) { $0 + $1.watts }
        if total > 0.01 {
            result.powerReadings.append(PowerReading(name: "Total Power", watts: total))
        }

        // --- Build frequency readings ---
        if let eFreq = computeAvgFrequency(
            opps: eClusterOPPs,
            fallbackMin: 600, fallbackMax: 2800
        ) {
            result.frequencyReadings.append(
                FrequencyReading(name: "CPU E-Cores", ghz: eFreq / 1000.0)
            )
        }

        if let pFreq = computeAvgFrequency(
            opps: pClusterOPPs,
            fallbackMin: 600, fallbackMax: 4500
        ) {
            result.frequencyReadings.append(
                FrequencyReading(name: "CPU P-Cores", ghz: pFreq / 1000.0)
            )
        }

        if let gpuFreq = computeGPUAvgFrequency(
            opps: gpuOPPs,
            fallbackMax: 1580
        ) {
            result.frequencyReadings.append(
                FrequencyReading(name: "Graphics", ghz: gpuFreq / 1000.0)
            )
        }

        return result
    }

    // MARK: - State Name Parsing

    /// Parse "V{domain}P{index}" → OPP index (e.g., "V0P6" → 6)
    private func parseOPPIndex(_ stateName: String) -> Int? {
        guard stateName.hasPrefix("V") else { return nil }
        let rest = stateName.dropFirst() // "0P6"
        guard let pIdx = rest.firstIndex(of: "P") else { return nil }
        let indexStr = rest[rest.index(after: pIdx)...]
        return Int(indexStr)
    }

    /// Parse GPU state "P{n}" → 0-based index (e.g., "P1" → 0, "P2" → 1)
    private func parseGPUStateIndex(_ stateName: String) -> Int? {
        guard stateName.hasPrefix("P"), let num = Int(stateName.dropFirst()) else { return nil }
        return num - 1
    }

    // MARK: - DVFS Frequency Table (from IORegistry)

    private func loadFrequencyTables() {
        let entry = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/arm-io/pmgr")
        guard entry != IO_OBJECT_NULL else { return }
        defer { IOObjectRelease(entry) }

        var cfProps: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(
            entry, &cfProps, kCFAllocatorDefault, 0
        ) == KERN_SUCCESS,
              let props = cfProps?.takeRetainedValue() as? [String: Any]
        else { return }

        for (key, value) in props {
            guard key.hasPrefix("voltage-states") && key.hasSuffix("-sram"),
                  let data = value as? Data, data.count >= 8 else { continue }

            // Extract domain index from "voltage-states{N}-sram"
            let stripped = key
                .replacingOccurrences(of: "voltage-states", with: "")
                .replacingOccurrences(of: "-sram", with: "")
            guard let domainIndex = Int(stripped) else { continue }

            // Each entry is 8 bytes: freq_Hz (UInt32 LE) + voltage_mV (UInt32 LE)
            var freqsMHz: [Double] = []
            for offset in stride(from: 0, to: data.count - 3, by: 8) {
                let freqHz: UInt32 = data.withUnsafeBytes { ptr in
                    ptr.load(fromByteOffset: offset, as: UInt32.self)
                }
                freqsMHz.append(Double(freqHz) / 1_000_000.0)
            }

            if !freqsMHz.isEmpty {
                dvfsTables[domainIndex] = freqsMHz
            }
        }

        // Try to identify GPU frequency table (highest domain index with entries < 2 GHz)
        for (_, freqs) in dvfsTables.sorted(by: { $0.key > $1.key }) {
            let maxFreq = freqs.max() ?? 0
            if maxFreq > 200 && maxFreq < 2500 && freqs.count >= 5 {
                gpuFreqTable = freqs
                break
            }
        }
    }

    // MARK: - Frequency Computation

    private struct OPPResidency {
        let oppIndex: Int
        let residency: Int64
    }

    /// Compute residency-weighted average CPU frequency in MHz
    private func computeAvgFrequency(
        opps: [OPPResidency],
        fallbackMin: Double,
        fallbackMax: Double
    ) -> Double? {
        guard !opps.isEmpty else { return nil }
        let totalRes = opps.reduce(Int64(0)) { $0 + $1.residency }
        guard totalRes > 0 else { return nil }

        // Try DVFS table from IORegistry (CPU states use domain 0: "V0P{index}")
        let table = dvfsTables[0]

        let minOPP = opps.min(by: { $0.oppIndex < $1.oppIndex })?.oppIndex ?? 0
        let maxOPP = opps.max(by: { $0.oppIndex < $1.oppIndex })?.oppIndex ?? 1
        let oppRange = max(1, maxOPP - minOPP)

        var avg = 0.0
        for opp in opps {
            let freqMHz: Double
            if let table = table, opp.oppIndex < table.count, table[opp.oppIndex] > 0 {
                freqMHz = table[opp.oppIndex]
            } else {
                // Proportional fallback using known min/max for this cluster type
                let fraction = Double(opp.oppIndex - minOPP) / Double(oppRange)
                freqMHz = fallbackMin + fraction * (fallbackMax - fallbackMin)
            }
            avg += freqMHz * Double(opp.residency) / Double(totalRes)
        }

        return avg
    }

    /// Compute residency-weighted average GPU frequency in MHz
    private func computeGPUAvgFrequency(
        opps: [OPPResidency],
        fallbackMax: Double
    ) -> Double? {
        guard !opps.isEmpty else { return nil }
        let totalRes = opps.reduce(Int64(0)) { $0 + $1.residency }
        guard totalRes > 0 else { return nil }

        let maxIdx = opps.max(by: { $0.oppIndex < $1.oppIndex })?.oppIndex ?? 1

        var avg = 0.0
        for opp in opps {
            let freqMHz: Double
            if opp.oppIndex < gpuFreqTable.count && gpuFreqTable[opp.oppIndex] > 0 {
                freqMHz = gpuFreqTable[opp.oppIndex]
            } else {
                // Proportional: P1 = lowest, P15 = highest
                let fraction = maxIdx > 0 ? Double(opp.oppIndex) / Double(maxIdx) : 1.0
                freqMHz = 200 + fraction * (fallbackMax - 200)
            }
            avg += freqMHz * Double(opp.residency) / Double(totalRes)
        }

        return avg
    }

    // MARK: - Helpers

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private func machToSeconds(_ ticks: UInt64) -> TimeInterval {
        return TimeInterval(ticks) * TimeInterval(Self.timebase.numer)
            / TimeInterval(Self.timebase.denom) / 1_000_000_000
    }
}
