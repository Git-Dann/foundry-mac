import SwiftUI

/// Start a new Pulse scan (URL · GitHub repo · free-text description). On success calls back with
/// the new scan id so the list can refresh and surface the running scan.
struct CreateScanSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var onCreated: (String) -> Void

    @State private var projectName = ""
    @State private var inputType: PulseInputType = .url
    @State private var inputUrl = ""
    @State private var inputRepo = ""
    @State private var freeText = ""
    @State private var submitting = false
    @State private var error: String?

    private var canSubmit: Bool {
        guard !projectName.trimmed.isEmpty else { return false }
        switch inputType {
        case .url: return !inputUrl.trimmed.isEmpty
        case .githubRepo: return !inputRepo.trimmed.isEmpty
        case .freeText: return !freeText.trimmed.isEmpty
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Pulse scan").font(.title3.weight(.semibold))
            Form {
                TextField("Project name", text: $projectName)
                Picker("Scan type", selection: $inputType) {
                    ForEach(PulseInputType.allCases) { Text($0.label).tag($0) }
                }
                switch inputType {
                case .url:
                    TextField("https://example.com", text: $inputUrl)
                case .githubRepo:
                    TextField("owner/repo or GitHub URL", text: $inputRepo)
                case .freeText:
                    TextField("Describe the project to validate…", text: $freeText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .formStyle(.columns)
            if let error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button { Task { await submit() } } label: {
                    if submitting { ProgressView().controlSize(.small) } else { Text("Start scan") }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || submitting)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func submit() async {
        submitting = true
        error = nil
        defer { submitting = false }
        let input = PulseScanInput(
            projectName: projectName.trimmed,
            inputType: inputType,
            inputUrl: inputType == .url ? inputUrl.trimmed.nilIfEmpty : nil,
            inputGithubRepo: inputType == .githubRepo ? inputRepo.trimmed.nilIfEmpty : nil,
            inputDescription: inputType == .freeText ? freeText.trimmed.nilIfEmpty : nil,
            clientId: nil
        )
        do {
            let scan = try await model.api.createPulseScan(input)
            onCreated(scan.id)
        } catch {
            self.error = error.userMessage
        }
    }
}
