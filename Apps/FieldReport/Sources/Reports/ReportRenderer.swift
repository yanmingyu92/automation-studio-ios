import Foundation
import UIKit

enum ReportRenderer {
    enum RenderError: LocalizedError {
        case missingTitle
        case exportFailed

        var errorDescription: String? {
            switch self {
            case .missingTitle: "Give the project a title before exporting its report."
            case .exportFailed: "The PDF could not be created. Check available device storage and try again."
            }
        }
    }

    static func render(_ report: ReportSnapshot) throws -> URL {
        guard !report.title.isEmpty else { throw RenderError.missingTitle }
        let safeTitle = report.title.replacingOccurrences(of: "[^A-Za-z0-9 _-]", with: "", options: .regularExpression)
        let fileName = (safeTitle.isEmpty ? "Inspection report" : safeTitle) + "-" + String(UUID().uuidString.prefix(8)) + ".pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [
            kCGPDFContextTitle as String: report.title,
            kCGPDFContextCreator as String: "FieldReport",
            kCGPDFContextAuthor as String: report.inspectorName.isEmpty ? report.companyName : report.inspectorName
        ]
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect, format: format)
        do {
            try renderer.writePDF(to: url) { context in
                ReportPageRenderer(context: context, report: report, pageRect: pageRect).render()
            }
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw RenderError.exportFailed
        }
    }
}

private final class ReportPageRenderer {
    private let context: UIGraphicsPDFRendererContext
    private let report: ReportSnapshot
    private let pageRect: CGRect
    private let margin: CGFloat = 48
    private var cursor: CGFloat = 0
    private var pageNumber = 0

    private var contentWidth: CGFloat { pageRect.width - margin * 2 }
    private var bottomLimit: CGFloat { pageRect.height - 56 }
    private let ink = UIColor(red: 0.08, green: 0.12, blue: 0.16, alpha: 1)
    private let secondary = UIColor(red: 0.34, green: 0.39, blue: 0.42, alpha: 1)
    private let teal = UIColor(red: 0.10, green: 0.56, blue: 0.49, alpha: 1)

    init(context: UIGraphicsPDFRendererContext, report: ReportSnapshot, pageRect: CGRect) {
        self.context = context
        self.report = report
        self.pageRect = pageRect
    }

    func render() {
        beginPage()
        drawCover()
        if !report.reportNotes.isEmpty {
            drawLabeledText("Report notes", report.reportNotes, spacingBefore: 20)
        }
        drawFindings()
        drawClosing()
    }

    private func drawCover() {
        let headerRect = CGRect(x: margin, y: cursor, width: contentWidth, height: 118)
        UIColor(red: 0.075, green: 0.12, blue: 0.16, alpha: 1).setFill()
        UIBezierPath(roundedRect: headerRect, cornerRadius: 12).fill()
        drawFixed("FIELDREPORT", at: CGPoint(x: margin + 20, y: cursor + 18), font: .systemFont(ofSize: 10, weight: .bold), color: UIColor(red: 0.4, green: 0.85, blue: 0.76, alpha: 1))
        let titleFont = UIFont.systemFont(ofSize: 25, weight: .bold)
        let titleRect = CGRect(x: margin + 20, y: cursor + 42, width: contentWidth - 40, height: 56)
        NSString(string: report.title).draw(in: titleRect, withAttributes: [
            .font: titleFont,
            .foregroundColor: UIColor.white,
            .paragraphStyle: paragraph(lineBreak: .byTruncatingTail)
        ])
        cursor += 142

        let details: [(String, String)] = [
            ("Inspection date", report.inspectionDate.formatted(date: .long, time: .omitted)),
            ("Site", report.siteAddress),
            ("Customer", report.customerName),
            ("Customer contact", report.customerContact),
            ("Inspector", report.inspectorName),
            ("Company", report.companyName)
        ].filter { !$0.1.isEmpty }
        drawDetailGrid(details)
        if !report.companyDetails.isEmpty {
            drawText(report.companyDetails, font: .systemFont(ofSize: 9), color: secondary, spacingBefore: 8)
        }
    }

    private func drawDetailGrid(_ details: [(String, String)]) {
        guard !details.isEmpty else { return }
        let rows = stride(from: 0, to: details.count, by: 2).map { Array(details[$0..<min($0 + 2, details.count)]) }
        for row in rows {
            let titleFont = UIFont.systemFont(ofSize: 8, weight: .semibold)
            let valueFont = UIFont.systemFont(ofSize: 11)
            let valueHeight = row.map { height(for: $0.1, font: valueFont, width: contentWidth / 2 - 14) }.max() ?? 16
            let rowHeight = max(46, valueHeight + 25)
            ensureSpace(rowHeight + 4)
            for (index, detail) in row.enumerated() {
                let x = margin + CGFloat(index) * contentWidth / 2
                drawFixed(detail.0.uppercased(), at: CGPoint(x: x, y: cursor), font: titleFont, color: secondary)
                let rect = CGRect(x: x, y: cursor + 15, width: contentWidth / 2 - 14, height: valueHeight + 3)
                NSString(string: detail.1).draw(in: rect, withAttributes: [
                    .font: valueFont,
                    .foregroundColor: ink,
                    .paragraphStyle: paragraph()
                ])
            }
            cursor += rowHeight
        }
    }

    private func drawFindings() {
        ensureSpace(62)
        cursor += 14
        drawFixed("FINDINGS", at: CGPoint(x: margin, y: cursor), font: .systemFont(ofSize: 11, weight: .bold), color: teal)
        cursor += 24
        if report.findings.isEmpty {
            drawText("No findings were recorded in this report.", font: .systemFont(ofSize: 11), color: secondary)
            return
        }
        for (index, finding) in report.findings.enumerated() {
            if index > 0 {
                ensureSpace(28)
                UIColor.separator.setStroke()
                context.cgContext.move(to: CGPoint(x: margin, y: cursor))
                context.cgContext.addLine(to: CGPoint(x: margin + contentWidth, y: cursor))
                context.cgContext.strokePath()
                cursor += 20
            }
            drawFinding(finding, index: index + 1)
        }
    }

    private func drawFinding(_ finding: FindingSnapshot, index: Int) {
        ensureSpace(74)
        let numberRect = CGRect(x: margin, y: cursor, width: 30, height: 30)
        teal.setFill()
        UIBezierPath(ovalIn: numberRect).fill()
        let number = NSString(string: "\(index)")
        let numberAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: UIColor.white
        ]
        let numberSize = number.size(withAttributes: numberAttributes)
        number.draw(at: CGPoint(x: numberRect.midX - numberSize.width / 2, y: numberRect.midY - numberSize.height / 2), withAttributes: numberAttributes)
        let title = finding.title.isEmpty ? "Finding \(index)" : finding.title
        let titleFont = UIFont.systemFont(ofSize: 17, weight: .semibold)
        let titleStartPage = pageNumber
        let titleLines = title.components(separatedBy: .newlines).flatMap { paragraph in
            paragraph.isEmpty ? [""] : wrappedLines(paragraph, font: titleFont, width: contentWidth - 42)
        }
        for line in titleLines {
            ensureSpace(ceil(titleFont.lineHeight + 1))
            NSString(string: line).draw(at: CGPoint(x: margin + 42, y: cursor), withAttributes: [
                .font: titleFont,
                .foregroundColor: ink
            ])
            cursor += ceil(titleFont.lineHeight + 1)
        }
        if pageNumber == titleStartPage {
            cursor = max(cursor + 6, numberRect.maxY + 8)
        } else {
            cursor += 6
        }
        drawText("\(finding.category)  •  \(finding.severity)  •  \(finding.createdAt.formatted(date: .abbreviated, time: .shortened))", font: .systemFont(ofSize: 10, weight: .medium), color: teal)
        drawText(finding.severityDescription, font: .systemFont(ofSize: 9), color: secondary, spacingBefore: 3)
        if let duration = finding.audioDuration {
            drawText("Voice note: \(formattedDuration(duration))", font: .systemFont(ofSize: 9), color: secondary, spacingBefore: 4)
        }
        if !finding.notes.isEmpty {
            drawLabeledText("Observations", finding.notes)
        }
        if !finding.transcript.isEmpty {
            drawLabeledText("On-device voice transcript", finding.transcript)
        }
        if !finding.recommendation.isEmpty {
            drawLabeledText("Recommendation", finding.recommendation)
        }
        drawPhotos(finding.photos)
    }

    private func drawPhotos(_ photos: [PhotoSnapshot]) {
        guard !photos.isEmpty else { return }
        ensureSpace(34)
        cursor += 16
        drawFixed("PHOTOS", at: CGPoint(x: margin, y: cursor), font: .systemFont(ofSize: 9, weight: .bold), color: secondary)
        cursor += 18
        for (index, photo) in photos.enumerated() {
            autoreleasepool {
                guard let image = LocalFileStore.loadImage(fileName: photo.fileName) else {
                    drawText("Photo \(index + 1) is unavailable on this device.", font: .italicSystemFont(ofSize: 9), color: secondary)
                    return
                }
                let maxHeight: CGFloat = 310
                let scale = min(contentWidth / image.size.width, maxHeight / image.size.height, 1)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                let captionHeight = photo.caption.isEmpty ? 0 : height(for: photo.caption, font: .systemFont(ofSize: 9), width: contentWidth) + 6
                ensureSpace(size.height + captionHeight + 16)
                let rect = CGRect(x: margin, y: cursor, width: size.width, height: size.height)
                image.draw(in: rect)
                UIColor.separator.setStroke()
                context.cgContext.stroke(rect)
                cursor += size.height + 5
                if !photo.caption.isEmpty {
                    drawText("\(index + 1). \(photo.caption)", font: .systemFont(ofSize: 9), color: secondary)
                } else {
                    drawText("Photo \(index + 1)", font: .systemFont(ofSize: 9), color: secondary)
                }
                cursor += 10
            }
        }
    }

    private func drawClosing() {
        ensureSpace(44)
        cursor += 18
        drawText("Findings and recommendations were entered by the inspector. Generated \(report.generatedAt.formatted(date: .long, time: .shortened)).", font: .systemFont(ofSize: 8), color: secondary)
    }

    private func drawLabeledText(_ label: String, _ text: String, spacingBefore: CGFloat = 14) {
        ensureSpace(34)
        cursor += spacingBefore
        drawFixed(label.uppercased(), at: CGPoint(x: margin, y: cursor), font: .systemFont(ofSize: 9, weight: .bold), color: secondary)
        cursor += 17
        drawText(text, font: .systemFont(ofSize: 11), color: ink)
    }

    private func drawText(_ text: String, font: UIFont, color: UIColor, spacingBefore: CGFloat = 0) {
        cursor += spacingBefore
        let paragraphs = text.components(separatedBy: .newlines)
        for (index, paragraphText) in paragraphs.enumerated() {
            if paragraphText.isEmpty {
                cursor += font.lineHeight * 0.55
                continue
            }
            for line in wrappedLines(paragraphText, font: font, width: contentWidth) {
                ensureSpace(font.lineHeight + 2)
                NSString(string: line).draw(at: CGPoint(x: margin, y: cursor), withAttributes: [
                    .font: font,
                    .foregroundColor: color
                ])
                cursor += ceil(font.lineHeight + 1)
            }
            if index < paragraphs.count - 1 { cursor += 2 }
        }
    }

    private func wrappedLines(_ text: String, font: UIFont, width: CGFloat) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
            let candidate = current.isEmpty ? word : current + " " + word
            if size(of: candidate, font: font).width <= width {
                current = candidate
            } else {
                if !current.isEmpty { lines.append(current) }
                if size(of: word, font: font).width <= width {
                    current = word
                } else {
                    var fragment = ""
                    for character in word {
                        let candidateFragment = fragment + String(character)
                        if size(of: candidateFragment, font: font).width > width, !fragment.isEmpty {
                            lines.append(fragment)
                            fragment = String(character)
                        } else {
                            fragment = candidateFragment
                        }
                    }
                    current = fragment
                }
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines.isEmpty ? [""] : lines
    }

    private func ensureSpace(_ height: CGFloat) {
        if cursor + height > bottomLimit { beginPage() }
    }

    private func beginPage() {
        context.beginPage()
        pageNumber += 1
        cursor = 54
        drawFixed("FIELDREPORT", at: CGPoint(x: margin, y: 25), font: .systemFont(ofSize: 8, weight: .bold), color: teal)
        let footer = "Page \(pageNumber)"
        let footerWidth = size(of: footer, font: .systemFont(ofSize: 8)).width
        drawFixed(footer, at: CGPoint(x: pageRect.width - margin - footerWidth, y: pageRect.height - 34), font: .systemFont(ofSize: 8), color: secondary)
        UIColor.separator.setStroke()
        context.cgContext.move(to: CGPoint(x: margin, y: pageRect.height - 44))
        context.cgContext.addLine(to: CGPoint(x: margin + contentWidth, y: pageRect.height - 44))
        context.cgContext.strokePath()
    }

    private func drawFixed(_ text: String, at point: CGPoint, font: UIFont, color: UIColor) {
        NSString(string: text).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private func size(of text: String, font: UIFont) -> CGSize {
        NSString(string: text).size(withAttributes: [.font: font])
    }

    private func height(for text: String, font: UIFont, width: CGFloat) -> CGFloat {
        NSString(string: text).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font, .paragraphStyle: paragraph()],
            context: nil
        ).height
    }

    private func paragraph(lineBreak: NSLineBreakMode = .byWordWrapping) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = lineBreak
        return style
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
