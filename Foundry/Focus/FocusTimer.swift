import Foundation
import Observation
import UserNotifications

/// The arithmetic of one timed block, kept free of clocks and storage so it can be tested.
/// Time spent paused is not counted, so the end moves later by however long it was paused.
struct FocusClock: Codable, Equatable, Sendable {
    var duration: TimeInterval
    var startedAt: Date
    var pausedAt: Date?
    var pausedTotal: TimeInterval = 0

    var isPaused: Bool { pausedAt != nil }

    func elapsed(at now: Date) -> TimeInterval {
        let end = pausedAt ?? now
        return min(duration, max(0, end.timeIntervalSince(startedAt) - pausedTotal))
    }

    func remaining(at now: Date) -> TimeInterval { max(0, duration - elapsed(at: now)) }

    /// 0 at the start, 1 when the time is up.
    func progress(at now: Date) -> Double {
        duration > 0 ? elapsed(at: now) / duration : 1
    }

    func isFinished(at now: Date) -> Bool { remaining(at: now) <= 0 }

    /// When it will end if left running. Nil while paused, since nobody knows yet.
    var endDate: Date? {
        isPaused ? nil : startedAt.addingTimeInterval(pausedTotal + duration)
    }

    mutating func pause(at now: Date) {
        guard pausedAt == nil else { return }
        pausedAt = now
    }

    mutating func resume(at now: Date) {
        guard let pausedAt else { return }
        pausedTotal += max(0, now.timeIntervalSince(pausedAt))
        self.pausedAt = nil
    }
}

enum FocusPreset: Hashable, Identifiable, Sendable {
    case short, standard, long, custom

    static let allCases: [FocusPreset] = [.short, .standard, .long, .custom]
    var id: Self { self }

    var minutes: Int? {
        switch self {
        case .short: 15
        case .standard: 25
        case .long: 50
        case .custom: nil
        }
    }

    var label: String { minutes.map { "\($0) min" } ?? "Custom" }

    static func matching(minutes: Int) -> FocusPreset {
        allCases.first { $0.minutes == minutes } ?? .custom
    }
}

/// One focus timer for the whole app, so the window and the menu bar always agree.
@MainActor
@Observable
final class FocusSession {
    static let shared = FocusSession()

    enum State: Equatable { case idle, running, paused, onBreak }
    enum Phase: String, Codable { case focus, rest }

    static let defaultMinutes = 25
    static let breakMinutes = 5
    static let storageKey = "focus.session"
    static let lengthKey = "focus.lengthMinutes"
    static let completedKey = "focus.completed"
    static let notificationId = "focus.end"

    private struct Stored: Codable {
        var clock: FocusClock
        var phase: Phase
        var todoId: String?
        var todoTitle: String?
    }

    private struct Completed: Codable {
        var day: Date
        var count: Int
    }

    /// Minutes for the next focus block.
    var lengthMinutes: Int {
        get { storedLength }
        set {
            storedLength = max(1, min(180, newValue))
            defaults.set(storedLength, forKey: Self.lengthKey)
        }
    }
    private var storedLength: Int

    private(set) var clock: FocusClock?
    private(set) var phase: Phase = .focus
    private(set) var todoId: String?
    private(set) var todoTitle: String?
    private var completed: Completed?

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let notifies: Bool
    @ObservationIgnored private var endTask: Task<Void, Never>?

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current,
        now: @escaping () -> Date = Date.init,
        notifies: Bool = Bundle.main.bundleIdentifier != nil
            && NSClassFromString("XCTestCase") == nil
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.now = now
        self.notifies = notifies
        let saved = defaults.integer(forKey: Self.lengthKey)
        storedLength = saved > 0 ? min(180, saved) : Self.defaultMinutes
        if let data = defaults.data(forKey: Self.completedKey),
           let c = try? JSONDecoder().decode(Completed.self, from: data) {
            completed = c
        }
        if let data = defaults.data(forKey: Self.storageKey),
           let s = try? JSONDecoder().decode(Stored.self, from: data) {
            clock = s.clock
            phase = s.phase
            todoId = s.todoId
            todoTitle = s.todoTitle
            // Finished while the app was closed: count it, and do not start a break nobody saw.
            if s.clock.isFinished(at: now()) {
                if s.phase == .focus { recordCompleted(on: s.clock.endDate ?? now()) }
                reset(cancelNotification: false)
            } else {
                watchForEnd()
            }
        }
    }

    // MARK: Reading

    var state: State {
        guard let clock else { return .idle }
        if phase == .rest { return .onBreak }
        return clock.isPaused ? .paused : .running
    }

    var isActive: Bool { clock != nil }

    func remaining(at date: Date) -> TimeInterval { clock?.remaining(at: date) ?? TimeInterval(lengthMinutes * 60) }
    func progress(at date: Date) -> Double { clock?.progress(at: date) ?? 0 }

    var completedToday: Int {
        guard let completed, calendar.isDate(completed.day, inSameDayAs: now()) else { return 0 }
        return completed.count
    }

    /// "24:59", or "1:04:59" past an hour.
    nonisolated static func format(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded(.up))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }

    // MARK: Controls

    func start(todoId: String? = nil, todoTitle: String? = nil) {
        clock = FocusClock(duration: TimeInterval(lengthMinutes * 60), startedAt: now())
        phase = .focus
        self.todoId = todoId
        self.todoTitle = todoTitle
        changed()
    }

    func pause() {
        guard clock != nil else { return }
        clock?.pause(at: now())
        changed()
    }

    func resume() {
        guard clock != nil else { return }
        clock?.resume(at: now())
        changed()
    }

    func stop() {
        reset(cancelNotification: true)
    }

    func startBreak() {
        clock = FocusClock(duration: TimeInterval(Self.breakMinutes * 60), startedAt: now())
        phase = .rest
        changed()
    }

    /// Moves on if the time is up. Called by the end timer, and safe to call from a view tick.
    func finishIfDue() {
        guard let clock, clock.isFinished(at: now()) else { return }
        if phase == .focus {
            recordCompleted(on: now())
            startBreak()
        } else {
            reset(cancelNotification: false)
        }
    }

    // MARK: Internals

    private func reset(cancelNotification: Bool) {
        clock = nil
        phase = .focus
        todoId = nil
        todoTitle = nil
        endTask?.cancel()
        endTask = nil
        defaults.removeObject(forKey: Self.storageKey)
        if cancelNotification { removeNotification() }
    }

    private func recordCompleted(on day: Date) {
        if let c = completed, calendar.isDate(c.day, inSameDayAs: day) {
            completed = Completed(day: c.day, count: c.count + 1)
        } else {
            completed = Completed(day: calendar.startOfDay(for: day), count: 1)
        }
        if let data = try? JSONEncoder().encode(completed) { defaults.set(data, forKey: Self.completedKey) }
    }

    private func changed() {
        persist()
        watchForEnd()
        scheduleNotification()
    }

    private func persist() {
        guard let clock else { defaults.removeObject(forKey: Self.storageKey); return }
        let stored = Stored(clock: clock, phase: phase, todoId: todoId, todoTitle: todoTitle)
        if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: Self.storageKey) }
    }

    private func watchForEnd() {
        endTask?.cancel()
        guard let end = clock?.endDate else { endTask = nil; return }
        let wait = max(0, end.timeIntervalSince(now()))
        endTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            self?.finishIfDue()
        }
    }

    private func removeNotification() {
        guard notifies else { return }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
    }

    /// Uses whatever permission the app already has; it never asks on its own.
    private func scheduleNotification() {
        guard notifies else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
        guard let end = clock?.endDate else { return }
        let wait = end.timeIntervalSince(now())
        guard wait > 0 else { return }
        let content = UNMutableNotificationContent()
        if phase == .focus {
            content.title = "Focus session done"
            content.body = todoTitle.map { "Time for a \(Self.breakMinutes)-minute break from “\($0)”." }
                ?? "Time for a \(Self.breakMinutes)-minute break."
        } else {
            content.title = "Break over"
            content.body = "Ready for the next session?"
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: Self.notificationId, content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: wait, repeats: false)
        )
        center.getNotificationSettings { settings in
            let allowed: [UNAuthorizationStatus] = [.authorized, .provisional]
            guard allowed.contains(settings.authorizationStatus) else { return }
            center.add(request)
        }
    }
}
