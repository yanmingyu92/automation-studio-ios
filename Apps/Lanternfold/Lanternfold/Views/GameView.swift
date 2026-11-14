import StoreKit
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
    @State private var solvedAt: Date?
    @State private var reminderNote: String?
    @Query private var records: [PuzzleRecord]
    @Environment(\.requestReview) private var requestReview
    @AppStorage("lastReviewRequest") private var lastReviewRequest = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                if !navigator.showingRules && !navigator.showingPaywall { session?.resume() }
            } else {
                session?.pause()
                try? context.save()
            }
        }
        .onChange(of: navigator.showingRules || navigator.showingPaywall) { _, showing in
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
                    start(restored)
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
            start(fresh)
        } catch {
            failure = error.localizedDescription
        }
    }

    private func start(_ session: GameSession) {
        let context = context
        session.onPersist = { try? context.save() }
        self.session = session
        if !navigator.showingRules && !navigator.showingPaywall {
            session.resume()
        }
    }

    // MARK: Play

    private func play(_ session: GameSession) -> some View {
        GeometryReader { screen in
            playContent(session, boardLimit: max(240, min(720, screen.size.height - 230)))
        }
    }

    private func playContent(_ session: GameSession, boardLimit: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                statusRow(session)
                BoardView(session: session)
                    .frame(maxWidth: boardLimit)
                    .overlay {
                        if let solvedAt, !reduceMotion {
                            Fireflies(start: solvedAt)
                        }
                    }
                if session.isComplete {
                    solvedCard(session)
                        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                } else {
                    if let hint = session.hint {
                        hintCard(hint, session: session)
                    }
                    controls(session)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : .spring(duration: 0.5).delay(0.9), value: session.isComplete)
        }
        .onChange(of: session.isComplete) { _, done in
            guard done else { return }
            solvedAt = .now
            try? context.save()
            afterSolve(session)
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
        .frame(maxWidth: 720)
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
        .frame(maxWidth: 720)
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
                        if session.isComplete {
                            Haptics.solved(lanterns: session.puzzle.size)
                            AccessibilityNotification.Announcement("Garden lit. Puzzle solved.").post()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Dismiss") { session.hint = nil }
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: 720)
        .onAppear {
            AccessibilityNotification.Announcement(hint.message).post()
        }
    }

    private var isOnDayDaily: Bool {
        if case .daily(let day) = source { return day == DayStamp.today }
        return false
    }

    /// Refreshes reminders and, at a rare and happy moment, asks for an App Store rating.
    private func afterSolve(_ session: GameSession) {
        if isOnDayDaily {
            Task { await ReminderScheduler.refresh(todaySolved: true) }
        }
        let summary = ProgressSummary(records: records)
        var finishedPack = false
        if case .journey(let pack, let level) = source, let item = JourneyPack.all.first(where: { $0.index == pack }) {
            finishedPack = level + 1 == item.levelCount
        }
        let goodMoment = (isOnDayDaily && summary.currentStreak >= 3) || finishedPack
        let sinceLast = Date.now.timeIntervalSince1970 - lastReviewRequest
        guard session.hintsUsed == 0, summary.solvedTotal >= 5, goodMoment, sinceLast > 60 * 86_400 else { return }
        lastReviewRequest = Date.now.timeIntervalSince1970
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            requestReview()
        }
    }

    private func solvedCard(_ session: GameSession) -> some View {
        let summary = ProgressSummary(records: records)
        let hints = session.hintsUsed
        let hintText = hints == 0 ? "no hints" : (hints == 1 ? "1 hint" : "\(hints) hints")
        return Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    LanternGlyph(glowing: true).frame(width: 40, height: 40)
                    Text("Garden lit")
                        .font(.title2.bold())
                        .accessibilityAddTraits(.isHeader)
                }
                Text("Solved in \(Clock.text(session.elapsed())) with \(hintText).")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Solved in \(Clock.spoken(session.elapsed())) with \(hintText)")
                if case .daily = source, session.record.completedOnDay {
                    Label(
                        summary.currentStreak <= 1 ? "Your streak has begun" : "\(summary.currentStreak)-day streak · longest \(summary.longestStreak)",
                        systemImage: "flame.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                }
                HStack {
                    if let next = source.next {
                        let open = next.isUnlocked(isPro: store.isPro)
                        Button {
                            navigator.play(next, isPro: store.isPro, replacingCurrent: true)
                        } label: {
                            Label(open ? "Next garden" : "More gardens · Full Garden", systemImage: open ? "arrow.right" : "lock.open.fill")
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
                    ShareLink(item: session.shareText(streak: isOnDayDaily ? summary.currentStreak : 0)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.bordered)
                }
                if isOnDayDaily {
                    if let reminderNote {
                        Text(reminderNote).font(.footnote).foregroundStyle(.secondary)
                    } else if !ReminderScheduler.isEnabled {
                        Button {
                            Task {
                                let granted = await ReminderScheduler.enable()
                                await ReminderScheduler.refresh(todaySolved: true)
                                reminderNote = granted
                                    ? "You'll get a reminder when tomorrow's garden is ready."
                                    : "Notifications are off for Lanternfold. You can allow them in iOS Settings."
                            }
                        } label: {
                            Label("Remind me about tomorrow's garden", systemImage: "bell")
                        }
                        .font(.subheadline)
                    }
                    if !store.isPro {
                        Button {
                            navigator.showingPaywall = true
                        } label: {
                            Label("Want another? Endless is part of the Full Garden", systemImage: "infinity")
                        }
                        .font(.subheadline)
                    }
                }
            }
        }
        .frame(maxWidth: 720)
    }
}
