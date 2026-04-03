import Foundation
import CIOKit

struct ThermalData {
    var cpuTemp: Double?
    var gpuTemp: Double?
    var sensors: [TemperatureSensor]
    var fans: [FanInfo]
    var powerReadings: [PowerReading]
    var frequencyReadings: [FrequencyReading]
    var voltage: Double?
}

final class ThermalFanMonitor {
    private struct SMCTemperatureKey {
        let key: String
        let name: String
        let priority: Int
    }

    private var smcConnection: io_connect_t = 0
    private var cachedTemperatureKeys: [SMCTemperatureKey] = []
    private var keyInfoCache: [String: SMCKeyInfo] = [:]

    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { return }
        IOServiceOpen(service, mach_task_self_, 0, &smcConnection)
        IOObjectRelease(service)
    }

    deinit {
        if smcConnection != 0 { IOServiceClose(smcConnection) }
    }

    /// Lightweight: reads only a few SMC keys for CPU temperature.
    /// Used in statusBar scope to avoid the full sample() overhead.
    func readCPUTempOnly() -> Double? {
        guard smcConnection != 0 else { return nil }

        // Performance cores first (higher priority), then efficiency cores
        let cpuKeys = ["Tp0P", "Tp0D", "TC1C", "Tp1P", "Tp1D", "TC2C", "TDEC"]

        for key in cpuKeys {
            if let temp = readTemperatureValue(for: key), isValidTemperature(temp) {
                return temp
            }
        }
        return nil
    }

    func sample() -> ThermalData {
        let sensors = readTemperatureSensors()
        let cpuTemp = readCPUTemp(from: sensors)
        let gpuTemp = sensors.first(where: { $0.name == "Graphics" })?.valueCelsius
        let power = readPowerFromSMC()
        let voltage = readVoltageFromSMC()
        return ThermalData(
            cpuTemp: cpuTemp, gpuTemp: gpuTemp, sensors: sensors, fans: readFans(),
            powerReadings: power, frequencyReadings: [], voltage: voltage
        )
    }

    private func readCPUTemp(from sensors: [TemperatureSensor]) -> Double? {
        let preferredNames = [
            "CPU Performance Cores", "CPU Efficiency Cores"
        ]
        for name in preferredNames {
            if let value = sensors.first(where: { $0.name == name })?.valueCelsius {
                return value
            }
        }
        return sensors.first?.valueCelsius
    }

    private func readTemperatureSensors() -> [TemperatureSensor] {
        let discoveredKeys = discoverTemperatureKeys()
        // Aggregate multiple keys per sensor name using the max value
        // (e.g. 44 Tg* GPU die sensors → one "Graphics" entry with peak temp)
        var bestByName: [String: Double] = [:]

        for sensorKey in discoveredKeys {
            guard let temp = readTemperatureValue(for: sensorKey.key), isValidTemperature(temp) else { continue }
            bestByName[sensorKey.name] = max(bestByName[sensorKey.name] ?? 0, temp)
        }

        return bestByName.map { TemperatureSensor(name: $0.key, valueCelsius: $0.value) }
            .sorted { $0.name < $1.name }
    }

    private func readFans() -> [FanInfo] {
        guard smcConnection != 0 else { return [] }
        let fanCount = readUInt8Key("FNum")
        guard fanCount > 0 else { return [] }

        var fans: [FanInfo] = []
        for i in 0..<fanCount {
            let current = readFanSpeed("F\(i)Ac")
            let min = readFanSpeed("F\(i)Mn")
            let max = readFanSpeed("F\(i)Mx")
            let name = readFanName(Int(i))
            let usage = max > min ? Double(current - min) / Double(max - min) * 100.0 : 0
            fans.append(FanInfo(index: Int(i), name: name, rpm: current,
                                minRpm: min, maxRpm: max, usagePercent: usage))
        }
        return fans
    }

    /// Read fan speed with format auto-detection
    private func readFanSpeed(_ key: String) -> Int {
        guard let keyInfo = readKeyInfo(key) else { return 0 }

        switch keyInfo.dataType {
        case "flt ":
            if let val = readFloatKey(key), val >= 0, val < 10000 {
                return Int(val.rounded())
            }
            return 0
        case "fpe2":
            return readFPE2Key(key)
        default:
            // Fallback: try float for 4-byte data, otherwise fpe2
            if keyInfo.dataSize == 4, let val = readFloatKey(key), val >= 0, val < 10000 {
                return Int(val.rounded())
            }
            return readFPE2Key(key)
        }
    }

    // MARK: - Power & Voltage (SMC fallback)

    private func readPowerFromSMC() -> [PowerReading] {
        guard smcConnection != 0 else { return [] }
        var readings: [PowerReading] = []

        let powerKeys: [(key: String, name: String)] = [
            ("PCPC", "CPU"), ("PC0C", "CPU"),
            ("PCPG", "Graphics"), ("PGTR", "Graphics"),
            ("PSTR", "Total Power"),
        ]

        var seen = Set<String>()
        for entry in powerKeys {
            guard !seen.contains(entry.name) else { continue }
            if let watts = readPowerValue(for: entry.key),
               watts > 0 && watts < 500 {
                readings.append(PowerReading(name: entry.name, watts: watts))
                seen.insert(entry.name)
            }
        }
        return readings
    }

    private func readVoltageFromSMC() -> Double? {
        guard smcConnection != 0 else { return nil }
        let voltageKeys = ["VD0R", "VP0R", "VBAT"]
        for key in voltageKeys {
            if let volts = readPowerValue(for: key),
               volts > 0 && volts < 30 {
                return volts
            }
        }
        return nil
    }

    private func readPowerValue(for key: String) -> Double? {
        guard let keyInfo = readKeyInfo(key) else { return nil }
        switch keyInfo.dataType {
        case "sp78":
            return readSP78Key(key)
        case "flt ":
            return readFloatKey(key)
        case "ioft":
            return readIOFloatKey(key)
        case "fpe2":
            return Double(readFPE2Key(key))
        default:
            if keyInfo.dataSize == 4 {
                return readFloatKey(key)
            }
            return nil
        }
    }

    private func readFloatKey(_ key: String) -> Double? {
        guard let data = readSMCKey(key), data.count >= 4 else { return nil }
        // Apple Silicon SMC stores flt values in little-endian byte order
        let bits = UInt32(data[0])
            | (UInt32(data[1]) << 8)
            | (UInt32(data[2]) << 16)
            | (UInt32(data[3]) << 24)
        let value = Double(Float(bitPattern: bits))
        guard value.isFinite else { return nil }
        return value
    }

    /// Read 8-byte ioft (IOFloat64) value used by Apple Silicon GPU sensors
    private func readIOFloatKey(_ key: String) -> Double? {
        guard let data = readSMCKey(key), data.count >= 8 else { return nil }
        let bits = UInt64(data[0])
            | (UInt64(data[1]) << 8)
            | (UInt64(data[2]) << 16)
            | (UInt64(data[3]) << 24)
            | (UInt64(data[4]) << 32)
            | (UInt64(data[5]) << 40)
            | (UInt64(data[6]) << 48)
            | (UInt64(data[7]) << 56)
        let value = Double(bitPattern: bits)
        guard value.isFinite else { return nil }
        return value
    }

    private func readSP78Key(_ key: String) -> Double? {
        guard let data = readSMCKey(key) else { return nil }
        let hi = Int16(data[0])
        let lo = Int16(data[1])
        return Double(hi) + Double(lo) / 256.0
    }

    private func readUInt8Key(_ key: String) -> UInt8 {
        guard let data = readSMCKey(key) else { return 0 }
        return data[0]
    }

    private func readUInt32Key(_ key: String) -> UInt32? {
        guard let data = readSMCKey(key), data.count >= 4 else { return nil }
        return data.prefix(4).reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func readFPE2Key(_ key: String) -> Int {
        guard let data = readSMCKey(key) else { return 0 }
        return (Int(data[0]) << 6) + (Int(data[1]) >> 2)
    }

    private func readFanName(_ id: Int) -> String {
        guard let data = readSMCKey("F\(id)ID"), data.count > 4 else {
            return defaultFanName(id)
        }
        let nameBytes = Array(data[4...min(19, data.count - 1)])
        // Find null terminator
        let endIdx = nameBytes.firstIndex(of: 0) ?? nameBytes.endIndex
        let trimmedBytes = Array(nameBytes[..<endIdx])
        if let name = String(bytes: trimmedBytes, encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters.union(.whitespacesAndNewlines)),
           !name.isEmpty {
            return name
        }
        return defaultFanName(id)
    }

    private func defaultFanName(_ id: Int) -> String {
        switch id {
        case 0: return "Left Fan"
        case 1: return "Right Fan"
        default: return "Fan \(id)"
        }
    }

    private func discoverTemperatureKeys() -> [SMCTemperatureKey] {
        if !cachedTemperatureKeys.isEmpty {
            return cachedTemperatureKeys
        }

        var discovered: [SMCTemperatureKey] = []
        var seenKeys = Set<String>()

        if let keyCount = readUInt32Key("#KEY"), keyCount > 0 {
            for index in 0..<keyCount {
                guard let key = readKey(at: index),
                      !seenKeys.contains(key),
                      let keyInfo = readKeyInfo(key),
                      supportsTemperatureValue(for: keyInfo.dataType),
                      let sensorKey = temperatureKeyDescriptor(for: key)
                else {
                    continue
                }

                discovered.append(sensorKey)
                seenKeys.insert(key)
            }
        }

        for sensorKey in fallbackTemperatureKeys() where !seenKeys.contains(sensorKey.key) {
            discovered.append(sensorKey)
            seenKeys.insert(sensorKey.key)
        }

        cachedTemperatureKeys = discovered.sorted { ($0.priority, $0.name, $0.key) < ($1.priority, $1.name, $1.key) }
        return cachedTemperatureKeys
    }

    private func readTemperatureValue(for key: String) -> Double? {
        guard let keyInfo = readKeyInfo(key) else { return nil }
        switch keyInfo.dataType {
        case "sp78":
            return readSP78Key(key)
        case "fpe2":
            return Double(readFPE2Key(key))
        case "flt ":
            return readFloatKey(key)
        case "ioft":
            return readIOFloatKey(key)
        default:
            if keyInfo.dataSize == 4 {
                return readFloatKey(key)
            }
            return nil
        }
    }

    private func supportsTemperatureValue(for type: String) -> Bool {
        type == "sp78" || type == "fpe2" || type == "flt " || type == "flt" || type == "ioft"
    }

    private func isValidTemperature(_ value: Double) -> Bool {
        // Require at least 1°C - sensors reporting ~0° are typically idle/unavailable
        value.isFinite && value >= 1 && value < 140
    }

    private func readKey(at index: UInt32) -> String? {
        guard smcConnection != 0 else { return nil }

        var input = SMCParamStruct()
        input.data8 = 8
        input.data32 = index

        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(
            smcConnection,
            2,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outSize
        )

        guard result == KERN_SUCCESS, output.result == 0 else { return nil }
        return stringFromKeyCode(output.key)
    }

    private func readKeyInfo(_ key: String) -> SMCKeyInfo? {
        if let cached = keyInfoCache[key] { return cached }
        guard smcConnection != 0, key.count == 4 else { return nil }

        var input = SMCParamStruct()
        input.key = keyCode(for: key)
        input.data8 = 9

        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(
            smcConnection,
            2,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outSize
        )

        guard result == KERN_SUCCESS, output.result == 0 else { return nil }
        let info = SMCKeyInfo(
            dataSize: Int(output.keyInfo_dataSize),
            dataType: stringFromKeyCode(output.keyInfo_dataType),
            attributes: output.keyInfo_dataAttributes
        )
        keyInfoCache[key] = info
        return info
    }

    private func readSMCKey(_ key: String) -> [UInt8]? {
        guard smcConnection != 0, key.count == 4 else { return nil }
        guard let keyInfo = readKeyInfo(key) else { return nil }

        var input = SMCParamStruct()
        input.key = keyCode(for: key)
        input.keyInfo_dataSize = UInt32(keyInfo.dataSize)
        input.keyInfo_dataType = keyCode(for: keyInfo.dataType)
        input.data8 = 5

        var output = SMCParamStruct()
        var outSize = MemoryLayout<SMCParamStruct>.stride

        let result = IOConnectCallStructMethod(
            smcConnection,
            2,
            &input,
            MemoryLayout<SMCParamStruct>.stride,
            &output,
            &outSize
        )

        guard result == KERN_SUCCESS, output.result == 0 else { return nil }
        return withUnsafeBytes(of: output.bytes) { Array($0.prefix(keyInfo.dataSize)) }
    }

    private func temperatureKeyDescriptor(for key: String) -> SMCTemperatureKey? {
        let explicit: [String: (String, Int)] = [
            // Airflow
            "TA0P": ("Airflow", 0), "TA0S": ("Airflow", 0), "TAOL": ("Airflow", 0),
            // Battery
            "TB0T": ("Battery", 1), "TB1T": ("Battery", 1), "TB2T": ("Battery", 1),
            // CPU Efficiency Cores
            "Tp1P": ("CPU Efficiency Cores", 2), "Tp1D": ("CPU Efficiency Cores", 2),
            "TC2C": ("CPU Efficiency Cores", 2), "TDEC": ("CPU Efficiency Cores", 2),
            // CPU Performance Cores
            "Tp0P": ("CPU Performance Cores", 3), "Tp0D": ("CPU Performance Cores", 3),
            "TC1C": ("CPU Performance Cores", 3),
            // Graphics (uppercase TG keys report 0 on M4 Max when idle)
            "TG0C": ("Graphics", 4), "TG0D": ("Graphics", 4),
            "TG0P": ("Graphics", 4), "TGDD": ("Graphics", 4),
            // Palm Rest
            "Ts0P": ("Palm Rest", 5), "Ts1P": ("Palm Rest", 5), "Th0P": ("Palm Rest", 5),
            // SSD
            "TH0A": ("SSD", 6), "TH0B": ("SSD", 6), "TH0C": ("SSD", 6),
            "TH0a": ("SSD", 6), "TH0b": ("SSD", 6),
            // Thunderbolt (M4 Max uses TaLT/TaRT instead of TI0P/TI2P)
            "TaLT": ("Thunderbolt Left", 7), "TI0P": ("Thunderbolt Left", 7),
            "TaRT": ("Thunderbolt Right", 8), "TI2P": ("Thunderbolt Right", 8),
            // Wi-Fi
            "TW0P": ("Wi-Fi", 9), "TW1P": ("Wi-Fi", 9),
        ]

        if let match = explicit[key] {
            return SMCTemperatureKey(key: key, name: match.0, priority: match.1)
        }

        // M4 Max GPU die sensors use lowercase Tg prefix (44 individual sensors)
        // Aggregate them all as "Graphics" — readTemperatureSensors takes the max
        if key.hasPrefix("Tg") {
            return SMCTemperatureKey(key: key, name: "Graphics", priority: 4)
        }

        return nil
    }

    private func fallbackTemperatureKeys() -> [SMCTemperatureKey] {
        [
            SMCTemperatureKey(key: "TAOL", name: "Airflow", priority: 0),
            SMCTemperatureKey(key: "TA0P", name: "Airflow", priority: 0),
            SMCTemperatureKey(key: "TB0T", name: "Battery", priority: 1),
            SMCTemperatureKey(key: "TB1T", name: "Battery", priority: 1),
            SMCTemperatureKey(key: "TDEC", name: "CPU Efficiency Cores", priority: 2),
            SMCTemperatureKey(key: "Tp1P", name: "CPU Efficiency Cores", priority: 2),
            SMCTemperatureKey(key: "Tp0P", name: "CPU Performance Cores", priority: 3),
            SMCTemperatureKey(key: "TG0C", name: "Graphics", priority: 4),
            SMCTemperatureKey(key: "Tg05", name: "Graphics", priority: 4),
            SMCTemperatureKey(key: "Ts0P", name: "Palm Rest", priority: 5),
            SMCTemperatureKey(key: "TH0a", name: "SSD", priority: 6),
            SMCTemperatureKey(key: "TH0A", name: "SSD", priority: 6),
            SMCTemperatureKey(key: "TaLT", name: "Thunderbolt Left", priority: 7),
            SMCTemperatureKey(key: "TI0P", name: "Thunderbolt Left", priority: 7),
            SMCTemperatureKey(key: "TaRT", name: "Thunderbolt Right", priority: 8),
            SMCTemperatureKey(key: "TI2P", name: "Thunderbolt Right", priority: 8),
            SMCTemperatureKey(key: "TW0P", name: "Wi-Fi", priority: 9),
        ]
    }

    private func keyCode(for key: String) -> UInt32 {
        key.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private func stringFromKeyCode(_ code: UInt32) -> String {
        let bytes: [UInt8] = [
            UInt8((code >> 24) & 0xFF),
            UInt8((code >> 16) & 0xFF),
            UInt8((code >> 8) & 0xFF),
            UInt8(code & 0xFF)
        ]
        // Only trim control characters (null bytes etc), preserve trailing spaces
        // which are part of FourCC type codes like "flt " and "ioft"
        return String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .controlCharacters) ?? ""
    }
}

private struct SMCKeyInfo {
    let dataSize: Int
    let dataType: String
    let attributes: UInt8
}

struct SMCParamStruct {
    var key: UInt32 = 0
    var vers_major: UInt8 = 0
    var vers_minor: UInt8 = 0
    var vers_build: UInt8 = 0
    var vers_reserved: UInt8 = 0
    var vers_release: UInt16 = 0
    var p_limit_version: UInt16 = 0
    var p_limit_length: UInt16 = 0
    var p_limit_cpu: UInt32 = 0
    var p_limit_gpu: UInt32 = 0
    var p_limit_mem: UInt32 = 0
    var keyInfo_dataSize: UInt32 = 0
    var keyInfo_dataType: UInt32 = 0
    var keyInfo_dataAttributes: UInt8 = 0
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) =
        (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}
