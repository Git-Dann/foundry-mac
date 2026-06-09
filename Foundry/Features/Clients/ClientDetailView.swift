import SwiftUI

/// Native client detail: profile fields, platforms, designs, and linked documents.
/// Editable natively; status changeable; deletable (with confirmation).
struct ClientDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let slug: String

    @State private var state: LoadState<ClientDetailResponse> = .idle
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    @State private var statusUpdating = false

    var body: some View {
        content
            .navigationTitle(state.value?.client.name ?? "Client")
            .toolbar { toolbar }
            .task { await load() }
            .onChange(of: model.refreshToken) { Task { await load() } }
            .sheet(isPresented: $showingEdit) {
                if let client = state.value?.client {
                    ClientEditSheet(client: client) { Task { await load() } }
                }
            }
            .alert("Delete client?", isPresented: $showingDeleteConfirm) {
                Button("Delete", role: .destructive) { Task { await deleteClient() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the client from Foundry and can't be undone.")
            }
            .navigationDestination(for: ClientTasksRoute.self) { route in
                ClientTasksView(clientId: route.clientId, clientName: route.clientName, clientSlug: route.clientSlug)
            }
            .navigationDestination(for: ClientMeetingsRoute.self) { route in
                ClientMeetingsView(clientSlug: route.clientSlug, clientName: route.clientName, clientId: route.clientId)
            }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .idle, .loading:
            LoadingView(label: "Loading client…")
        case .failed(let message):
            ErrorStateView(message: message) { Task { await load() } }
        case .loaded(let detail):
            Form {
                overview(detail.client)
                Section {
                    NavigationLink(value: ClientTasksRoute(clientId: detail.client.id, clientName: detail.client.name, clientSlug: slug)) {
                        Label("Tasks", systemImage: "checklist")
                    }
                    NavigationLink(value: ClientMeetingsRoute(clientSlug: slug, clientName: detail.client.name, clientId: detail.client.id)) {
                        Label("Meeting notes", systemImage: "text.bubble")
                    }
                }
                if !detail.platforms.isEmpty { platforms(detail.platforms) }
                if !detail.designs.isEmpty { designs(detail.designs) }
                if !detail.proposals.isEmpty { proposals(detail.proposals) }
            }
            .formStyle(.grouped)
        }
    }

    private func overview(_ c: ClientDetail) -> some View {
        Section("Overview") {
            LabeledContent("Status") { StatusChip(text: c.status.label, tint: c.status.tint) }
            if let website = c.website, let url = URL(string: website.hasPrefix("http") ? website : "https://\(website)") {
                LabeledContent("Website") { Link(website, destination: url) }
            }
            if let name = c.primaryContactName, !name.isEmpty { LabeledContent("Contact", value: name) }
            if let email = c.primaryContactEmail, !email.isEmpty { LabeledContent("Email", value: email) }
            if let phone = c.primaryContactPhone, !phone.isEmpty { LabeledContent("Phone", value: phone) }
            if let company = c.legalCompanyName, !company.isEmpty { LabeledContent("Legal name", value: company) }
            if let address = addressLine(c) { LabeledContent("Address", value: address) }
            if let notes = c.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Notes").font(.caption).foregroundStyle(.secondary)
                    Text(notes).font(.callout)
                }
            }
        }
    }

    private func platforms(_ items: [ClientPlatform]) -> some View {
        Section("Platforms") {
            ForEach(items) { platform in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(platform.name).fontWeight(.medium)
                        if let type = platform.platformType, !type.isEmpty {
                            Text(type).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let url = platform.url, let link = URL(string: url) { Link(url, destination: link).font(.caption) }
                    if let repo = platform.repoUrl, let link = URL(string: repo) { Link(repo, destination: link).font(.caption) }
                }
            }
        }
    }

    private func designs(_ items: [ClientDesign]) -> some View {
        Section("Designs") {
            ForEach(items) { design in
                if let url = design.url, let link = URL(string: url) {
                    Link(design.name, destination: link)
                } else {
                    Text(design.name)
                }
            }
        }
    }

    private func proposals(_ items: [ProposalListItem]) -> some View {
        Section("Documents (\(items.count))") {
            ForEach(items) { item in
                NavigationLink(value: ProposalRoute(id: item.id)) {
                    HStack {
                        Text(item.title)
                        Spacer()
                        StatusChip(text: item.status.label, tint: item.status.tint)
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .secondaryAction) {
            Menu {
                ForEach(WorkspaceClientStatus.selectable) { status in
                    Button(status.label) { Task { await setStatus(status) } }
                }
            } label: {
                Label("Status", systemImage: "flag")
            }
            .disabled(state.value == nil || statusUpdating)
        }
        ToolbarItem(placement: .secondaryAction) {
            Button(role: .destructive) { showingDeleteConfirm = true } label: { Label("Delete", systemImage: "trash") }
                .disabled(state.value == nil)
        }
        ToolbarItem(placement: .secondaryAction) {
            Button {
                model.openWeb(path: "app/clients/\(slug)")
            } label: {
                Label("Open in Foundry Web", systemImage: "safari")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button { showingEdit = true } label: { Label("Edit", systemImage: "pencil") }
                .disabled(state.value == nil)
        }
    }

    private func addressLine(_ c: ClientDetail) -> String? {
        let parts = [c.addressLine1, c.city, c.postcode, c.country].compactMap { $0?.nilIfEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func load() async {
        if state.value == nil { state = .loading }
        do {
            state = .loaded(try await model.api.getClient(slug: slug))
        } catch {
            state = .failed(error.userMessage)
        }
    }

    private func setStatus(_ status: WorkspaceClientStatus) async {
        statusUpdating = true
        defer { statusUpdating = false }
        do {
            try await model.api.setClientStatus(slug: slug, status: status)
            await load()
        } catch {
            state = .failed(error.userMessage)
        }
    }

    private func deleteClient() async {
        do {
            try await model.api.deleteClient(slug: slug)
            model.requestRefresh()
            dismiss()
        } catch {
            state = .failed(error.userMessage)
        }
    }
}
