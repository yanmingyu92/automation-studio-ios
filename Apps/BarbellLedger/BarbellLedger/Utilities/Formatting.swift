import Foundation

extension Double {
    var cleanString: String {
        guard isFinite else { return "0" }
        if rounded() == self, abs(self) <= Double(Int.max) { return String(Int(self)) }
        return String(format: "%.2f", self).replacingOccurrences(of: "0+$", with: "", options: .regularExpression).replacingOccurrences(of: "\\.$", with: "", options: .regularExpression)
    }
}

extension Int {
    var clockString: String { TimeInterval(self).clockString }
}

extension TimeInterval {
    var clockString: String {
        let seconds = max(0, Int(rounded()))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let remainder = seconds % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, remainder) }
        return String(format: "%d:%02d", minutes, remainder)
    }
}

extension Date {
    var mediumDay: String {
        formatted(date: .abbreviated, time: .omitted)
    }

    var dayAndTime: String {
        formatted(date: .abbreviated, time: .shortened)
    }

    var trainingWeek: String {
        let components = Calendar.current.dateComponents([.yearForWeekOfYear, .weekOfYear], from: self)
        return "\(components.yearForWeekOfYear ?? 0)-\(components.weekOfYear ?? 0)"
    }
}

struct NumberParsing {
    static func double(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let value = Double(trimmed) { return value }
        let normalized = trimmed.replacingOccurrences(of: " ", with: "")
        if normalized.contains(",") && normalized.contains(".") {
            let commaIsDecimal = (normalized.lastIndex(of: ",")?.utf16Offset(in: normalized) ?? 0) > (normalized.lastIndex(of: ".")?.utf16Offset(in: normalized) ?? 0)
            let converted = commaIsDecimal
                ? normalized.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
                : normalized.replacingOccurrences(of: ",", with: "")
            return Double(converted)
        }
        if normalized.contains(",") {
            let pieces = normalized.split(separator: ",")
            if pieces.count > 2 || (pieces.last?.count == 3 && (pieces.first?.count ?? 0) <= 3) {
                return Double(normalized.replacingOccurrences(of: ",", with: ""))
            }
            return Double(normalized.replacingOccurrences(of: ",", with: "."))
        }
        return Double(normalized)
    }

    static func duration(_ text: String) -> TimeInterval? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", omittingEmptySubsequences: false)
            guard (2...3).contains(parts.count) else { return nil }
            var total = 0.0
            for part in parts {
                guard let number = double(String(part)), number >= 0 else { return nil }
                total = total * 60 + number
            }
            return total
        }
        return double(trimmed)
    }
}
