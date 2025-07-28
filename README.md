# AI Helper2 - iOS Chatbot App

An iOS chatbot application that supports both Claude and OpenAI APIs with text and voice input capabilities.

## Features

- **Multiple AI Providers**: Support for both Claude (Anthropic) and OpenAI APIs
- **Configurable Settings**: Easy-to-use settings interface for API configuration
- **Voice Input**: Speech-to-text functionality for hands-free interaction
- **Text Input**: Traditional text-based chat interface
- **Persistent Configuration**: API settings are saved between app launches
- **Real-time Chat**: Live chat interface with message history

## Setup Instructions

### 1. API Configuration
- Launch the app and tap "Settings" in the top-right corner
- Choose your preferred AI provider (OpenAI or Claude)
- Enter your API key:
  - **OpenAI**: Get your API key from [OpenAI Platform](https://platform.openai.com/api-keys)
  - **Claude**: Get your API key from [Anthropic Console](https://console.anthropic.com/)
- Configure model settings using dropdown menus:
  - **Model**: Select from available models for your chosen provider
  - **Max Tokens**: Choose from preset options (Short/Medium/Long/Very Long)
  - **Temperature**: Use slider to adjust creativity (0.0 = Conservative, 2.0 = Creative)

### 2. Add Required Permissions

**IMPORTANT**: You must add privacy permissions to your app before building:

1. Open the project in Xcode
2. Select the "AI Helper2" target in the project navigator
3. Go to the "Info" tab
4. Add the following entries under "Custom iOS Target Properties":

   - **Key**: `NSMicrophoneUsageDescription`
   - **Type**: String  
   - **Value**: `This app needs microphone access to convert your voice to text for chatting with the AI assistant.`

   - **Key**: `NSSpeechRecognitionUsageDescription`
   - **Type**: String
   - **Value**: `This app uses speech recognition to convert your voice input to text for AI conversations.`

These permissions are required for the voice input functionality to work properly.

### 3. Usage

#### Text Input
1. Type your message in the text field at the bottom
2. Tap the send button (paper plane icon) to send

#### Voice Input
1. Tap the microphone icon next to the text field
2. Allow microphone and speech recognition permissions if prompted
3. Tap the large microphone button to start recording
4. Speak your message
5. Tap "Stop" when finished
6. Review the transcribed text and tap "Done" to use it

## Project Structure

- `Models.swift` - Data models for API configuration and chat messages
- `ChatView.swift` - Main chat interface with message bubbles
- `SettingsView.swift` - Configuration interface for API settings
- `AIService.swift` - Service layer for API communication
- `VoiceInputManager.swift` - Speech-to-text functionality
- `ContentView.swift` - Root view controller
- `AI_Helper2App.swift` - App entry point

## API Support

### OpenAI
- Endpoint: `https://api.openai.com/v1/chat/completions`
- Available models: GPT-4o, GPT-4o-mini, GPT-4-turbo, GPT-4, GPT-3.5-turbo, GPT-3.5-turbo-16k
- Default model: `gpt-3.5-turbo`
- Authentication: Bearer token

### Claude (Anthropic)
- Endpoint: `https://api.anthropic.com/v1/messages`
- Available models: Claude-3.5-Sonnet, Claude-3.5-Haiku, Claude-3-Opus, Claude-3-Sonnet, Claude-3-Haiku
- Default model: `claude-3-haiku-20240307`
- Authentication: API key header
- API version: `2023-06-01`

## Error Handling

The app includes comprehensive error handling for:
- Invalid API responses
- Network connectivity issues
- Missing API keys
- Speech recognition failures

## Privacy

- API keys are stored securely in UserDefaults
- Voice input is processed using Apple's on-device speech recognition when possible
- No chat history is stored permanently - messages are cleared when the app is closed

## Requirements

- iOS 14.0+
- Xcode 12.0+
- Valid API key from OpenAI or Anthropic

## Building the Project

1. Open `AI Helper2.xcodeproj` in Xcode
2. Ensure you have the required Info.plist permissions set up
3. Build and run on device or simulator

Note: Voice input functionality requires a physical device for full testing as the simulator has limited microphone support.