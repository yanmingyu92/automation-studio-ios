import SwiftUI

struct RulesView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var example = RulesView.makeExample()

    private let rules: [(icon: String, text: String)] = [
        ("arrow.left.and.right", "Every row holds exactly one lantern."),
        ("arrow.up.and.down", "Every column holds exactly one lantern."),
        ("square.on.square.dashed", "Every coloured plot holds exactly one lantern."),
        ("circle.dashed", "Lanterns never touch each other, not even at a corner."),
        ("number.circle.fill", "A stone shows how many lanterns stand in the cells around it. A stone never holds a lantern.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Light the garden")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text("Each garden has exactly one solution and never needs a guess.")
                        .foregroundStyle(.secondary)

                    if let example {
                        BoardView(session: example, interactive: false)
                            .frame(maxWidth: 280)
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("A solved example garden")
                    }

                    ForEach(rules, id: \.text) { rule in
                        Label {
                            Text(rule.text)
                        } icon: {
                            Image(systemName: rule.icon).foregroundStyle(Color.accentColor)
                        }
                    }

                    Text("Controls")
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)
                    Label("Tap a cell to mark it empty, tap again for a lantern, and once more to clear it.", systemImage: "hand.tap")
                    Label("Drag across cells to mark several as empty.", systemImage: "hand.draw")
                    Label("Stuck? A hint explains the next logical step instead of just revealing it.", systemImage: "sparkles")

                    Button {
                        dismiss()
                    } label: {
                        Text("Start playing")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(20)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Palette.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .fontDesign(.rounded)
    }

    /// A small solved garden with a stone, built by the real generator and never saved.
    private static func makeExample() -> GameSession? {
        let source = PuzzleSource.endless(id: "rules", request: GeneratorRequest(size: 5, difficulty: .easy, stones: .required))
        var random = SeededRandom(text: "lanternfold-rules-1")
        let puzzle = PuzzleGenerator.generate(source.request, random: &random)
        guard let record = try? PuzzleRecord(source: source, puzzle: puzzle),
              let session = GameSession(source: source, record: record) else { return nil }
        for cell in puzzle.solutionCells.sorted() {
            session.set(cell, to: .lantern)
        }
        return session
    }
}
