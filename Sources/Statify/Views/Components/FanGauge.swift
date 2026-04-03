import SwiftUI

struct FanGauge: View {
    let fan: FanInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(fan.name.uppercased()).font(CP.fontSansSmall).foregroundColor(CP.textMuted)
                Spacer()
                Text("\(fan.rpm) RPM").font(CP.fontMonoSmall).foregroundColor(CP.warning)
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(CP.surface).frame(height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(CP.primary.opacity(0.5))
                    .frame(width: max(4, CGFloat(fan.usagePercent / 100.0) * 120), height: 4)
            }
            Text(fan.displayUsage).font(CP.fontSansSmall).foregroundColor(CP.textDim)
        }
    }
}
