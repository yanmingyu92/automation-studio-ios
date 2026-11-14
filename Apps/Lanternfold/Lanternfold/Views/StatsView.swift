import SwiftData
import SwiftUI

struct StatsView: View {
    @Query private var records: [PuzzleRecord]

    var body: some View {
        let summary = ProgressSummary(records: records)
        List {
            if summary.solvedTotal == 0 {
                ContentUnavailableView(
                    "No gardens lit yet",
                    systemImage: "chart.bar",
                    description: Text("Solve a puzzle and your times and streaks will appear here.")
                )
                .listRowBackground(Color.clear)
            } else {
                Section("Daily streak") {
                    LabeledContent("Current", value: dayCount(summary.currentStreak))
                    LabeledContent("Longest", value: dayCount(summary.longestStreak))
                }
                Section("Gardens lit") {
                    LabeledContent("Total", value: "\(summary.solvedTotal)")
                    LabeledContent("Daily", value: "\(summary.solvedDaily)")
                    LabeledContent("Journey", value: "\(summary.solvedJourney) of \(JourneyPack.totalLevels)")
                    LabeledContent("Endless", value: "\(summary.solvedEndless)")
                    LabeledContent("Without hints", value: "\(summary.solvedWithoutHints)")
                    LabeledContent("Time played", value: Clock.text(summary.totalTime))
                        .accessibilityValue(Clock.spoken(summary.totalTime))
                }
                Section("Times by size") {
                    ForEach(summary.bySize) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(item.size)×\(item.size) · \(item.solved) solved")
                                .font(.headline)
                            Text("Best \(Clock.text(item.best)) · Average \(Clock.text(item.average))")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.size) by \(item.size): \(item.solved) solved, best \(Clock.spoken(item.best)), average \(Clock.spoken(item.average))")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Palette.background.ignoresSafeArea())
        .navigationTitle("Statistics")
    }

    private func dayCount(_ value: Int) -> String {
        value == 1 ? "1 day" : "\(value) days"
    }
}
