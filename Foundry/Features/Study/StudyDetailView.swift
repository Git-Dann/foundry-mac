import SwiftUI

/// Native study detail. Drives the whole lifecycle: generate the research plan, run the
/// interviews (live over SSE — sessions/turns appear as the agents work), read the report.
struct StudyDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: String

    @State private var study: StudyRecord?
    @State private var state: LoadState<Void> = .idle
    @State private var streamTask: Task<Void, Never>?
    @State private var busy = false
    @State private var actionError: String?
    @State private var confirmDelete = false

    var body: some View {
        content
            .navigationTitle(study?.title ?? "Study")
            .navigationSubtitle(study?.status.label ?? "")
            .toolbar { toolbar }
            .task { await load() }
            .onDisappear { streamTask?.cancel() }
            .alert("Delete study?", isPresented: $confirmDelete) {
                Button("Delete", role: .destructive) { Task { await deleteStudy() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the study, its sessions and report. It can't be undone.")
            }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading where study == nil:
            LoadingView(label: "Loading study…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        default:
            if let study {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header(study)
                        if let actionError { Text(actionError).font(.callout).foregroundStyle(.red) }
                        if study.status.isActive { activeBanner(study) }
                        nextStep(study)
                        if let report = study.report?.payload { ReportSection(report: report) }
                        if let plan = study.plan, !plan.questions.isEmpty { PlanSection(plan: plan) }
                        if !study.sessions.isEmpty { sessionsSection(study) }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func header(_ study: StudyRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                StatusChip(text: study.status.label, tint: study.status.tint)
                Text(study.sessionMode == "GROUP" ? "Group session" : "1-on-1 interviews")
                    .font(.caption).foregroundStyle(.secondary)
                if let client = study.workspaceClientName {
                    Text("· \(client)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text(study.problemStatement).font(.callout).textSelection(.enabled)
            ForEach(study.researchGoals, id: \.self) { goal in
                Text("· \(goal)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func activeBanner(_ study: StudyRecord) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(study.status == .planGenerating
                 ? "Generating the research plan…"
                 : "Interviews running — sessions update live as personas respond.")
                .font(.callout).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    /// The single most useful action for the study's current state.
    @ViewBuilder private func nextStep(_ study: StudyRecord) -> some View {
        switch study.status {
        case .draft, .failed:
            Button {
                runAction { try await model.api.generateStudyPlan(id: id) }
            } label: {
                Label(study.plan == nil ? "Generate research plan" : "Regenerate research plan", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy)
        case .planReady:
            Button {
                runAction { try await model.api.runStudy(id: id) }
            } label: {
                Label("Run interviews", systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(busy)
        default:
            EmptyView()
        }
    }

    private func sessionsSection(_ study: StudyRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sessions (\(study.sessions.count))").font(.headline)
            ForEach(study.sessions) { SessionView(session: $0) }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                Button { model.openWeb(path: "app/study") } label: { Label("Open in Foundry Web", systemImage: "safari") }
                Button { Task { await load() } } label: { Label("Reload", systemImage: "arrow.clockwise") }
                Divider()
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete study", systemImage: "trash") }
            } label: {
                Label("Actions", systemImage: "ellipsis.circle")
            }
        }
    }

    // MARK: Data + stream

    private func load() async {
        if study == nil { state = .loading }
        do {
            let record = try await model.api.getStudy(id: id)
            study = record
            state = .loaded(())
            if record.status.isActive { startStreaming() } else { streamTask?.cancel() }
        } catch {
            state = .failed(error.userMessage)
        }
    }

    private func startStreaming() {
        streamTask?.cancel()
        streamTask = Task { @MainActor in
            do {
                let stream = try model.api.studyStream(id: id)
                for try await payload in stream {
                    guard let data = payload.data(using: .utf8),
                          let envelope = try? JSONDecoder.foundry.decode(StudyStreamEnvelope.self, from: data)
                    else { continue }
                    if let updated = envelope.study { study = updated }
                    if envelope.type == "complete" { break }
                }
            } catch {
                // Stream dropped — the reload below recovers final state.
            }
            await load()
        }
    }

    private func runAction(_ work: @escaping () async throws -> Void) {
        Task {
            busy = true
            actionError = nil
            defer { busy = false }
            do {
                try await work()
                await load()
            } catch {
                actionError = error.userMessage
            }
        }
    }

    private func deleteStudy() async {
        do {
            try await model.api.deleteStudy(id: id)
            model.requestRefresh()
            dismiss()
        } catch {
            actionError = error.userMessage
        }
    }
}

// MARK: - Plan

private struct PlanSection: View {
    let plan: StudyPlan

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(plan.questions.sorted { $0.orderIndex < $1.orderIndex }) { question in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(question.text).font(.callout.weight(.medium))
                        if let rationale = question.rationale, !rationale.isEmpty {
                            Text(rationale).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let notes = plan.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Research plan (\(plan.questions.count) questions)").font(.headline)
        }
    }
}

// MARK: - Sessions / transcript

private struct SessionView: View {
    let session: StudySession

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array((session.transcriptData?.turns ?? []).enumerated()), id: \.offset) { _, turn in
                    TurnView(turn: turn)
                }
                if let synthesis = session.transcriptData?.synthesis {
                    SynthesisView(synthesis: synthesis)
                }
                if (session.transcriptData?.turns ?? []).isEmpty {
                    Text(session.status == .pending ? "Waiting to start…" : "No transcript yet.")
                        .font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 8) {
                Text(session.personaName).font(.callout.weight(.medium))
                if session.status == .running { ProgressView().controlSize(.mini) }
                Spacer()
                StatusChip(
                    text: session.status.label,
                    tint: session.status == .completed ? .green : (session.status == .running ? .orange : .secondary)
                )
            }
        }
    }
}

private struct TurnView: View {
    let turn: StudyTurn

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let question = turn.questionText {
                Text(question).font(.callout.weight(.semibold))
            }
            ForEach(Array((turn.exchanges ?? []).enumerated()), id: \.offset) { _, exchange in
                VStack(alignment: .leading, spacing: 3) {
                    if exchange.isFollowUp == true, let followUp = exchange.question {
                        Text("↳ \(followUp)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                    if let response = exchange.response {
                        HStack(alignment: .top, spacing: 6) {
                            Circle().fill(Color.sentiment(response.sentiment)).frame(width: 6, height: 6).padding(.top, 5)
                            Text(response.spoken ?? "—").font(.callout).textSelection(.enabled)
                        }
                        tags(response)
                    }
                }
                .padding(.leading, exchange.isFollowUp == true ? 14 : 0)
            }
            if let summary = turn.synthesis?.summary, !summary.isEmpty {
                Text(summary).font(.caption).foregroundStyle(.secondary).padding(.leading, 12)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private func tags(_ response: StudyResponse) -> some View {
        let pains = response.painPoints ?? []
        let delights = response.delights ?? []
        if !pains.isEmpty || !delights.isEmpty {
            HStack(spacing: 5) {
                ForEach(pains.prefix(3), id: \.self) { StatusChip(text: $0, tint: .red) }
                ForEach(delights.prefix(3), id: \.self) { StatusChip(text: $0, tint: .green) }
            }
            .padding(.leading, 12)
        }
    }
}

private struct SynthesisView: View {
    let synthesis: StudySessionSynthesis

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Session synthesis").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let summary = synthesis.summary { Text(summary).font(.callout) }
            ForEach(synthesis.keyThemes ?? [], id: \.self) { theme in
                Text("· \(theme)").font(.caption).foregroundStyle(.secondary)
            }
            ForEach((synthesis.notableQuotes ?? []).prefix(3), id: \.self) { quote in
                Text("“\(quote)”").font(.caption.italic()).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(Color.foundryBlue.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Report

private struct ReportSection: View {
    let report: StudyReportPayload

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Report").font(.headline)
            if let summary = report.executiveSummary {
                Text(summary).font(.callout).textSelection(.enabled)
            }
            ForEach(report.keyFindings ?? [], id: \.self) { finding in
                Label(finding, systemImage: "lightbulb").font(.callout)
            }
            ForEach(report.themes ?? []) { theme in
                VStack(alignment: .leading, spacing: 1) {
                    Text(theme.theme).font(.callout.weight(.medium))
                    if let description = theme.description {
                        Text(description).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            ForEach(report.recommendations ?? []) { recommendation in
                HStack(alignment: .top, spacing: 8) {
                    StatusChip(
                        text: recommendation.priority?.capitalized ?? "—",
                        tint: recommendation.priority == "HIGH" ? .red : (recommendation.priority == "MEDIUM" ? .orange : .secondary)
                    )
                    VStack(alignment: .leading, spacing: 1) {
                        Text(recommendation.title).font(.callout.weight(.medium))
                        if let rationale = recommendation.rationale {
                            Text(rationale).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let questions = report.openQuestions, !questions.isEmpty {
                Text("Open questions").font(.callout.weight(.semibold))
                ForEach(questions, id: \.self) { question in
                    Text("· \(question)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}
