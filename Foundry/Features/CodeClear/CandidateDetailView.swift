import SwiftUI

/// Read-only candidate detail (editing stays in Foundry Web).
struct CandidateDetailView: View {
    @Environment(AppModel.self) private var model
    let candidate: Candidate

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
        }
        .formStyle(.grouped)
        .navigationTitle(candidate.name)
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
}
