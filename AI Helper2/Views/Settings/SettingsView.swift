import SwiftUI

struct SettingsView: View {
    @Binding var configuration: APIConfiguration
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            Form {
                Section("Reasoning Mode") {
                    Toggle("Multi-Step Reasoning", isOn: .constant(true))
                        .disabled(true)
                    
                    HStack {
                        Text("Max Steps")
                        Spacer()
                        Text("6")
                            .foregroundColor(.secondary)
                    }
                    
                    Text("Multi-step reasoning with tool calling. The AI will continue using tools until it reaches a final answer.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                
                Section(header: Text("AI Provider")) {
                    Picker("Provider", selection: $configuration.provider) {
                        ForEach(AIProvider.allCases, id: \.self) { provider in
                            Text(provider.rawValue).tag(provider)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .onChange(of: configuration.provider) { newProvider in
                        // Reset to default model when provider changes
                        configuration.model = newProvider.defaultModel
                    }
                }
                
                Section(header: Text("API Configuration")) {
                    SecureField("API Key", text: $configuration.apiKey)
                        .textContentType(.password)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Model")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Model", selection: $configuration.model) {
                            ForEach(configuration.provider.availableModels, id: \.self) { model in
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
                                MaxTokensOption.allCases.first { $0.rawValue == configuration.maxTokens } ?? .medium
                            },
                            set: { option in
                                configuration.maxTokens = option.rawValue
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
                            Text(String(format: "%.1f", configuration.temperature))
                                .foregroundColor(.secondary)
                        }
                        Slider(value: $configuration.temperature, in: 0...2, step: 0.1)
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
                
                Section(header: Text("Calendar Integration")) {
                    Toggle("Enable Calendar Integration", isOn: $configuration.enableMCP)
                    
                    if configuration.enableMCP {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("When enabled, I can create calendar events from your messages")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack {
                                Label("Calendar", systemImage: "calendar")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                Text("Create events")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                
                Section(header: Text("Current Configuration")) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Provider:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(configuration.provider.rawValue)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Selected Model:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(configuration.model)
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Max Tokens:")
                                .fontWeight(.medium)
                            Spacer()
                            Text("\(configuration.maxTokens)")
                                .foregroundColor(.secondary)
                        }
                        
                        HStack {
                            Text("Temperature:")
                                .fontWeight(.medium)
                            Spacer()
                            Text(String(format: "%.1f", configuration.temperature))
                                .foregroundColor(.secondary)
                        }
                    }
                    .font(.caption)
                }
                
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("2.0.0")
                            .foregroundColor(.secondary)
                    }
                    
                    HStack {
                        Text("Mode")
                        Spacer()
                        Text("Reason-Act Enabled")
                            .foregroundColor(.green)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}