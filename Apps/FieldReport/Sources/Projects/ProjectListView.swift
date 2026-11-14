import SwiftData
import SwiftUI

struct ProjectListView: View {
    @Query(sort: \InspectionProject.updatedAt, order: .reverse) private var projects: [InspectionProject]
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var store: StoreManager
    @EnvironmentObject private var quota: ExportQuota
    @EnvironmentObject private var transcription: TranscriptionManager
    @State private var isAddingProject = false
    @State private var searchText = ""
    @State private var projectToDelete: InspectionProject?
    @State private var errorMessage: String?

    private var filteredProjects: [InspectionProject] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return projects }
        return projects.filter {
            $0.title.localizedCaseInsensitiveContains(query)
                || $0.siteAddress.localizedCaseInsensitiveContains(query)
                || $0.customerName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    emptyProjects
                } else {
                    projectList
                }
            }
            .background(Color.fieldCanvas)
            .navigationTitle("Projects")
            .searchable(text: $searchText, prompt: "Site, customer, or project")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isAddingProject = true
                    } label: {
                        Label("New project", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingProject) {
                ProjectEditorView(mode: .new)
            }
            .alert("Delete project?", isPresented: Binding(
                get: { projectToDelete != nil },
                set: { if !$0 { projectToDelete = nil } }
            )) {
                Button("Delete project and media", role: .destructive) {
                    if let projectToDelete { delete(projectToDelete) }
                }
                Button("Cancel", role: .cancel) { projectToDelete = nil }
            } message: {
                Text("This permanently removes the project, findings, photos, and recordings from this device.")
            }
            .errorAlert($errorMessage)
        }
    }

    private var emptyProjects: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 24) {
                    Spacer()
                    Image(systemName: "doc.viewfinder.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Color.fieldTeal)
                        .accessibilityHidden(true)
                    VStack(spacing: 10) {
                        Text("Start at the site")
                            .font(.largeTitle.bold())
                            .foregroundStyle(Color.fieldInk)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Create a project, record what you see, attach photos, and leave with a professional PDF.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 340)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button("Create first project") { isAddingProject = true }
                        .buttonStyle(PrimaryButtonStyle())
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)
                    Label("No account or connection needed", systemImage: "checkmark.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding()
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
    }

    private var projectList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                exportStatus
                if filteredProjects.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .padding(.top, 40)
                } else {
                    ForEach(filteredProjects) { project in
                        NavigationLink(value: project) {
                            ProjectCard(project: project)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button(role: .destructive) { projectToDelete = project } label: {
                                Label("Delete project", systemImage: "trash")
                            }
                        }
                        .accessibilityHint("Opens project details")
                    }
                }
            }
            .padding()
        }
        .navigationDestination(for: InspectionProject.self) { project in
            ProjectDetailView(project: project)
        }
    }

    private var exportStatus: some View {
        HStack(spacing: 14) {
            Image(systemName: store.isPro ? "checkmark.seal.fill" : "doc.badge.arrow.up")
                .font(.title2)
                .foregroundStyle(Color.fieldTeal)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(store.isPro ? "FieldReport Pro" : "Free report exports")
                    .font(.headline)
                Text(store.isPro ? "Unlimited exports are active." : "\(quota.remainingExports(isPro: false) ?? 0) of 3 remaining on this device.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }

    private func delete(_ project: InspectionProject) {
        // A transcription started in this project keeps running after leaving the editor; stop it before
        // its audio file and finding are removed.
        if let active = transcription.activeFindingID, project.findings.contains(where: { $0.id == active }) {
            transcription.cancelTranscription()
        }
        let audioFiles = project.findings.compactMap(\.audioFileName)
        let photoFiles = project.findings.flatMap { finding in
            finding.photos.map { ($0.fileName, $0.thumbnailFileName) }
        }
        modelContext.delete(project)
        do {
            try modelContext.save()
            audioFiles.forEach { LocalFileStore.deleteAudio(fileName: $0) }
            for (fileName, thumbnailFileName) in photoFiles {
                if let url = try? LocalFileStore.photoURL(fileName: fileName) {
                    try? FileManager.default.removeItem(at: url)
                }
                if let url = try? LocalFileStore.photoURL(fileName: thumbnailFileName, thumbnail: true) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        } catch {
            errorMessage = "The project could not be deleted. \(error.localizedDescription)"
        }
        projectToDelete = nil
    }
}

private struct ProjectCard: View {
    let project: InspectionProject

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Image(systemName: "building.2.crop.circle.fill")
                    .font(.title)
                    .foregroundStyle(Color.fieldTeal)
                    .accessibilityHidden(true)
                Spacer()
                Text(project.inspectionDate.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(project.title)
                    .font(.title3.bold())
                    .foregroundStyle(Color.fieldInk)
                if !project.siteAddress.isEmpty {
                    Label(project.siteAddress, systemImage: "mappin")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if !project.customerName.isEmpty {
                    Text(project.customerName)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Label("\(project.findings.count) finding\(project.findings.count == 1 ? "" : "s")", systemImage: "list.clipboard")
                Spacer()
                let mediaCount = project.findings.reduce(0) { $0 + $1.photos.count }
                if mediaCount > 0 {
                    Label("\(mediaCount)", systemImage: "photo")
                        .accessibilityLabel("\(mediaCount) photo\(mediaCount == 1 ? "" : "s")")
                }
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .accessibilityHidden(true)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.quaternary))
    }
}
