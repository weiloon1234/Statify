import SwiftUI

enum CP {
    static let bg = Color(hex: "06080f")
    static let bgGradEnd = Color(hex: "0a0f1a")
    static let panel = Color(hex: "0f1624")
    static let panelBorder = Color(hex: "1a2235")
    static let surface = Color(hex: "0d1220")

    static let primary = Color(hex: "00d4ff")
    static let download = Color(hex: "3b82f6")
    static let upload = Color(hex: "ef4444")
    static let accent = Color(hex: "a855f7")
    static let success = Color(hex: "22c55e")
    static let warning = Color(hex: "f59e0b")

    static let text = Color(hex: "e2e8f0")
    static let textMuted = Color(hex: "64748b")
    static let textDim = Color(hex: "475569")

    static let fontMono = Font.custom("SF Mono", size: 11).monospaced()
    static let fontMonoSmall = Font.custom("SF Mono", size: 9).monospaced()
    static let fontMonoLarge = Font.custom("SF Mono", size: 14).monospaced()
    static let fontMonoXLarge = Font.custom("SF Mono", size: 18).monospaced()

    static let fontSans = Font.system(size: 11, weight: .regular, design: .default)
    static let fontSansSmall = Font.system(size: 9, weight: .light, design: .default)
    static let fontSansBold = Font.system(size: 11, weight: .semibold, design: .default)
    static let fontSansLarge = Font.system(size: 14, weight: .semibold, design: .default)

    static func subtleGlow(color: Color) -> some ViewModifier {
        SubtleGlow(color: color, radius: 3)
    }

    static func edgeGlow(color: Color) -> some ViewModifier {
        EdgeGlow(color: color)
    }

    static func valueColor(for usage: Double) -> Color {
        if usage > 80 { return upload }
        if usage > 50 { return warning }
        if usage > 25 { return success }
        return primary
    }
}

struct SubtleGlow: ViewModifier {
    let color: Color
    let radius: CGFloat

    func body(content: Content) -> some View {
        content
            .shadow(color: color.opacity(0.3), radius: radius)
    }
}

struct EdgeGlow: ViewModifier {
    let color: Color

    func body(content: Content) -> some View {
        content
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(color.opacity(0.15), lineWidth: 0.5)
            )
            .shadow(color: color.opacity(0.08), radius: 4, y: 2)
    }
}

struct CornerAccent: View {
    let color: Color

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 8))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 8, y: 0))
            }
            .stroke(color.opacity(0.4), lineWidth: 1)

            Path { path in
                path.move(to: CGPoint(x: 0, y: 12))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: 12, y: 0))
            }
            .stroke(color.opacity(0.15), lineWidth: 0.5)
        }
        .frame(width: 12, height: 12)
    }
}

struct MicroLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 7, weight: .light, design: .monospaced))
            .foregroundColor(CP.textDim)
            .tracking(0.5)
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r) / 255, green: Double(g) / 255,
                  blue: Double(b) / 255, opacity: Double(a) / 255)
    }
}
