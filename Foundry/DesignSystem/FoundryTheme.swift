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
