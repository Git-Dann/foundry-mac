import Charts
import SwiftUI

/// Habits kept on this Mac: tick the days, keep the streak going.
struct HabitsView: View {
    private var store: HabitStore { .shared }
    @State private var showingNew = false
    @State private var selectedId: UUID?

    private let calendar = HabitStats.weekCalendar()

    var body: some View {
        Group {
            if store.habits.isEmpty {
                ContentUnavailableView {
                    Label("No Habits Yet", systemImage: "repeat.circle")
                } description: {
                    Text(store.loadError ?? "Add something you want to do most days, then tick it off as you go.")
                } actions: {
                    Button("New Habit", systemImage: "plus") { showingNew = true }
                        .buttonStyle(.glassProminent)
                }
            } else {
                TimelineView(.everyMinute) { context in
                    List {
                        ForEach(store.habits) { habit in
                            HabitRow(
                                habit: habit, today: context.date, calendar: calendar,
                                isSelected: selectedId == habit.id
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { selectedId = selectedId == habit.id ? nil : habit.id }
                            .contextMenu {
                                Button("Show Chart", systemImage: "chart.bar") { selectedId = habit.id }
                                Button("Archive", systemImage: "archivebox") {
                                    if selectedId == habit.id { selectedId = nil }
                                    store.archive(habit.id)
                                }
                            }
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                    .listStyle(.inset)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Habits")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Habit", systemImage: "plus") { showingNew = true }
            }
        }
        .inspector(isPresented: Binding(get: { selectedId != nil }, set: { if !$0 { selectedId = nil } })) {
            if let id = selectedId, let habit = store.habits.first(where: { $0.id == id }) {
                HabitDetail(habit: habit, calendar: calendar)
                    .inspectorColumnWidth(min: 280, ideal: 320, max: 420)
            }
        }
        .sheet(isPresented: $showingNew) {
            NewHabitSheet()
        }
    }
}

private struct HabitRow: View {
    let habit: Habit
    let today: Date
    let calendar: Calendar
    let isSelected: Bool
    private var store: HabitStore { .shared }

    var body: some View {
        let days = store.days(for: habit.id)
        let streak = HabitStats.currentStreak(days: days, today: today, calendar: calendar)
        let thisWeek = HabitStats.weekCount(days: days, containing: today, calendar: calendar)

        HStack(alignment: .center, spacing: 16) {
            Image(systemName: habit.symbol)
                .font(.title2)
                .foregroundStyle(habit.color)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name).font(.headline)
                HStack(spacing: 8) {
                    Label(streak == 1 ? "1-day streak" : "\(streak)-day streak", systemImage: "flame")
                        .foregroundStyle(streak > 0 ? .orange : .secondary)
                    Text("\(thisWeek) of \(habit.targetPerWeek) this week")
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .contentTransition(.numericText())
            }
            Spacer(minLength: 12)
            weekButtons(days: days)
        }
        .padding(16)
        .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
    }

    private func weekButtons(days: Set<Date>) -> some View {
        HStack(spacing: 6) {
            ForEach(HabitStats.weekDays(containing: today, calendar: calendar), id: \.self) { day in
                let done = days.contains(calendar.startOfDay(for: day))
                let isToday = calendar.isDate(day, inSameDayAs: today)
                let isFuture = calendar.startOfDay(for: day) > calendar.startOfDay(for: today)
                VStack(spacing: 4) {
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Color.accentColor : .secondary)
                    Button {
                        store.toggle(habit.id, on: day, now: today)
                    } label: {
                        Image(systemName: done ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(done ? habit.color : (isToday ? Color.accentColor : .secondary))
                            .symbolEffect(.bounce, value: done)
                    }
                    .buttonStyle(.borderless)
                    .disabled(isFuture)
                    .accessibilityLabel("\(day.formatted(.dateTime.weekday(.wide))), \(done ? "done" : "not done")")
                }
            }
        }
    }
}

private struct HabitDetail: View {
    let habit: Habit
    let calendar: Calendar
    private var store: HabitStore { .shared }

    var body: some View {
        let days = store.days(for: habit.id)
        let rates = HabitStats.weeklyRates(days: days, targetPerWeek: habit.targetPerWeek, today: .now, calendar: calendar)
        let overall = HabitStats.completionRate(days: days, targetPerWeek: habit.targetPerWeek, today: .now, calendar: calendar)

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label(habit.name, systemImage: habit.symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(habit.color)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Last 12 weeks").font(.headline)
                    Chart(rates) { week in
                        BarMark(
                            x: .value("Week", week.weekStart, unit: .weekOfYear),
                            y: .value("Days", week.count)
                        )
                        .foregroundStyle(habit.color.gradient)
                        RuleMark(y: .value("Target", habit.targetPerWeek))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    .chartYScale(domain: 0...7)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .weekOfYear, count: 3)) {
                            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        }
                    }
                    .frame(height: 180)
                    Text("Met \(overall.formatted(.percent.precision(.fractionLength(0)))) of the target of \(habit.targetPerWeek) a week.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .padding(20)
        }
    }
}

private struct NewHabitSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = HabitPalette.symbols[0]
    @State private var colorName = HabitPalette.names[0]
    @State private var target = 7

    var body: some View {
        VStack(spacing: 0) {
            Form {
                TextField("Name", text: $name, prompt: Text("Walk at lunch"))
                Picker("Symbol", selection: $symbol) {
                    ForEach(HabitPalette.symbols, id: \.self) { s in
                        Label(s, systemImage: s).labelStyle(.iconOnly).tag(s)
                    }
                }
                Picker("Colour", selection: $colorName) {
                    ForEach(HabitPalette.names, id: \.self) { n in
                        Label {
                            Text(n.capitalized)
                        } icon: {
                            Image(systemName: "circle.fill").foregroundStyle(HabitPalette.color(n))
                        }
                        .tag(n)
                    }
                }
                Stepper(target == 7 ? "Every day" : "\(target) days a week", value: $target, in: 1...7)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Button("Add Habit") {
                    HabitStore.shared.add(name: name, symbol: symbol, colorName: colorName, targetPerWeek: target)
                    dismiss()
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 420)
        .navigationTitle("New Habit")
    }
}
