import SwiftUI

struct DetailPanelView: View {
    @ObservedObject var state: AppState
    let onClose: () -> Void

    var stats: SystemStats { state.stats }
    var processes: [ProcessStats] { state.processes }

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Rectangle().fill(CP.panelBorder).frame(height: 0.5)
            quickStatsSection.padding(10).background(CP.panel)
            Rectangle().fill(CP.panelBorder).frame(height: 0.5)
            hardwareSection.padding(10).background(CP.panel)
            Rectangle().fill(CP.panelBorder).frame(height: 0.5)
            coreSection.padding(10).background(CP.panel)
            Rectangle().fill(CP.panelBorder).frame(height: 0.5)
            processSection
        }
        .frame(width: 420, height: 520)
        .background(
            LinearGradient(colors: [CP.bg, CP.bgGradEnd], startPoint: .top, endPoint: .bottom)
        )
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(CP.panelBorder, lineWidth: 0.5)
        )
    }

    var headerSection: some View {
        HStack {
            Text("CYBERMON").font(CP.fontSansLarge).foregroundColor(CP.text).tracking(2)
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(CP.textMuted)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(CP.panel)
    }

    var quickStatsSection: some View {
        HStack(spacing: 16) {
            statBlock(label: "CPU", value: String(format: "%.0f%%", stats.cpuUsage), color: CP.primary)
            statBlock(label: "MEM", value: String(format: "%.0f%%", stats.memoryUsage), color: CP.accent)
            statBlock(label: "SSD", value: String(format: "%.0fG", stats.diskUsedGB), color: CP.warning)
            statBlock(label: "NET", value: String(format: "↓%.0f↑%.0f", stats.downloadKBps, stats.uploadKBps), color: CP.success)
        }
    }

    var hardwareSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("HARDWARE")
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CPU").font(CP.fontSansSmall).foregroundColor(CP.textMuted)
                    Text(stats.cpuGhz.map { String(format: "%.2f GHz", $0) } ?? "-- GHz")
                        .font(CP.fontMono).foregroundColor(CP.primary)
                    Text(stats.cpuTemp.map { String(format: "%.0f°C", $0) } ?? "--°C")
                        .font(CP.fontMono).foregroundColor(CP.warning)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("GPU").font(CP.fontSansSmall).foregroundColor(CP.textMuted)
                    Text(stats.gpuGhz.map { String(format: "%.2f GHz", $0) } ?? "-- GHz")
                        .font(CP.fontMono).foregroundColor(CP.primary)
                    Text(stats.gpuTemp.map { String(format: "%.0f°C", $0) } ?? "--°C")
                        .font(CP.fontMono).foregroundColor(CP.warning)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("FANS").font(CP.fontSansSmall).foregroundColor(CP.textMuted)
                    if stats.fans.isEmpty {
                        Text("--").font(CP.fontMono).foregroundColor(CP.textDim)
                    } else {
                        ForEach(stats.fans) { fan in
                            Text("\(fan.name): \(fan.rpm)rpm \(fan.displayUsage)")
                                .font(CP.fontMonoSmall).foregroundColor(CP.success)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("POWER").font(CP.fontSansSmall).foregroundColor(CP.textMuted)
                    Text(stats.powerWatts.map { String(format: "%.1fW", $0) } ?? "--W")
                        .font(CP.fontMono).foregroundColor(CP.warning)
                }
            }
        }
    }

    var coreSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("CPU CORES")
            EqualizerBars(
                usages: stats.coreUsages,
                pCoreCount: stats.pCoreCount,
                eCoreCount: stats.eCoreCount
            )
        }
    }

    var processSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                sectionSubHeader("TOP PROCESSES")
                let topCPU = processes.filter { $0.cpuUsage > 0 }.prefix(8)
                if topCPU.isEmpty {
                    let topMem = processes.sorted { $0.memoryBytes > $1.memoryBytes }.prefix(8)
                    if topMem.isEmpty {
                        Text("Waiting for data...").font(CP.fontSansSmall).foregroundColor(CP.textDim)
                            .padding(.horizontal, 8)
                    } else {
                        sectionSubHeader("BY MEMORY")
                        ForEach(Array(topMem.enumerated()), id: \.element.id) { _, p in
                            ProcessRow(process: p, showNetwork: false)
                        }
                    }
                } else {
                    ForEach(Array(topCPU.enumerated()), id: \.element.id) { _, p in
                        ProcessRow(process: p, showNetwork: false)
                    }
                }
            }
            .padding(10)
        }
        .frame(maxHeight: 200)
    }

    func statBlock(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(CP.fontSansSmall).foregroundColor(CP.textMuted)
            Text(value).font(CP.fontMonoLarge).foregroundColor(color)
        }
    }

    func sectionHeader(_ title: String) -> some View {
        HStack(spacing: 6) {
            CornerAccent(color: CP.primary)
            Text(title).font(CP.fontSansBold).foregroundColor(CP.text).tracking(1.5)
            Spacer()
            Rectangle().fill(CP.panelBorder).frame(height: 0.5)
        }
    }

    func sectionSubHeader(_ title: String) -> some View {
        Text(title).font(CP.fontSansSmall).foregroundColor(CP.textMuted).tracking(1)
            .padding(.bottom, 4)
    }
}
