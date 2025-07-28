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
                        Label("Calendar", systemImage: "calendar")
                            .font(.caption2)
                            .foregroundColor(.blue)
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
                    
                    // Show calendar icon for successful calendar events
                    if !message.isUser && message.content.contains("✅") && message.content.contains("calendar event") {
                        HStack {
                            Image(systemName: "calendar.badge.plus")
                                .font(.caption2)
                                .foregroundColor(.green)
                            Text("Calendar event created")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 4)
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
                        quickActionButton("📅 Create event", "Create a meeting tomorrow at 2 PM")
                        quickActionButton("⏰ Set reminder", "Remind me about the presentation on Friday")
                        quickActionButton("📝 Schedule call", "Schedule a call with John next week")
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