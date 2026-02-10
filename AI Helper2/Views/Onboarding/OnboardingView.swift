import SwiftUI
import EventKit
import AVFoundation

// MARK: - Onboarding View

struct OnboardingView: View {
    @Binding var isOnboardingComplete: Bool
    @StateObject private var viewModel = OnboardingViewModel()

    var body: some View {
        TabView(selection: $viewModel.currentStep) {
            WelcomeStep(onNext: viewModel.nextStep)
                .tag(OnboardingStep.welcome)

            ProviderStep(
                selectedProvider: $viewModel.selectedProvider,
                onNext: viewModel.nextStep
            )
            .tag(OnboardingStep.provider)

            APIKeyStep(
                provider: viewModel.selectedProvider,
                apiKey: $viewModel.apiKey,
                validationState: viewModel.validationState,
                onValidate: { Task { await viewModel.validateKey() } },
                onNext: viewModel.nextStep
            )
            .tag(OnboardingStep.apiKey)

            PermissionsStep(
                calendarStatus: viewModel.calendarPermission,
                reminderStatus: viewModel.reminderPermission,
                microphoneStatus: viewModel.microphonePermission,
                onRequestCalendar: { Task { await viewModel.requestCalendarPermission() } },
                onRequestReminder: { Task { await viewModel.requestReminderPermission() } },
                onRequestMicrophone: { viewModel.requestMicrophonePermission() },
                onNext: viewModel.nextStep
            )
            .tag(OnboardingStep.permissions)

            ReadyStep(onFinish: {
                viewModel.completeOnboarding()
                isOnboardingComplete = true
            })
            .tag(OnboardingStep.ready)
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .animation(.easeInOut, value: viewModel.currentStep)
        .ignoresSafeArea()
    }
}

// MARK: - Onboarding Step Enum

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case provider
    case apiKey
    case permissions
    case ready
}

// MARK: - Onboarding View Model

class OnboardingViewModel: ObservableObject {
    @Published var currentStep: OnboardingStep = .welcome
    @Published var selectedProvider: AIProvider = .openai
    @Published var apiKey: String = ""
    @Published var validationState: ValidationState = .idle
    @Published var calendarPermission: PermissionStatus = .notDetermined
    @Published var reminderPermission: PermissionStatus = .notDetermined
    @Published var microphonePermission: PermissionStatus = .notDetermined

    private let validator = APIKeyValidator()
    private let eventStore = EKEventStore()

    init() {
        checkCurrentPermissions()
    }

    func nextStep() {
        guard let nextIndex = OnboardingStep(rawValue: currentStep.rawValue + 1) else { return }
        currentStep = nextIndex
    }

    func validateKey() async {
        await MainActor.run { validationState = .validating }
        let result = await validator.validate(apiKey: apiKey, provider: selectedProvider)
        await MainActor.run {
            switch result {
            case .valid:
                validationState = .valid
            case .invalid(let msg):
                validationState = .invalid(msg)
            case .networkError(let msg):
                validationState = .networkError(msg)
            }
        }
    }

    func completeOnboarding() {
        // Save provider and API key
        var config = APIConfiguration(provider: selectedProvider, apiKey: apiKey)
        config.model = selectedProvider.defaultModel

        if let encoded = try? JSONEncoder().encode(config) {
            try? KeychainManager.shared.saveData(encoded, for: "APIConfiguration")
        }
        if !apiKey.isEmpty {
            try? KeychainManager.shared.saveAPIKey(apiKey, for: selectedProvider.rawValue)
        }

        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
    }

    // MARK: - Permissions

    private func checkCurrentPermissions() {
        // Calendar
        let calStatus = EKEventStore.authorizationStatus(for: .event)
        calendarPermission = mapEKStatus(calStatus)

        // Reminders
        let remStatus = EKEventStore.authorizationStatus(for: .reminder)
        reminderPermission = mapEKStatus(remStatus)

        // Microphone
        switch AVAudioApplication.shared.recordPermission {
        case .granted: microphonePermission = .granted
        case .denied: microphonePermission = .denied
        case .undetermined: microphonePermission = .notDetermined
        @unknown default: microphonePermission = .notDetermined
        }
    }

    func requestCalendarPermission() async {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            await MainActor.run {
                calendarPermission = granted ? .granted : .denied
            }
        } catch {
            await MainActor.run { calendarPermission = .denied }
        }
    }

    func requestReminderPermission() async {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            await MainActor.run {
                reminderPermission = granted ? .granted : .denied
            }
        } catch {
            await MainActor.run { reminderPermission = .denied }
        }
    }

    func requestMicrophonePermission() {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                self.microphonePermission = granted ? .granted : .denied
            }
        }
    }

    private func mapEKStatus(_ status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .fullAccess, .authorized: return .granted
        case .denied, .restricted: return .denied
        case .notDetermined, .writeOnly: return .notDetermined
        @unknown default: return .notDetermined
        }
    }
}

// MARK: - Supporting Types

enum ValidationState: Equatable {
    case idle
    case validating
    case valid
    case invalid(String)
    case networkError(String)
}

enum PermissionStatus {
    case notDetermined
    case granted
    case denied
}

// MARK: - Welcome Step

struct WelcomeStep: View {
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "brain.head.profile")
                .font(.system(size: 80))
                .foregroundStyle(.blue.gradient)

            VStack(spacing: 12) {
                Text("AI Helper")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Your intelligent assistant for calendar, reminders, and more.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            Button(action: onNext) {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Provider Step

struct ProviderStep: View {
    @Binding var selectedProvider: AIProvider
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "cpu")
                    .font(.system(size: 50))
                    .foregroundStyle(.purple.gradient)

                Text("Choose AI Provider")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Select which AI service you want to use.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 16) {
                ProviderCard(
                    provider: .openai,
                    isSelected: selectedProvider == .openai,
                    onTap: { selectedProvider = .openai }
                )
                ProviderCard(
                    provider: .claude,
                    isSelected: selectedProvider == .claude,
                    onTap: { selectedProvider = .claude }
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            Button(action: onNext) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

struct ProviderCard: View {
    let provider: AIProvider
    let isSelected: Bool
    let onTap: () -> Void

    private var icon: String {
        switch provider {
        case .openai: return "sparkles"
        case .claude: return "brain"
        }
    }

    private var subtitle: String {
        switch provider {
        case .openai: return "GPT-4o, GPT-4, GPT-3.5"
        case .claude: return "Claude 3.5 Sonnet, Haiku, Opus"
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .white : .blue)
                    .frame(width: 44, height: 44)
                    .background(isSelected ? Color.blue : Color.blue.opacity(0.1))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 4) {
                    Text(provider.rawValue)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .font(.title3)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color(.systemGray4), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - API Key Step

struct APIKeyStep: View {
    let provider: AIProvider
    @Binding var apiKey: String
    let validationState: ValidationState
    let onValidate: () -> Void
    let onNext: () -> Void

    private var canProceed: Bool {
        validationState == .valid
    }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "key.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.orange.gradient)

                Text("Enter API Key")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Your \(provider.rawValue) API key is stored securely in the iOS Keychain.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 16) {
                TextField("Paste your API key", text: $apiKey)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 24)

                // Validation status
                Group {
                    switch validationState {
                    case .idle:
                        EmptyView()
                    case .validating:
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.8)
                            Text("Validating...").font(.caption).foregroundColor(.secondary)
                        }
                    case .valid:
                        Label("API key is valid", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundColor(.green)
                    case .invalid(let msg):
                        Label("Invalid: \(msg)", systemImage: "xmark.circle.fill")
                            .font(.caption).foregroundColor(.red)
                    case .networkError(let msg):
                        Label("Network error: \(msg)", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption).foregroundColor(.orange)
                    }
                }

                if !apiKey.isEmpty && validationState != .validating {
                    Button("Validate Key", action: onValidate)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }

            Spacer()

            Button(action: onNext) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(canProceed ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .disabled(!canProceed)
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

// MARK: - Permissions Step

struct PermissionsStep: View {
    let calendarStatus: PermissionStatus
    let reminderStatus: PermissionStatus
    let microphoneStatus: PermissionStatus
    let onRequestCalendar: () -> Void
    let onRequestReminder: () -> Void
    let onRequestMicrophone: () -> Void
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 50))
                    .foregroundStyle(.green.gradient)

                Text("Grant Permissions")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("AI Helper works best with access to your calendar, reminders, and microphone.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            VStack(spacing: 12) {
                PermissionRow(
                    icon: "calendar",
                    title: "Calendar",
                    description: "Create and manage events",
                    status: calendarStatus,
                    onRequest: onRequestCalendar
                )
                PermissionRow(
                    icon: "checklist",
                    title: "Reminders",
                    description: "Manage tasks and to-dos",
                    status: reminderStatus,
                    onRequest: onRequestReminder
                )
                PermissionRow(
                    icon: "mic.fill",
                    title: "Microphone",
                    description: "Voice input with Whisper",
                    status: microphoneStatus,
                    onRequest: onRequestMicrophone
                )
            }
            .padding(.horizontal, 24)

            Spacer()

            VStack(spacing: 8) {
                Button(action: onNext) {
                    Text("Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(14)
                }

                Text("You can change permissions later in Settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}

struct PermissionRow: View {
    let icon: String
    let title: String
    let description: String
    let status: PermissionStatus
    let onRequest: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.blue)
                .frame(width: 36, height: 36)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).fontWeight(.medium)
                Text(description).font(.caption).foregroundColor(.secondary)
            }

            Spacer()

            switch status {
            case .granted:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .denied:
                Text("Denied")
                    .font(.caption)
                    .foregroundColor(.red)
            case .notDetermined:
                Button("Allow", action: onRequest)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

// MARK: - Ready Step

struct ReadyStep: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green.gradient)

            VStack(spacing: 12) {
                Text("You're All Set!")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Start chatting with your AI assistant. Try asking about your schedule or creating reminders.")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }

            Spacer()

            Button(action: onFinish) {
                Text("Start Chatting")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.green)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
    }
}
