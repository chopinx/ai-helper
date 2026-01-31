import Foundation
import AVFoundation
import os.log

class VoiceInputManager: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var isTranscribing = false
    @Published var hasPermissions = false
    @Published var transcriptionText = ""

    var apiKey: String = ""

    private let logger = Logger(subsystem: "com.aihelper.voice", category: "VoiceInputManager")
    private let whisperService = WhisperTranscriptionService()
    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var transcriptionCompletion: ((String) -> Void)?

    override init() {
        super.init()
        requestPermissions()
    }

    func requestPermissions() {
        if #available(iOS 17.0, *) {
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    self?.hasPermissions = granted
                    if granted {
                        self?.logger.info("Microphone permission granted")
                    } else {
                        self?.logger.warning("Microphone permission denied")
                    }
                }
            }
        } else {
            AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
                DispatchQueue.main.async {
                    self?.hasPermissions = granted
                    if granted {
                        self?.logger.info("Microphone permission granted")
                    } else {
                        self?.logger.warning("Microphone permission denied")
                    }
                }
            }
        }
    }

    func startRecording(completion: @escaping (String) -> Void) {
        guard hasPermissions, !isRecording else { return }

        transcriptionCompletion = completion

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("Audio session setup failed: \(error.localizedDescription)")
            return
        }

        // Create recording URL
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let audioFilename = documentsPath.appendingPathComponent("recording_\(UUID().uuidString).m4a")
        recordingURL = audioFilename

        // Configure recorder settings for m4a format
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()
            isRecording = true
            logger.info("Recording started")
        } catch {
            logger.error("Failed to start recording: \(error.localizedDescription)")
            cleanupRecording()
        }
    }

    func stopRecording(completion: ((String) -> Void)? = nil) {
        guard isRecording else { return }

        // Use passed completion if provided, otherwise use stored one
        if let completion = completion {
            transcriptionCompletion = completion
        }

        audioRecorder?.stop()
        isRecording = false
        logger.info("Recording stopped")

        guard let recordingURL = recordingURL else {
            logger.error("No recording URL available")
            cleanupRecording()
            return
        }

        // Check if API key is available
        guard !apiKey.isEmpty else {
            logger.error("API key not configured for Whisper transcription")
            cleanupRecording()
            return
        }

        // Start transcription
        isTranscribing = true

        Task { @MainActor in
            do {
                let text = try await whisperService.transcribe(audioURL: recordingURL, apiKey: apiKey)
                transcriptionText = text
                transcriptionCompletion?(text)
                logger.info("Transcription successful: \(text.prefix(50))...")
            } catch {
                logger.error("Transcription failed: \(error.localizedDescription)")
            }

            isTranscribing = false
            cleanupRecording()
        }
    }

    func cancelRecording() {
        guard isRecording else { return }

        audioRecorder?.stop()
        isRecording = false
        transcriptionCompletion = nil
        cleanupRecording()
        logger.info("Recording cancelled")
    }

    func clearText() {
        transcriptionText = ""
    }

    private func cleanupRecording() {
        // Remove temporary recording file
        if let url = recordingURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordingURL = nil
        audioRecorder = nil
        transcriptionCompletion = nil

        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            logger.warning("Audio session deactivation failed: \(error.localizedDescription)")
        }
    }
}
