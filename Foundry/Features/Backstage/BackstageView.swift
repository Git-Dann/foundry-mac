import SwiftUI

/// Backstage — internal ops: Leave + Expenses. Approvers (admins / `backstage.approve`) get a
/// Mine/Team scope toggle and approve/reject actions.
struct BackstageView: View {
    @Environment(AppModel.self) private var model

    enum Tab: String, CaseIterable, Identifiable {
        case leave = "Leave", expenses = "Expenses"
        var id: String { rawValue }
    }
    @State private var tab: Tab = .leave

    private var canApprove: Bool { model.auth.currentUser?.can("backstage.approve") ?? false }

    var body: some View {
        Group {
            switch tab {
            case .leave: LeaveView(canApprove: canApprove)
            case .expenses: ExpensesView(canApprove: canApprove)
            }
        }
        .navigationTitle("Backstage")
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $tab) { ForEach(Tab.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).fixedSize()
            }
        }
    }
}

// MARK: - Leave

private struct LeaveView: View {
    @Environment(AppModel.self) private var model
    let canApprove: Bool

    @State private var allowance: LeaveAllowance?
    @State private var leave: [LeaveRequest] = []
    @State private var state: LoadState<Void> = .idle
    @State private var scope = "me"
    @State private var showingBook = false

    var body: some View {
        content
            .toolbar {
                if canApprove {
                    ToolbarItem(placement: .secondaryAction) {
                        Picker("Scope", selection: $scope) { Text("Mine").tag("me"); Text("Team").tag("team") }
                            .pickerStyle(.segmented).fixedSize()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingBook = true } label: { Label("Book leave", systemImage: "plus") }
                }
            }
            .task(id: scope) { await load() }
            .onChange(of: model.refreshToken) { Task { await load() } }
            .sheet(isPresented: $showingBook) { BookLeaveSheet { Task { await load() } } }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading where leave.isEmpty: LoadingView(label: "Loading leave…")
        case .failed(let m): ErrorStateView(message: m) { Task { await load() } }
        default:
            List {
                if let allowance {
                    Section("Allowance · \(allowance.year)") {
                        LabeledContent("Allocated", value: dayCount(allowance.allocated))
                        LabeledContent("Used", value: dayCount(allowance.used))
                        if allowance.pending > 0 { LabeledContent("Pending", value: dayCount(allowance.pending)) }
                        LabeledContent("Remaining", value: dayCount(allowance.remaining)).fontWeight(.semibold)
                    }
                }
                Section("Requests") {
                    if leave.isEmpty {
                        Text("No leave requests.").foregroundStyle(.secondary)
                    } else {
                        ForEach(leave) { request in
                            LeaveRow(request: request, canApprove: canApprove, currentUserId: model.auth.currentUser?.id) { action in
                                await act(request, action)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
        }
    }

    private func dayCount(_ value: Double) -> String {
        let n = value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(n) day\(value == 1 ? "" : "s")"
    }

    enum LeaveAction { case approve, reject, cancel }

    private func load() async {
        if leave.isEmpty { state = .loading }
        do {
            async let allowanceTask = try? model.api.leaveAllowance()
            async let leaveTask = model.api.listLeave(scope: scope)
            allowance = await allowanceTask
            leave = try await leaveTask
            state = .loaded(())
            model.lastRefresh = Date()
        } catch { state = .failed(error.userMessage) }
    }

    private func act(_ request: LeaveRequest, _ action: LeaveAction) async {
        switch action {
        case .approve: _ = try? await model.api.approveLeave(id: request.id, note: nil)
        case .reject: _ = try? await model.api.rejectLeave(id: request.id, note: nil)
        case .cancel: try? await model.api.cancelLeave(id: request.id)
        }
        await load()
    }
}

private struct LeaveRow: View {
    let request: LeaveRequest
    let canApprove: Bool
    let currentUserId: String?
    let act: (LeaveView.LeaveAction) async -> Void

    private var isOwn: Bool { request.user.id == currentUserId }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(request.type.label) · \(request.dateRange)").fontWeight(.medium).lineLimit(1)
                HStack(spacing: 6) {
                    Text("\(dayCount) day\(request.workingDays == 1 ? "" : "s")")
                    if !isOwn { Text("· \(request.user.name)") }
                    if let reason = request.reason, !reason.isEmpty { Text("· \(reason)").lineLimit(1) }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            StatusChip(text: request.status.label, tint: request.status.tint)
            if request.status == .pending {
                Menu {
                    if canApprove && !isOwn {
                        Button("Approve") { Task { await act(.approve) } }
                        Button("Reject", role: .destructive) { Task { await act(.reject) } }
                    }
                    if isOwn { Button("Cancel request", role: .destructive) { Task { await act(.cancel) } } }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            }
        }
        .padding(.vertical, 2)
    }

    private var dayCount: String {
        request.workingDays == request.workingDays.rounded() ? String(format: "%.0f", request.workingDays) : String(format: "%.1f", request.workingDays)
    }
}

private struct BookLeaveSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onBooked: () -> Void

    @State private var type: LeaveType = .annual
    @State private var start = Date()
    @State private var end = Date()
    @State private var halfDayStart = false
    @State private var halfDayEnd = false
    @State private var reason = ""
    @State private var submitting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Book leave").font(.title3.weight(.semibold))
            Form {
                Picker("Type", selection: $type) {
                    ForEach(LeaveType.allCases.filter { $0 != .unknown }) { Text($0.label).tag($0) }
                }
                DatePicker("Start", selection: $start, displayedComponents: .date)
                DatePicker("End", selection: $end, displayedComponents: .date)
                Toggle("Half day at start", isOn: $halfDayStart)
                Toggle("Half day at end", isOn: $halfDayEnd)
                TextField("Reason (optional)", text: $reason, axis: .vertical).lineLimit(1...3)
            }
            .formStyle(.columns)
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button { Task { await submit() } } label: {
                    if submitting { ProgressView().controlSize(.small) } else { Text("Request") }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(submitting || end < start)
            }
        }
        .padding(20).frame(width: 460)
    }

    private func submit() async {
        submitting = true; error = nil; defer { submitting = false }
        let input = LeaveRequestInput(
            type: type,
            startDate: Formatters.isoDay(start),
            endDate: Formatters.isoDay(end),
            halfDayStart: halfDayStart ? true : nil,
            halfDayEnd: halfDayEnd ? true : nil,
            reason: reason.trimmed.nilIfEmpty
        )
        do { _ = try await model.api.requestLeave(input); onBooked(); dismiss() }
        catch { self.error = error.userMessage }
    }
}

// MARK: - Expenses

private struct ExpensesView: View {
    @Environment(AppModel.self) private var model
    let canApprove: Bool

    @State private var expenses: [Expense] = []
    @State private var state: LoadState<Void> = .idle
    @State private var scope = "me"
    @State private var showingNew = false

    var body: some View {
        content
            .toolbar {
                if canApprove {
                    ToolbarItem(placement: .secondaryAction) {
                        Picker("Scope", selection: $scope) { Text("Mine").tag("me"); Text("Team").tag("team") }
                            .pickerStyle(.segmented).fixedSize()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { showingNew = true } label: { Label("New expense", systemImage: "plus") }
                }
            }
            .task(id: scope) { await load() }
            .onChange(of: model.refreshToken) { Task { await load() } }
            .sheet(isPresented: $showingNew) { NewExpenseSheet { Task { await load() } } }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading where expenses.isEmpty: LoadingView(label: "Loading expenses…")
        case .failed(let m): ErrorStateView(message: m) { Task { await load() } }
        default:
            if expenses.isEmpty {
                ContentUnavailableView {
                    Label("No expenses", systemImage: "creditcard")
                } description: {
                    Text("Submit an expense for review.")
                } actions: {
                    Button("New expense") { showingNew = true }.buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(expenses) { expense in
                        ExpenseRow(expense: expense, canApprove: canApprove, currentUserId: model.auth.currentUser?.id) { status in
                            await review(expense, status)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func load() async {
        if expenses.isEmpty { state = .loading }
        do { expenses = try await model.api.listExpenses(scope: scope); state = .loaded(()); model.lastRefresh = Date() }
        catch { state = .failed(error.userMessage) }
    }

    private func review(_ expense: Expense, _ status: ExpenseStatus) async {
        _ = try? await model.api.reviewExpense(id: expense.id, status: status, note: nil)
        await load()
    }
}

private struct ExpenseRow: View {
    let expense: Expense
    let canApprove: Bool
    let currentUserId: String?
    let review: (ExpenseStatus) async -> Void

    private var isOwn: Bool { expense.user.id == currentUserId }

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(expense.amountText).fontWeight(.medium)
                    Text("· \(expense.category.label)").foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    if let vendor = expense.vendor, !vendor.isEmpty { Text(vendor) }
                    Text("· \(Formatters.day(expense.occurredOn))")
                    if !isOwn { Text("· \(expense.user.name)") }
                    if expense.hasReceipt { Image(systemName: "paperclip") }
                }
                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            StatusChip(text: expense.status.label, tint: expense.status.tint)
            if canApprove && !isOwn && expense.status == .submitted {
                Menu {
                    Button("Approve") { Task { await review(.approved) } }
                    Button("Mark reimbursed") { Task { await review(.reimbursed) } }
                    Button("Reject", role: .destructive) { Task { await review(.rejected) } }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize()
            }
        }
        .padding(.vertical, 2)
    }
}

private struct NewExpenseSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onSubmitted: () -> Void

    @State private var amount = 0.0
    @State private var currency = "GBP"
    @State private var category: ExpenseCategory = .software
    @State private var vendor = ""
    @State private var date = Date()
    @State private var notes = ""
    @State private var submitting = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New expense").font(.title3.weight(.semibold))
            Form {
                TextField("Amount", value: $amount, format: .number)
                TextField("Currency", text: $currency)
                Picker("Category", selection: $category) {
                    ForEach(ExpenseCategory.allCases.filter { $0 != .unknown }) { Text($0.label).tag($0) }
                }
                TextField("Vendor (optional)", text: $vendor)
                DatePicker("Date", selection: $date, displayedComponents: .date)
                TextField("Notes (optional)", text: $notes, axis: .vertical).lineLimit(1...3)
            }
            .formStyle(.columns)
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button { Task { await submit() } } label: {
                    if submitting { ProgressView().controlSize(.small) } else { Text("Submit") }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(amount <= 0 || submitting)
            }
        }
        .padding(20).frame(width: 460)
    }

    private func submit() async {
        submitting = true; error = nil; defer { submitting = false }
        let input = ExpenseInput(
            amount: amount,
            currency: currency.trimmed.isEmpty ? "GBP" : currency.trimmed.uppercased(),
            category: category,
            vendor: vendor.trimmed.nilIfEmpty,
            occurredOn: Formatters.isoDay(date),
            notes: notes.trimmed.nilIfEmpty
        )
        do { _ = try await model.api.submitExpense(input); onSubmitted(); dismiss() }
        catch { self.error = error.userMessage }
    }
}
