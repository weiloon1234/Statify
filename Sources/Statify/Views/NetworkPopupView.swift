import SwiftUI
import AppKit
import Darwin

struct NetworkBarChart: View {
    let downloadValues: [Double]
    let uploadValues: [Double]

    var body: some View {
        GeometryReader { geo in
            let count = max(downloadValues.count, uploadValues.count, 1)
            let groupGap: CGFloat = 1
            let barGap: CGFloat = 1
            let totalGaps = CGFloat(count - 1) * groupGap
            let availableWidth = geo.size.width - totalGaps
            let groupWidth = max(4.0, availableWidth / CGFloat(count))
            let barWidth = max(1.5, (groupWidth - barGap) / 2)
            let maxVal = max(downloadValues.max() ?? 1, uploadValues.max() ?? 1, 1)
            let midY = geo.size.height / 2
            let maxBarH = midY - 2

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: midY))
                    path.addLine(to: CGPoint(x: geo.size.width, y: midY))
                }
                .stroke(style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                .foregroundColor(CP.textDim.opacity(0.3))

                ForEach(0..<count, id: \.self) { i in
                    let groupX = CGFloat(i) * (groupWidth + groupGap)
                    let downVal = i < downloadValues.count ? downloadValues[i] : 0
                    let upVal = i < uploadValues.count ? uploadValues[i] : 0

                    let downH = CGFloat(downVal / maxVal) * maxBarH
                    let upH = CGFloat(upVal / maxVal) * maxBarH

                    if downH > 0 {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(CP.download.opacity(0.8))
                            .frame(width: barWidth, height: max(1, downH))
                            .position(x: groupX + barWidth / 2, y: midY + max(0.5, downH / 2))
                    }

                    if upH > 0 {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(CP.upload.opacity(0.8))
                            .frame(width: barWidth, height: max(1, upH))
                            .position(x: groupX + barWidth + barGap + barWidth / 2, y: midY - max(0.5, upH / 2))
                    }
                }
            }
        }
        .frame(height: 70)
    }
}

struct CopyableRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(CP.fontSansSmall)
                .foregroundColor(CP.textMuted)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(CP.fontMono)
                .foregroundColor(CP.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }) {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 9))
                    .foregroundColor(CP.textDim)
            }
            .buttonStyle(.plain)
            .help("Copy")
        }
        .padding(.vertical, 1)
    }
}

struct CompactProcessRow: View {
    let process: ProcessStats

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: ProcessIconCache.icon(for: process.pid))
                .resizable()
                .frame(width: 14, height: 14)
            Text(truncatedName(process.name))
                .font(CP.fontSansSmall)
                .foregroundColor(CP.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            if process.downloadKBps > 0 || process.uploadKBps > 0 {
                Text(String(format: "↓%.0f", process.downloadKBps))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(CP.download.opacity(0.9))
                Text(String(format: "↑%.0f", process.uploadKBps))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(CP.upload.opacity(0.9))
            } else {
                Text(String(format: "%.1f%%", process.cpuUsage))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(CP.upload.opacity(0.9))
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
    }

    private func truncatedName(_ name: String) -> String {
        if name.count > 14 {
            return String(name.prefix(12)) + "…"
        }
        return name
    }
}

func formatNetSpeed(_ kbps: Double) -> String {
    if kbps >= 1_048_576 {
        return String(format: "%.1f GB/s", kbps / 1_048_576)
    } else if kbps >= 1024 {
        return String(format: "%.1f MB/s", kbps / 1024)
    } else {
        return String(format: "%.0f KB/s", kbps)
    }
}

struct NetworkPopupView: View {
    @ObservedObject var state: AppState
    var stats: SystemStats { state.stats }
    var netInfo: NetworkInfo { state.networkInfo }
    private var netProcesses: [ProcessStats] {
        state.processes
            .filter { $0.downloadKBps > 0 || $0.uploadKBps > 0 }
            .sorted { ($0.downloadKBps + $0.uploadKBps) > ($1.downloadKBps + $1.uploadKBps) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            networkSpeedSection
            networkChartSection
            networkInfoSection
            processSection
        }
        .padding(8)
    }

    var networkSpeedSection: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(CP.upload)
                    .frame(width: 6, height: 6)
                Text(formatNetSpeed(stats.uploadKBps))
                    .font(CP.fontMono)
                    .foregroundColor(CP.upload)
                Text("Upload")
                    .font(CP.fontSansSmall)
                    .foregroundColor(CP.textMuted)
            }
            Spacer()
            HStack(spacing: 6) {
                Text("Download")
                    .font(CP.fontSansSmall)
                    .foregroundColor(CP.textMuted)
                Text(formatNetSpeed(stats.downloadKBps))
                    .font(CP.fontMono)
                    .foregroundColor(CP.download)
                Circle()
                    .fill(CP.download)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(CP.panel)
        .cornerRadius(14)
    }

    var networkChartSection: some View {
        NetworkBarChart(
            downloadValues: state.netDownloadHistory.values,
            uploadValues: state.netUploadHistory.values
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(CP.panel)
        .cornerRadius(14)
    }

    var networkInfoSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let wifi = netInfo.wifiName {
                CopyableRow(label: "Wi-Fi", value: wifi)
            }
            if let publicIP = netInfo.publicIP {
                if let flag = netInfo.countryFlag, let country = netInfo.countryName, !flag.isEmpty {
                    CopyableRow(label: "Public IP", value: "\(flag) \(publicIP)")
                    HStack(spacing: 4) {
                        Text("").frame(width: 60)
                        Text(country)
                            .font(CP.fontSansSmall)
                            .foregroundColor(CP.textMuted)
                        Spacer()
                    }
                } else {
                    CopyableRow(label: "Public IP", value: publicIP)
                }
            }
            if let localIP = netInfo.localIP {
                CopyableRow(label: "Local IP", value: localIP)
            }
            if let routerIP = netInfo.routerIP {
                CopyableRow(label: "Router", value: routerIP)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CP.panel)
        .cornerRadius(14)
    }

    var processSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(CP.download)
                Text("TOP PROCESSES")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(CP.download)
                    .tracking(0.8)
                Spacer()
                Text("↓")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(CP.download)
                    .frame(width: 34, alignment: .trailing)
                Text("↑")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(CP.upload)
                    .frame(width: 34, alignment: .trailing)
            }

            if !netProcesses.isEmpty {
                ForEach(Array(netProcesses.prefix(8).enumerated()), id: \.element.id) { _, p in
                    NetworkProcessRow(process: p)
                }
            } else {
                Text("No active network processes")
                    .font(CP.fontSansSmall)
                    .foregroundColor(CP.textDim)
                    .padding(.vertical, 6)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(CP.panel)
        .cornerRadius(14)
    }
}

struct NetworkProcessRow: View {
    let process: ProcessStats

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: ProcessIconCache.icon(for: process.pid))
                .resizable()
                .frame(width: 14, height: 14)
            Text(truncatedName(process.name))
                .font(CP.fontSansSmall)
                .foregroundColor(CP.text)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text(compactRate(process.downloadKBps))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(CP.download)
                .frame(width: 34, alignment: .trailing)
            Text(compactRate(process.uploadKBps))
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(CP.upload)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
    }

    private func compactRate(_ kbps: Double) -> String {
        if kbps <= 0 {
            return "-"
        }
        if kbps >= 1024 {
            return String(format: "%.1fM", kbps / 1024)
        }
        return String(format: "%.0fK", kbps)
    }

    private func truncatedName(_ name: String) -> String {
        if name.count > 14 {
            return String(name.prefix(12)) + "…"
        }
        return name
    }
}
