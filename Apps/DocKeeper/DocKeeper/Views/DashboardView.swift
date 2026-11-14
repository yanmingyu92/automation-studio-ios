import SwiftData
import SwiftUI

struct DashboardView: View {
    @Query(sort: [SortDescriptor(\DocumentRecord.updatedAt, order: .reverse)]) private var documents: [DocumentRecord]

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private var thirtyDaysOut: Date { Calendar.current.date(byAdding: .day, value: 30, to: today) ?? today }

    private var expired: [DocumentRecord] {
        documents.filter { $0.expiryDate.map { $0 < today } == true }
            .sorted { ($0.expiryDate ?? .distantPast) < ($1.expiryDate ?? .distantPast) }
    }

    private var expiring: [DocumentRecord] {
        documents.filter { $0.expiryDate.map { $0 >= today && $0 <= thirtyDaysOut } == true }
            .sorted { ($0.expiryDate ?? .distantFuture) < ($1.expiryDate ?? .distantFuture) }
    }

    private var renewals: [DocumentRecord] {
        documents.filter { $0.renewalDate.map { $0 >= today && $0 <= thirtyDaysOut } == true }
            .sorted { ($0.renewalDate ?? .distantFuture) < ($1.renewalDate ?? .distantFuture) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 145), spacing: 12)], spacing: 12) {
                        SummaryCard(value: documents.count, title: "Documents", icon: "doc.on.doc", color: .accentColor)
                        SummaryCard(value: expired.count, title: "Expired", icon: "exclamationmark.triangle", color: .red)
                        SummaryCard(value: expiring.count, title: "Next 30 days", icon: "calendar", color: .orange)
                        SummaryCard(value: renewals.count, title: "Renewals", icon: "arrow.triangle.2.circlepath", color: .blue)
                    }

                    if documents.isEmpty {
                        ContentUnavailableView {
                            Label("No Dates to Track", systemImage: "calendar.badge.clock")
                        } description: {
                            Text("Add warranty, expiry, and renewal dates when you save a document. They will appear here automatically.")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                    } else {
                        DashboardSection(title: "Needs Attention", systemImage: "exclamationmark.triangle.fill", documents: expired, dateKeyPath: \.expiryDate, emptyText: "No expired warranties or documents.")
                        DashboardSection(title: "Expiring in 30 Days", systemImage: "calendar", documents: expiring, dateKeyPath: \.expiryDate, emptyText: "Nothing is expiring in the next 30 days.")
                        DashboardSection(title: "Upcoming Renewals", systemImage: "arrow.triangle.2.circlepath", documents: renewals, dateKeyPath: \.renewalDate, emptyText: "No renewals are due in the next 30 days.")
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Expirations")
        }
    }
}

private struct SummaryCard: View {
    let value: Int
    let title: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value, format: .number).font(.title.bold())
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }
}

private struct DashboardSection: View {
    let title: String
    let systemImage: String
    let documents: [DocumentRecord]
    let dateKeyPath: KeyPath<DocumentRecord, Date?>
    let emptyText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: systemImage).font(.title3.bold())
            if documents.isEmpty {
                Text(emptyText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            } else {
                VStack(spacing: 0) {
                    ForEach(documents) { document in
                        NavigationLink {
                            DocumentDetailView(document: document)
                        } label: {
                            HStack(spacing: 12) {
                                DocumentThumbnail(data: document.thumbnailData, category: document.category, width: 46, height: 60)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(document.title).font(.headline).foregroundStyle(.primary)
                                    if let date = document[keyPath: dateKeyPath] {
                                        Text(date.formatted(date: .abbreviated, time: .omitted))
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                    .accessibilityHidden(true)
                            }
                            .padding()
                        }
                        if document.id != documents.last?.id { Divider().padding(.leading, 70) }
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}
