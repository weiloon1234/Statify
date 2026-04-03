import Foundation

final class HistoryTracker {
    private var buffer: ContiguousArray<Double>
    private var head = 0
    private var count = 0
    private let maxPoints: Int
    private let key: String

    init(maxPoints: Int = 30, key: String = "") {
        self.maxPoints = maxPoints
        self.key = key
        self.buffer = ContiguousArray(repeating: 0, count: maxPoints)
        load()
        if count == 0 {
            count = maxPoints
        }
    }

    func add(_ value: Double) {
        buffer[head] = value
        head = (head + 1) % maxPoints
        if count < maxPoints { count += 1 }
        scheduleSave()
    }

    var values: [Double] {
        var result = [Double]()
        result.reserveCapacity(count)
        for i in 0..<count {
            let idx = (head - count + i + maxPoints) % maxPoints
            result.append(buffer[idx])
        }
        return result
    }

    var isEmpty: Bool { count == 0 }

    private let saveQueue = DispatchQueue(label: "com.statify.history.save", qos: .utility)
    private var lastSave: Date?

    private func scheduleSave() {
        guard !key.isEmpty else { return }
        if let lastSave, Date().timeIntervalSince(lastSave) < 5 { return }
        lastSave = Date()
        let snapshot = self.buffer
        let saveCount = count
        let saveHead = head
        let saveMax = maxPoints
        saveQueue.async { [key] in
            var data: [[Double]] = []
            data.reserveCapacity(saveCount)
            for i in 0..<saveCount {
                let idx = (saveHead - saveCount + i + saveMax) % saveMax
                data.append([0, snapshot[idx]])
            }
            UserDefaults.standard.set(data, forKey: "history_\(key)")
        }
    }

    private func load() {
        guard !key.isEmpty,
              let data = UserDefaults.standard.array(forKey: "history_\(key)") as? [[Double]] else { return }
        for pair in data.prefix(maxPoints) {
            guard pair.count >= 2 else { continue }
            buffer[count % maxPoints] = pair[1]
            count += 1
        }
    }
}

struct DiskIOStats {
    var readKBps: Double
    var writeKBps: Double
}

struct NetworkHistory {
    var download: [Double] = []
    var upload: [Double] = []
}
