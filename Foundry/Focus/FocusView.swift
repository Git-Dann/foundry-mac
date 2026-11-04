import SwiftUI

/// The focus timer: a ring counting down, what it is for, and the controls.
struct FocusView: View {
    @Environment(AppModel.self) private var model
    /// The to-do to start a session for. The running session's own to-do wins while it runs.
    var todoId: String?

    private var session: FocusSession { .shared }
    @State private var preset: FocusPreset = .matching(minutes: FocusSession.shared.lengthMinutes)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(now: context.date)
                .onChange(of: context.date) { _, _ in session.finishIfDue() }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var todoTitle: String? {
        if session.isActive { return session.todoTitle }
        return todoId.flatMap { model.store.commitment(id: $0)?.title }
    }

    @ViewBuilder
    private func content(now: Date) -> some View {
        VStack(spacing: 28) {
            VStack(spacing: 24) {
                ring(now: now)
                VStack(spacing: 6) {
                    Text(statusLine)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if let todoTitle {
                        Text(todoTitle)
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 440)
            .background(.fill.quinary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            lengthPicker
            controls
            Label(completedLine, systemImage: "checkmark.seal")
                .font(.callout)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
        }
    }

    private func ring(now: Date) -> some View {
        ZStack {
            Gauge(value: session.progress(at: now)) { EmptyView() }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(session.state == .onBreak ? .green : .accentColor)
                .scaleEffect(3.4)
                .frame(width: 200, height: 200)
            Text(FocusSession.format(session.remaining(at: now)))
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(FocusSession.format(session.remaining(at: now))) remaining")
    }

    private var lengthPicker: some View {
        VStack(spacing: 10) {
            Picker("Length", selection: $preset) {
                ForEach(FocusPreset.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 320)
            .onChange(of: preset) { _, new in
                if let m = new.minutes { session.lengthMinutes = m }
            }
            if preset == .custom {
                Stepper(
                    "\(session.lengthMinutes) minutes",
                    value: Binding(get: { session.lengthMinutes }, set: { session.lengthMinutes = $0 }),
                    in: 1...180, step: 5
                )
                .fixedSize()
            }
        }
        .disabled(session.isActive)
    }

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 12) {
            switch session.state {
            case .idle:
                Button("Start", systemImage: "play.fill") {
                    session.start(todoId: todoId, todoTitle: todoTitle)
                }
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
            case .running:
                Button("Pause", systemImage: "pause.fill") { session.pause() }
                    .buttonStyle(.glassProminent)
                Button("Stop", systemImage: "stop.fill", role: .destructive) { session.stop() }
                    .buttonStyle(.glass)
            case .paused:
                Button("Resume", systemImage: "play.fill") { session.resume() }
                    .buttonStyle(.glassProminent)
                Button("Stop", systemImage: "stop.fill", role: .destructive) { session.stop() }
                    .buttonStyle(.glass)
            case .onBreak:
                Button("Skip break", systemImage: "forward.fill") { session.stop() }
                    .buttonStyle(.glass)
            }
        }
        .controlSize(.large)
        .animation(.smooth, value: session.state)
    }

    private var statusLine: String {
        switch session.state {
        case .idle: "Ready to focus"
        case .running: "Focusing"
        case .paused: "Paused"
        case .onBreak: "On a break"
        }
    }

    private var completedLine: String {
        let n = session.completedToday
        return n == 1 ? "1 session today" : "\(n) sessions today"
    }
}

/// A compact line for the menu bar panel. Shows nothing while no session is running.
struct FocusMenuBarItem: View {
    private var session: FocusSession { .shared }

    var body: some View {
        if session.isActive {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 10) {
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(session.state == .onBreak ? "Break" : session.state == .paused ? "Paused" : "Focusing")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let title = session.todoTitle {
                                Text(title).lineLimit(1)
                            }
                        }
                    } icon: {
                        Image(systemName: session.state == .onBreak ? "cup.and.saucer.fill" : "timer")
                            .symbolEffect(.pulse, isActive: session.state == .running)
                    }
                    Spacer(minLength: 8)
                    Text(FocusSession.format(session.remaining(at: context.date)))
                        .monospacedDigit()
                        .font(.body.weight(.semibold))
                    Button("Stop", systemImage: "stop.fill") { session.stop() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.glass)
                        .help("Stop the session")
                }
                .onChange(of: context.date) { _, _ in session.finishIfDue() }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
