import Foundation

/// Turns the store's list into the widget's snapshot.
enum WidgetPublisher {
    static func snapshot(_ items: [Commitment], signedIn: Bool, now: Date = Date(), calendar: Calendar = .current) -> WidgetSnapshot {
        guard signedIn else { return WidgetSnapshot(signedIn: false, updatedAt: now) }
        let horizon = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now))!
        let soon = items
            .filter { $0.state == .open && !$0.isSnoozed(at: now) }
            .filter { ($0.dueAt.map { $0 < horizon }) ?? false }
            .sorted(by: CommitmentGrouping.order)
            .prefix(12)
            .map { WidgetSnapshot.Item(id: $0.id, title: $0.title, dueAt: $0.dueAt, counterpart: $0.counterpart) }
        return WidgetSnapshot(
            signedIn: true, items: Array(soon),
            reviewCount: items.filter { $0.state == .suggested }.count, updatedAt: now
        )
    }

    static func publish(_ items: [Commitment], signedIn: Bool) {
        guard Bundle.main.bundleIdentifier != nil, Entitlements.hasAppGroup else { return }
        AppGroupStore.write(snapshot(items, signedIn: signedIn))
    }
}
