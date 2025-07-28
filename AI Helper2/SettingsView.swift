import SwiftUI

struct SettingsView: View {
    @ObservedObject var chatViewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("AI Provider")) {
                    Picker("Provider", selection: $chatViewModel.apiConfiguration.provider) {
                        ForEach(AIProvider.allCases, id: \.self) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: chatViewModel.apiConfiguration.provider) { newProvider in
                        // Reset to default model when provider changes
                        chatViewModel.apiConfiguration.model = newProvider.defaultModel
                    }
                }
                
                Section(header: Text("API Configuration")) {
                    SecureField("API Key", text: $chatViewModel.apiConfiguration.apiKey)
                        .textContentType(.password)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Model", selection: $chatViewModel.apiConfiguration.model) {
                            ForEach(chatViewModel.apiConfiguration.provider.availableModels, id: \.self) { model in
                                Text(model).tag(model)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                }
                
                Section(header: Text("Generation Parameters")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Max Tokens")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Max Tokens", selection: Binding(
                            get: {
                                MaxTokensOption.allCases.first { $0.rawValue == chatViewModel.apiConfiguration.maxTokens } ?? .medium
                            },
                            set: { option in
                                chatViewModel.apiConfiguration.maxTokens = option.rawValue
                            }
                        )) {
                            ForEach(MaxTokensOption.allCases, id: \.self) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Temperature")
                            Spacer()
                            Text(String(format: "%.1f", chatViewModel.apiConfiguration.temperature))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $chatViewModel.apiConfiguration.temperature, in: 0...2, step: 0.1)
                        HStack {
                            Text("Conservative")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("Creative")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Section(header: Text("Current Configuration")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Provider:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(chatViewModel.apiConfiguration.provider.rawValue)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Selected Model:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(chatViewModel.apiConfiguration.model)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Max Tokens:")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(chatViewModel.apiConfiguration.maxTokens)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Temperature:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.1f", chatViewModel.apiConfiguration.temperature))
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.caption)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        chatViewModel.saveConfiguration()
                        dismiss()
                    }
                    .disabled(chatViewModel.apiConfiguration.apiKey.isEmpty)
                }
            }
        }
    }
}

extension View {
    func placeholder<Content: View>(
        when shouldShow: Bool,
        alignment: Alignment = .leading,
        @ViewBuilder placeholder: () -> Content) -> some View {

        ZStack(alignment: alignment) {
            placeholder().opacity(shouldShow ? 1 : 0)
            self
        }
    }
}

#Preview {
    SettingsView(chatViewModel: ChatViewModel())
}