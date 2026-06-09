import SwiftUI

/// Create a client (`POST /api/clients`).
struct ClientCreateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onCreated: () -> Void

    @State private var fields = ClientFormFields()
    @State private var submitting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ClientFieldsForm(fields: $fields, error: error)
                .navigationTitle("New Client")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") { submit() }
                            .disabled(fields.name.trimmed.isEmpty || submitting)
                    }
                }
        }
        .frame(width: 520, height: 520)
    }

    private func submit() {
        submitting = true
        error = nil
        Task {
            defer { submitting = false }
            do {
                try await model.api.createClient(fields.input(includingName: true))
                onCreated()
                dismiss()
            } catch {
                self.error = error.userMessage
            }
        }
    }
}

/// Edit a client (`PATCH /api/clients/[slug]`).
struct ClientEditSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let client: ClientDetail
    var onSaved: () -> Void

    @State private var fields: ClientFormFields
    @State private var submitting = false
    @State private var error: String?

    init(client: ClientDetail, onSaved: @escaping () -> Void) {
        self.client = client
        self.onSaved = onSaved
        _fields = State(initialValue: ClientFormFields(client: client))
    }

    var body: some View {
        NavigationStack {
            ClientFieldsForm(fields: $fields, error: error)
                .navigationTitle("Edit Client")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { submit() }
                            .disabled(fields.name.trimmed.isEmpty || submitting)
                    }
                }
        }
        .frame(width: 520, height: 520)
    }

    private func submit() {
        submitting = true
        error = nil
        Task {
            defer { submitting = false }
            do {
                try await model.api.updateClient(slug: client.slug, fields.input(includingName: true))
                onSaved()
                dismiss()
            } catch {
                self.error = error.userMessage
            }
        }
    }
}

/// Shared editable fields for create/edit.
struct ClientFormFields {
    var name = ""
    var website = ""
    var primaryContactName = ""
    var primaryContactEmail = ""
    var primaryContactPhone = ""
    var legalCompanyName = ""
    var addressLine1 = ""
    var city = ""
    var postcode = ""
    var country = ""
    var notes = ""

    init() {}

    init(client: ClientDetail) {
        name = client.name
        website = client.website ?? ""
        primaryContactName = client.primaryContactName ?? ""
        primaryContactEmail = client.primaryContactEmail ?? ""
        primaryContactPhone = client.primaryContactPhone ?? ""
        legalCompanyName = client.legalCompanyName ?? ""
        addressLine1 = client.addressLine1 ?? ""
        city = client.city ?? ""
        postcode = client.postcode ?? ""
        country = client.country ?? ""
        notes = client.notes ?? ""
    }

    func input(includingName: Bool) -> ClientInput {
        ClientInput(
            name: includingName ? name.nilIfEmpty : nil,
            website: website.nilIfEmpty,
            primaryContactName: primaryContactName.nilIfEmpty,
            primaryContactEmail: primaryContactEmail.nilIfEmpty,
            primaryContactPhone: primaryContactPhone.nilIfEmpty,
            notes: notes.nilIfEmpty,
            addressLine1: addressLine1.nilIfEmpty,
            city: city.nilIfEmpty,
            postcode: postcode.nilIfEmpty,
            country: country.nilIfEmpty,
            legalCompanyName: legalCompanyName.nilIfEmpty
        )
    }
}

private struct ClientFieldsForm: View {
    @Binding var fields: ClientFormFields
    var error: String?

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $fields.name)
                TextField("Website", text: $fields.website)
            }
            Section("Primary contact") {
                TextField("Name", text: $fields.primaryContactName)
                TextField("Email", text: $fields.primaryContactEmail)
                TextField("Phone", text: $fields.primaryContactPhone)
            }
            Section("Company") {
                TextField("Legal company name", text: $fields.legalCompanyName)
                TextField("Address", text: $fields.addressLine1)
                TextField("City", text: $fields.city)
                TextField("Postcode", text: $fields.postcode)
                TextField("Country", text: $fields.country)
            }
            Section("Notes") {
                TextField("Notes", text: $fields.notes, axis: .vertical).lineLimit(2...6)
            }
            if let error {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
        }
        .formStyle(.grouped)
    }
}
