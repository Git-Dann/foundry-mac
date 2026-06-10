import Foundation

/// App Group shared by the main app and the widget extension.
///
/// On macOS (unlike iOS) `group.*` App Groups don't require a provisioning profile — an
/// ad-hoc/unsigned build just triggers a one-time system consent prompt for cross-process
/// container access (macOS 15+). Once the app is Developer ID-signed with the group registered
/// to the team, the prompt goes away.
enum FoundryAppGroup {
    static let identifier = "group.co.gitwork.foundry"
    static let snapshotKey = "widget.snapshot.v1"
}

/// The data the widgets render. Written by the main app whenever fresh data loads; widgets only
/// READ this (no network, no auth in the extension). Each writer updates just its slice.
struct WidgetSnapshot: Codable, Sendable {
    struct AiSpend: Codable, Sendable {
        var today: Double
        var monthToDate: Double
        var currency: String
    }

    struct Event: Codable, Sendable, Identifiable {
        var id: String
        var title: String
        var start: Date
        var isAllDay: Bool
    }

    struct Scan: Codable, Sendable, Identifiable {
        var id: String
        var name: String
        var score: Int?
    }

    var aiSpend: AiSpend?
    var events: [Event] = []
    var scans: [Scan] = []
    var updatedAt: Date = .distantPast

    static let empty = WidgetSnapshot()
}
