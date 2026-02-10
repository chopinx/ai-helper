import SwiftUI

struct SettingsView: View {
    @Binding var configuration: APIConfiguration
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyText = ""
    @State private var isValidating = false
    @State private var validationResult: APIKeyValidationResult?
    @State private var validationTask: Task<Void, Never>?
    private let validator = APIKeyValidator()

    var body: some View {
        NavigationView {
            Form {
                providerSection
                apiConfigSection
                parametersSection
                personaSection
                calendarSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                apiKeyText = configuration.apiKey
            }
            .onDisappear {
                if !apiKeyText.isEmpty {
                    try? KeychainManager.shared.saveAPIKey(apiKeyText, for: configuration.provider.rawValue)
                }
            }
        }
    }

    // MARK: - Sections

    private var providerSection: some View {
        Section("AI Provider") {
            Picker("Provider", selection: $configuration.provider) {
                ForEach(AIProvider.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(SegmentedPickerStyle())
            .onChange(of: configuration.provider) { oldProvider, newProvider in
                if !apiKeyText.isEmpty {
                    try? KeychainManager.shared.saveAPIKey(apiKeyText, for: oldProvider.rawValue)
                }
                configuration.model = newProvider.defaultModel
                apiKeyText = KeychainManager.shared.getAPIKey(for: newProvider.rawValue) ?? ""
                configuration.apiKey = apiKeyText
                validationResult = nil
            }
        }
    }

    private var apiConfigSection: some View {
        Section("API Configuration") {
            TextField("API Key", text: $apiKeyText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: apiKeyText) {
                    configuration.apiKey = apiKeyText
                    validationResult = nil
                    scheduleAutoValidation()
                }

            validationStatusRow

            Picker("Model", selection: $configuration.model) {
                ForEach(configuration.provider.availableModels, id: \.self) { Text($0).tag($0) }
            }
        }
    }

    private var parametersSection: some View {
        Section("Generation Parameters") {
            Picker("Max Tokens", selection: Binding(
                get: { MaxTokensOption.allCases.first { $0.rawValue == configuration.maxTokens } ?? .medium },
                set: { configuration.maxTokens = $0.rawValue }
            )) {
                ForEach(MaxTokensOption.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }

            if AIProvider.isReasoningModel(configuration.model) {
                HStack {
                    Text("Temperature")
                    Spacer()
                    Text("N/A").foregroundColor(.secondary)
                }
                Text("Reasoning models don't support temperature")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Temperature")
                        Spacer()
                        Text(String(format: "%.1f", configuration.temperature)).foregroundColor(.secondary)
                    }
                    Slider(value: $configuration.temperature, in: 0...2, step: 0.1)
                }
            }
        }
    }

    private var personaSection: some View {
        Section("System Persona") {
            ForEach(SystemPersona.allCases, id: \.self) { persona in
                Button {
                    configuration.systemPersona = persona
                } label: {
                    HStack {
                        Image(systemName: persona.icon)
                            .frame(width: 24)
                        Text(persona.displayName)
                        Spacer()
                        if configuration.systemPersona == persona {
                            Image(systemName: "checkmark")
                                .foregroundColor(.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if configuration.systemPersona == .custom {
                TextEditor(text: $configuration.customSystemPrompt)
                    .frame(minHeight: 80)
                    .overlay(
                        Group {
                            if configuration.customSystemPrompt.isEmpty {
                                Text("Enter custom system prompt...")
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 8)
                                    .allowsHitTesting(false)
                            }
                        },
                        alignment: .topLeading
                    )
            }

            if configuration.systemPersona != .custom {
                Text(configuration.systemPersona.promptPrefix)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var calendarSection: some View {
        Section("Calendar Integration") {
            Toggle("Enable Calendar Integration", isOn: $configuration.enableMCP)
            if configuration.enableMCP {
                Text("When enabled, I can create calendar events from your messages")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: "2.0.0")
            LabeledContent("Mode") {
                Text("Reason-Act Enabled").foregroundColor(DS.Colors.success)
            }
        }
    }

    // MARK: - Validation

    @ViewBuilder
    private var validationStatusRow: some View {
        if isValidating {
            HStack(spacing: 8) {
                ProgressView().scaleEffect(0.8)
                Text("Validating...").font(.caption).foregroundColor(.secondary)
            }
        } else if let result = validationResult {
            validationStatusView(for: result)
        } else if !configuration.apiKey.isEmpty {
            Label("Not validated", systemImage: "questionmark.circle")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private func validationStatusView(for result: APIKeyValidationResult) -> some View {
        let (icon, color, text): (String, Color, String) = {
            switch result {
            case .valid: return ("checkmark.circle.fill", DS.Colors.success, "API key is valid")
            case .invalid(let msg): return ("xmark.circle.fill", DS.Colors.error, "Invalid: \(msg)")
            case .networkError(let msg): return ("exclamationmark.triangle.fill", DS.Colors.warning, "Network error: \(msg)")
            }
        }()

        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundColor(color)
            .lineLimit(2)
    }

    private func scheduleAutoValidation() {
        validationTask?.cancel()
        guard !configuration.apiKey.isEmpty else { return }

        validationTask = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await validateAPIKey()
        }
    }

    private func validateAPIKey() async {
        await MainActor.run { isValidating = true; validationResult = nil }
        let result = await validator.validate(apiKey: configuration.apiKey, provider: configuration.provider)
        await MainActor.run { validationResult = result; isValidating = false }
    }
}
