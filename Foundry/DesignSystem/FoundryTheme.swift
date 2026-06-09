import SwiftUI

/// Brand colours, mirrored from the iOS app's asset catalog so the Apple family stays
/// visually consistent. The app otherwise leans on the system font (SF) and standard
/// controls for a first-class, native macOS feel.
extension Color {
    static let foundryBlue = Color("FoundryBlue")
    static let foundryPurple = Color("FoundryPurple")
    static let foundryCanvas = Color("FoundryCanvas")
    static let foundryInk = Color("FoundryInk")
    static let foundryMist = Color("FoundryMist")
    static let foundryMistBorder = Color("FoundryMistBorder")
}

extension DocumentStatus {
    /// Semantic tint for status chips (uses system colours so it adapts to appearance).
    var tint: Color {
        switch self {
        case .draft: return .secondary
        case .productSignOff, .techSignOff, .inReview: return .orange
        case .approved, .sent: return .blue
        case .accepted: return .green
        case .declined: return .red
        case .archived: return .secondary
        case .unknown: return .secondary
        }
    }
}

extension WorkspaceClientStatus {
    var tint: Color {
        switch self {
        case .active: return .green
        case .pendingReview: return .orange
        case .archived: return .secondary
        case .unknown: return .secondary
        }
    }
}

extension PipelineStatus {
    var tint: Color {
        switch self {
        case .placed: return .green
        case .codeclearComplete: return .blue
        case .assessmentInProgress, .invited: return .orange
        case .recheckDue: return .red
        case .sourced: return .secondary
        case .unknown: return .secondary
        }
    }
}

extension PulseScanStatus {
    var tint: Color {
        switch self {
        case .completed: return .green
        case .running, .pending: return .orange
        case .failed: return .red
        case .cancelled, .unknown: return .secondary
        }
    }
}

extension PulseCheckStatus {
    var tint: Color {
        switch self {
        case .pass: return .green
        case .warn: return .orange
        case .fail: return .red
        case .skipped, .unknown: return .secondary
        }
    }

    var systemImage: String {
        switch self {
        case .pass: return "checkmark.circle.fill"
        case .warn: return "exclamationmark.triangle.fill"
        case .fail: return "xmark.octagon.fill"
        case .skipped, .unknown: return "minus.circle"
        }
    }
}

extension Color {
    /// Health-score tint: green ≥ 80, amber ≥ 50, else red.
    static func pulseHealth(_ score: Int) -> Color {
        score >= 80 ? .green : (score >= 50 ? .orange : .red)
    }

    /// Resolve a FeatureBlock/Milestone colour key to a SwiftUI colour (Gantt bars + milestones).
    static func featureBlock(_ key: String?) -> Color {
        switch key {
        case "blue": return .blue
        case "violet": return .purple
        case "emerald": return .green
        case "amber": return .orange
        case "rose": return .pink
        case "slate": return .secondary
        default: return .foundryBlue
        }
    }
}

extension TaskStatus {
    var tint: Color {
        switch self {
        case .backlog: return .secondary
        case .todo: return .blue
        case .doing: return .orange
        case .inReview: return .purple
        case .done: return .green
        }
    }
}

extension TaskPriority {
    var tint: Color {
        switch self {
        case .low: return .secondary
        case .medium: return .blue
        case .high: return .red
        }
    }
}

extension TicketStatus {
    var tint: Color {
        switch self {
        case .open: return .blue
        case .inProgress: return .orange
        case .devReview: return .purple
        case .awaitingCustomer: return .yellow
        case .resolved: return .green
        case .unknown: return .secondary
        }
    }
}

extension TicketPriority {
    var tint: Color {
        switch self {
        case .urgent: return .red
        case .high: return .orange
        case .normal: return .blue
        case .low, .unknown: return .secondary
        }
    }
}

extension ConversationSentiment {
    var tint: Color {
        switch self {
        case .positive: return .green
        case .neutral, .unknown: return .secondary
        case .negative: return .red
        }
    }
}

extension LeaveStatus {
    var tint: Color {
        switch self {
        case .pending: return .orange
        case .approved: return .green
        case .rejected: return .red
        case .cancelled, .unknown: return .secondary
        }
    }
}

extension ExpenseStatus {
    var tint: Color {
        switch self {
        case .submitted: return .orange
        case .approved: return .blue
        case .reimbursed: return .green
        case .rejected: return .red
        case .unknown: return .secondary
        }
    }
}

/// Small, reusable status chip. A plain rounded capsule with a tinted label — NOT a glass
/// surface (glass is reserved for system chrome).
struct StatusChip: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
            .accessibilityLabel(text)
    }
}
