import SwiftUI

// The native full-report sections for a Pulse scan (previously a WebKit embed). Each section
// renders only when its payload exists, so partially-analysed scans degrade gracefully.

// MARK: - Lighthouse / browser scores

struct BrowserInsightsSection: View {
    let insights: PulseBrowserInsights

    private var scores: [(label: String, value: Double?)] {
        [("Performance", insights.performanceScore),
         ("Accessibility", insights.accessibilityScore),
         ("SEO", insights.seoScore),
         ("Best practices", insights.bestPracticesScore)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lighthouse").font(.headline)
            HStack(spacing: 14) {
                ForEach(scores, id: \.label) { score in
                    VStack(spacing: 4) {
                        if let value = score.value {
                            Text("\(Int(value))")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.pulseHealth(Int(value)))
                                .monospacedDigit()
                        } else {
                            Text("—").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(.secondary)
                        }
                        Text(score.label).font(.caption2).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(12)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
            HStack(spacing: 14) {
                metric("LCP", insights.lcp, suffix: "ms")
                metric("CLS", insights.cls, suffix: nil)
                metric("FCP", insights.fcp, suffix: "ms")
                metric("TBT", insights.tbt, suffix: "ms")
                if let crux = insights.cruxCategory, !crux.isEmpty {
                    Text("CrUX: \(crux.capitalized)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder private func metric(_ label: String, _ value: Double?, suffix: String?) -> some View {
        if let value {
            HStack(spacing: 3) {
                Text(label).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(suffix == nil ? String(format: "%.2f", value) : "\(Int(value))\(suffix!)")
                    .font(.caption.monospacedDigit())
            }
        }
    }
}

// MARK: - Code + deploy insights

struct CodeInsightsSection: View {
    let insights: PulseCodeInsights

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repository").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 5) {
                GridRow {
                    fact("Branch protection", insights.branchProtected.map { $0 ? "On" : "Off" })
                    fact("Reviews required", insights.requiresReviews.map { $0 ? "Yes" : "No" })
                }
                GridRow {
                    fact("PR review rate", insights.prReviewRate.map { Formatters.percent($0 > 1 ? $0 / 100 : $0) })
                    fact("Contributors", insights.uniqueContributors.map(String.init))
                }
            }
            if let vulnerabilities = insights.vulnerabilities, !vulnerabilities.isEmpty {
                ForEach(vulnerabilities) { vulnerability in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(vulnerability.packageName ?? "Dependency") · \(vulnerability.severity?.capitalized ?? "—")")
                                .font(.callout.weight(.medium))
                            if let detail = vulnerability.description { Text(detail).font(.caption).foregroundStyle(.secondary) }
                        }
                    } icon: {
                        Image(systemName: "shield.lefthalf.filled.trianglebadge.exclamationmark").foregroundStyle(.red)
                    }
                }
            }
        }
    }

    @ViewBuilder private func fact(_ label: String, _ value: String?) -> some View {
        if let value {
            HStack(spacing: 5) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.caption.weight(.semibold))
            }
        }
    }
}

struct DeployInsightsSection: View {
    let insights: PulseDeployInsights

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Deployment").font(.headline)
            HStack(spacing: 16) {
                if let platform = insights.platform { chip(platform.capitalized) }
                if let recent = insights.recentDeployments { chip("\(recent) recent deploys") }
                if let failed = insights.failedDeployments, failed > 0 { chip("\(failed) failed", tint: .red) }
                if let build = insights.avgBuildMs { chip("avg build \(Formatters.duration(ms: build))") }
                Spacer()
            }
            ForEach(insights.buildWarnings ?? [], id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
            }
            ForEach(insights.recentErrorPatterns ?? [], id: \.self) { pattern in
                Label(pattern, systemImage: "xmark.octagon").font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func chip(_ text: String, tint: Color = .secondary) -> some View {
        Text(text).font(.caption.weight(.medium)).foregroundStyle(tint)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - Opportunities · roadmap · tech debt

struct OpportunitiesSection: View {
    let analysis: PulseAnalysis

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                if let opportunities = analysis.buildOpportunities, !opportunities.isEmpty {
                    ForEach(opportunities) { opportunity in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(opportunity.title).font(.callout.weight(.medium))
                                if let effort = opportunity.estimatedEffort {
                                    Text(effort).font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            if let description = opportunity.description {
                                Text(description).font(.caption).foregroundStyle(.secondary)
                            }
                            if let value = opportunity.businessValue {
                                Text(value).font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                if let roadmap = analysis.scalingRoadmap, !roadmap.isEmpty {
                    Text("Roadmap").font(.callout.weight(.semibold))
                    ForEach(roadmap) { phase in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                if let number = phase.phase { Text("Phase \(number)").font(.caption.monospaced()).foregroundStyle(.secondary) }
                                Text(phase.title).font(.callout.weight(.medium))
                                if let duration = phase.duration { Text(duration).font(.caption2).foregroundStyle(.tertiary) }
                            }
                            ForEach(phase.goals ?? [], id: \.self) { goal in
                                Text("· \(goal)").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if let debt = analysis.techDebt, !debt.isEmpty {
                    Text("Tech debt").font(.callout.weight(.semibold))
                    ForEach(debt) { item in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(item.area)\(item.severity.map { " · \($0.capitalized)" } ?? "")").font(.callout.weight(.medium))
                                if let description = item.description { Text(description).font(.caption).foregroundStyle(.secondary) }
                            }
                        } icon: {
                            Image(systemName: "wrench.adjustable").foregroundStyle(.orange)
                        }
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Opportunities & roadmap").font(.headline)
        }
    }
}

// MARK: - Production readiness

struct ReadinessSection: View {
    let analysis: PulseAnalysis

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(analysis.productionBlockers ?? []) { blocker in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(blocker.blocker).font(.callout.weight(.medium))
                            if let why = blocker.why { Text(why).font(.caption).foregroundStyle(.secondary) }
                            if let service = blocker.recommendedService {
                                Text("Recommended: \(service)").font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                    } icon: {
                        Image(systemName: "hand.raised.fill").foregroundStyle(.red)
                    }
                }
                if let checklist = analysis.productionReadinessChecklist, !checklist.isEmpty {
                    ForEach(checklist) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: item.isReady ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(item.isReady ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.item).font(.callout)
                                if let notes = item.notes, !notes.isEmpty {
                                    Text(notes).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if let status = item.status {
                                Text(status.capitalized).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
                if let stack = analysis.techStackAnalysis {
                    if let assessment = stack.assessment { Text(assessment).font(.callout) }
                    if let missing = stack.missingForProduction, !missing.isEmpty {
                        Text("Missing for production: \(missing.joined(separator: ", "))")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if let recommendations = stack.recommendations, !recommendations.isEmpty {
                        ForEach(recommendations, id: \.self) { rec in
                            Text("· \(rec)").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Production readiness").font(.headline)
        }
    }
}

// MARK: - Discovery kit

struct DiscoveryKitSection: View {
    let kit: PulseDiscoveryKit

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                if let opening = kit.openingStatement, !opening.isEmpty {
                    Text(opening).font(.callout).textSelection(.enabled)
                }
                if let wow = kit.wowFinding, let finding = wow.finding {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(finding).font(.callout.weight(.medium))
                            if let impact = wow.impact { Text(impact).font(.caption).foregroundStyle(.secondary) }
                        }
                    } icon: {
                        Image(systemName: "star.fill").foregroundStyle(.yellow)
                    }
                }
                ForEach(kit.questions ?? []) { question in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(question.question).font(.callout.weight(.medium))
                        if let context = question.context { Text(context).font(.caption).foregroundStyle(.secondary) }
                        if let followUp = question.followUp { Text("Follow-up: \(followUp)").font(.caption).foregroundStyle(.tertiary) }
                    }
                }
                ForEach(kit.anticipatedObjections ?? []) { objection in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("“\(objection.objection)”").font(.callout.italic())
                        if let response = objection.response { Text(response).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let anchor = kit.pricingAnchor, let low = anchor.low, let high = anchor.high {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Pricing anchor: \(Formatters.currency(low, code: "GBP")) – \(Formatters.currency(high, code: "GBP"))")
                            .font(.callout.weight(.medium))
                        if let rationale = anchor.rationale { Text(rationale).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                if let points = kit.talkingPoints, !points.isEmpty {
                    ForEach(points, id: \.self) { point in
                        Text("· \(point)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Text("Discovery kit").font(.headline)
        }
    }
}

// MARK: - Competitors

struct CompetitorsSection: View {
    let data: PulseCompetitorData
    let ownScore: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Competitors").font(.headline)
            ForEach(data.scans ?? []) { competitor in
                HStack(spacing: 10) {
                    HealthBadge(score: competitor.healthScore, size: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(competitor.url).font(.callout).lineLimit(1)
                        if let stack = competitor.techStack, !stack.isEmpty {
                            Text(stack.prefix(4).joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    if let pass = competitor.checksPass, let fail = competitor.checksFail {
                        Text("\(pass)✓ \(fail)✗").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
            }
            if let comparison = data.comparison {
                if let summary = comparison.summary { Text(summary).font(.callout) }
                ForEach(comparison.advantages ?? [], id: \.self) { advantage in
                    Label(advantage, systemImage: "arrow.up.right").font(.caption).foregroundStyle(.green)
                }
                ForEach(comparison.gaps ?? [], id: \.self) { gap in
                    Label(gap, systemImage: "arrow.down.right").font(.caption).foregroundStyle(.orange)
                }
                if let recommendation = comparison.recommendation {
                    Text(recommendation).font(.callout.weight(.medium))
                }
            }
        }
    }
}
