import Foundation

/// App Group shared by the main app and the widget extension.
///
/// On macOS `group.*` App Groups don't need a provisioning profile. An ad-hoc build triggers a
/// one-time consent prompt for cross-process container access; a Developer ID build with the
/// group registered to the team doesn't.
enum FoundryAppGroup {
    static let identifier = "group.co.gitwork.foundry"
    static let snapshotKey = "widget.commitments.v2"
}

/// What the widget renders. Written by the app whenever its list changes; the widget only reads
/// it (no network and no sign-in in the extension). Titles only: no quotes or notes leave the app.
struct WidgetSnapshot: Codable, Sendable, Equatable {
    struct Item: Codable, Sendable, Identifiable, Equatable {
        var id: String
        var title: String
        var dueAt: Date?
        var counterpart: String?
    }

    var signedIn: Bool = false
    /// Open commitments due by the end of tomorrow, plus overdue ones, soonest first.
    var items: [Item] = []
    var reviewCount: Int = 0
    var updatedAt: Date = .distantPast

    static let empty = WidgetSnapshot()

    /// Overdue and due-today items as of `date` (the widget calls this per timeline entry).
    func today(at date: Date, calendar: Calendar = .current) -> [Item] {
        items.filter { item in
            guard let due = item.dueAt else { return false }
            return due < date || calendar.isDate(due, inSameDayAs: date)
        }
    }

    func isOverdue(_ item: Item, at date: Date) -> Bool {
        (item.dueAt.map { $0 < date }) ?? false
    }
}
