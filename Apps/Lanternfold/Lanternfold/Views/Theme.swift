import SwiftUI
import UIKit

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255,
                alpha: 1
            )
        })
    }
}

enum Palette {
    static let background = Color(light: 0xF7F3EA, dark: 0x101226)
    static let surface = Color(light: 0xFFFDF8, dark: 0x1B1E3A)
    static let ink = Color(light: 0x1F2240, dark: 0xF1ECDD)
    static let boardLine = Color(light: 0x1F2240, dark: 0x0A0B18)
    static let conflict = Color(light: 0xC62828, dark: 0xFF6B6B)
    static let glow = Color(light: 0xFFC83D, dark: 0xFFD466)
    static let lanternTop = Color(light: 0xFFD45C, dark: 0xFFE08A)
    static let lanternBottom = Color(light: 0xE4572E, dark: 0xF0703F)
    static let lanternFrame = Color(light: 0x3A2A1E, dark: 0x1E1410)
    static let stone = Color(light: 0x4A4F63, dark: 0x878DA6)
    static let stoneText = Color(light: 0xFFFFFF, dark: 0x101226)

    private static let plots: [(name: String, color: Color)] = [
        ("amber", Color(light: 0xF6D58A, dark: 0x7A5A1E)),
        ("rose", Color(light: 0xF4B6C0, dark: 0x7B3A48)),
        ("sky", Color(light: 0xA9D3F2, dark: 0x2F5878)),
        ("mint", Color(light: 0xB4E3C3, dark: 0x2E6146)),
        ("lilac", Color(light: 0xCDBDF0, dark: 0x51407F)),
        ("peach", Color(light: 0xF8C3A0, dark: 0x80492B)),
        ("teal", Color(light: 0x9EDBD8, dark: 0x235F5E)),
        ("sand", Color(light: 0xE3DCC6, dark: 0x5E5744)),
        ("slate", Color(light: 0xBCC6D6, dark: 0x414B5E))
    ]

    static func plot(_ index: Int) -> Color {
        plots[index % plots.count].color
    }

    static func plotName(_ index: Int) -> String {
        plots[index % plots.count].name
    }
}

/// A paper lantern drawn from shapes so it scales with the board.
struct LanternGlyph: View {
    var glowing = false

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Palette.glow.opacity(glowing ? 0.95 : 0.7), Palette.glow.opacity(0)],
                        center: .center, startRadius: side * 0.08, endRadius: side * (glowing ? 0.62 : 0.5)
                    ))
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: side * 0.03)
                        .fill(Palette.lanternFrame)
                        .frame(width: side * 0.3, height: side * 0.08)
                    RoundedRectangle(cornerRadius: side * 0.17)
                        .fill(LinearGradient(colors: [Palette.lanternTop, Palette.lanternBottom], startPoint: .top, endPoint: .bottom))
                        .overlay {
                            HStack(spacing: side * 0.1) {
                                ForEach(0..<2, id: \.self) { _ in
                                    Capsule().fill(Palette.lanternFrame.opacity(0.28)).frame(width: side * 0.025)
                                }
                            }
                            .padding(.vertical, side * 0.04)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: side * 0.17)
                                .stroke(Palette.lanternFrame.opacity(0.55), lineWidth: max(1, side * 0.025))
                        }
                        .frame(width: side * 0.46, height: side * 0.44)
                    RoundedRectangle(cornerRadius: side * 0.03)
                        .fill(Palette.lanternFrame)
                        .frame(width: side * 0.24, height: side * 0.07)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

struct CrossGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = min(rect.width, rect.height) * 0.36
        let box = rect.insetBy(dx: inset, dy: inset)
        var path = Path()
        path.move(to: CGPoint(x: box.minX, y: box.minY))
        path.addLine(to: CGPoint(x: box.maxX, y: box.maxY))
        path.move(to: CGPoint(x: box.maxX, y: box.minY))
        path.addLine(to: CGPoint(x: box.minX, y: box.maxY))
        return path
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Palette.ink.opacity(0.08), lineWidth: 1)
            }
    }
}

struct Pill: View {
    let text: String
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(text)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Palette.ink.opacity(0.08), in: Capsule())
    }
}

@MainActor
enum Haptics {
    private static var enabled: Bool {
        UserDefaults.standard.object(forKey: SettingKey.haptics) as? Bool ?? true
    }

    static func mark() {
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func lantern() {
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func solved() {
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

enum SettingKey {
    static let haptics = "haptics"
    static let showConflicts = "showConflicts"
    static let dimBlocked = "dimBlocked"
    static let lanternFirst = "lanternFirst"
    static let showTimer = "showTimer"
    static let seenRules = "seenRules"
}
