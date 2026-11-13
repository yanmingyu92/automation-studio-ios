import SwiftData
import SwiftUI

struct ProjectDetailView: View {
    @Bindable var project: InspectionProject
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var quota: ExportQuota
    @State private var isEditingProject = false
    @State private var isAddingFinding = false
    @State private var isExporting = false
    @State private var isShowingPaywall = false

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                projectSummary
                HStack {
                    SectionHeading(title: "Findings", subtitle: "Observations, evidence, and next steps")
                    Spacer()
                    Button {
                        isAddingFinding = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
                if project.sortedFindings.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "list.clipboard")
                            .font(.largeTitle)
                            .foregroundStyle(Color.fieldTeal)
                        Text("No findings yet")
                            .font(.headline)
                        Text("Add a manual finding, then attach photos and a voice note when useful.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Add first finding") { isAddingFinding = true }
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .frame(maxWidth: .infinity)
                    .padding(28)
                    .background(.background, in: RoundedRectangle(cornerRadius: 18))
                } else {
                    ForEach(project.sortedFindings) { finding in
                        NavigationLink(value: finding) {
                            FindingCard(finding: finding)
                        }
                        .buttonStyle(.plain)
                    }
                }
                exportButton
            }
            .padding()
        }
        .background(Color.fieldCanvas)
        .navigationTitle(project.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { isEditingProject = true } label: { Label("Project details", systemImage: "pencil") }
                    Button { exportReport() } label: { Label("Export PDF", systemImage: "square.and.arrow.up") }
                } label: {
                    Label("Project actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .navigationDestination(for: Finding.self) { finding in
            FindingEditorView(finding: finding)
        }
        .sheet(isPresented: $isEditingProject) {
            ProjectEditorView(mode: .edit(project))
        }
        .sheet(isPresented: $isAddingFinding) {
            NewFindingView(project: project)
        }
        .sheet(isPresented: $isExporting) {
            ReportExportView(project: project)
        }
        .sheet(isPresented: $isShowingPaywall) {
            PaywallView()
        }
    }

    private var projectSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(project.siteAddress, systemImage: "mappin.and.ellipse")
                .font(.headline)
                .foregroundStyle(Color.fieldInk)
            if !project.customerName.isEmpty {
                Label(project.customerName, systemImage: "person")
                    .foregroundStyle(.secondary)
            }
            Label(project.inspectionDate.formatted(date: .long, time: .omitted), systemImage: "calendar")
                .foregroundStyle(.secondary)
            Button("Edit project details") { isEditingProject = true }
                .font(.subheadline.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
    }

    private var exportButton: some View {
        VStack(spacing: 10) {
            Button(action: exportReport) {
                Label("Preview & export PDF", systemImage: "doc.richtext")
            }
            .buttonStyle(PrimaryButtonStyle())
            if !store.isPro {
                Text("\(quota.remainingExports(isPro: false) ?? 0) free exports remaining")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 8)
    }

    private func exportReport() {
        if quota.canExport(isPro: store.isPro) {
            isExporting = true
        } else {
            isShowingPaywall = true
        }
    }
}

private struct FindingCard: View {
    let finding: Finding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: finding.category.symbol)
                    .font(.title3)
                    .foregroundStyle(Color.fieldTeal)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(finding.title.isEmpty ? "Untitled finding" : finding.title)
                        .font(.headline)
                        .foregroundStyle(Color.fieldInk)
                    Text(finding.category.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(title: finding.severity.rawValue, color: finding.severity.color, symbol: finding.severity.symbol)
            }
            let preview = finding.notes.isEmpty ? finding.transcript : finding.notes
            if !preview.isEmpty {
                Text(preview)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            HStack(spacing: 16) {
                if !finding.photos.isEmpty {
                    Label("\(finding.photos.count)", systemImage: "photo.on.rectangle")
                }
                if finding.audioFileName != nil {
                    Label(formattedDuration(finding.audioDuration), systemImage: "waveform")
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = max(0, Int(duration.rounded()))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
