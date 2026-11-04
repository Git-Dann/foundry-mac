import SwiftUI
import UniformTypeIdentifiers

/// Your week: calendar events and commitments on one grid, with an inbox of what's waiting.
/// Drag a commitment onto a time to give it one; drag it again to move it. Events are read-only.
struct CalendarScreen: View {
    @Environment(AppModel.self) private var model
    @State private var anchor = Date()
    @State private var mode: CalendarMode = .week
    @AppStorage("calendar.inboxShown") private var inboxShown = true

    var body: some View {
        let days = CalendarLayout.days(around: anchor, mode: mode)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header(days)
                if case .unavailable(let reason) = model.calendar.status {
                    CalendarNotice(reason: reason).padding(.horizontal, 20).padding(.bottom, 10)
                }
                WeekGrid(days: days)
            }
            .frame(minWidth: 520, maxWidth: .infinity)
            if inboxShown {
                Divider()
                InboxPanel().frame(width: 300)
            }
        }
        .navigationTitle("Calendar")
        .toolbar {
            ToolbarItem {
                Button { withAnimation(.easeOut(duration: 0.18)) { inboxShown.toggle() } } label: {
                    Label(inboxShown ? "Hide Inbox" : "Show Inbox", systemImage: "sidebar.right")
                }
                .help(inboxShown ? "Hide the inbox" : "Show the inbox")
            }
        }
        .task(id: days) {
            let cal = Calendar.current
            await model.calendar.load(from: days.first!, to: cal.date(byAdding: .day, value: 1, to: days.last!)!)
        }
    }

    private func header(_ days: [Date]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(CalendarLayout.title(for: days))
                    .font(.system(size: 28, weight: .bold))
                Text(CalendarLayout.subtitle(for: days))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("View", selection: $mode) {
                ForEach(CalendarMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Button("Today") { anchor = Date() }
                .keyboardShortcut("t", modifiers: .command)
            ControlGroup {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .help(mode == .week ? "Previous week" : "Previous day")
                    .keyboardShortcut(.leftArrow, modifiers: .command)
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .help(mode == .week ? "Next week" : "Next day")
                    .keyboardShortcut(.rightArrow, modifiers: .command)
            }
            .fixedSize()
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private func step(_ n: Int) {
        anchor = Calendar.current.date(byAdding: .day, value: n * (mode == .week ? 7 : 1), to: anchor) ?? anchor
    }
}

/// The time grid. A pinned row of day names, an all-day strip, then 24 hours that open around now.
private struct WeekGrid: View {
    @Environment(AppModel.self) private var model
    let days: [Date]
    private let gutter: CGFloat = 52

    var body: some View {
        let cal = Calendar.current
        let start = days.first ?? Date()
        let end = cal.date(byAdding: .day, value: 1, to: days.last ?? Date())!
        let events = model.calendar.events(from: start, to: end)
        let timed = events.filter { !$0.isAllDay }
        let allDay = events.filter(\.isAllDay)
        let commitments = model.store.items.filter { $0.state == .open && $0.dueAt != nil }

        VStack(spacing: 0) {
            // Header rows keep their natural height; the time grid takes the rest.
            dayHeader(commitments: commitments).fixedSize(horizontal: false, vertical: true)
            if !allDay.isEmpty { allDayStrip(allDay).fixedSize(horizontal: false, vertical: true) }
            Divider()
            ScrollViewReader { proxy in
                ScrollView(.vertical) {
                    TimelineView(.periodic(from: .now, by: 60)) { context in
                        ZStack(alignment: .topLeading) {
                            hourLines(hiding: nowHourLabel(context.date))
                            HStack(spacing: 0) {
                                Color.clear.frame(width: gutter)
                                ForEach(days, id: \.self) { day in
                                    DayColumn(
                                        day: day,
                                        events: timed.filter { cal.isDate($0.start, inSameDayAs: day) },
                                        commitments: commitments.filter { cal.isDate($0.dueAt!, inSameDayAs: day) }
                                    )
                                    .overlay(alignment: .leading) { Divider() }
                                }
                            }
                            nowLine(at: context.date)
                        }
                        .frame(height: 24 * CalendarLayout.hourHeight)
                    }
                }
                .onAppear { scrollToMorning(proxy) }
                .onChange(of: days) { scrollToMorning(proxy) }
            }
            .frame(maxHeight: .infinity)
            .layoutPriority(1)
        }
    }

    private func scrollToMorning(_ proxy: ScrollViewProxy) {
        let hour = Calendar.current.component(.hour, from: Date())
        let target = max(0, min(hour - 2, 7))
        DispatchQueue.main.async { proxy.scrollTo("hour-\(target)", anchor: .top) }
    }

    private func dayHeader(commitments: [Commitment]) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter)
            ForEach(days, id: \.self) { day in
                let isToday = Calendar.current.isDateInToday(day)
                let due = commitments.filter { Calendar.current.isDate($0.dueAt!, inSameDayAs: day) }.count
                HStack(spacing: 5) {
                    Text(isToday ? "Today" : day.formatted(.dateTime.weekday(.abbreviated)))
                        .fontWeight(.semibold)
                        .foregroundStyle(isToday ? Color.red : Color.primary)
                    Text(day.formatted(.dateTime.day()))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 2)
                    if due > 0 {
                        Text("\(due)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.tint)
                            .help("\(due) commitment\(due == 1 ? "" : "s") due")
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func allDayStrip(_ events: [CalendarEvent]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("all-day").font(.caption2).foregroundStyle(.secondary).frame(width: gutter, alignment: .trailing).padding(.trailing, 6)
            ForEach(days, id: \.self) { day in
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(events.filter { $0.start < Calendar.current.date(byAdding: .day, value: 1, to: day)! && $0.end > day }) { e in
                        Text(e.title)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(EventColor.fill, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 3)
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .padding(.vertical, 4)
    }

    /// The hour whose label the now badge would cover (within 12 minutes of it), if it's on screen.
    private func nowHourLabel(_ now: Date) -> Int? {
        guard days.contains(where: { Calendar.current.isDate($0, inSameDayAs: now) }) else { return nil }
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        guard let h = c.hour, let m = c.minute else { return nil }
        if m >= 48 { return (h + 1) % 24 }
        if m <= 12 { return h }
        return nil
    }

    private func hourLines(hiding hidden: Int?) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<24, id: \.self) { h in
                HStack(alignment: .top, spacing: 0) {
                    Text(h == 0 || h == hidden ? "" : String(format: "%02d:00", h))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: gutter - 8, alignment: .trailing)
                        .offset(y: -7)
                    VStack { Divider() }.padding(.leading, 8)
                }
                .frame(height: CalendarLayout.hourHeight, alignment: .top)
                .id("hour-\(h)")
            }
        }
    }

    @ViewBuilder private func nowLine(at now: Date) -> some View {
        if let index = days.firstIndex(where: { Calendar.current.isDate($0, inSameDayAs: now) }) {
            GeometryReader { geo in
                let colWidth = (geo.size.width - gutter) / CGFloat(days.count)
                let y = CalendarLayout.y(for: now)
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Color.red.opacity(0.35)).frame(height: 1)
                        .offset(x: gutter, y: y).frame(width: geo.size.width - gutter, alignment: .leading)
                    Rectangle().fill(Color.red).frame(width: colWidth, height: 2)
                        .offset(x: gutter + colWidth * CGFloat(index), y: y - 0.5)
                    Text(now.formatted(.dateTime.hour().minute()))
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Color.red, in: Capsule())
                        .offset(x: 2, y: y - 8)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

/// One day's column: events and commitments placed by time, side by side when they overlap.
/// Dropping a commitment here sets its time to where it lands.
private struct DayColumn: View {
    @Environment(AppModel.self) private var model
    let day: Date
    let events: [CalendarEvent]
    let commitments: [Commitment]
    @State private var dropY: CGFloat?

    var body: some View {
        let isWeekend = Calendar.current.isDateInWeekend(day)
        let spans = events.map { CalendarLayout.Span(id: "e:" + $0.id, start: $0.start, end: $0.end) }
            + commitments.map { CalendarLayout.Span(id: "c:" + $0.id, start: $0.dueAt!, end: $0.dueAt!.addingTimeInterval(CalendarLayout.commitmentMinutes * 60)) }
        let slots = CalendarLayout.slots(spans)

        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Rectangle().fill(isWeekend ? AnyShapeStyle(.quaternary.opacity(0.35)) : AnyShapeStyle(.clear))
                ForEach(events) { e in
                    let slot = slots["e:" + e.id] ?? .init(column: 0, columns: 1)
                    EventBlock(event: e)
                        .frame(width: width(geo, slot), height: CalendarLayout.height(start: e.start, end: e.end))
                        .offset(x: x(geo, slot), y: CalendarLayout.y(for: e.start))
                }
                ForEach(commitments) { c in
                    let slot = slots["c:" + c.id] ?? .init(column: 0, columns: 1)
                    CommitmentBlock(commitment: c)
                        .frame(width: width(geo, slot), height: CalendarLayout.commitmentMinutes / 60 * CalendarLayout.hourHeight)
                        .offset(x: x(geo, slot), y: CalendarLayout.y(for: c.dueAt!))
                }
                if let dropY {
                    let t = CalendarLayout.time(atY: dropY, on: day)
                    Text(t.formatted(.dateTime.hour().minute()))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.tint, in: Capsule())
                        .foregroundStyle(.white)
                        .offset(x: 4, y: CalendarLayout.y(for: t) - 9)
                }
            }
            .contentShape(Rectangle())
            .dropDestination(for: String.self) { ids, location in
                dropY = nil
                guard let id = ids.first, model.store.commitment(id: id) != nil else { return false }
                let time = CalendarLayout.time(atY: location.y, on: day)
                model.store.update(id, CommitmentPatch(dueAt: .set(time), snoozedUntil: .clear))
                return true
            } isTargeted: { targeted in
                if !targeted { dropY = nil }
            }
            .onContinuousHover { phase in
                // Shows the time a drop would land at while something is dragged over the day.
                if case .active(let p) = phase, dropY != nil { dropY = p.y }
            }
        }
    }

    private func width(_ geo: GeometryProxy, _ s: CalendarLayout.Slot) -> CGFloat {
        max(geo.size.width / CGFloat(s.columns) - 4, 10)
    }

    private func x(_ geo: GeometryProxy, _ s: CalendarLayout.Slot) -> CGFloat {
        geo.size.width / CGFloat(s.columns) * CGFloat(s.column) + 2
    }
}

/// Meetings are filled and quiet; commitments are outlined with a tick, so the two never look alike.
enum EventColor {
    static let fill = Color.secondary.opacity(0.16)
    static let bar = Color.secondary
}

private struct EventBlock: View {
    let event: CalendarEvent
    @State private var showing = false

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(EventColor.bar).frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).font(.caption.weight(.semibold)).lineLimit(2)
                Text(event.start.formatted(.dateTime.hour().minute())).font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 5).padding(.vertical, 3)
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(EventColor.fill)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .contentShape(Rectangle())
        .onTapGesture { showing = true }
        .popover(isPresented: $showing, arrowEdge: .trailing) { EventDetail(event: event) }
        .help(event.title)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

private struct EventDetail: View {
    @Environment(AppModel.self) private var model
    let event: CalendarEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Google Calendar").font(.caption).foregroundStyle(.secondary)
            Text(event.title).font(.headline)
            Text(event.isAllDay ? event.start.formatted(.dateTime.weekday(.wide).day().month())
                 : "\(event.start.formatted(.dateTime.weekday(.wide).day().month().hour().minute())) – \(event.end.formatted(.dateTime.hour().minute()))")
                .foregroundStyle(.secondary)
            if let location = event.location { Label(location, systemImage: "mappin").font(.callout).lineLimit(2) }
            if event.attendees > 0 {
                Label("\(event.attendees) other\(event.attendees == 1 ? "" : "s")", systemImage: "person.2").font(.callout)
            }
            HStack {
                if let meet = event.meetLink { Button("Join") { NSWorkspace.shared.open(meet) }.buttonStyle(.borderedProminent) }
                if let link = event.htmlLink { Button("Open in Google Calendar") { NSWorkspace.shared.open(link) } }
            }
            .controlSize(.small)
            Divider()
            Button {
                // A commitment to follow up, due the end of the meeting's day. Nothing is sent.
                let due = Calendar.current.date(bySettingHour: DueDateParser.defaultHour, minute: 0, second: 0, of: event.end) ?? event.end
                model.store.add(NewCommitment(title: "Follow up after “\(event.title)”", dueAt: max(due, event.end)))
            } label: {
                Label("Add a follow-up commitment", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }
}

private struct CommitmentBlock: View {
    @Environment(AppModel.self) private var model
    let commitment: Commitment
    @State private var showing = false

    var body: some View {
        let overdue = (commitment.dueAt.map { $0 < Date() } ?? false)
        HStack(alignment: .top, spacing: 5) {
            CompleteButton(done: false) { model.complete(commitment.id) }
                .scaleEffect(0.8)
                .frame(width: 16, height: 16)
            Text(commitment.title)
                .font(.caption.weight(.medium))
                .lineLimit(2)
                .foregroundStyle(overdue ? Color.red : Color.primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4).padding(.vertical, 3)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(.background, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(overdue ? Color.red.opacity(0.7) : Color.accentColor.opacity(0.7), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { showing = true }
        .draggable(commitment.id) {
            Text(commitment.title).font(.caption).padding(6).background(.background, in: RoundedRectangle(cornerRadius: 6))
        }
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            CommitmentDetail(id: commitment.id).frame(width: 440, height: 520).environment(model)
        }
        .contextMenu { CommitmentContextMenu(commitment: commitment) }
        .help("\(commitment.title), due \(commitment.dueAt?.formatted(.dateTime.hour().minute()) ?? "")")
    }
}

/// What's waiting: suggestions to review, and commitments without a date (drag one onto the
/// calendar to give it a time).
private struct InboxPanel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let review = CommitmentGrouping.suggestions(model.store.items)
        let undated = model.store.items.filter { $0.state == .open && $0.dueAt == nil }.sorted(by: CommitmentGrouping.order)
        VStack(alignment: .leading, spacing: 0) {
            Text("Inbox").font(.system(size: 22, weight: .bold)).padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 4)
            Text("Drag onto the calendar to give it a time.").font(.callout).foregroundStyle(.secondary).padding(.horizontal, 16).padding(.bottom, 8)
            QuickAddField(prompt: "Add a commitment").padding(.horizontal, 12).padding(.bottom, 6)
            List {
                if undated.isEmpty && review.isEmpty {
                    Text("Nothing waiting. Everything has a date.").foregroundStyle(.secondary).listRowSeparator(.hidden)
                }
                if !undated.isEmpty {
                    Section("No date") {
                        ForEach(undated) { c in
                            CommitmentRow(commitment: c, compact: true)
                                .draggable(c.id) { Text(c.title).font(.caption).padding(6) }
                        }
                    }
                }
                if !review.isEmpty {
                    Section("To review · \(review.count)") {
                        ForEach(review) { c in
                            SuggestionRow(commitment: c, compact: true)
                                .draggable(c.id) { Text(c.title).font(.caption).padding(6) }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
        }
        .background(.background.secondary)
    }
}

/// Why the calendar is empty, in Foundry's words, with the one thing to do about it.
private struct CalendarNotice: View {
    @Environment(AppModel.self) private var model
    let reason: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark").font(.title3).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Your meetings can't be shown").fontWeight(.semibold)
                Text(reason).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Open Foundry") { NSWorkspace.shared.open(model.environment.webAppURL) }
        }
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}
