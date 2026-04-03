import SwiftUI

struct MenuBarView: View {
    let stats: SystemStats

    var body: some View {
        Text(menuText)
            .font(CP.fontMono)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
    }

    var menuText: String {
        let cpu = String(format: "CPU:%.0f%%", stats.cpuUsage)
        let mem = String(format: "MEM:%.0f%%", stats.memoryUsage)
        let disk = String(format: "SSD:%.0fG", stats.diskUsedGB)
        let net = String(format: "↓%.0f↑%.0f", stats.downloadKBps, stats.uploadKBps)
        let temp = stats.cpuTemp.map { String(format: "%.0f°C", $0) } ?? "--°C"
        return "\(cpu) \(mem) \(disk) \(net) \(temp)"
    }
}
