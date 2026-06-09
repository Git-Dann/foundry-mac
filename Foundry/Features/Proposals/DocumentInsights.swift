import SwiftUI

/// Per-document link-tracking insights: visitors, conversion, most-read sections, recent visits.
/// A self-loading `Form` section for the proposal detail.
struct DocumentInsightsSection: View {
    @Environment(AppModel.self) private var model
    let documentId: String

    @State private var analytics: DocumentAnalytics?
    @State private var state: LoadState<Void> = .idle

    var body: some View {
        Section("Insights") {
            switch state {
            case .idle, .loading:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading view data…").foregroundStyle(.secondary)
                }
            case .failed:
                Text("View data unavailable.").foregroundStyle(.secondary)
            case .loaded:
                if let analytics { rows(analytics) } else { Text("No view data yet.").foregroundStyle(.secondary) }
            }
        }
        .task(id: documentId) { await load() }
        .onChange(of: model.refreshToken) { Task { await load() } }
    }

    @ViewBuilder private func rows(_ a: DocumentAnalytics) -> some View {
        LabeledContent("Views", value: "\(a.totalViews)")
        LabeledContent("Unique visitors", value: "\(a.uniqueVisitors)")
        if a.returningVisitors > 0 { LabeledContent("Returning", value: "\(a.returningVisitors)") }
        if let time = a.timeToFirstOpenMs { LabeledContent("Time to first open", value: Formatters.duration(ms: time)) }
        if let avg = a.avgDurationMs { LabeledContent("Avg time on doc", value: Formatters.duration(ms: avg)) }
        LabeledContent("Conversion") {
            if a.converted { StatusChip(text: "Accepted", tint: .green) }
            else if a.declinedAt != nil { StatusChip(text: "Declined", tint: .red) }
            else if a.isShared { StatusChip(text: "Awaiting", tint: .orange) }
            else { Text("Not shared").foregroundStyle(.secondary) }
        }

        if !a.sections.isEmpty {
            let top = Array(a.sections.sorted { $0.totalDwellMs > $1.totalDwellMs }.prefix(5))
            DisclosureGroup("Most-read sections") {
                ForEach(top) { section in
                    LabeledContent {
                        Text(Formatters.duration(ms: section.totalDwellMs)).monospacedDigit()
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(section.title)
                            Text("\(section.viewers) viewer\(section.viewers == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        if !a.recentVisits.isEmpty {
            DisclosureGroup("Recent visits") {
                ForEach(a.recentVisits.prefix(6)) { visit in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            Text(visit.visitorLabel)
                            Spacer()
                            Text(Formatters.relative(visit.createdAt)).font(.caption).foregroundStyle(.tertiary)
                        }
                        Text(visitDetail(visit)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func visitDetail(_ v: DocumentAnalytics.Visit) -> String {
        var parts = [v.place, v.device, v.browser].compactMap { $0 }
        if let duration = v.durationMs { parts.append(Formatters.duration(ms: duration)) }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func load() async {
        if analytics == nil { state = .loading }
        do {
            analytics = try await model.api.documentAnalytics(id: documentId)
            state = .loaded(())
        } catch {
            state = .failed(error.userMessage)
        }
    }
}

/// Version history (read-only). Renders nothing until at least one version exists.
struct DocumentVersionsSection: View {
    @Environment(AppModel.self) private var model
    let documentId: String
    @State private var versions: [DocumentVersion] = []

    var body: some View {
        Group {
            if !versions.isEmpty {
                Section("Versions (\(versions.count))") {
                    ForEach(versions) { version in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack {
                                Text("v\(version.version)").fontWeight(.medium)
                                Spacer()
                                Text(Formatters.relative(version.createdAt)).font(.caption).foregroundStyle(.tertiary)
                            }
                            if let changelog = version.changelog, !changelog.isEmpty {
                                Text(changelog).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .task(id: documentId) { versions = (try? await model.api.documentVersions(id: documentId)) ?? [] }
    }
}

/// Threaded comments (read-only). Renders nothing until at least one comment exists.
struct DocumentCommentsSection: View {
    @Environment(AppModel.self) private var model
    let documentId: String
    @State private var comments: [DocumentComment] = []

    var body: some View {
        Group {
            if !comments.isEmpty {
                Section("Comments (\(comments.count))") {
                    ForEach(comments) { comment in
                        CommentRow(comment: comment, depth: 0)
                        if let replies = comment.replies {
                            ForEach(replies) { CommentRow(comment: $0, depth: 1) }
                        }
                    }
                }
            }
        }
        .task(id: documentId) { comments = (try? await model.api.documentComments(id: documentId)) ?? [] }
    }
}

private struct CommentRow: View {
    let comment: DocumentComment
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(comment.authorName).font(.callout.weight(.medium))
                if comment.isFromClient { StatusChip(text: "Client", tint: .foundryBlue) }
                if comment.isResolved { StatusChip(text: "Resolved", tint: .green) }
                Spacer()
                Text(Formatters.relative(comment.createdAt)).font(.caption).foregroundStyle(.tertiary)
            }
            Text(comment.body).font(.callout).foregroundStyle(.primary)
        }
        .padding(.leading, depth > 0 ? 16 : 0)
    }
}
