import SwiftUI

/// Read-only candidate detail (editing stays in Foundry Web).
struct CandidateDetailView: View {
    @Environment(AppModel.self) private var model
    let candidate: Candidate

    @State private var detail: CandidateDetail?
    @State private var newNote = ""
    @State private var addingNote = false

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    CandidateAvatar(url: candidate.avatarUrl, name: candidate.name)
                        .scaleEffect(1.6)
                        .frame(width: 44, height: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(candidate.name).font(.title3.weight(.semibold))
                        Text("@\(candidate.githubHandle)").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        StatusChip(text: candidate.status.label, tint: candidate.status.tint)
                        StatusChip(text: candidate.effectiveTier.label, tint: .blue)
                    }
                }
            }

            Section("Profile") {
                LabeledContent("Primary stack", value: candidate.primaryStack)
                if !candidate.techStacks.isEmpty {
                    LabeledContent("Tech", value: candidate.techStacks.joined(separator: ", "))
                }
                if let location = candidate.location, !location.isEmpty { LabeledContent("Location", value: location) }
                if let years = candidate.yearsExperience { LabeledContent("Experience", value: "\(years) yr\(years == 1 ? "" : "s")") }
                if let rate = candidate.hourlyRate {
                    LabeledContent("Rate", value: Formatters.currency(rate, code: candidate.currency ?? "GBP"))
                }
            }

            if let score = candidate.score {
                Section("CodeClear score") {
                    if let overall = score.overallScore {
                        LabeledContent("Overall", value: String(format: "%.0f", overall)).fontWeight(.semibold)
                    }
                    scoreRow("Technical depth", score.technicalDepth)
                    scoreRow("Code quality", score.codeQuality)
                    scoreRow("AI fluency", score.aiFluency)
                    scoreRow("Delivery readiness", score.deliveryReadiness)
                    if let confidence = score.identityConfidence {
                        LabeledContent("Identity confidence", value: confidence.capitalized)
                    }
                }
            }

            if !candidate.currentClients.isEmpty {
                Section("Engagements") {
                    ForEach(candidate.currentClients) { client in
                        Text(client.name)
                    }
                }
            }

            if let detail {
                if !detail.placements.isEmpty { placementsSection(detail.placements) }
                if let run = detail.latestGitHubAnalysis { analysisSection(run) }
                if !detail.checks.isEmpty { checksSection(detail.checks) }
            }

            if let bio = candidate.bio, !bio.isEmpty {
                Section("Bio") { Text(bio).font(.callout) }
            }

            Section("Links") {
                if let url = URL(string: "https://github.com/\(candidate.githubHandle)") {
                    Link("GitHub profile", destination: url)
                }
                if let linkedin = candidate.linkedinUrl, let url = URL(string: linkedin) {
                    Link("LinkedIn", destination: url)
                }
            }

            notesSection
        }
        .formStyle(.grouped)
        .navigationTitle(candidate.name)
        .task { await loadDetail() }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    model.openWeb(path: "app/code")
                } label: {
                    Label("Open in Foundry Web", systemImage: "safari")
                }
            }
        }
    }

    @ViewBuilder private func scoreRow(_ label: String, _ value: Double?) -> some View {
        if let value {
            LabeledContent(label, value: String(format: "%.0f", value))
        }
    }

    private func placementsSection(_ placements: [CodeClearPlacement]) -> some View {
        Section("Placements") {
            ForEach(placements) { placement in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(placement.projectName).fontWeight(.medium)
                        Spacer()
                        if let alloc = placement.allocationPercent { Text("\(alloc)%").font(.caption).foregroundStyle(.secondary) }
                    }
                    Text(placement.clientName).font(.caption).foregroundStyle(.secondary)
                    if let start = placement.startDate {
                        Text("\(Formatters.medium(start))\(placement.endDate.map { " – \(Formatters.medium($0))" } ?? " – ongoing")")
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    private func analysisSection(_ run: GitHubAnalysisRun) -> some View {
        Section("GitHub analysis") {
            if let summary = run.llmSummary, !summary.isEmpty { Text(summary).font(.callout) }
            if let flags = run.redFlags, !flags.isEmpty {
                ForEach(Array(flags.enumerated()), id: \.offset) { _, flag in
                    Label(flag, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
            }
            if let done = run.completedAt { LabeledContent("Last run", value: Formatters.relative(done)) }
        }
    }

    private func checksSection(_ checks: [CodeClearCheck]) -> some View {
        Section("Checks (\(checks.count))") {
            ForEach(checks.sorted { $0.sortOrder < $1.sortOrder }) { check in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: check.checkStatus.systemImage).foregroundStyle(check.checkStatus.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(check.label).font(.callout)
                        if let detail = check.detail, !detail.isEmpty {
                            Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var notesSection: some View {
        Section("Notes\(detail.map { " (\($0.notes.count))" } ?? "")") {
            if let detail {
                ForEach(detail.notes) { note in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(note.createdBy ?? "—").font(.caption.weight(.medium))
                            Spacer()
                            Text(Formatters.relative(note.createdAt)).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text(note.body).font(.callout)
                    }
                }
            }
            HStack {
                TextField("Add a note", text: $newNote, axis: .vertical).lineLimit(1...4)
                Button("Add") { Task { await addNote() } }.disabled(newNote.trimmed.isEmpty || addingNote)
            }
        }
    }

    private func loadDetail() async {
        detail = try? await model.api.getCandidate(id: candidate.id)
    }

    private func addNote() async {
        let text = newNote.trimmed
        guard !text.isEmpty else { return }
        addingNote = true
        defer { addingNote = false }
        if (try? await model.api.addCandidateNote(id: candidate.id, body: text)) != nil {
            newNote = ""
            await loadDetail()
        }
    }
}
