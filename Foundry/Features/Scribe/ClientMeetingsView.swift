import SwiftUI

/// Navigation value: open a client's Scribe meeting notes.
struct ClientMeetingsRoute: Hashable {
    let clientSlug: String
    let clientName: String
    let clientId: String
}

/// Scribe: per-client AI meeting notes. Ingested notes plus "recent calls" candidates that can
/// have their Gemini notes fetched. Tapping a note opens the detail (summary, decisions, action
/// items — each convertible to a task).
struct ClientMeetingsView: View {
    @Environment(AppModel.self) private var model
    let clientSlug: String
    let clientName: String
    let clientId: String

    @State private var response: MeetingsResponse?
    @State private var state: LoadState<Void> = .idle
    @State private var search = ""
    @State private var selectedMeeting: Meeting?
    @State private var busyCandidate: String?

    var body: some View {
        content
            .navigationTitle("Meeting notes")
            .navigationSubtitle(clientName)
            .searchable(text: $search, prompt: "Search notes")
            .onSubmit(of: .search) { Task { await load() } }
            .task { await load() }
            .onChange(of: model.refreshToken) { Task { await load() } }
            .sheet(item: $selectedMeeting) { meeting in
                MeetingDetailSheet(clientSlug: clientSlug, clientId: clientId, meetingId: meeting.id) {
                    Task { await load() }
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading where response == nil:
            LoadingView(label: "Loading meetings…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        default:
            if let response { list(response) } else { EmptyView() }
        }
    }

    @ViewBuilder private func list(_ response: MeetingsResponse) -> some View {
        if response.meetings.isEmpty && response.candidates.isEmpty {
            ContentUnavailableView {
                Label("No meeting notes", systemImage: "text.bubble")
            } description: {
                Text(response.calendarConnected
                     ? "No client calls found yet. Notes appear here once a Google Meet with “Take notes for me” is processed."
                     : "Connect your Google Calendar in Foundry Web to pull meeting notes.")
            }
        } else {
            List {
                if !response.meetings.isEmpty {
                    Section("Notes") {
                        ForEach(response.meetings) { meeting in
                            Button { selectedMeeting = meeting } label: { MeetingRow(meeting: meeting) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                if !response.candidates.isEmpty {
                    Section("Recent calls") {
                        ForEach(response.candidates) { candidate in
                            CandidateRow(candidate: candidate, busy: busyCandidate == candidate.id) {
                                await fetchNotes(candidate)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func load() async {
        if response == nil { state = .loading }
        do {
            response = try await model.api.listMeetings(clientSlug: clientSlug, query: search.nilIfEmpty)
            state = .loaded(())
            model.lastRefresh = Date()
        } catch {
            state = .failed(error.userMessage)
        }
    }

    private func fetchNotes(_ candidate: MeetingCandidate) async {
        guard let code = candidate.meetingCode else { return }
        busyCandidate = candidate.id
        defer { busyCandidate = nil }
        let input = MeetingIngestInput(
            calendarEventId: candidate.calendarEventId,
            meetingCode: code,
            title: candidate.title,
            start: ISO8601DateParser.string(from: candidate.start),
            end: ISO8601DateParser.string(from: candidate.end),
            attendees: candidate.attendees
        )
        if let meeting = try? await model.api.ingestMeeting(clientSlug: clientSlug, input) {
            await load()
            selectedMeeting = meeting
        } else {
            await load()
        }
    }
}

private struct MeetingRow: View {
    let meeting: Meeting

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(meeting.title).font(.body.weight(.medium)).lineLimit(1)
                HStack(spacing: 6) {
                    if let date = meeting.startedAt { Text(Formatters.medium(date)) }
                    if !meeting.actionItems.isEmpty { Text("· \(meeting.actionItems.count) action\(meeting.actionItems.count == 1 ? "" : "s")") }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            StatusChip(text: meeting.status.label, tint: meeting.status == .summarised ? .green : .secondary)
        }
        .padding(.vertical, 3)
    }
}

private struct CandidateRow: View {
    let candidate: MeetingCandidate
    let busy: Bool
    let fetch: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.title).font(.body.weight(.medium)).lineLimit(1)
                Text(Formatters.medium(candidate.start)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if candidate.meetingCode != nil {
                Button { Task { await fetch() } } label: {
                    if busy { ProgressView().controlSize(.small) } else { Text("Fetch notes") }
                }
                .buttonStyle(.bordered)
                .disabled(busy)
            } else {
                Text("No Meet link").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 3)
    }
}

/// Meeting detail: summary, decisions, attendees, and action items (toggle done · add to the
/// client's task board).
struct MeetingDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let clientSlug: String
    let clientId: String
    let meetingId: String
    var onChanged: () -> Void

    @State private var meeting: Meeting?
    @State private var state: LoadState<Void> = .idle
    @State private var addedActionIds: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Scribe").font(.caption.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
            }
            .padding(16)
            Divider()
            ScrollView {
                switch state {
                case .idle, .loading:
                    LoadingView(label: "Loading notes…").frame(height: 220)
                case .failed(let message):
                    ErrorStateView(message: message) { Task { await load() } }.frame(height: 220)
                case .loaded:
                    if let meeting { body(meeting) }
                }
            }
        }
        .frame(width: 560, height: 660)
        .task { await load() }
    }

    @ViewBuilder private func body(_ meeting: Meeting) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(meeting.title).font(.title2.weight(.semibold))
                if let date = meeting.startedAt {
                    Text(Formatters.medium(date)).font(.callout).foregroundStyle(.secondary)
                }
                if !meeting.attendees.isEmpty {
                    Text(meeting.attendees.joined(separator: ", ")).font(.caption).foregroundStyle(.tertiary)
                }
            }

            if let summary = meeting.summary, !summary.isEmpty {
                section("Summary") { Text(summary).font(.callout) }
            }

            if !meeting.decisions.isEmpty {
                section("Decisions") {
                    ForEach(Array(meeting.decisions.enumerated()), id: \.offset) { _, decision in
                        Label { Text(decision).font(.callout) } icon: { Image(systemName: "checkmark.seal").foregroundStyle(.blue) }
                    }
                }
            }

            if !meeting.actionItems.isEmpty {
                section("Action items") {
                    ForEach(meeting.actionItems) { item in
                        ActionItemRow(
                            item: item,
                            added: addedActionIds.contains(item.id),
                            toggleDone: { await toggleDone(item) },
                            addTask: { await addTask(item) }
                        )
                    }
                }
            }
        }
        .padding(16)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content()
        }
    }

    private func load() async {
        if meeting == nil { state = .loading }
        do {
            meeting = try await model.api.getMeeting(clientSlug: clientSlug, id: meetingId)
            state = .loaded(())
        } catch {
            state = .failed(error.userMessage)
        }
    }

    private func toggleDone(_ item: MeetingActionItem) async {
        meeting = try? await model.api.setMeetingActionDone(
            clientSlug: clientSlug, meetingId: meetingId, actionItemId: item.id, done: !item.done
        )
        onChanged()
    }

    private func addTask(_ item: MeetingActionItem) async {
        let input = TaskInput(clientId: clientId, title: item.text)
        if (try? await model.api.createTask(input)) != nil {
            addedActionIds.insert(item.id)
        }
    }
}

private struct ActionItemRow: View {
    let item: MeetingActionItem
    let added: Bool
    let toggleDone: () async -> Void
    let addTask: () async -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button { Task { await toggleDone() } } label: {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.done ? .green : .secondary)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.text).strikethrough(item.done)
                if let owner = item.owner, !owner.isEmpty {
                    Text(owner).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if added {
                Label("Added", systemImage: "checkmark").font(.caption).foregroundStyle(.green)
            } else {
                Button { Task { await addTask() } } label: { Label("Task", systemImage: "plus") }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
    }
}
