import SwiftData
import SwiftUI

struct GameView: View {
    let source: PuzzleSource

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(Navigator.self) private var navigator
    @Environment(StoreManager.self) private var store
    @AppStorage(SettingKey.showTimer) private var showTimer = true
    @State private var session: GameSession?
    @State private var failure: String?
    @State private var confirmingClear = false

    var body: some View {
        Group {
            if let session {
                play(session)
            } else if let failure {
                ContentUnavailableView {
                    Label("This garden could not be opened", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Try again") {
                        self.failure = nil
                        Task { await load() }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Laying out the garden…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle(source.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("How to play", systemImage: "questionmark.circle") { navigator.showingRules = true }
            }
        }
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                session?.resume()
            } else {
                session?.pause()
                try? context.save()
            }
        }
        .onChange(of: navigator.showingRules) { _, showing in
            if showing { session?.pause() } else if scenePhase == .active { session?.resume() }
        }
        .onDisappear {
            session?.pause()
            try? context.save()
        }
    }

    private func load() async {
        guard session == nil else {
            session?.resume()
            return
        }
        let key = source.key
        var descriptor = FetchDescriptor<PuzzleRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        do {
            if let existing = try context.fetch(descriptor).first {
                if let restored = GameSession(source: source, record: existing) {
                    session = restored
                    restored.resume()
                    return
                }
                context.delete(existing)
            }
            let puzzle = await PuzzleFactory.make(source)
            guard !Task.isCancelled else { return }
            let record = try PuzzleRecord(source: source, puzzle: puzzle)
            context.insert(record)
            try context.save()
            guard let fresh = GameSession(source: source, record: record) else {
                failure = "The saved puzzle data is unreadable."
                return
            }
            session = fresh
            fresh.resume()
        } catch {
            failure = error.localizedDescription
        }
    }

    // MARK: Play

    private func play(_ session: GameSession) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                statusRow(session)
                BoardView(session: session)
                    .frame(maxWidth: 560)
                if session.isComplete {
                    solvedCard(session)
                } else {
                    if let hint = session.hint {
                        hintCard(hint, session: session)
                    }
                    controls(session)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
        }
        .confirmationDialog("Clear every mark and lantern?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear the garden", role: .destructive) { session.clearBoard() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func statusRow(_ session: GameSession) -> some View {
        HStack(spacing: 8) {
            Pill(text: "\(session.puzzle.size)×\(session.puzzle.size)")
            Pill(text: session.puzzle.difficulty.title)
            Pill(text: "\(session.lanternsPlaced)/\(session.puzzle.size)", systemImage: "lightbulb.fill")
                .accessibilityLabel("\(session.lanternsPlaced) of \(session.puzzle.size) lanterns placed")
            Spacer()
            if showTimer {
                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let seconds = session.elapsed(at: timeline.date)
                    Text(Clock.text(seconds))
                        .font(.headline.monospacedDigit())
                        .accessibilityLabel("Time \(Clock.spoken(seconds))")
                }
            }
        }
        .frame(maxWidth: 560)
    }

    private func controls(_ session: GameSession) -> some View {
        HStack(spacing: 10) {
            Button {
                session.undo()
            } label: {
                Label("Undo", systemImage: "arrow.uturn.backward").frame(maxWidth: .infinity)
            }
            .disabled(!session.canUndo)
            Button {
                confirmingClear = true
            } label: {
                Label("Clear", systemImage: "trash").frame(maxWidth: .infinity)
            }
            .disabled(!session.hasMarks)
            Button {
                session.requestHint()
            } label: {
                Label("Hint", systemImage: "sparkles").frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(maxWidth: 560)
    }

    private func hintCard(_ hint: ActiveHint, session: GameSession) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Label(hint.message, systemImage: "sparkles")
                    .font(.body)
                    .foregroundStyle(Palette.ink)
                HStack {
                    Button("Do it for me") {
                        session.applyHint()
                        if session.isComplete { Haptics.solved() }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Dismiss") { session.hint = nil }
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: 560)
        .onAppear {
            AccessibilityNotification.Announcement(hint.message).post()
        }
    }

    private func solvedCard(_ session: GameSession) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("Garden lit")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                let hints = session.hintsUsed
                Text("Solved in \(Clock.text(session.elapsed())) with \(hints == 0 ? "no hints" : (hints == 1 ? "1 hint" : "\(hints) hints")).")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Solved in \(Clock.spoken(session.elapsed())) with \(hints == 0 ? "no hints" : (hints == 1 ? "1 hint" : "\(hints) hints"))")
                if case .daily = source, session.record.completedOnDay {
                    Label("Counts toward your daily streak", systemImage: "flame.fill")
                        .font(.subheadline)
                        .foregroundStyle(Color.accentColor)
                }
                HStack {
                    if let next = source.next {
                        Button {
                            navigator.play(next, isPro: store.isPro, replacingCurrent: true)
                        } label: {
                            Label("Next garden", systemImage: "arrow.right")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            if !navigator.path.isEmpty { navigator.path.removeLast() }
                        } label: {
                            Label("Done", systemImage: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    ShareLink(item: session.shareText) {
                        Label("Share result", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: 560)
    }
}
