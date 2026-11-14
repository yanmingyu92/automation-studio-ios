import SwiftUI

/// Thin lines between cells and heavy lines between plots.
private struct BoardLines: Shape {
    let size: Int
    let regions: [Int]
    let heavy: Bool

    func path(in rect: CGRect) -> Path {
        let step = rect.width / CGFloat(size)
        var path = Path()
        for row in 0..<size {
            for column in 0..<size {
                let cell = row * size + column
                if column + 1 < size, (regions[cell] != regions[cell + 1]) == heavy {
                    let x = rect.minX + CGFloat(column + 1) * step
                    path.move(to: CGPoint(x: x, y: rect.minY + CGFloat(row) * step))
                    path.addLine(to: CGPoint(x: x, y: rect.minY + CGFloat(row + 1) * step))
                }
                if row + 1 < size, (regions[cell] != regions[cell + size]) == heavy {
                    let y = rect.minY + CGFloat(row + 1) * step
                    path.move(to: CGPoint(x: rect.minX + CGFloat(column) * step, y: y))
                    path.addLine(to: CGPoint(x: rect.minX + CGFloat(column + 1) * step, y: y))
                }
            }
        }
        return path
    }
}

struct BoardView: View {
    let session: GameSession
    var interactive = true

    @AppStorage(SettingKey.showConflicts) private var showConflicts = true
    @AppStorage(SettingKey.dimBlocked) private var dimBlocked = true
    @AppStorage(SettingKey.lanternFirst) private var lanternFirst = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum StrokeMode {
        case undecided, paint, erase, ignore
    }

    @State private var strokeStart: Int?
    @State private var strokeLast: Int?
    @State private var strokeMode = StrokeMode.undecided

    private var size: Int { session.puzzle.size }

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            let step = side / CGFloat(size)
            let corner = max(8, step * 0.18)
            ZStack(alignment: .topLeading) {
                ForEach(0..<(size * size), id: \.self) { cell in
                    cellView(cell, step: step)
                        .frame(width: step, height: step)
                        .position(x: (CGFloat(cell % size) + 0.5) * step, y: (CGFloat(cell / size) + 0.5) * step)
                }
                BoardLines(size: size, regions: session.puzzle.regions, heavy: false)
                    .stroke(Palette.boardLine.opacity(0.18), lineWidth: 1)
                    .allowsHitTesting(false)
                BoardLines(size: size, regions: session.puzzle.regions, heavy: true)
                    .stroke(Palette.boardLine, style: StrokeStyle(lineWidth: max(2.5, step * 0.07), lineCap: .round))
                    .allowsHitTesting(false)
            }
            .frame(width: side, height: side)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Palette.boardLine, lineWidth: max(3, step * 0.08))
            }
            .contentShape(Rectangle())
            .gesture(interactive ? stroke(step: step) : nil)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Garden, \(size) by \(size)")
    }

    // MARK: Cells

    @ViewBuilder
    private func cellView(_ cell: Int, step: CGFloat) -> some View {
        let mark = session.marks[cell]
        let isStone = session.isStone(cell)
        let inConflict = showConflicts && session.conflicts.contains(cell)
        let isTarget = session.hint?.targets.contains(cell) ?? false
        let inContext = session.hint?.context.contains(cell) ?? false
        let hintActive = session.hint != nil

        ZStack {
            Palette.plot(session.puzzle.regions[cell])
            if hintActive && !inContext && !isTarget {
                Palette.background.opacity(0.45)
            }
            if isStone {
                stoneView(cell, step: step, inConflict: inConflict)
            } else {
                switch mark {
                case .lantern:
                    LanternGlyph(glowing: session.isComplete)
                        .padding(step * 0.04)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
                    if inConflict {
                        Circle()
                            .stroke(Palette.conflict, lineWidth: max(2, step * 0.06))
                            .padding(step * 0.1)
                    }
                case .cross:
                    CrossGlyph()
                        .stroke(Palette.ink.opacity(0.6), style: StrokeStyle(lineWidth: max(1.5, step * 0.045), lineCap: .round))
                case .blank:
                    if dimBlocked && session.blocked.contains(cell) {
                        Circle()
                            .fill(Palette.ink.opacity(0.3))
                            .frame(width: step * 0.12, height: step * 0.12)
                    }
                }
            }
            if isTarget {
                RoundedRectangle(cornerRadius: step * 0.14, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: max(3, step * 0.08))
                    .padding(step * 0.07)
            }
        }
        .animation(reduceMotion ? nil : .spring(duration: 0.22), value: mark)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cellLabel(cell))
        .accessibilityValue(cellValue(cell, mark: mark, isStone: isStone, inConflict: inConflict, isTarget: isTarget))
        .accessibilityAddTraits(isStone || !interactive ? [] : .isButton)
        .modifier(CellActions(enabled: interactive && !isStone && !session.isComplete, session: session, cell: cell, lanternFirst: lanternFirst))
    }

    private func stoneView(_ cell: Int, step: CGFloat, inConflict: Bool) -> some View {
        let clue = session.puzzle.stones[cell] ?? 0
        return ZStack {
            Circle()
                .fill(inConflict ? Palette.conflict : Palette.stone)
                .padding(step * 0.14)
            Text("\(clue)")
                .font(.system(size: step * 0.4, weight: .heavy, design: .rounded))
                .foregroundStyle(Palette.stoneText)
        }
    }

    private func cellLabel(_ cell: Int) -> String {
        "Row \(cell / size + 1), column \(cell % size + 1), \(Palette.plotName(session.puzzle.regions[cell])) plot"
    }

    private func cellValue(_ cell: Int, mark: Mark, isStone: Bool, inConflict: Bool, isTarget: Bool) -> String {
        var parts = [String]()
        if isStone {
            let clue = session.puzzle.stones[cell] ?? 0
            parts.append("stone, \(clue) \(clue == 1 ? "lantern" : "lanterns") around it, \(session.lanternsAround(stoneAt: cell)) placed")
        } else {
            switch mark {
            case .lantern: parts.append("lantern")
            case .cross: parts.append("marked empty")
            case .blank: parts.append(session.blocked.contains(cell) ? "open, seen by a lantern" : "open")
            }
        }
        if inConflict { parts.append("conflict") }
        if isTarget { parts.append("hint") }
        return parts.joined(separator: ", ")
    }

    // MARK: Touch

    private func cell(at point: CGPoint, step: CGFloat) -> Int? {
        let column = Int(floor(point.x / step))
        let row = Int(floor(point.y / step))
        guard row >= 0, row < size, column >= 0, column < size else { return nil }
        return row * size + column
    }

    private func stroke(step: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard !session.isComplete, let cell = cell(at: value.location, step: step) else { return }
                guard let start = strokeStart else {
                    strokeStart = cell
                    strokeLast = cell
                    strokeMode = .undecided
                    return
                }
                guard cell != strokeLast else { return }
                if strokeMode == .undecided {
                    switch session.marks[start] {
                    case .blank: strokeMode = session.isStone(start) ? .ignore : .paint
                    case .cross: strokeMode = .erase
                    case .lantern: strokeMode = .ignore
                    }
                    if strokeMode != .ignore {
                        session.beginGroup()
                        paint(start)
                    }
                }
                paint(cell)
                strokeLast = cell
            }
            .onEnded { _ in
                if let start = strokeStart {
                    if strokeMode == .undecided {
                        session.tap(start, lanternFirst: lanternFirst)
                        feedback(for: start)
                    } else {
                        session.endGroup()
                    }
                }
                strokeStart = nil
                strokeLast = nil
                strokeMode = .undecided
            }
    }

    private func paint(_ cell: Int) {
        switch strokeMode {
        case .paint where session.marks[cell] == .blank:
            session.set(cell, to: .cross)
            Haptics.mark()
        case .erase where session.marks[cell] == .cross:
            session.set(cell, to: .blank)
            Haptics.mark()
        default:
            break
        }
    }

    private func feedback(for cell: Int) {
        if session.isComplete {
            Haptics.solved()
        } else if session.marks[cell] == .lantern {
            Haptics.lantern()
        } else {
            Haptics.mark()
        }
    }
}

/// VoiceOver actions for one cell; touch input is handled by the board's own gesture.
private struct CellActions: ViewModifier {
    let enabled: Bool
    let session: GameSession
    let cell: Int
    let lanternFirst: Bool

    func body(content: Content) -> some View {
        if enabled {
            content
                .accessibilityAction {
                    session.tap(cell, lanternFirst: lanternFirst)
                    announce()
                }
                .accessibilityAction(named: "Place lantern") {
                    session.set(cell, to: .lantern)
                    announce()
                }
                .accessibilityAction(named: "Mark empty") {
                    session.set(cell, to: .cross)
                }
                .accessibilityAction(named: "Clear") {
                    session.set(cell, to: .blank)
                }
        } else {
            content
        }
    }

    private func announce() {
        if session.isComplete {
            Haptics.solved()
            AccessibilityNotification.Announcement("Garden lit. Puzzle solved.").post()
        }
    }
}
