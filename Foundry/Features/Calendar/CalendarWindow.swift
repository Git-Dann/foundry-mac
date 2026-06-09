import SwiftUI

/// The Calendar — its own window. Three states: needs a client ID → setup; not connected →
/// connect (PKCE in the default browser); connected → agenda with two-way create/edit/delete.
struct CalendarWindow: View {
    @Environment(AppModel.self) private var model
    @State private var configToken = 0

    var body: some View {
        Group {
            if !GoogleOAuthConfig.isConfigured {
                CalendarSetupView { configToken += 1 }
            } else if !model.google.isSignedIn {
                CalendarConnectView(onReconfigure: { configToken += 1 })
            } else {
                CalendarAgendaView()
            }
        }
        .id(configToken)
        .frame(minWidth: 540, minHeight: 480)
        .navigationTitle("Calendar")
    }
}

private struct CalendarSetupView: View {
    var onSaved: () -> Void
    @State private var clientID = GoogleOAuthConfig.clientID

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect your calendar").font(.title2.weight(.semibold))
            Text("Paste the Google **Desktop app** OAuth client ID (from Cloud project 266306419039). PKCE is used — no client secret is stored.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            TextField("266306419039-….apps.googleusercontent.com", text: $clientID)
                .textFieldStyle(.roundedBorder)
            HStack {
                Spacer()
                Button("Save") { GoogleOAuthConfig.setClientID(clientID); onSaved() }
                    .buttonStyle(.borderedProminent)
                    .disabled(clientID.trimmed.isEmpty)
            }
        }
        .padding(28)
        .frame(maxWidth: 520)
    }
}

private struct CalendarConnectView: View {
    @Environment(AppModel.self) private var model
    var onReconfigure: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar").font(.system(size: 44)).foregroundStyle(Color.foundryBlue)
            Text("Connect Google Calendar").font(.title2.weight(.semibold))
            Text("Opens Google sign-in in your default browser. Only @gitwork.co.uk accounts.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button {
                Task { try? await model.google.signIn() }
            } label: {
                if model.google.isAuthenticating { ProgressView().controlSize(.small) } else { Text("Connect") }
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.google.isAuthenticating)
            if let error = model.google.lastError { Text(error).font(.caption).foregroundStyle(.red) }
            Button("Change client ID", action: onReconfigure).buttonStyle(.link).font(.caption)
        }
        .padding(32)
        .frame(maxWidth: 460)
    }
}

private struct CalendarAgendaView: View {
    @Environment(AppModel.self) private var model

    @State private var events: [GCalEvent] = []
    @State private var state: LoadState<Void> = .idle
    @State private var showingCreate = false
    @State private var editing: GCalEvent?

    private var service: GoogleCalendarService { GoogleCalendarService(auth: model.google) }

    var body: some View {
        content
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showingCreate = true } label: { Label("New Event", systemImage: "plus") }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button { Task { await load() } } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        if let email = model.google.email { Text(email) }
                        Button("Disconnect", role: .destructive) { model.google.signOut() }
                    } label: { Label("Account", systemImage: "person.crop.circle") }
                }
            }
            .task { await load() }
            .sheet(isPresented: $showingCreate) {
                EventSheet(service: service, event: nil) { Task { await load() } }
            }
            .sheet(item: $editing) { event in
                EventSheet(service: service, event: event) { Task { await load() } }
            }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading where events.isEmpty:
            LoadingView(label: "Loading calendar…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        default:
            if events.isEmpty {
                ContentUnavailableView("Nothing scheduled", systemImage: "calendar", description: Text("No events in the next 30 days."))
            } else {
                List {
                    ForEach(grouped, id: \.day) { group in
                        Section(group.day.formatted(date: .complete, time: .omitted)) {
                            ForEach(group.events) { event in
                                Button { editing = event } label: { EventRow(event: event) }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var grouped: [(day: Date, events: [GCalEvent])] {
        let cal = Calendar.current
        let dated = events.compactMap { event -> (Date, GCalEvent)? in
            event.startDate.map { (cal.startOfDay(for: $0), event) }
        }
        let dict = Dictionary(grouping: dated, by: { $0.0 })
        return dict.keys.sorted().map { day in
            (day, dict[day]!.map(\.1).sorted { ($0.startDate ?? .distantPast) < ($1.startDate ?? .distantPast) })
        }
    }

    private func load() async {
        if events.isEmpty { state = .loading }
        let now = Date()
        let end = Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        do { events = try await service.listEvents(from: now, to: end); state = .loaded(()) }
        catch { state = .failed(error.userMessage) }
    }
}

private struct EventRow: View {
    let event: GCalEvent
    var body: some View {
        HStack(spacing: 10) {
            Text(timeText).font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 56, alignment: .leading)
            VStack(alignment: .leading, spacing: 1) {
                Text(event.title).lineLimit(1)
                if let location = event.location, !location.isEmpty {
                    Text(location).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    private var timeText: String {
        if event.isAllDay { return "All day" }
        guard let date = event.startDate else { return "—" }
        return date.formatted(date: .omitted, time: .shortened)
    }
}

/// Create or edit an event (delete when editing).
private struct EventSheet: View {
    @Environment(\.dismiss) private var dismiss
    let service: GoogleCalendarService
    let event: GCalEvent?
    var onChanged: () -> Void

    @State private var title = ""
    @State private var allDay = false
    @State private var start = Date()
    @State private var end = Date().addingTimeInterval(3600)
    @State private var location = ""
    @State private var notes = ""
    @State private var saving = false
    @State private var error: String?

    private var isEditing: Bool { event != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isEditing ? "Edit event" : "New event").font(.title3.weight(.semibold))
            Form {
                TextField("Title", text: $title)
                Toggle("All day", isOn: $allDay)
                DatePicker("Start", selection: $start, displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                DatePicker("End", selection: $end, displayedComponents: allDay ? .date : [.date, .hourAndMinute])
                TextField("Location (optional)", text: $location)
                TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(1...4)
            }
            .formStyle(.columns)
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                if isEditing {
                    Button("Delete", role: .destructive) { Task { await deleteEvent() } }.disabled(saving)
                }
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button { Task { await save() } } label: {
                    if saving { ProgressView().controlSize(.small) } else { Text(isEditing ? "Save" : "Create") }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(title.trimmed.isEmpty || saving)
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear(perform: prefill)
    }

    private func prefill() {
        guard let event else { return }
        title = event.summary ?? ""
        location = event.location ?? ""
        notes = event.description ?? ""
        allDay = event.isAllDay
        if let s = event.startDate { start = s }
        if let e = event.end?.resolvedDate { end = e }
    }

    private func makeInput() -> GCalEventInput {
        let startTime: GCalEventTime
        let endTime: GCalEventTime
        if allDay {
            let cal = Calendar.current
            let endDay = cal.date(byAdding: .day, value: 1, to: end) ?? end // Google all-day end is exclusive
            startTime = GCalEventTime(dateTime: nil, date: Formatters.isoDay(start), timeZone: nil)
            endTime = GCalEventTime(dateTime: nil, date: Formatters.isoDay(endDay), timeZone: nil)
        } else {
            let tz = TimeZone.current.identifier
            startTime = GCalEventTime(dateTime: ISO8601DateParser.string(from: start), date: nil, timeZone: tz)
            endTime = GCalEventTime(dateTime: ISO8601DateParser.string(from: end), date: nil, timeZone: tz)
        }
        return GCalEventInput(
            summary: title.trimmed,
            description: notes.trimmed.nilIfEmpty,
            location: location.trimmed.nilIfEmpty,
            start: startTime,
            end: endTime
        )
    }

    private func save() async {
        saving = true; error = nil; defer { saving = false }
        do {
            if let event {
                _ = try await service.updateEvent(id: event.id, makeInput())
            } else {
                _ = try await service.createEvent(makeInput())
            }
            onChanged(); dismiss()
        } catch { self.error = error.userMessage }
    }

    private func deleteEvent() async {
        guard let event else { return }
        saving = true; error = nil; defer { saving = false }
        do { try await service.deleteEvent(id: event.id); onChanged(); dismiss() }
        catch { self.error = error.userMessage }
    }
}
