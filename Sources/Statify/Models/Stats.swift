import Foundation

struct SystemStats {
    var cpuUsage: Double
    var cpuUserUsage: Double
    var cpuSystemUsage: Double
    var memoryUsage: Double
    var memoryUsedGB: Double
    var memoryTotalGB: Double
    var memoryAppGB: Double
    var memoryWiredGB: Double
    var memoryCompressedGB: Double
    var memoryFreeGB: Double
    var memoryPressure: Double
    var memoryPageInsKB: Double
    var memoryPageOutsKB: Double
    var memorySwapUsedKB: Double
    var diskUsedGB: Double
    var diskTotalGB: Double
    var downloadKBps: Double
    var uploadKBps: Double
    var cpuTemp: Double?
    var cpuGhz: Double?
    var gpuGhz: Double?
    var gpuTemp: Double?
    var powerWatts: Double?
    var loadAverage1: Double
    var loadAverage5: Double
    var loadAverage15: Double
    var uptime: TimeInterval
    var chipName: String
    var pCoreCount: Int
    var eCoreCount: Int
    var totalCores: Int
    var coreUsages: [Double]
    var temperatureSensors: [TemperatureSensor]
    var fans: [FanInfo]
    var networkInfo: NetworkInfo
    var powerReadings: [PowerReading]
    var frequencyReadings: [FrequencyReading]
    var voltage: Double?
}

extension SystemStats {
    static var empty: SystemStats {
        SystemStats(
            cpuUsage: 0, cpuUserUsage: 0, cpuSystemUsage: 0, memoryUsage: 0, memoryUsedGB: 0, memoryTotalGB: 0,
            memoryAppGB: 0, memoryWiredGB: 0, memoryCompressedGB: 0, memoryFreeGB: 0, memoryPressure: 0,
            memoryPageInsKB: 0, memoryPageOutsKB: 0, memorySwapUsedKB: 0,
            diskUsedGB: 0, diskTotalGB: 0, downloadKBps: 0, uploadKBps: 0,
            cpuTemp: nil, cpuGhz: nil, gpuGhz: nil, gpuTemp: nil, powerWatts: nil,
            loadAverage1: 0, loadAverage5: 0, loadAverage15: 0, uptime: 0,
            chipName: "", pCoreCount: 0, eCoreCount: 0, totalCores: 0,
            coreUsages: [], temperatureSensors: [], fans: [], networkInfo: NetworkInfo(),
            powerReadings: [], frequencyReadings: [], voltage: nil
        )
    }
}

struct TemperatureSensor: Identifiable {
    let name: String
    let valueCelsius: Double

    var id: String { name }
}

struct FanInfo: Identifiable {
    var id: Int { index }
    var index: Int
    var name: String
    var rpm: Int
    var minRpm: Int
    var maxRpm: Int
    var usagePercent: Double

    var displayUsage: String {
        if maxRpm > minRpm {
            return String(format: "%.0f%%", usagePercent)
        }
        return "--"
    }
}

struct PowerReading: Identifiable {
    let name: String
    let watts: Double
    var id: String { name }

    var displayValue: String {
        if watts > 0 && watts < 1 {
            return String(format: "%.0f mW", watts * 1000)
        }
        return String(format: "%.1f W", watts)
    }
}

struct FrequencyReading: Identifiable {
    let name: String
    let ghz: Double
    var id: String { name }
}

struct ProcessStats: Identifiable {
    var id: Int32 { pid }
    var pid: Int32
    var name: String
    var cpuUsage: Double
    var memoryBytes: UInt64
    var downloadKBps: Double
    var uploadKBps: Double
    var diskReadKBps: Double
    var diskWriteKBps: Double
}
