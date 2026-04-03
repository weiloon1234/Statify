import SwiftUI

struct ProcessRow: View {
    let process: ProcessStats
    let showNetwork: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(process.name).font(CP.fontMono).foregroundColor(CP.text)
                .lineLimit(1).truncationMode(.tail)
            Spacer()
            Text(String(format: "%.1f%%", process.cpuUsage))
                .font(CP.fontMonoSmall).foregroundColor(CP.warning)
            Text(formatBytes(process.memoryBytes))
                .font(CP.fontMonoSmall).foregroundColor(CP.success)
            if showNetwork {
                Text(String(format: "↓%.0f↑%.0f", process.downloadKBps, process.uploadKBps))
                    .font(CP.fontSansSmall).foregroundColor(CP.textDim)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824.0
        if gb >= 1.0 { return String(format: "%.1fG", gb) }
        let mb = Double(bytes) / 1_048_576.0
        return String(format: "%.0fM", mb)
    }
}
