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
        let locked = !pack.isFree && !store.isPro
        return Button {
            if locked {
                navigator.showingPaywall = true
            } else {
                navigator.open(.pack(pack.index))
            }
        } label: {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(pack.name)
                            .font(.headline)
                            .foregroundStyle(Palette.ink)
                        Spacer()
                        if locked {
                            Pill(text: "Full Garden", systemImage: "lock.fill")
                        } else {
                            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                        }
                    }
                    Text("\(pack.size)×\(pack.size) · \(pack.blurb)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: Double(solved), total: Double(pack.levelCount))
                        .accessibilityHidden(true)
                    Text("\(solved) of \(pack.levelCount) solved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint(locked ? "Opens the Full Garden purchase" : "Shows the gardens in this pack")
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
        let status = solved ? "solved" : (started ? "in progress" : "not started")
        return Button {
            navigator.play(source, isPro: store.isPro)
        } label: {
            VStack(spacing: 4) {
                Text("\(level + 1)")
                    .font(.title3.bold())
                Image(systemName: solved ? "checkmark.circle.fill" : (started ? "circle.lefthalf.filled" : "circle"))
                    .font(.footnote)
                    .foregroundStyle(solved ? Color.accentColor : Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 60)
            .background(solved ? Color.accentColor.opacity(0.16) : Palette.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Palette.ink.opacity(0.1), lineWidth: 1)
            }
            .foregroundStyle(Palette.ink)
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
