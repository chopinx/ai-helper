import SwiftUI

struct ChatView: View {
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var voiceInputManager = VoiceInputManager()
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Reason-Act Timeline
                if chatViewModel.isReasonActMode && !chatViewModel.reasonActSteps.isEmpty {
                    Divider()
                    
                    HStack {
                        Text("Reasoning Steps")
                            .font(.headline)
                            .padding(.leading)
                        Spacer()
                    }
                    ReasonActTimelineView(steps: chatViewModel.reasonActSteps)
                        .frame(maxHeight: 200)
                        .background(Color(.systemGray6))
                }
                
                // Main Chat Content
                chatContentView
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        if !chatViewModel.messages.isEmpty {
                            Button(action: {
                                chatViewModel.clearConversation()
                            }) {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                        
                        Button("Settings") {
                            showingSettings = true
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack {
                        Button(chatViewModel.isReasonActMode ? "💭" : "🔧") {
                            chatViewModel.toggleReasonActMode()
                        }
                        
                        if chatViewModel.messages.isEmpty {
                            Button(action: {
                                chatViewModel.toggleSuggestedPrompts()
                            }) {
                                Image(systemName: chatViewModel.shouldShowSuggestedPrompts ? "lightbulb.fill" : "lightbulb")
                                    .foregroundColor(.orange)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView(configuration: $chatViewModel.apiConfiguration)
            }
        }
        .onAppear {
            // Setup voice input if needed
            voiceInputManager.requestPermissions()
            voiceInputManager.apiKey = chatViewModel.apiConfiguration.apiKey
        }
        .onChange(of: chatViewModel.apiConfiguration.apiKey) {
            voiceInputManager.apiKey = chatViewModel.apiConfiguration.apiKey
        }
    }
    
    private var chatContentView: some View {
        VStack {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        // Show suggested prompts when conversation is empty
                        if chatViewModel.shouldShowSuggestedPrompts {
                            SuggestedPromptsView(viewModel: chatViewModel)
                                .padding(.horizontal)
                                .padding(.top)
                        }
                        
                        ForEach(chatViewModel.messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        if chatViewModel.isLoading {
                            HStack {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("AI is thinking...")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding()
                }
                .onChange(of: chatViewModel.messages.count) {
                    withAnimation {
                        if let lastMessage = chatViewModel.messages.last {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
                .onChange(of: chatViewModel.reasonActSteps.count) {
                    // Auto-scroll when final summary arrives
                    if !chatViewModel.isLoading {
                        withAnimation {
                            if let lastMessage = chatViewModel.messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
            
            ChatInputView(
                currentMessage: $chatViewModel.currentMessage,
                isLoading: chatViewModel.isLoading,
                voiceInputManager: voiceInputManager,
                sendAction: {
                    Task {
                        await chatViewModel.sendMessage()
                    }
                }
            )
        }
    }
}

// MARK: - Reason-Act Timeline View

struct ReasonActTimelineView: View {
    let steps: [ReasonActStep]
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(steps) { step in
                    ReasonActStepView(step: step)
                }
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
}

struct ReasonActStepView: View {
    let step: ReasonActStep
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Step \(step.stepNumber)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            if !step.assistantMessage.isEmpty {
                Text(step.assistantMessage.prefix(50) + (step.assistantMessage.count > 50 ? "..." : ""))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            ForEach(step.toolExecutions) { execution in
                HStack(spacing: 4) {
                    Text(execution.statusIcon)
                        .font(.caption2)
                    
                    Text(execution.toolName)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(execution.isError ? .red : .green)
                    
                    Text(execution.durationString)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            if step.toolExecutions.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(.caption2)
                        .foregroundColor(.blue)
                    
                    Text("Thinking...")
                        .font(.caption2)
                        .foregroundColor(.blue)
                        .italic()
                }
            }
        }
        .padding(8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(radius: 1)
        .frame(width: 120)
    }
}

// MARK: - Chat Input View

struct ChatInputView: View {
    @Binding var currentMessage: String
    let isLoading: Bool
    let voiceInputManager: VoiceInputManager
    let sendAction: () -> Void
    
    var body: some View {
        HStack {
            TextField("Type your message...", text: $currentMessage, axis: .vertical)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .lineLimit(1...4)
                .onSubmit {
                    if !isLoading && !currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        sendAction()
                    }
                }
            
            // Voice input button (if permissions granted)
            if voiceInputManager.hasPermissions {
                Button(action: {
                    if voiceInputManager.isRecording {
                        voiceInputManager.stopRecording()
                    } else {
                        voiceInputManager.startRecording { transcript in
                            currentMessage = transcript
                        }
                    }
                }) {
                    Image(systemName: voiceInputManager.isRecording ? "mic.fill" : "mic")
                        .foregroundColor(voiceInputManager.isRecording ? .red : .blue)
                        .font(.title2)
                }
                .padding(.trailing, 4)
            }
            
            Button(action: sendAction) {
                Image(systemName: "paperplane.fill")
                    .foregroundColor(isLoading || currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
            }
            .disabled(isLoading || currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding()
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer()
            }
            
            Text(cleanedContent)
                .padding(12)
                .background(message.isUser ? Color.blue : Color(.systemGray5))
                .foregroundColor(message.isUser ? .white : .primary)
                .cornerRadius(16)
                .frame(maxWidth: .infinity * 0.8, alignment: message.isUser ? .trailing : .leading)
            
            if !message.isUser {
                Spacer()
            }
        }
    }
    
    private var cleanedContent: String {
        // Remove any final response markers from display
        return message.content.replacingOccurrences(of: "<|FINAL_RESPONSE|>", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Suggested Prompts View

struct SuggestedPromptsView: View {
    @ObservedObject var viewModel: ChatViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "sparkles")
                        .foregroundColor(.blue)
                        .font(.title2)
                    
                    Text("推荐提示词")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    Button(action: {
                        viewModel.toggleSuggestedPrompts()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.title3)
                    }
                }
                
                Text("选择一个提示词快速开始对话，或者直接在下方输入您的问题")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Categories
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(PromptCategory.allCases, id: \.self) { category in
                        CategoryView(
                            category: category,
                            prompts: viewModel.promptsByCategory(category),
                            onPromptTap: { prompt in
                                viewModel.selectSuggestedPrompt(prompt)
                            }
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct CategoryView: View {
    let category: PromptCategory
    let prompts: [SuggestedPrompt]
    let onPromptTap: (SuggestedPrompt) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Category Header
            HStack(spacing: 6) {
                Circle()
                    .fill(categoryColor)
                    .frame(width: 8, height: 8)
                
                Text(category.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
            }
            
            // Prompts in Category
            VStack(spacing: 6) {
                ForEach(prompts) { prompt in
                    PromptCardView(prompt: prompt, onTap: onPromptTap)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(radius: 1)
        .frame(width: 200)
    }
    
    private var categoryColor: Color {
        switch category.color {
        case "blue": return .blue
        case "green": return .green
        case "purple": return .purple
        case "orange": return .orange
        case "red": return .red
        default: return .gray
        }
    }
}

struct PromptCardView: View {
    let prompt: SuggestedPrompt
    let onTap: (SuggestedPrompt) -> Void
    
    var body: some View {
        Button(action: {
            onTap(prompt)
        }) {
            HStack(spacing: 8) {
                Image(systemName: prompt.icon)
                    .foregroundColor(.blue)
                    .font(.caption)
                    .frame(width: 16)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(prompt.title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .multilineTextAlignment(.leading)
                    
                    Text(prompt.prompt.prefix(40) + (prompt.prompt.count > 40 ? "..." : ""))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                
                Spacer()
            }
            .padding(8)
            .background(Color(.systemGray6))
            .cornerRadius(6)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    ChatView()
}

#Preview("Settings") {
    SettingsView(configuration: .constant(APIConfiguration()))
}

#Preview("Timeline") {
    ReasonActTimelineView(steps: [
        ReasonActStep(stepNumber: 1, assistantMessage: "I need to create a calendar event", toolExecutions: [
            ReasonActStep.ToolExecution(toolName: "create_event", arguments: ["title": "Meeting"], result: "Event created successfully", isError: false, duration: 1.2)
        ]),
        ReasonActStep(stepNumber: 2, assistantMessage: "Let me check the calendar", toolExecutions: [
            ReasonActStep.ToolExecution(toolName: "list_events", arguments: [:], result: "No events found", isError: true, duration: 0.8)
        ])
    ])
    .frame(height: 200)
}