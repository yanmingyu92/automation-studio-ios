import Foundation
import SwiftUI

@MainActor
final class ExportQuota: ObservableObject {
    static let freeReportLimit = 3
    private let key = "exports.successfulReportCount"
    private let defaults: UserDefaults

    @Published private(set) var exportedReportCount: Int

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        exportedReportCount = max(0, defaults.integer(forKey: key))
    }

    func canExport(isPro: Bool) -> Bool {
        isPro || exportedReportCount < Self.freeReportLimit
    }

    func remainingExports(isPro: Bool) -> Int? {
        isPro ? nil : max(0, Self.freeReportLimit - exportedReportCount)
    }

    func recordSuccessfulExport(isPro: Bool) {
        guard !isPro else { return }
        exportedReportCount += 1
        defaults.set(exportedReportCount, forKey: key)
    }
}
