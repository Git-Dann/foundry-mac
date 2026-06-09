import SwiftUI

/// Rate card: people + their source rates. Full native CRUD (create / edit / remove) with an
/// include-archived toggle.
struct RateCardView: View {
    @Environment(AppModel.self) private var model

    @State private var state: LoadState<[RateCardPerson]> = .idle
    @State private var search = ""
    @State private var includeArchived = false
    @State private var showingCreate = false
    @State private var editing: RateCardPerson?
    @State private var pendingRemoval: RateCardPerson?
    @FocusState private var searchFocused: Bool

    var body: some View {
        content
            .navigationTitle("Rate Card")
            .searchable(text: $search, prompt: "Search people")
            .searchFocused($searchFocused)
            .onSubmit(of: .search) { Task { await load() } }
            .toolbar {
                ToolbarItem(placement: .secondaryAction) {
                    Toggle(isOn: $includeArchived) { Label("Show archived", systemImage: "archivebox") }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button { showingCreate = true } label: { Label("Add Person", systemImage: "plus") }
                }
            }
            .task(id: includeArchived) { await load() }
            .onChange(of: model.refreshToken) { Task { await load() } }
            .onChange(of: model.searchToken) { searchFocused = true }
            .sheet(isPresented: $showingCreate) {
                RatePersonForm(mode: .create) { Task { await load() } }
            }
            .sheet(item: $editing) { person in
                RatePersonForm(mode: .edit(person)) { Task { await load() } }
            }
            .alert(item: $pendingRemoval) { person in
                Alert(
                    title: Text("Remove \(person.name)?"),
                    primaryButton: .destructive(Text("Remove")) { Task { await remove(person) } },
                    secondaryButton: .cancel()
                )
            }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading:
            LoadingView(label: "Loading rate card…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        case .loaded(let people):
            if people.isEmpty {
                ContentUnavailableView {
                    Label("No people", systemImage: "person.2.badge.gearshape")
                } description: {
                    Text("Add people and their day rates to power proposal costing.")
                } actions: {
                    Button("Add Person") { showingCreate = true }.buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(people) { person in
                        RatePersonRow(person: person)
                            .contentShape(Rectangle())
                            .onTapGesture { editing = person }
                            .contextMenu {
                                Button("Edit") { editing = person }
                                Button("Remove", role: .destructive) { pendingRemoval = person }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            let people = try await model.api.listRateCard(search: search.nilIfEmpty, includeArchived: includeArchived)
            state = .loaded(people)
            model.lastRefresh = Date()
        } catch {
            state = .failed(error.userMessage)
        }
    }

    private func remove(_ person: RateCardPerson) async {
        do {
            try await model.api.deleteRatePerson(id: person.id)
            await load()
        } catch {
            state = .failed(error.userMessage)
        }
    }
}

private struct RatePersonRow: View {
    let person: RateCardPerson

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(person.name).font(.body.weight(.medium))
                    if person.isArchived { StatusChip(text: "Archived", tint: .secondary) }
                }
                Text(person.area).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(Formatters.currency(person.sourceRate, code: person.sourceCurrencyCode)) \(person.billingPeriod.label)")
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}

/// Create / edit a rate card person.
struct RatePersonForm: View {
    enum Mode {
        case create
        case edit(RateCardPerson)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let mode: Mode
    var onSaved: () -> Void

    @State private var name: String
    @State private var area: String
    @State private var rate: Double
    @State private var currency: String
    @State private var period: RateBillingPeriod
    @State private var submitting = false
    @State private var error: String?

    init(mode: Mode, onSaved: @escaping () -> Void) {
        self.mode = mode
        self.onSaved = onSaved
        switch mode {
        case .create:
            _name = State(initialValue: "")
            _area = State(initialValue: "")
            _rate = State(initialValue: 0)
            _currency = State(initialValue: "GBP")
            _period = State(initialValue: .month)
        case .edit(let person):
            _name = State(initialValue: person.name)
            _area = State(initialValue: person.area)
            _rate = State(initialValue: person.sourceRate)
            _currency = State(initialValue: person.sourceCurrencyCode)
            _period = State(initialValue: person.billingPeriod == .unknown ? .month : person.billingPeriod)
        }
    }

    private var isEditing: Bool { if case .edit = mode { return true }; return false }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Area / role", text: $area)
                TextField("Rate", value: $rate, format: .number)
                TextField("Currency code", text: $currency)
                Picker("Billing period", selection: $period) {
                    ForEach(RateBillingPeriod.selectable) { Text($0.label).tag($0) }
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit Person" : "Add Person")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { submit() }
                        .disabled(!isValid || submitting)
                }
            }
        }
        .frame(width: 460, height: 380)
    }

    private var isValid: Bool {
        !name.trimmed.isEmpty && !area.trimmed.isEmpty && rate > 0 && currency.trimmed.count >= 3
    }

    private func submit() {
        submitting = true
        error = nil
        Task {
            defer { submitting = false }
            do {
                switch mode {
                case .create:
                    try await model.api.createRatePerson(
                        RateCardPersonCreateInput(
                            name: name.trimmed, area: area.trimmed, sourceRate: rate,
                            sourceCurrencyCode: currency.trimmed.uppercased(), billingPeriod: period
                        )
                    )
                case .edit(let person):
                    try await model.api.updateRatePerson(
                        id: person.id,
                        RateCardPersonUpdateInput(
                            name: name.trimmed, area: area.trimmed, sourceRate: rate,
                            sourceCurrencyCode: currency.trimmed.uppercased(), billingPeriod: period
                        )
                    )
                }
                onSaved()
                dismiss()
            } catch {
                self.error = error.userMessage
            }
        }
    }
}
