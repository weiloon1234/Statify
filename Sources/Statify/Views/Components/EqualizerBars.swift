import SwiftUI

struct EqualizerBars: View {
    let usages: [Double]
    let pCoreCount: Int
    let eCoreCount: Int

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            if pCoreCount > 0 {
                coreGroup(label: "P-CORES", count: pCoreCount, offset: 0, color: CP.primary)
            }
            if eCoreCount > 0 {
                coreGroup(label: "E-CORES", count: eCoreCount, offset: pCoreCount, color: CP.success)
            }
            if pCoreCount == 0 && eCoreCount == 0 {
                coreGroup(label: "CORES", count: usages.count, offset: 0, color: CP.primary)
            }
        }
    }

    func coreGroup(label: String, count: Int, offset: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(CP.fontSansSmall).foregroundColor(CP.textMuted).tracking(1)
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 3), count: 4), alignment: .center, spacing: 6) {
                ForEach(0..<count, id: \.self) { i in
                    let idx = offset + i
                    let usage = usages.indices.contains(idx) ? usages[idx] : 0
                    VStack(spacing: 2) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(CP.panel)
                                .frame(width: 12, height: 50)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(CP.valueColor(for: usage))
                                .frame(height: max(1, 50 * usage / 100.0))
                                .frame(width: 12)
                        }
                        Text(String(format: "%.0f", usage))
                            .font(.system(size: 7, design: .monospaced))
                            .foregroundColor(CP.valueColor(for: usage))
                    }
                }
            }
        }
    }
}
