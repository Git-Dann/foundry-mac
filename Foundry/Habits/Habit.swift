import Foundation
import Observation
import SwiftData
import SwiftUI

@Model
final class Habit {
    @Attribute(.unique) var id: UUID
    var name: String
    var symbol: String
    var colorName: String
    /// Days a week it should happen, 1 to 7.
    var targetPerWeek: Int
    var createdAt: Date
    var archived: Bool

    init(
        id: UUID = UUID(), name: String, symbol: String = "checkmark.circle", colorName: String = "blue",
        targetPerWeek: Int = 7, createdAt: Date = .now, archived: Bool = false
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.colorName = colorName
        self.targetPerWeek = max(1, min(7, targetPerWeek))
        self.createdAt = createdAt
        self.archived = archived
    }

    var color: Color { HabitPalette.color(colorName) }
}

@Model
final class HabitCheck {
    @Attribute(.unique) var id: UUID
    var habitId: UUID
    /// The start of the day it was done.
    var day: Date

    init(id: UUID = UUID(), habitId: UUID, day: Date) {
        self.id = id
        self.habitId = habitId
        self.day = day
    }
}

enum HabitPalette {
    static let names = ["blue", "green", "orange", "pink", "purple", "teal", "red", "yellow"]
    static let symbols = [
        "checkmark.circle", "figure.walk", "figure.run", "dumbbell", "book", "drop",
        "bed.double", "leaf", "brain.head.profile", "pencil", "cup.and.saucer", "heart",
    ]

    static func color(_ name: String) -> Color {
        switch name {
        case "green": .green
        case "orange": .orange
        case "pink": .pink
        case "purple": .purple
        case "teal": .teal
        case "red": .red
        case "yellow": .yellow
        default: .blue
        }
    }
}

/// Streaks and weekly counts, worked out from the days a habit was done.
enum HabitStats {
    struct WeekRate: Identifiable, Equatable {
        var weekStart: Date
        var count: Int
        /// Share of the weekly target met, 0 to 1.
        var rate: Double
        var id: Date { weekStart }
    }

    /// The calendar the habits screen uses: weeks run Monday to Sunday.
    static func weekCalendar(_ base: Calendar = .current) -> Calendar {
        var c = base
        c.firstWeekday = 2
        return c
    }

    /// Consecutive days ending today, or yesterday when today isn't done yet.
    static func currentStreak(days: Set<Date>, today: Date, calendar: Calendar) -> Int {
        let done = Set(days.map { calendar.startOfDay(for: $0) })
        var day = calendar.startOfDay(for: today)
        if !done.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day), done.contains(yesterday) else {
                return 0
            }
            day = yesterday
        }
        var streak = 0
        while done.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// The seven days of the week holding `date`, in the calendar's own order.
    static func weekDays(containing date: Date, calendar: Calendar) -> [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// How many days were done in the week holding `date`.
    static func weekCount(days: Set<Date>, containing date: Date, calendar: Calendar) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        return Set(days.map { calendar.startOfDay(for: $0) }).filter { $0 >= week.start && $0 < week.end }.count
    }

    /// The last `weeks` weeks, oldest first, ending with the week holding `today`.
    static func weeklyRates(
        days: Set<Date>, targetPerWeek: Int, weeks: Int = 12, today: Date, calendar: Calendar
    ) -> [WeekRate] {
        let target = Double(max(1, min(7, targetPerWeek)))
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start else { return [] }
        return (0..<weeks).reversed().compactMap { back in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek) else { return nil }
            let count = weekCount(days: days, containing: start, calendar: calendar)
            return WeekRate(weekStart: start, count: count, rate: min(1, Double(count) / target))
        }
    }

    /// Average share of the target met over the last `weeks` weeks.
    static func completionRate(
        days: Set<Date>, targetPerWeek: Int, weeks: Int = 12, today: Date, calendar: Calendar
    ) -> Double {
        let rates = weeklyRates(days: days, targetPerWeek: targetPerWeek, weeks: weeks, today: today, calendar: calendar)
        guard !rates.isEmpty else { return 0 }
        return rates.map(\.rate).reduce(0, +) / Double(rates.count)
    }
}

/// Owns the habits database, kept on this Mac only.
@MainActor
@Observable
final class HabitStore {
    static let shared = HabitStore()

    private(set) var habits: [Habit] = []
    private(set) var checks: [UUID: Set<Date>] = [:]
    /// Set when the store on disk could not be opened, so the screen can say so.
    private(set) var loadError: String?

    @ObservationIgnored let container: ModelContainer
    @ObservationIgnored private let calendar: Calendar
    private var context: ModelContext { container.mainContext }

    static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appending(path: "co.gitwork.foundry", directoryHint: .isDirectory)
            .appending(path: "habits.store")
    }

    init(inMemory: Bool = false, calendar: Calendar = .current) {
        self.calendar = calendar
        let schema = Schema([Habit.self, HabitCheck.self])
        var opened: ModelContainer?
        var error: String?
        if !inMemory {
            do {
                try FileManager.default.createDirectory(
                    at: Self.storeURL.deletingLastPathComponent(), withIntermediateDirectories: true
                )
                opened = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: Self.storeURL))
            } catch let e {
                error = "Habits couldn't be loaded: \(e.localizedDescription)"
            }
        }
        // swiftlint:disable:next force_try
        container = opened ?? (try! ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)))
        loadError = error
        reload()
    }

    func reload() {
        let all = (try? context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.createdAt)]))) ?? []
        habits = all.filter { !$0.archived }
        var map: [UUID: Set<Date>] = [:]
        for check in (try? context.fetch(FetchDescriptor<HabitCheck>())) ?? [] {
            map[check.habitId, default: []].insert(check.day)
        }
        checks = map
    }

    func days(for habitId: UUID) -> Set<Date> { checks[habitId] ?? [] }

    func isDone(_ habitId: UUID, on day: Date) -> Bool {
        days(for: habitId).contains(calendar.startOfDay(for: day))
    }

    @discardableResult
    func add(name: String, symbol: String, colorName: String, targetPerWeek: Int) -> Habit? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let habit = Habit(name: String(trimmed.prefix(80)), symbol: symbol, colorName: colorName, targetPerWeek: targetPerWeek)
        context.insert(habit)
        save()
        return habit
    }

    func archive(_ habitId: UUID) {
        guard let habit = habit(habitId) else { return }
        habit.archived = true
        save()
    }

    /// Ticks or unticks a day. Days after today can't be ticked.
    func toggle(_ habitId: UUID, on date: Date, now: Date = .now) {
        let day = calendar.startOfDay(for: date)
        guard day <= calendar.startOfDay(for: now) else { return }
        let existing = (try? context.fetch(FetchDescriptor<HabitCheck>(
            predicate: #Predicate { $0.habitId == habitId && $0.day == day }
        ))) ?? []
        if existing.isEmpty {
            context.insert(HabitCheck(habitId: habitId, day: day))
        } else {
            existing.forEach(context.delete)
        }
        save()
    }

    private func habit(_ id: UUID) -> Habit? {
        try? context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })).first
    }

    private func save() {
        try? context.save()
        reload()
    }
}
