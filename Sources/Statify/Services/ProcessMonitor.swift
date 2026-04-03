import Foundation
import Darwin

final class ProcessMonitor {
    enum SampleMode {
        case basic
        case network
        case disk
        case full
    }

    private struct RecentNetworkActivity {
        var downloadKBps: Double
        var uploadKBps: Double
        var timestamp: Date
    }

    private struct RecentDiskActivity {
        var readKBps: Double
        var writeKBps: Double
        var timestamp: Date
    }

    private var previousCPU: [Int32: UInt64] = [:]
    private var previousTimestamp: Date?
    private var previousNetIn: [Int32: UInt64] = [:]
    private var previousNetOut: [Int32: UInt64] = [:]
    private var previousDiskRead: [Int32: UInt64] = [:]
    private var previousDiskWrite: [Int32: UInt64] = [:]
    private var recentNetworkActivity: [Int32: RecentNetworkActivity] = [:]
    private var recentDiskActivity: [Int32: RecentDiskActivity] = [:]
    private var cachedNetStats: [Int32: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
    private var nameCache: [Int32: String] = [:]
    private var nettopQueue = DispatchQueue(label: "com.statify.nettop", qos: .background)
    private var processQueue = DispatchQueue(label: "com.statify.process", qos: .utility)
    private var nettopFetchCount = 0
    private var lastNettopFetch: Date?
    private var lastSample: [ProcessStats] = []
    private var isSampling = false
    private let recentActivityRetention: TimeInterval = 15
    private var sampleCount = 0
    private var diskSampleCount = 0

    func sample(mode: SampleMode, onUpdate: (([ProcessStats]) -> Void)? = nil) -> [ProcessStats] {
        if !isSampling {
            isSampling = true
            processQueue.async { [weak self] in
                let result = self?.sampleSync(mode: mode) ?? []
                DispatchQueue.main.async {
                    self?.lastSample = result
                    self?.isSampling = false
                    onUpdate?(result)
                }
            }
        }

        return lastSample
    }

    private func sampleSync(mode: SampleMode) -> [ProcessStats] {
        let maxPids = 20480
        var pids = [pid_t](repeating: 0, count: maxPids)
        let count = proc_listallpids(&pids, Int32(maxPids) * Int32(MemoryLayout<pid_t>.stride))
        guard count > 0 else { return [] }

        let actualCount = min(Int(count), maxPids)
        var result: [ProcessStats] = []

        let now = Date()
        let elapsed = previousTimestamp.map { now.timeIntervalSince($0) } ?? 1.0
        let includesNetwork = mode == .network || mode == .full
        let includesDisk = mode == .disk || mode == .full
        let netStats = includesNetwork ? cachedNetStats : [:]

        for i in 0..<actualCount {
            let pid = pids[i]
            guard pid > 0 else { continue }

            var ptInfo = proc_taskinfo()
            let ptSize = MemoryLayout<proc_taskinfo>.size
            let infoResult = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ptInfo, Int32(ptSize))
            guard infoResult == Int32(ptSize) else { continue }

            let name = resolveName(for: pid)

            let memoryBytes = ptInfo.pti_resident_size
            let cpuTotal = ptInfo.pti_total_user + ptInfo.pti_total_system

            var cpuPercent = 0.0
            if let prev = previousCPU[pid] {
                let cpuDelta = Double(cpuTotal) - Double(prev)
                cpuPercent = (cpuDelta / (elapsed * 1_000_000_000.0)) * 100.0
                cpuPercent = max(0, min(100, cpuPercent))
            }
            previousCPU[pid] = cpuTotal

            var downloadKBps = 0.0
            var uploadKBps = 0.0
            var diskReadKBps = 0.0
            var diskWriteKBps = 0.0
            if includesNetwork, let net = netStats[pid] {
                if let prevIn = previousNetIn[pid], let prevOut = previousNetOut[pid] {
                    downloadKBps = Double(safeDelta(current: net.bytesIn, previous: prevIn)) / 1024.0 / elapsed
                    uploadKBps = Double(safeDelta(current: net.bytesOut, previous: prevOut)) / 1024.0 / elapsed
                }
                previousNetIn[pid] = net.bytesIn
                previousNetOut[pid] = net.bytesOut
            }

            if includesNetwork, (downloadKBps > 0 || uploadKBps > 0) {
                recentNetworkActivity[pid] = RecentNetworkActivity(
                    downloadKBps: downloadKBps,
                    uploadKBps: uploadKBps,
                    timestamp: now
                )
            } else if includesNetwork, let recent = recentNetworkActivity[pid],
                      now.timeIntervalSince(recent.timestamp) <= recentActivityRetention {
                downloadKBps = recent.downloadKBps
                uploadKBps = recent.uploadKBps
            }

            if includesDisk && diskSampleCount % 3 == 0 {
                var usage = rusage_info_v4()
                let rusageResult = withUnsafeMutablePointer(to: &usage) { usagePointer in
                    usagePointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { reboundPointer in
                        proc_pid_rusage(pid, RUSAGE_INFO_V4, reboundPointer)
                    }
                }
                if rusageResult == 0 {
                    let bytesRead = usage.ri_diskio_bytesread
                    let bytesWritten = usage.ri_diskio_byteswritten

                    if let prevRead = previousDiskRead[pid], let prevWrite = previousDiskWrite[pid] {
                        diskReadKBps = Double(safeDelta(current: bytesRead, previous: prevRead)) / 1024.0 / elapsed
                        diskWriteKBps = Double(safeDelta(current: bytesWritten, previous: prevWrite)) / 1024.0 / elapsed
                    }

                    previousDiskRead[pid] = bytesRead
                    previousDiskWrite[pid] = bytesWritten
                }

                if diskReadKBps > 0 || diskWriteKBps > 0 {
                    recentDiskActivity[pid] = RecentDiskActivity(
                        readKBps: diskReadKBps,
                        writeKBps: diskWriteKBps,
                        timestamp: now
                    )
                } else if let recent = recentDiskActivity[pid],
                          now.timeIntervalSince(recent.timestamp) <= recentActivityRetention {
                    diskReadKBps = recent.readKBps
                    diskWriteKBps = recent.writeKBps
                }
            }

            result.append(ProcessStats(
                pid: pid, name: name, cpuUsage: cpuPercent,
                memoryBytes: memoryBytes,
                downloadKBps: downloadKBps, uploadKBps: uploadKBps,
                diskReadKBps: diskReadKBps, diskWriteKBps: diskWriteKBps
            ))
        }

        if includesNetwork {
            recentNetworkActivity = recentNetworkActivity.filter {
                now.timeIntervalSince($0.value.timestamp) <= recentActivityRetention
            }
            fetchNettopStatsAsync()
        }
        if includesDisk {
            recentDiskActivity = recentDiskActivity.filter {
                now.timeIntervalSince($0.value.timestamp) <= recentActivityRetention
            }
            diskSampleCount += 1
        }
        previousTimestamp = now

        // Prune stale PID caches every 10 samples
        sampleCount += 1
        if sampleCount % 10 == 0 {
            let livePids = Set(pids[0..<actualCount])
            nameCache = nameCache.filter { livePids.contains($0.key) }
            previousCPU = previousCPU.filter { livePids.contains($0.key) }
            previousNetIn = previousNetIn.filter { livePids.contains($0.key) }
            previousNetOut = previousNetOut.filter { livePids.contains($0.key) }
            previousDiskRead = previousDiskRead.filter { livePids.contains($0.key) }
            previousDiskWrite = previousDiskWrite.filter { livePids.contains($0.key) }
        }

        return result.sorted {
            let lhsNet = $0.downloadKBps + $0.uploadKBps
            let rhsNet = $1.downloadKBps + $1.uploadKBps
            if lhsNet != rhsNet {
                return lhsNet > rhsNet
            }
            return $0.cpuUsage > $1.cpuUsage
        }
    }

    private func safeDelta(current: UInt64, previous: UInt64) -> UInt64 {
        current >= previous ? (current - previous) : 0
    }

    private func resolveName(for pid: Int32) -> String {
        if let cached = nameCache[pid] { return cached }

        var nameBuf = [CChar](repeating: 0, count: Int(MAXCOMLEN) + 1)
        let nameLen = proc_name(pid, &nameBuf, UInt32(MemoryLayout<CChar>.stride * (Int(MAXCOMLEN) + 1)))

        if nameLen > 0 {
            let name = String(cString: nameBuf)
            if !name.isEmpty {
                nameCache[pid] = name
                return name
            }
        }

        let pathBuffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(MAXPATHLEN))
        defer { pathBuffer.deallocate() }
        let result = proc_pidpath(pid, pathBuffer, UInt32(MAXPATHLEN))
        if result > 0 {
            let path = String(cString: pathBuffer)
            let url = URL(fileURLWithPath: path)
            for component in url.pathComponents {
                if component.hasSuffix(".app") {
                    let appName = String(component.dropLast(4))
                    nameCache[pid] = appName
                    return appName
                }
            }
            let exeName = url.lastPathComponent
            nameCache[pid] = exeName
            return exeName
        }

        let fallback = "PID \(pid)"
        nameCache[pid] = fallback
        return fallback
    }

    private func fetchNettopStatsAsync() {
        guard (lastNettopFetch.map { Date().timeIntervalSince($0) > 15 } ?? true) else { return }
        lastNettopFetch = Date()

        nettopFetchCount += 1
        let fetchId = nettopFetchCount

        nettopQueue.async { [weak self] in
            guard let self = self else { return }
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
            task.arguments = ["-P", "-l", "1", "-J", "bytes_in,bytes_out", "-x"]
            task.standardOutput = Pipe()

            do {
                try task.run()
                let data = (task.standardOutput as! Pipe).fileHandleForReading.readDataToEndOfFile()
                task.waitUntilExit()

                guard let output = String(data: data, encoding: .utf8) else { return }
                let stats = self.parseNettopOutput(output)

                if fetchId == self.nettopFetchCount && !stats.isEmpty {
                    DispatchQueue.main.async {
                        self.cachedNetStats = stats
                    }
                }
            } catch {
            }
        }
    }

    private func parseNettopOutput(_ output: String) -> [Int32: (bytesIn: UInt64, bytesOut: UInt64)] {
        var result: [Int32: (bytesIn: UInt64, bytesOut: UInt64)] = [:]
        let lines = output.split(separator: "\n")
        guard lines.count > 1 else { return result }

        for line in lines.dropFirst(1) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            let fields = trimmed
                .split(maxSplits: 2, whereSeparator: { $0.isWhitespace })
                .map(String.init)
            guard fields.count == 3 else { continue }

            let namePid = fields[0]
            guard let dotIndex = namePid.lastIndex(of: "."),
                  let pid = Int32(namePid[namePid.index(after: dotIndex)...]) else { continue }

            let bytesIn = UInt64(fields[1].replacingOccurrences(of: ",", with: "")) ?? 0
            let bytesOut = UInt64(fields[2].replacingOccurrences(of: ",", with: "")) ?? 0

            result[pid] = (bytesIn: bytesIn, bytesOut: bytesOut)
        }

        return result
    }
}
