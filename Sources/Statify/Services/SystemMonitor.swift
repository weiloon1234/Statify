import Foundation
import Combine
import Darwin.Mach

final class SystemMonitor: @unchecked Sendable {
    private(set) var stats = SystemStats(
        cpuUsage: 0, cpuUserUsage: 0, cpuSystemUsage: 0, memoryUsage: 0, memoryUsedGB: 0, memoryTotalGB: 0,
        memoryAppGB: 0, memoryWiredGB: 0, memoryCompressedGB: 0, memoryFreeGB: 0, memoryPressure: 0,
        memoryPageInsKB: 0, memoryPageOutsKB: 0, memorySwapUsedKB: 0,
        diskUsedGB: 0, diskTotalGB: 0, downloadKBps: 0, uploadKBps: 0,
        cpuTemp: nil, cpuGhz: nil, gpuGhz: nil, gpuTemp: nil, powerWatts: nil,
        loadAverage1: 0, loadAverage5: 0, loadAverage15: 0, uptime: 0,
        chipName: "Apple Silicon",
        pCoreCount: 0, eCoreCount: 0, totalCores: 0, coreUsages: [], temperatureSensors: [], fans: [],
        networkInfo: NetworkInfo(),
        powerReadings: [], frequencyReadings: [], voltage: nil
    )

    private let cpuMonitor = CPUMonitor()
    private let memMonitor = MemoryMonitor()
    private let diskMonitor = DiskMonitor()
    private let netMonitor = NetworkMonitor()
    private let thermalFan = ThermalFanMonitor()
    private let powerMetrics = PowerMetricsService()

    func sample() -> SystemStats {
        let cpu = cpuMonitor.sample()
        let mem = memMonitor.sample()
        let disk = diskMonitor.sample()
        let net = netMonitor.sample()
        let thermal = thermalFan.sample()
        let pm = powerMetrics.sample()

        let coreDetector = CoreDetector()
        let cores = coreDetector.detect()
        let chipName = ChipDetector.detect()
        let totalCores = cores.pCores + cores.eCores
        let loadAverage = SystemLoadAverage.current()
        let uptime = ProcessInfo.processInfo.systemUptime

        // Merge power: prefer powermetrics, fall back to SMC
        let powerReadings = (pm?.powerReadings.isEmpty == false) ? pm!.powerReadings : thermal.powerReadings
        let totalPower = powerReadings.first(where: { $0.name == "Total Power" })?.watts

        // Merge frequency: prefer powermetrics, fall back to static estimate
        let frequencyReadings = pm?.frequencyReadings ?? []
        let cpuGhz = frequencyReadings
            .first(where: { $0.name.contains("P-Cores") || $0.name.contains("Performance") })?.ghz
            ?? ChipDetector.getCpuGhz()
        let gpuGhz = frequencyReadings
            .first(where: { $0.name == "Graphics" })?.ghz

        // Voltage from SMC
        let voltage = thermal.voltage

        let stats = SystemStats(
            cpuUsage: cpu.overall,
            cpuUserUsage: cpu.user,
            cpuSystemUsage: cpu.system,
            memoryUsage: mem.percentUsed,
            memoryUsedGB: mem.usedGB,
            memoryTotalGB: mem.totalGB,
            memoryAppGB: mem.appGB,
            memoryWiredGB: mem.wiredGB,
            memoryCompressedGB: mem.compressedGB,
            memoryFreeGB: mem.freeGB,
            memoryPressure: mem.pressure,
            memoryPageInsKB: mem.pageInsKB,
            memoryPageOutsKB: mem.pageOutsKB,
            memorySwapUsedKB: mem.swapUsedKB,
            diskUsedGB: disk.usedGB,
            diskTotalGB: disk.totalGB,
            downloadKBps: net.downloadKBs,
            uploadKBps: net.uploadKBs,
            cpuTemp: thermal.cpuTemp,
            cpuGhz: cpuGhz,
            gpuGhz: gpuGhz,
            gpuTemp: thermal.gpuTemp,
            powerWatts: totalPower,
            loadAverage1: loadAverage.oneMinute,
            loadAverage5: loadAverage.fiveMinute,
            loadAverage15: loadAverage.fifteenMinute,
            uptime: uptime,
            chipName: chipName,
            pCoreCount: cores.pCores,
            eCoreCount: cores.eCores,
            totalCores: totalCores,
            coreUsages: cpu.perCore,
            temperatureSensors: thermal.sensors,
            fans: thermal.fans,
            networkInfo: NetworkInfo(),
            powerReadings: powerReadings,
            frequencyReadings: frequencyReadings,
            voltage: voltage
        )
        self.stats = stats
        return stats
    }
}
    
extension SystemMonitor {
    private func sysctlInt(_ name: String) -> Int32 {
        var result: Int32 = 0
        var size = MemoryLayout<Int32>.size
        _ = name.withCString { ptr in
            sysctlbyname(ptr, &result, &size, nil, 0)
        }
        return result
    }
}

// MARK: - CPU Monitor

struct CPUUsage {
    var overall: Double
    var user: Double
    var system: Double
    var perCore: [Double]
}

final class CPUMonitor {
    private var previousTotal: [Double] = []
    private var previousBusy: [Double] = []
    private var previousUser: [Double] = []
    private var previousSystem: [Double] = []

    func sample() -> CPUUsage {
        let hostPort = mach_host_self()
        var count = mach_msg_type_number_t(0)
        var processorInfo: processor_info_array_t!
        var processorCount: mach_msg_type_number_t = 0

        let kr = host_processor_info(hostPort, PROCESSOR_CPU_LOAD_INFO,
                                      &count, &processorInfo, &processorCount)
        guard kr == KERN_SUCCESS else { return CPUUsage(overall: 0, user: 0, system: 0, perCore: []) }

        let cpuCount = Int(processorCount)
        var total: [Double] = []
        var busy: [Double] = []
        var userTicks: [Double] = []
        var systemTicks: [Double] = []

        for cpu in 0..<cpuCount {
            let offset = cpu * Int(CPU_STATE_MAX)
            let user   = Double(processorInfo[offset + Int(CPU_STATE_USER)])
            let system = Double(processorInfo[offset + Int(CPU_STATE_SYSTEM)])
            let idle   = Double(processorInfo[offset + Int(CPU_STATE_IDLE)])
            let nice   = Double(processorInfo[offset + Int(CPU_STATE_NICE)])
            total.append(user + system + idle + nice)
            busy.append(user + system + nice)
            userTicks.append(user + nice)
            systemTicks.append(system)
        }

        var perCore: [Double] = []
        for i in 0..<cpuCount {
            if i < previousTotal.count {
                let dt = total[i] - previousTotal[i]
                let db = busy[i] - previousBusy[i]
                perCore.append(dt > 0 ? max(0, min(100, (db / dt) * 100.0)) : 0)
            } else {
                perCore.append(0)
            }
        }

        let overallTotal = total.reduce(0, +)
        let overallBusy  = busy.reduce(0, +)
        let overallUser = userTicks.reduce(0, +)
        let overallSystem = systemTicks.reduce(0, +)
        var overall = 0.0
        var user = 0.0
        var system = 0.0
        if previousTotal.count > 0 {
            let dt = overallTotal - previousTotal.reduce(0, +)
            let db = overallBusy  - previousBusy.reduce(0, +)
            overall = dt > 0 ? max(0, min(100, (db / dt) * 100.0)) : 0
            let du = overallUser - previousUser.reduce(0, +)
            let ds = overallSystem - previousSystem.reduce(0, +)
            user = dt > 0 ? max(0, min(100, (du / dt) * 100.0)) : 0
            system = dt > 0 ? max(0, min(100, (ds / dt) * 100.0)) : 0
        }

        previousTotal = total
        previousBusy  = busy
        previousUser = userTicks
        previousSystem = systemTicks
        return CPUUsage(overall: overall, user: user, system: system, perCore: perCore)
    }
}

// MARK: - Memory Monitor

struct MemoryUsage {
    var usedGB: Double
    var totalGB: Double
    var percentUsed: Double
    var appGB: Double
    var wiredGB: Double
    var compressedGB: Double
    var freeGB: Double
    var pressure: Double
    var pageInsKB: Double
    var pageOutsKB: Double
    var swapUsedKB: Double
}

final class MemoryMonitor {
    private var lastPageIns: UInt64 = 0
    private var lastPageOuts: UInt64 = 0
    private var lastTimestamp: Date?

    func sample() -> MemoryUsage {
        let hostPort = mach_host_self()
        var pageSize: vm_size_t = 0
        host_page_size(hostPort, &pageSize)

        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size
            / MemoryLayout<integer_t>.size)
        var stats = vm_statistics64_data_t()

        let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(hostPort, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else {
            return MemoryUsage(
                usedGB: 0, totalGB: 0, percentUsed: 0,
                appGB: 0, wiredGB: 0, compressedGB: 0, freeGB: 0, pressure: 0,
                pageInsKB: 0, pageOutsKB: 0, swapUsedKB: 0
            )
        }

        let pageF64 = Double(pageSize)
        let gb = 1_073_741_824.0
        let totalBytes = Double(ProcessInfo.processInfo.physicalMemory)

        let appPages = max(0, Double(stats.internal_page_count) - Double(stats.purgeable_count))
        let appBytes = appPages * pageF64
        let wiredBytes = Double(stats.wire_count) * pageF64
        let compressedBytes = Double(stats.compressor_page_count) * pageF64
        let reclaimableBytes = (Double(stats.free_count) + Double(stats.speculative_count) + Double(stats.purgeable_count)) * pageF64
        let freeBytes = min(reclaimableBytes, totalBytes)
        let usedBytes = min(totalBytes, appBytes + wiredBytes + compressedBytes)
        let pressureBytes = wiredBytes + compressedBytes
        let now = Date()
        let currentPageIns = UInt64(stats.pageins)
        let currentPageOuts = UInt64(stats.pageouts)
        var pageInsKB = 0.0
        var pageOutsKB = 0.0
        if let lastTimestamp {
            let elapsed = now.timeIntervalSince(lastTimestamp)
            if elapsed > 0 {
                pageInsKB = Double(safeDelta(current: currentPageIns, previous: lastPageIns)) * pageF64 / 1024.0 / elapsed
                pageOutsKB = Double(safeDelta(current: currentPageOuts, previous: lastPageOuts)) * pageF64 / 1024.0 / elapsed
            }
        }
        lastPageIns = currentPageIns
        lastPageOuts = currentPageOuts
        self.lastTimestamp = now
        let swapUsedKB = readSwapUsageKB()

        return MemoryUsage(
            usedGB: usedBytes / gb,
            totalGB: totalBytes / gb,
            percentUsed: totalBytes > 0 ? (usedBytes / totalBytes) * 100.0 : 0,
            appGB: appBytes / gb,
            wiredGB: wiredBytes / gb,
            compressedGB: compressedBytes / gb,
            freeGB: freeBytes / gb,
            pressure: totalBytes > 0 ? min(100, (pressureBytes / totalBytes) * 100.0) : 0,
            pageInsKB: pageInsKB,
            pageOutsKB: pageOutsKB,
            swapUsedKB: swapUsedKB
        )
    }

    private func readSwapUsageKB() -> Double {
        var swap = xsw_usage()
        var size = MemoryLayout.size(ofValue: swap)
        let result = sysctlbyname("vm.swapusage", &swap, &size, nil, 0)
        guard result == 0 else { return 0 }
        return Double(swap.xsu_used) / 1024.0
    }

    private func safeDelta(current: UInt64, previous: UInt64) -> UInt64 {
        current >= previous ? (current - previous) : 0
    }
}

// MARK: - Disk Monitor

struct DiskUsage {
    var usedGB: Double
    var totalGB: Double
    var percentUsed: Double
}

final class DiskMonitor {
    func sample() -> DiskUsage {
        var st = statfs()
        guard statfs("/", &st) == 0 else {
            return DiskUsage(usedGB: 0, totalGB: 0, percentUsed: 0)
        }
        let gb = 1_073_741_824.0
        let blockSize = Double(st.f_bsize)
        let totalBytes = Double(st.f_blocks) * blockSize
        let freeBytes  = Double(st.f_bfree)  * blockSize
        let usedBytes  = totalBytes - freeBytes
        return DiskUsage(
            usedGB: usedBytes / gb,
            totalGB: totalBytes / gb,
            percentUsed: totalBytes > 0 ? (usedBytes / totalBytes) * 100.0 : 0
        )
    }
}

// MARK: - Network Monitor

struct NetworkStatsResult {
    var downloadKBs: Double
    var uploadKBs: Double
}

final class NetworkMonitor {
    private var lastBytesIn: UInt64 = 0
    private var lastBytesOut: UInt64 = 0
    private var lastTimestamp: Date?

    func sample() -> NetworkStatsResult {
        let mib: [Int32] = [CTL_NET, PF_ROUTE, 0, 0, NET_RT_IFLIST2, 0]
        var length = 0
        guard mib.withUnsafeBufferPointer({ mibPtr in
            sysctl(UnsafeMutablePointer(mutating: mibPtr.baseAddress), 6, nil, &length, nil, 0)
        }) == 0 else {
            return NetworkStatsResult(downloadKBs: 0, uploadKBs: 0)
        }

        var buffer = [UInt8](repeating: 0, count: length)
        guard mib.withUnsafeBufferPointer({ mibPtr in
            buffer.withUnsafeMutableBytes({ ptr in
                sysctl(UnsafeMutablePointer(mutating: mibPtr.baseAddress), 6, ptr.baseAddress, &length, nil, 0)
            })
        }) == 0 else {
            return NetworkStatsResult(downloadKBs: 0, uploadKBs: 0)
        }

        var totalIn: UInt64 = 0
        var totalOut: UInt64 = 0

        buffer.withUnsafeBytes { rawPtr in
            var ptr = rawPtr.baseAddress!
            let end = ptr.advanced(by: length)
            while ptr < end {
                let msg = ptr.assumingMemoryBound(to: if_msghdr.self)
                if msg.pointee.ifm_type == RTM_IFINFO2 {
                    let msg2 = ptr.assumingMemoryBound(to: if_msghdr2.self)
                    let flags = UInt32(msg2.pointee.ifm_flags)
                    if (flags & UInt32(IFF_LOOPBACK)) == 0 &&
                       (flags & UInt32(IFF_UP)) != 0 &&
                       (flags & UInt32(IFF_RUNNING)) != 0 {
                        totalIn  += UInt64(msg2.pointee.ifm_data.ifi_ibytes)
                        totalOut += UInt64(msg2.pointee.ifm_data.ifi_obytes)
                    }
                }
                ptr = ptr.advanced(by: Int(msg.pointee.ifm_msglen))
            }
        }

        let now = Date()
        var downloadKBs = 0.0
        var uploadKBs = 0.0

        if let last = lastTimestamp {
            let elapsed = now.timeIntervalSince(last)
            if elapsed > 0 {
                downloadKBs = (Double(totalIn) - Double(lastBytesIn)) / 1024.0 / elapsed
                uploadKBs   = (Double(totalOut) - Double(lastBytesOut)) / 1024.0 / elapsed
            }
        }

        lastBytesIn  = totalIn
        lastBytesOut = totalOut
        lastTimestamp = now

        return NetworkStatsResult(downloadKBs: max(0, downloadKBs), uploadKBs: max(0, uploadKBs))
    }
}

struct SystemLoadAverage {
    var oneMinute: Double
    var fiveMinute: Double
    var fifteenMinute: Double

    static func current() -> SystemLoadAverage {
        var values = [Double](repeating: 0, count: 3)
        let result = getloadavg(&values, 3)
        guard result == 3 else {
            return SystemLoadAverage(oneMinute: 0, fiveMinute: 0, fifteenMinute: 0)
        }
        return SystemLoadAverage(
            oneMinute: values[0],
            fiveMinute: values[1],
            fifteenMinute: values[2]
        )
    }
}

// MARK: - Core Detector

struct CoreInfo {
    var pCores: Int
    var eCores: Int
    var isAppleSilicon: Bool
}

final class CoreDetector {
    func detect() -> CoreInfo {
        let pPhysical = sysctlInt("hw.perflevel0.physicalcpu")
        let ePhysical = sysctlInt("hw.perflevel1.physicalcpu")
        let isAS = pPhysical > 0 && ePhysical > 0
        return CoreInfo(
            pCores: isAS ? Int(pPhysical) : 0,
            eCores: isAS ? Int(ePhysical) : 0,
            isAppleSilicon: isAS
        )
    }

    private func sysctlInt(_ name: String) -> Int32 {
        var result: Int32 = 0
        var size = MemoryLayout<Int32>.size
        _ = name.withCString { ptr in
            sysctlbyname(ptr, &result, &size, nil, 0)
        }
        return result
    }
}

enum ChipDetector {
    static func detect() -> String {
        let pCores = sysctlInt("hw.perflevel0.physicalcpu")
        let eCores = sysctlInt("hw.perflevel1.physicalcpu")
        let totalCores = Int(pCores) + Int(eCores)

        let pName = sysctlString("hw.perflevel0.name")
        if !pName.isEmpty {
            return parseChipName(pName, coreCount: totalCores)
        }

        let brand = sysctlString("machdep.cpu.brand_string")
        if !brand.isEmpty {
            return brand
        }

        return "Apple Silicon (\(totalCores) cores)"
    }

    private static func parseChipName(_ name: String, coreCount: Int) -> String {
        let nameLower = name.lowercased()
        if nameLower.contains("avalanche") || nameLower.contains("blizzard") {
            if coreCount <= 8 { return "Apple M1" }
            if coreCount <= 10 { return "Apple M1 Pro" }
            if coreCount <= 12 { return "Apple M1 Max" }
            if coreCount <= 16 { return "Apple M1 Ultra" }
        }
        if nameLower.contains("everest") || nameLower.contains("sawtooth") {
            if coreCount <= 8 { return "Apple M2" }
            if coreCount <= 10 { return "Apple M2 Pro" }
            if coreCount <= 12 { return "Apple M2 Max" }
            if coreCount <= 16 { return "Apple M2 Ultra" }
        }
        if nameLower.contains("tempest") || nameLower.contains("sawtooth") {
            if coreCount <= 8 { return "Apple M3" }
            if coreCount <= 10 { return "Apple M3 Pro" }
            if coreCount <= 12 { return "Apple M3 Max" }
            if coreCount <= 16 { return "Apple M3 Ultra" }
        }
        if nameLower.contains("atlas") || nameLower.contains("opal") {
            if coreCount <= 8 { return "Apple M4" }
            if coreCount <= 10 { return "Apple M4 Pro" }
            if coreCount <= 12 { return "Apple M4 Max" }
        }
        return "Apple Silicon (\(coreCount) cores)"
    }

    private static func sysctlInt(_ name: String) -> Int32 {
        var result: Int32 = 0
        var size = MemoryLayout<Int32>.size
        _ = name.withCString { ptr in
            sysctlbyname(ptr, &result, &size, nil, 0)
        }
        return result
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        _ = name.withCString { ptr in
            sysctlbyname(ptr, nil, &size, nil, 0)
        }
        guard size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        _ = name.withCString { ptr in
            sysctlbyname(ptr, &buffer, &size, nil, 0)
        }
        return String(cString: buffer)
    }

    static func getCpuGhz() -> Double? {
        let freq = sysctlInt("hw.cpufrequency")
        if freq > 0 {
            return Double(freq) / 1_000_000_000.0
        }
        let pCores = sysctlInt("hw.perflevel0.physicalcpu")
        let eCores = sysctlInt("hw.perflevel1.physicalcpu")
        let totalCores = Int(pCores) + Int(eCores)
        let pName = sysctlString("hw.perflevel0.name").lowercased()
        if totalCores == 0 { return nil }
        if pName.contains("avalanche") || pName.contains("blizzard") {
            if totalCores <= 8 { return 3.2 }
            if totalCores <= 10 { return 3.2 }
            if totalCores <= 12 { return 3.2 }
            return 3.2
        }
        if pName.contains("everest") || pName.contains("sawtooth") {
            if totalCores <= 8 { return 3.5 }
            if totalCores <= 10 { return 3.7 }
            if totalCores <= 12 { return 3.7 }
            return 3.7
        }
        if pName.contains("tempest") || pName.contains("sawtooth") {
            if totalCores <= 8 { return 4.0 }
            if totalCores <= 10 { return 4.0 }
            if totalCores <= 12 { return 4.0 }
            return 4.0
        }
        if pName.contains("atlas") || pName.contains("opal") {
            if totalCores <= 8 { return 4.4 }
            if totalCores <= 10 { return 4.5 }
            if totalCores <= 12 { return 4.5 }
            return 4.5
        }
        return nil
    }
}
