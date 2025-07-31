import SwiftUI

struct ChatView: View {
    @StateObject private var chatViewModel = ChatViewModel()
    @StateObject private var voiceInputManager = VoiceInputManager()
    @State private var showingSettings = false
    
    var body: some View {
        NavigationView {
            VStack {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
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
                    .onChange(of: chatViewModel.messages.count) { _ in
                        if let lastMessage = chatViewModel.messages.last {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            }
                        }
                    }
                }
                
                Divider()
                
                // MCP Evaluation Details
                if chatViewModel.apiConfiguration.enableMCP && chatViewModel.showMCPDetails {
                    MCPEvaluationDetailsView(mcpManager: chatViewModel.mcpManager)
                        .padding(.horizontal)
                    Divider()
                }
                
                ChatInputView(
                    chatViewModel: chatViewModel,
                    voiceInputManager: voiceInputManager
                )
            }
            .navigationTitle("AI Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if chatViewModel.apiConfiguration.enableMCP {
                        HStack {
                            Label("MCP", systemImage: "gearshape.2")
                                .font(.caption2)
                                .foregroundColor(.blue)
                            
                            Button(action: {
                                chatViewModel.showMCPDetails.toggle()
                            }) {
                                Image(systemName: chatViewModel.showMCPDetails ? "eye.slash" : "eye")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Settings") {
                        showingSettings = true
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView(chatViewModel: chatViewModel)
        }
        .onAppear {
            if chatViewModel.messages.isEmpty {
                let greeting = chatViewModel.apiConfiguration.enableMCP ? 
                    "Hello! I'm your AI assistant with calendar integration. I can help answer questions and create calendar events for you. Try saying 'Create a meeting tomorrow at 2 PM' or just ask me anything!" :
                    "Hello! I'm your AI assistant. How can I help you today?"
                
                chatViewModel.messages.append(
                    ChatMessage(content: greeting, isUser: false)
                )
            }
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    
    var body: some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 50)
            }
            
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message.content)
                        .padding(12)
                        .background(message.isUser ? Color.blue : Color.gray.opacity(0.2))
                        .foregroundColor(message.isUser ? .white : .primary)
                        .cornerRadius(16)
                    
                    // Show calendar icons for various calendar operations
                    if !message.isUser {
                        if message.content.contains("✅") && message.content.contains("calendar event") {
                            HStack {
                                Image(systemName: "calendar.badge.plus")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Text("Calendar event created")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 4)
                        } else if message.content.contains("✅") && (message.content.contains("updated successfully") || message.content.contains("deleted successfully")) {
                            HStack {
                                Image(systemName: message.content.contains("updated") ? "calendar.badge.checkmark" : "calendar.badge.minus")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Text(message.content.contains("updated") ? "Event updated" : "Event deleted")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 4)
                        } else if message.content.contains("Today's events") || message.content.contains("Found") && message.content.contains("events") {
                            HStack {
                                Image(systemName: "calendar")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                                Text("Calendar view")
                                    .font(.caption2)
                                    .foregroundColor(.blue)
                            }
                            .padding(.horizontal, 4)
                        }
                    }
                }
                
                Text(DateFormatter.time.string(from: message.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            if !message.isUser {
                Spacer(minLength: 50)
            }
        }
    }
}

struct ChatInputView: View {
    @ObservedObject var chatViewModel: ChatViewModel
    @ObservedObject var voiceInputManager: VoiceInputManager
    @State private var showingVoiceInput = false
    
    var body: some View {
        VStack(spacing: 12) {
            // Quick actions for MCP
            if chatViewModel.apiConfiguration.enableMCP && chatViewModel.currentMessage.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Create actions
                        quickActionButton("📅 Create event", "Create a meeting tomorrow at 2 PM")
                        quickActionButton("📝 Schedule call", "Schedule a call with John next week")
                        
                        // View actions
                        quickActionButton("📋 Today's events", "What's on my calendar today?")
                        quickActionButton("🔮 Upcoming events", "Show me my upcoming events")
                        
                        // Search actions
                        quickActionButton("🔍 Find event", "Find my dentist appointment")
                        quickActionButton("🗑️ Cancel event", "Cancel my team meeting")
                    }
                    .padding(.horizontal)
                }
            }
            
            if showingVoiceInput {
                VoiceInputView(voiceInputManager: voiceInputManager) {
                    showingVoiceInput = false
                    if !voiceInputManager.recognizedText.isEmpty {
                        chatViewModel.currentMessage = voiceInputManager.recognizedText
                        voiceInputManager.clearText()
                    }
                }
            }
            
            HStack(spacing: 12) {
                TextField("Type your message...", text: $chatViewModel.currentMessage, axis: .vertical)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .lineLimit(1...4)
                
                Button(action: {
                    if voiceInputManager.isAuthorized {
                        showingVoiceInput.toggle()
                    }
                }) {
                    Image(systemName: showingVoiceInput ? "mic.fill" : "mic")
                        .foregroundColor(voiceInputManager.isAuthorized ? .blue : .gray)
                }
                .disabled(!voiceInputManager.isAuthorized)
                
                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(canSendMessage ? .blue : .gray)
                }
                .disabled(!canSendMessage)
            }
        }
        .padding()
    }
    
    private var canSendMessage: Bool {
        !chatViewModel.currentMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !chatViewModel.isLoading &&
        !chatViewModel.apiConfiguration.apiKey.isEmpty
    }
    
    private func sendMessage() {
        Task {
            await chatViewModel.sendMessage()
        }
    }
    
    private func quickActionButton(_ title: String, _ message: String) -> some View {
        Button(action: {
            chatViewModel.currentMessage = message
        }) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .foregroundColor(.blue)
                .cornerRadius(16)
        }
    }
}

struct VoiceInputView: View {
    @ObservedObject var voiceInputManager: VoiceInputManager
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Voice Input")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    if voiceInputManager.isRecording {
                        voiceInputManager.stopRecording()
                    }
                    onDismiss()
                }
            }
            
            if !voiceInputManager.recognizedText.isEmpty {
                ScrollView {
                    Text(voiceInputManager.recognizedText)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                .frame(maxHeight: 100)
            }
            
            HStack(spacing: 20) {
                Button(action: {
                    if voiceInputManager.isRecording {
                        voiceInputManager.stopRecording()
                    } else {
                        voiceInputManager.startRecording()
                    }
                }) {
                    Image(systemName: voiceInputManager.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 50))
                        .foregroundColor(voiceInputManager.isRecording ? .red : .blue)
                }
                
                if !voiceInputManager.recognizedText.isEmpty {
                    Button("Clear") {
                        voiceInputManager.clearText()
                    }
                    .foregroundColor(.orange)
                }
            }
            
            Text(voiceInputManager.isRecording ? "Listening..." : "Tap to start recording")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(radius: 5)
        .padding()
    }
}

struct MCPEvaluationDetailsView: View {
    @ObservedObject var mcpManager: MCPManager
    @State private var isExpanded = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "gearshape.2.fill")
                    .foregroundColor(.blue)
                Text("MCP Evaluation")
                    .font(.headline)
                    .foregroundColor(.blue)
                
                Spacer()
                
                if !mcpManager.evaluationSteps.isEmpty {
                    Button(action: {
                        isExpanded.toggle()
                    }) {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .foregroundColor(.blue)
                    }
                }
            }
            
            // Summary stats
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Servers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(mcpManager.availableServers.count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Steps")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(mcpManager.evaluationSteps.count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Last Update")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(mcpManager.evaluationSteps.last?.timestamp ?? Date(), style: .time)
                        .font(.caption)
                        .fontWeight(.semibold)
                }
                
                Spacer()
            }
            
            // Detailed steps (expandable)
            if isExpanded && !mcpManager.evaluationSteps.isEmpty {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(mcpManager.evaluationSteps.indices, id: \.self) { index in
                            let step = mcpManager.evaluationSteps[index]
                            HStack(alignment: .top, spacing: 8) {
                                // Server indicator
                                Circle()
                                    .fill(serverColor(for: step.serverName))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 4)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(step.serverName)
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(serverColor(for: step.serverName))
                                        
                                        Text("•")
                                            .foregroundColor(.secondary)
                                        
                                        Text(step.step)
                                            .font(.caption)
                                            .foregroundColor(.primary)
                                        
                                        Spacer()
                                        
                                        Text(step.timestamp, style: .time)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    if !step.details.isEmpty {
                                        Text(step.details)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                            .lineLimit(3)
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 200)
                .background(Color.gray.opacity(0.05))
                .cornerRadius(8)
            }
        }
        .padding(12)
        .background(Color.blue.opacity(0.05))
        .cornerRadius(12)
    }
    
    private func serverColor(for serverName: String) -> Color {
        switch serverName {
        case "calendar":
            return .green
        case "System":
            return .blue
        default:
            return .orange
        }
    }
}

extension DateFormatter {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview {
    ChatView()
}