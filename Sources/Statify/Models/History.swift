import Foundation

struct HistoryPoint {
    var timestamp: Date
    var value: Double
}

final class HistoryTracker {
    private var points: [HistoryPoint] = []
    private let saveQueue = DispatchQueue(label: "com.statify.history.save", qos: .utility)
    private var pendingSaveWorkItem: DispatchWorkItem?
    let maxPoints: Int
    let key: String

    init(maxPoints: Int = 30, key: String = "") {
        self.maxPoints = maxPoints
        self.key = key
        load()
        if points.isEmpty {
            for _ in 0..<maxPoints {
                points.append(HistoryPoint(timestamp: Date().addingTimeInterval(-Double(maxPoints)), value: 0))
            }
        }
    }

    func add(_ value: Double) {
        points.append(HistoryPoint(timestamp: Date(), value: value))
        if points.count > maxPoints {
            points.removeFirst(points.count - maxPoints)
        }
        scheduleSave()
    }

    var values: [Double] { points.map(\.value) }
    var isEmpty: Bool { points.isEmpty }

    private func scheduleSave() {
        guard !key.isEmpty else { return }
        pendingSaveWorkItem?.cancel()
        let snapshot = points.map { [$0.timestamp.timeIntervalSince1970, $0.value] }
        let workItem = DispatchWorkItem { [key] in
            UserDefaults.standard.set(snapshot, forKey: "history_\(key)")
        }
        pendingSaveWorkItem = workItem
        saveQueue.asyncAfter(deadline: .now() + 1.0, execute: workItem)
    }

    private func save() {
        guard !key.isEmpty else { return }
        let data = points.map { [$0.timestamp.timeIntervalSince1970, $0.value] }
        UserDefaults.standard.set(data, forKey: "history_\(key)")
    }

    private func load() {
        guard !key.isEmpty,
              let data = UserDefaults.standard.array(forKey: "history_\(key)") as? [[Double]] else { return }
        points = data.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return HistoryPoint(timestamp: Date(timeIntervalSince1970: pair[0]), value: pair[1])
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
