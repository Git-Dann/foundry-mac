import Foundation
import UserNotifications

/// What the app will notify about. Two kinds only, by design: one morning digest, and a nudge
/// when something becomes overdue. A new suggestion never pings; it waits in the review list.
struct PlannedNotification: Equatable, Sendable {
    enum Kind: String, Sendable { case digest, overdue }
    var id: String
    var kind: Kind
    var date: Date
    var title: String
    var body: String
    var commitmentId: String?
}

struct NotificationPreferences: Equatable, Sendable {
    var digestEnabled = true
    var digestHour = 9
    var digestMinute = 0
    var overdueEnabled = true

    static let digestEnabledKey = "notifications.digest.enabled"
    static let digestTimeKey = "notifications.digest.minutes"
    static let overdueEnabledKey = "notifications.overdue.enabled"

    static func load(_ d: UserDefaults = .standard) -> NotificationPreferences {
        var p = NotificationPreferences()
        if d.object(forKey: digestEnabledKey) != nil { p.digestEnabled = d.bool(forKey: digestEnabledKey) }
        if d.object(forKey: overdueEnabledKey) != nil { p.overdueEnabled = d.bool(forKey: overdueEnabledKey) }
        if d.object(forKey: digestTimeKey) != nil {
            let m = max(0, min(23 * 60 + 59, d.integer(forKey: digestTimeKey)))
            p.digestHour = m / 60; p.digestMinute = m % 60
        }
        return p
    }
}

enum NotificationPlan {
    static let idPrefix = "commitments."
    /// macOS keeps a limited number of pending requests; nudges beyond this are planned on a later
    /// reschedule, once nearer ones have fired.
    static let maxOverdueNudges = 40
    static let digestDays = 3

    static func make(
        items: [Commitment], now: Date, prefs: NotificationPreferences, calendar: Calendar = .current
    ) -> [PlannedNotification] {
        var plan: [PlannedNotification] = []
        let open = items.filter { $0.state == .open }

        // Reminders the person set at a time: always delivered, whatever the digest settings.
        plan += open.compactMap { c -> PlannedNotification? in
            guard let at = c.remindAt, at > now else { return nil }
            return PlannedNotification(
                id: idPrefix + "remind." + c.id, kind: .overdue, date: at,
                title: "Reminder", body: c.title, commitmentId: c.id
            )
        }.sorted { $0.date < $1.date }.prefix(maxOverdueNudges)

        if prefs.overdueEnabled {
            let nudges = open.compactMap { c -> PlannedNotification? in
                guard let due = c.dueAt else { return nil }
                // A snoozed commitment nudges when its snooze ends, if it is overdue by then.
                let fireAt = max(due, c.snoozedUntil ?? due)
                guard fireAt > now else { return nil }
                return PlannedNotification(
                    id: idPrefix + "overdue." + c.id, kind: .overdue, date: fireAt,
                    title: "Now overdue", body: c.counterpart.map { "\(c.title) · \($0)" } ?? c.title,
                    commitmentId: c.id
                )
            }
            plan += nudges.sorted { $0.date < $1.date }.prefix(maxOverdueNudges)
        }

        if prefs.digestEnabled {
            let reviewCount = items.filter { $0.state == .suggested }.count
            for offset in 0..<(digestDays + 1) {
                guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                      let at = calendar.date(bySettingHour: prefs.digestHour, minute: prefs.digestMinute, second: 0, of: day),
                      at > now
                else { continue }
                // What will be due that day, and what will already be late by that morning.
                let dueThatDay = open.filter { c in
                    guard let due = c.dueAt, !(c.snoozedUntil.map { $0 > at } ?? false) else { return false }
                    return calendar.isDate(due, inSameDayAs: at) && due >= at
                }.count
                let lateBy = open.filter { c in
                    guard let due = c.dueAt, !(c.snoozedUntil.map { $0 > at } ?? false) else { return false }
                    return due < at
                }.count
                // Only the next digest can know how many suggestions are waiting.
                let review = plan.contains { $0.kind == .digest } ? 0 : reviewCount
                guard let body = digestBody(due: dueThatDay, overdue: lateBy, review: review) else { continue }
                plan.append(PlannedNotification(
                    id: idPrefix + "digest." + String(Int(at.timeIntervalSince1970)), kind: .digest, date: at,
                    title: "Your to-dos today", body: body, commitmentId: nil
                ))
                if plan.filter({ $0.kind == .digest }).count >= digestDays { break }
            }
        }
        return plan
    }

    /// A quiet morning sends nothing.
    static func digestBody(due: Int, overdue: Int, review: Int) -> String? {
        var parts: [String] = []
        if due > 0 { parts.append("\(due) due today") }
        if overdue > 0 { parts.append("\(overdue) overdue") }
        if review > 0 { parts.append("\(review) to review") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ") + "."
    }
}

/// Puts the plan into the system. Replaces all of this app's pending requests on each change, so
/// a completed or snoozed commitment never nudges.
@MainActor
final class NotificationScheduler: NSObject, UNUserNotificationCenterDelegate {
    static let overdueCategory = "commitment.overdue"
    static let completeAction = "commitment.complete"
    static let snoozeAction = "commitment.snooze"

    private var center: UNUserNotificationCenter? {
        // Unit tests run without a bundle that can talk to the notification service.
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    private var lastPlan: [PlannedNotification] = []

    override init() {
        super.init()
        guard let center else { return }
        center.delegate = self
        let done = UNNotificationAction(identifier: Self.completeAction, title: "Mark done")
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Tomorrow, 09:00")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.overdueCategory, actions: [done, snooze], intentIdentifiers: []),
        ])
    }

    func requestAuthorizationIfNeeded() {
        center?.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func reschedule(items: [Commitment], prefs: NotificationPreferences = .load()) {
        let plan = NotificationPlan.make(items: items, now: Date(), prefs: prefs)
        guard plan != lastPlan, let center else { return }
        lastPlan = plan
        center.getPendingNotificationRequests { requests in
            let ours = requests.map(\.identifier).filter { $0.hasPrefix(NotificationPlan.idPrefix) }
            center.removePendingNotificationRequests(withIdentifiers: ours)
            for n in plan {
                let content = UNMutableNotificationContent()
                content.title = n.title
                content.body = n.body
                content.sound = n.kind == .overdue ? .default : nil
                if let id = n.commitmentId {
                    content.userInfo = ["commitmentId": id]
                    content.categoryIdentifier = Self.overdueCategory
                }
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: n.date)
                center.add(UNNotificationRequest(
                    identifier: n.id, content: content,
                    trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                ))
            }
        }
    }

    func clearAll() {
        lastPlan = []
        guard let center else { return }
        center.getPendingNotificationRequests { requests in
            center.removePendingNotificationRequests(withIdentifiers: requests.map(\.identifier).filter { $0.hasPrefix(NotificationPlan.idPrefix) })
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let id = response.notification.request.content.userInfo["commitmentId"] as? String
        let action = response.actionIdentifier
        await MainActor.run {
            let model = AppModel.shared
            switch (action, id) {
            case (Self.completeAction, let id?): model.complete(id)
            case (Self.snoozeAction, let id?): model.store.snooze(id, until: SnoozeOption.tomorrow.until(from: Date()))
            default: model.showInWindow(id: id)
            }
        }
    }
}
