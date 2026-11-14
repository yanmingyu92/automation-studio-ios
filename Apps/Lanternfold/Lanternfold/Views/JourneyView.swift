import SwiftData
import SwiftUI

struct JourneyView: View {
    @Environment(Navigator.self) private var navigator
    @Environment(StoreManager.self) private var store
    @Query(filter: #Predicate<PuzzleRecord> { $0.kind == "journey" }) private var records: [PuzzleRecord]

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(JourneyPack.all) { pack in
                    packCard(pack)
                }
            }
            .padding(16)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Journey")
    }

    private func packCard(_ pack: JourneyPack) -> some View {
        let prefix = "journey:\(pack.index):"
        let solved = records.filter { $0.isComplete && $0.key.hasPrefix(prefix) }.count
        let paid = !pack.isFree && !store.isPro
        return Button {
            navigator.open(.pack(pack.index))
        } label: {
            Card {
                HStack(spacing: 14) {
                    PackThumbnail(size: pack.size, tintIndex: pack.index)
                        .frame(width: 60, height: 60)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(pack.name)
                                .font(.headline)
                                .foregroundStyle(Palette.ink)
                            Spacer()
                            if paid {
                                Pill(text: "\(PuzzleSource.freeSampleLevels) free · Full Garden", systemImage: "lock.fill")
                            }
                        }
                        Text("\(pack.size)×\(pack.size) · \(pack.blurb)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        ProgressView(value: Double(solved), total: Double(pack.levelCount))
                            .tint(Palette.plot(pack.index))
                            .accessibilityHidden(true)
                        Text("\(solved) of \(pack.levelCount) solved")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(paid ? "The first \(PuzzleSource.freeSampleLevels) gardens are free; the rest need the Full Garden" : "Shows the gardens in this pack")
    }
}

/// A tiny garden in the pack's size and colour.
struct PackThumbnail: View {
    let size: Int
    let tintIndex: Int

    var body: some View {
        Canvas { context, canvas in
            let step = canvas.width / CGFloat(size)
            for row in 0..<size {
                for column in 0..<size {
                    let plot = (row / 2 + column / 3 + tintIndex) % 3 == 0 ? tintIndex : tintIndex + 1 + (row / 2 + column / 3) % 3
                    let rect = CGRect(x: CGFloat(column) * step, y: CGFloat(row) * step, width: step + 0.5, height: step + 0.5)
                    context.fill(Path(rect), with: .color(Palette.plot(plot)))
                }
            }
            for line in 1..<size {
                var path = Path()
                path.move(to: CGPoint(x: CGFloat(line) * step, y: 0))
                path.addLine(to: CGPoint(x: CGFloat(line) * step, y: canvas.height))
                path.move(to: CGPoint(x: 0, y: CGFloat(line) * step))
                path.addLine(to: CGPoint(x: canvas.width, y: CGFloat(line) * step))
                context.stroke(path, with: .color(Palette.boardLine.opacity(0.25)), lineWidth: 0.5)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Palette.boardLine, lineWidth: 2)
        }
        .accessibilityHidden(true)
    }
}

struct PackView: View {
    let packIndex: Int

    @Environment(Navigator.self) private var navigator
    @Environment(StoreManager.self) private var store
    @Query(filter: #Predicate<PuzzleRecord> { $0.kind == "journey" }) private var records: [PuzzleRecord]

    private var pack: JourneyPack? { JourneyPack.all.first { $0.index == packIndex } }

    var body: some View {
        ScrollView {
            if let pack {
                let states = Dictionary(uniqueKeysWithValues: records.map { ($0.key, $0) })
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 68), spacing: 10)], spacing: 10) {
                    ForEach(0..<pack.levelCount, id: \.self) { level in
                        let source = PuzzleSource.journey(pack: pack.index, level: level)
                        levelButton(level, pack: pack, source: source, record: states[source.key])
                    }
                }
                .padding(16)
                .frame(maxWidth: 640)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(pack?.name ?? "Journey")
    }

    private func levelButton(_ level: Int, pack: JourneyPack, source: PuzzleSource, record: PuzzleRecord?) -> some View {
        let solved = record?.isComplete == true
        let started = record?.isStarted == true && !solved
        let locked = !source.isUnlocked(isPro: store.isPro)
        let status = locked ? "needs the Full Garden" : (solved ? "solved" : (started ? "in progress" : "not started"))
        let accent = Palette.plot(pack.index)
        return Button {
            navigator.play(source, isPro: store.isPro)
        } label: {
            VStack(spacing: 2) {
                Text("\(level + 1)")
                    .font(.title3.bold())
                if locked {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(.secondary)
                } else if solved, let record {
                    Text(Clock.text(record.elapsed)).font(.caption2.monospacedDigit())
                } else {
                    Image(systemName: started ? "circle.lefthalf.filled" : "circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(solved ? accent : Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(solved ? Palette.boardLine.opacity(0.5) : Palette.ink.opacity(0.12), lineWidth: solved ? 1.5 : 1)
            }
            .foregroundStyle(solved ? Palette.boardLine : Palette.ink)
            .opacity(locked ? 0.6 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Garden \(level + 1), \(pack.difficulty(level: level).title), \(status)")
    }
}

struct ArchiveView: View {
    @Environment(Navigator.self) private var navigator
    @Environment(StoreManager.self) private var store
    @Query(filter: #Predicate<PuzzleRecord> { $0.kind == "daily" }) private var records: [PuzzleRecord]
    @State private var today = DayStamp.today

    var body: some View {
        let states = Dictionary(uniqueKeysWithValues: records.map { ($0.key, $0) })
        let count = max(1, today.days(since: .epoch) + 1)
        List {
            ForEach(0..<count, id: \.self) { offset in
                let day = today.adding(days: -offset)
                let source = PuzzleSource.daily(day)
                row(day: day, source: source, record: states[source.key])
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Daily archive")
        .onAppear { today = .today }
    }

    private func row(day: DayStamp, source: PuzzleSource, record: PuzzleRecord?) -> some View {
        let locked = !source.isUnlocked(isPro: store.isPro, today: today)
        let request = source.request
        return Button {
            navigator.play(source, isPro: store.isPro)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(source.title) · \(day.displayText)")
                        .font(.headline)
                        .foregroundStyle(Palette.ink)
                    Text("\(request.size)×\(request.size) · \(request.difficulty?.title ?? "Mixed")")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if locked {
                    Image(systemName: "lock.fill").foregroundStyle(.secondary)
                        .accessibilityLabel("Full Garden")
                } else if let record, record.isComplete {
                    Label(Clock.text(record.elapsed), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Solved in \(Clock.spoken(record.elapsed))")
                } else if record?.isStarted == true {
                    Text("In progress").foregroundStyle(.secondary)
                }
            }
        }
        .listRowBackground(Palette.surface)
    }
}

struct EndlessView: View {
    @Environment(Navigator.self) private var navigator
    @Environment(StoreManager.self) private var store
    @Query(filter: #Predicate<PuzzleRecord> { $0.kind == "endless" }, sort: \PuzzleRecord.updatedAt, order: .reverse)
    private var records: [PuzzleRecord]
    @AppStorage("endlessSize") private var size = 7
    @AppStorage("endlessDifficulty") private var difficultyRaw = 0
    @AppStorage("endlessStones") private var stonesRaw = StonePolicy.allowed.rawValue

    var body: some View {
        Form {
            if store.isPro {
                Section("New garden") {
                    Picker("Size", selection: $size) {
                        ForEach(Array(PuzzleGenerator.supportedSizes), id: \.self) { value in
                            Text("\(value)×\(value)").tag(value)
                        }
                    }
                    Picker("Difficulty", selection: $difficultyRaw) {
                        Text("Any").tag(0)
                        ForEach(Difficulty.allCases, id: \.rawValue) { value in
                            Text(value.title).tag(value.rawValue)
                        }
                    }
                    Picker("Stones", selection: $stonesRaw) {
                        Text("None").tag(StonePolicy.none.rawValue)
                        Text("Sometimes").tag(StonePolicy.allowed.rawValue)
                        Text("Always").tag(StonePolicy.required.rawValue)
                    }
                    Button {
                        let request = GeneratorRequest(
                            size: size,
                            difficulty: Difficulty(rawValue: difficultyRaw),
                            stones: StonePolicy(rawValue: stonesRaw) ?? .allowed
                        )
                        navigator.play(.endless(id: UUID().uuidString, request: request), isPro: true)
                    } label: {
                        Label("Grow a new garden", systemImage: "leaf.fill")
                    }
                }
                let unfinished = records.filter { !$0.isComplete }
                if !unfinished.isEmpty {
                    Section("Unfinished") {
                        ForEach(unfinished) { record in
                            if let source = PuzzleSource(record: record) {
                                Button {
                                    navigator.play(source, isPro: true)
                                } label: {
                                    LabeledContent("\(record.size)×\(record.size) · \(record.difficulty.title)", value: Clock.text(record.elapsed))
                                }
                            }
                        }
                    }
                }
                Section {
                    LabeledContent("Endless gardens solved", value: "\(records.filter(\.isComplete).count)")
                }
            } else {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Endless is part of the Full Garden", systemImage: "infinity")
                            .font(.headline)
                        Text("Grow a fresh, uniquely solvable garden whenever you like: any size from 5×5 to 9×9, any difficulty, with or without stones.")
                            .foregroundStyle(.secondary)
                        Button("See the Full Garden") { navigator.showingPaywall = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Endless")
    }
}
