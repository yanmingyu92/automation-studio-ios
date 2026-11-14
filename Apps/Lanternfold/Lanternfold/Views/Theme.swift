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
    static let boardLine = Color(light: 0x1F2240, dark: 0x05060F)
    static let conflict = Color(light: 0xC62828, dark: 0xFF6B6B)
    static let glow = Color(light: 0xFFC83D, dark: 0xFFD466)
    static let lanternCore = Color(light: 0xFFF3B0, dark: 0xFFF6C4)
    static let nightTop = Color(light: 0x2D2A5A, dark: 0x2D2A5A)
    static let nightBottom = Color(light: 0x14163A, dark: 0x14163A)
    static let lanternTop = Color(light: 0xFFD45C, dark: 0xFFE08A)
    static let lanternBottom = Color(light: 0xE4572E, dark: 0xF0703F)
    static let lanternFrame = Color(light: 0x3A2A1E, dark: 0x1E1410)
    static let stone = Color(light: 0x3E4358, dark: 0xECE8DA)
    static let stoneText = Color(light: 0xFFFFFF, dark: 0x101226)

    private static let plots: [(name: String, color: Color)] = [
        ("amber", Color(light: 0xF9D276, dark: 0xC9922E)),
        ("rose", Color(light: 0xF5A9B8, dark: 0xB84A68)),
        ("sky", Color(light: 0x9CCBF5, dark: 0x3F8FD0)),
        ("mint", Color(light: 0xA8E0B5, dark: 0x4FA873)),
        ("lilac", Color(light: 0xC9B5F2, dark: 0x7A5FCC)),
        ("peach", Color(light: 0xF9B98F, dark: 0xD9774A)),
        ("teal", Color(light: 0x7FD3CF, dark: 0x1C8085)),
        ("sand", Color(light: 0xE6DFCB, dark: 0xA39874)),
        ("slate", Color(light: 0xB3BDD0, dark: 0x566384))
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
                        colors: [Palette.glow.opacity(glowing ? 0.95 : 0.75), Palette.glow.opacity(0)],
                        center: .center, startRadius: side * 0.06, endRadius: side * (glowing ? 0.64 : 0.52)
                    ))
                VStack(spacing: -side * 0.01) {
                    Capsule()
                        .fill(Palette.lanternFrame)
                        .frame(width: side * 0.22, height: side * 0.06)
                    Ellipse()
                        .fill(RadialGradient(
                            colors: [Palette.lanternCore, Palette.lanternTop, Palette.lanternBottom],
                            center: UnitPoint(x: 0.5, y: 0.42), startRadius: 0, endRadius: side * 0.3
                        ))
                        .overlay {
                            ZStack {
                                Ellipse().stroke(Palette.lanternFrame.opacity(0.3), lineWidth: max(0.75, side * 0.018))
                                    .frame(width: side * 0.26)
                                Ellipse().stroke(Palette.lanternFrame.opacity(0.3), lineWidth: max(0.75, side * 0.018))
                                    .frame(width: side * 0.06)
                                Ellipse().stroke(Palette.lanternFrame.opacity(0.6), lineWidth: max(1, side * 0.025))
                            }
                        }
                        .frame(width: side * 0.48, height: side * 0.42)
                    Capsule()
                        .fill(Palette.lanternFrame)
                        .frame(width: side * 0.18, height: side * 0.055)
                    Capsule()
                        .fill(Palette.lanternBottom)
                        .frame(width: side * 0.03, height: side * 0.09)
                }
                .offset(y: side * 0.03)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityHidden(true)
    }
}

/// A ring of light that expands once when a lantern is placed.
struct LightRing: View {
    @State private var expanded = false

    var body: some View {
        Circle()
            .stroke(Palette.glow, lineWidth: 3)
            .scaleEffect(expanded ? 1.5 : 0.4)
            .opacity(expanded ? 0 : 0.9)
            .onAppear {
                withAnimation(.easeOut(duration: 0.4)) { expanded = true }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Fireflies that drift up over a solved garden for a few seconds.
struct Fireflies: View {
    let start: Date
    static let duration = 2.6

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let t = timeline.date.timeIntervalSince(start)
                guard t >= 0, t < Self.duration else { return }
                for index in 0..<26 {
                    let seed = Double(index)
                    let delay = (seed.truncatingRemainder(dividingBy: 7)) * 0.09
                    let life = (t - delay) / 1.7
                    guard life > 0, life < 1 else { continue }
                    let baseX = (sin(seed * 12.9898) * 0.5 + 0.5) * size.width
                    let x = baseX + sin(t * 3 + seed) * 10
                    let y = size.height * (0.95 - life * (0.55 + 0.4 * (cos(seed * 4.1) * 0.5 + 0.5)))
                    let radius = 2 + (seed.truncatingRemainder(dividingBy: 3))
                    let alpha = sin(life * .pi)
                    let rect = CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
                    context.fill(Path(ellipseIn: rect.insetBy(dx: -radius, dy: -radius)), with: .color(Palette.glow.opacity(alpha * 0.25)))
                    context.fill(Path(ellipseIn: rect), with: .color(Palette.lanternCore.opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
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

/// Touch and sound feedback for moves; each part can be switched off in Settings.
@MainActor
enum Haptics {
    private static var enabled: Bool {
        UserDefaults.standard.object(forKey: SettingKey.haptics) as? Bool ?? true
    }

    static func mark() {
        SoundPlayer.shared.mark()
        guard enabled else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    static func lantern(column: Int) {
        SoundPlayer.shared.lantern(step: column)
        guard enabled else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func solved(lanterns: Int) {
        SoundPlayer.shared.solved(notes: lanterns)
        guard enabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

enum SettingKey {
    static let haptics = "haptics"
    static let sounds = "sounds"
    static let showConflicts = "showConflicts"
    static let dimBlocked = "dimBlocked"
    static let lanternFirst = "lanternFirst"
    static let showTimer = "showTimer"
    static let seenRules = "seenRules"
}
