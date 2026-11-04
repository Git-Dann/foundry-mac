import SwiftUI

/// The four boxes of an Eisenhower matrix.
enum Quadrant: String, CaseIterable, Identifiable, Sendable {
    case doNow, schedule, delegate, later
    var id: String { rawValue }

    var important: Bool { self == .doNow || self == .schedule }
    var urgent: Bool { self == .doNow || self == .delegate }

    static func of(important: Bool, urgent: Bool) -> Quadrant {
        switch (important, urgent) {
        case (true, true): .doNow
        case (true, false): .schedule
        case (false, true): .delegate
        case (false, false): .later
        }
    }

    var title: String {
        switch self {
        case .doNow: "Do now"
        case .schedule: "Schedule"
        case .delegate: "Delegate"
        case .later: "Later"
        }
    }

    var explanation: String {
        switch self {
        case .doNow: "Important and due soon. Start here."
        case .schedule: "Important, not pressing. Give it a day."
        case .delegate: "Due soon, but someone else could do it."
        case .later: "Neither. Leave it, or let it go."
        }
    }

    var symbol: String {
        switch self {
        case .doNow: "flame"
        case .schedule: "calendar"
        case .delegate: "person.2"
        case .later: "tray"
        }
    }

    var tint: Color {
        switch self {
        case .doNow: .red
        case .schedule: .blue
        case .delegate: .orange
        case .later: .secondary
        }
    }
}

/// Where a to-do sits in the matrix, and what dragging it to another box changes. Pure.
enum MatrixRules {
    /// Important means priority 2 or 3.
    static func isImportant(_ c: Commitment) -> Bool { c.priority >= 2 }

    /// Urgent means a deadline within two days (or already passed), or planned for today or earlier.
    static func isUrgent(_ c: Commitment, now: Date, calendar: Calendar) -> Bool {
        if let due = c.dueAt, due <= now.addingTimeInterval(2 * 24 * 60 * 60) { return true }
        if let start = c.startAt,
           let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)),
           start < tomorrow { return true }
        return false
    }

    static func quadrant(_ c: Commitment, now: Date, calendar: Calendar) -> Quadrant {
        .of(important: isImportant(c), urgent: isUrgent(c, now: now, calendar: calendar))
    }

    /// The change that moves `c` into `target`. Nil when nothing would change (already there, or a
    /// board task where only its priority would have to move: board tasks keep their priority).
    static func patch(moving c: Commitment, to target: Quadrant, now: Date, calendar: Calendar) -> CommitmentPatch? {
        var patch = CommitmentPatch()

        let important = isImportant(c)
        if !c.isBoardTask && target.important != important {
            patch.priority = target.important ? 3 : 0
        }

        let urgent = isUrgent(c, now: now, calendar: calendar)
        if target.urgent != urgent {
            let today = calendar.startOfDay(for: now)
            if target.urgent {
                let fivePm = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: today) ?? now
                patch.dueAt = .set(fivePm)
            } else {
                let nextWeek = calendar.date(byAdding: .day, value: 7, to: today) ?? today
                let fivePm = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: nextWeek) ?? nextWeek
                patch.dueAt = .set(fivePm)
                // A planned day of today or earlier also makes it urgent: move that a week on too.
                if !c.isBoardTask, let start = c.startAt,
                   let tomorrow = calendar.date(byAdding: .day, value: 1, to: today), start < tomorrow {
                    patch.startAt = .set(nextWeek)
                }
            }
        }

        return patch.isEmpty ? nil : patch
    }
}

/// Every open to-do in an Eisenhower matrix. Drag between boxes to change priority or deadline.
struct MatrixView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let now = Date()
        let calendar = Calendar.current
        let open = model.store.items
            .filter { $0.state == .open && !$0.isSnoozed(at: now) }
            .sorted { ($0.dueAt ?? .distantFuture, $0.orderKey) < ($1.dueAt ?? .distantFuture, $1.orderKey) }
        let grouped = Dictionary(grouping: open) { MatrixRules.quadrant($0, now: now, calendar: calendar) }

        Grid(horizontalSpacing: 16, verticalSpacing: 16) {
            GridRow {
                QuadrantBox(quadrant: .doNow, items: grouped[.doNow] ?? [])
                QuadrantBox(quadrant: .schedule, items: grouped[.schedule] ?? [])
            }
            GridRow {
                QuadrantBox(quadrant: .delegate, items: grouped[.delegate] ?? [])
                QuadrantBox(quadrant: .later, items: grouped[.later] ?? [])
            }
        }
        .padding(16)
    }
}

private struct QuadrantBox: View {
    @Environment(AppModel.self) private var model
    let quadrant: Quadrant
    let items: [Commitment]
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Label(quadrant.title, systemImage: quadrant.symbol)
                        .font(.headline)
                        .foregroundStyle(quadrant.tint)
                    Spacer()
                    Text(items.count, format: .number)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(quadrant.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if items.isEmpty {
                Text("Nothing here")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            MatrixItem(commitment: item)
                            if item.id != items.last?.id { Divider() }
                        }
                    }
                }
                .scrollIndicators(.automatic)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(targeted ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.fill.quinary),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.smooth, value: targeted)
        .dropDestination(for: String.self) { ids, _ in
            let now = Date()
            var moved = false
            for id in ids {
                guard let c = model.store.commitment(id: id),
                      let patch = MatrixRules.patch(moving: c, to: quadrant, now: now, calendar: .current)
                else { continue }
                withAnimation(.smooth) { model.store.update(id, patch) }
                moved = true
            }
            return moved
        } isTargeted: { targeted = $0 }
    }
}

private struct MatrixItem: View {
    @Environment(AppModel.self) private var model
    let commitment: Commitment

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            CommitmentRow(commitment: commitment, compact: true)
            if commitment.priority > 0 {
                PriorityMarks(priority: commitment.priority)
            }
        }
        .padding(.horizontal, 4)
        .background(model.selectedCommitmentId == commitment.id ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { model.selectedCommitmentId = commitment.id }
        .draggable(commitment.id)
        .help(commitment.isBoardTask ? "Board task: dragging changes only its deadline" : "")
    }
}
