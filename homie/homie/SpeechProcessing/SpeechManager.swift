import AVFoundation
import Foundation

/// SpeechManager handles audio recording and transcription.
/// Supports both batch mode (existing) and streaming mode (new).
/// Transcription routing is delegated to FeatureGateway which handles auth/tier checks.
class SpeechManager: NSObject {
    private let audioEngine = AVAudioEngine()
    private var audioData = Data()
    private var isRecording = false

    /// Whether streaming mode is active (real-time transcription)
    private var isStreamingMode = false

    var onTranscriptionUpdate: ((String) -> Void)?
    var onTranscriptionFinal: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    override init() {
        super.init()
    }

    // MARK: - Streaming Mode

    /// Start listening in streaming mode with real-time transcription
    /// Uses TranscriptionStore for state management
    /// - Parameter isPremium: Whether user has premium access (determines cloud vs local)
    func startStreamingListening(isPremium: Bool) throws {
        // Stop any existing session
        stopListening()

        Logger.info("Starting streaming Whisper recording (premium: \(isPremium))...", module: "Speech")

        isStreamingMode = true

        // Check/request microphone permission using PermissionManager
        let status = PermissionManager.shared.checkMicrophoneStatus()
        if status.isGranted {
            // Start TranscriptionStore first
            Task { @MainActor in
                do {
                    try await TranscriptionStore.shared.startRecording(isPremium: isPremium)
                    try self.startStreamingAudioRecording()
                } catch {
                    Logger.error("Failed to start streaming: \(error)", module: "Speech")
                    self.isStreamingMode = false
                    self.onError?(error)
                }
            }
        } else {
            Task { [weak self] in
                let granted = await PermissionManager.shared.requestMicrophonePermission()
                await MainActor.run {
                    if granted {
                        Task { @MainActor in
                            do {
                                try await TranscriptionStore.shared.startRecording(isPremium: isPremium)
                                try self?.startStreamingAudioRecording()
                            } catch {
                                Logger.error("Failed to start streaming: \(error)", module: "Speech")
                                self?.isStreamingMode = false
                                self?.onError?(error)
                            }
                        }
                    } else {
                        let error = NSError(domain: "Speech", code: 4, userInfo: [NSLocalizedDescriptionKey: "Microphone access denied"])
                        Logger.info("Microphone access denied", module: "Speech")
                        self?.isStreamingMode = false
                        self?.onError?(error)
                    }
                }
            }
        }
    }

    /// Start audio recording in streaming mode (sends chunks to TranscriptionStore)
    private func startStreamingAudioRecording() throws {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        Logger.info("Installing streaming tap with format: \(recordingFormat)", module: "Speech")

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self, self.isStreamingMode else { return }

            // Convert buffer to Data
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)

            if let channelData = channelData {
                let data = Data(bytes: channelData, count: frameLength * MemoryLayout<Float>.size)

                // Send chunk to TranscriptionStore for streaming processing
                Task { @MainActor in
                    await TranscriptionStore.shared.processAudioChunk(data)
                }
            }
        }

        Logger.info("Preparing audio engine for streaming...", module: "Speech")
        audioEngine.prepare()

        Logger.info("Starting audio engine for streaming...", module: "Speech")
        try audioEngine.start()

        isRecording = true
        Logger.info("Streaming Whisper recording started successfully", module: "Speech")

        // Show recording status
        DispatchQueue.main.async {
            self.onTranscriptionUpdate?("🎤 Recording (streaming)...")
        }
    }

    /// Stop streaming recording
    func stopStreamingListening() {
        guard isRecording && isStreamingMode else { return }

        Logger.info("Stopping streaming Whisper recording...", module: "Speech")

        audioEngine.stop()

        // Remove tap from input node
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }

        isRecording = false
        isStreamingMode = false

        // Stop TranscriptionStore
        Task { @MainActor in
            await TranscriptionStore.shared.stopRecording()

            // Get final transcription and notify via callback
            let finalText = TranscriptionStore.shared.finalTranscription
            if !finalText.isEmpty {
                self.onTranscriptionFinal?(finalText)
            }
        }
    }

    /// Whether currently in streaming mode
    func isInStreamingMode() -> Bool {
        return isStreamingMode
    }

    // MARK: - Batch Mode (Original)

    func startListening() throws {
        // Stop any existing session
        stopListening()

        Logger.info("Starting Whisper recording...", module: "Speech")

        // Check/request microphone permission using PermissionManager
        let status = PermissionManager.shared.checkMicrophoneStatus()
        if status.isGranted {
            try startAudioRecording()
        } else {
            Task { [weak self] in
                let granted = await PermissionManager.shared.requestMicrophonePermission()
                await MainActor.run {
                    if granted {
                        do {
                            try self?.startAudioRecording()
                        } catch {
                            Logger.error("Failed to start audio recording: \(error)", module: "Speech")
                            self?.onError?(error)
                        }
                    } else {
                        let error = NSError(domain: "Speech", code: 4, userInfo: [NSLocalizedDescriptionKey: "Microphone access denied"])
                        Logger.info("Microphone access denied", module: "Speech")
                        self?.onError?(error)
                    }
                }
            }
        }
    }
    
    private func startAudioRecording() throws {
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        Logger.info("Installing tap with format: \(recordingFormat)", module: "Speech")
        
        // Clear previous audio data
        audioData = Data()
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            
            // Convert buffer to Data and append
            let channelData = buffer.floatChannelData?[0]
            let frameLength = Int(buffer.frameLength)
            
            if let channelData = channelData {
                let data = Data(bytes: channelData, count: frameLength * MemoryLayout<Float>.size)
                self.audioData.append(data)
            }
        }
        
        Logger.info("Preparing audio engine...", module: "Speech")
        audioEngine.prepare()
        
        Logger.info("Starting audio engine...", module: "Speech")
        try audioEngine.start()
        
        isRecording = true
        Logger.info("Whisper recording started successfully", module: "Speech")
        
        // Show recording status
        DispatchQueue.main.async {
            self.onTranscriptionUpdate?("🎤 Recording...")
        }
    }
    
    func stopListening() {
        guard isRecording else { return }
        
        Logger.info("Stopping Whisper recording...", module: "Speech")
        
        audioEngine.stop()
        
        // Remove tap from input node
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        
        isRecording = false
        
        // Process the recorded audio with Whisper
        if !audioData.isEmpty {
            processAudioWithWhisper()
        }
    }
    
    private func processAudioWithWhisper() {
        Logger.info("🎤 Processing audio...", module: "Speech")
        Logger.info("📊 Raw audio data size: \(audioData.count) bytes", module: "Speech")

        // Convert raw audio data to WAV format
        guard let wavData = createWAVData(from: audioData) else {
            Logger.error("❌ Failed to create WAV data from \(audioData.count) bytes", module: "Speech")
            let error = NSError(domain: "Whisper", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create WAV data"])
            DispatchQueue.main.async {
                self.onError?(error)
            }
            return
        }

        Logger.info("✅ Created WAV data: \(wavData.count) bytes", module: "Speech")

        // Delegate all transcription routing to FeatureGateway
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            self.onTranscriptionUpdate?("🔄 Transcribing...")

            // FeatureGateway handles all routing (premium -> WhisperAPI, free -> LocalWhisper)
            let result = await FeatureGateway.shared.transcribe(audioData: wavData)

            switch result {
            case .success(let transcription):
                Logger.info("✅ Transcription successful: \(transcription)", module: "Speech")
                self.onTranscriptionFinal?(transcription)

            case .accessDenied(let reason):
                Logger.error("❌ Transcription access denied: \(reason)", module: "Speech")
                let error = NSError(domain: "Whisper", code: 1, userInfo: [NSLocalizedDescriptionKey: "Transcription access denied"])
                self.onError?(error)

            case .error(let error):
                Logger.error("❌ Transcription error: \(error.localizedDescription)", module: "Speech")
                self.onError?(error)
            }
        }
    }
    
    private func createWAVData(from rawAudioData: Data) -> Data? {
        // WAV file format constants
        let sampleRate: UInt32 = 48000 // Match the audio engine format
        let numChannels: UInt16 = 1
        let bitsPerSample: UInt16 = 32 // Float32
        let bytesPerSample: UInt16 = bitsPerSample / 8
        let bytesPerFrame: UInt16 = numChannels * bytesPerSample
        let bytesPerSecond: UInt32 = sampleRate * UInt32(bytesPerFrame)
        
        let audioDataSize = UInt32(rawAudioData.count)
        let fileSize = 36 + audioDataSize
        
        var wavData = Data()
        
        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: fileSize.littleEndian) { Data($0) })
        wavData.append("WAVE".data(using: .ascii)!)
        
        // fmt chunk
        wavData.append("fmt ".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: UInt32(16).littleEndian) { Data($0) }) // chunk size
        wavData.append(withUnsafeBytes(of: UInt16(3).littleEndian) { Data($0) })   // format (3 = IEEE float)
        wavData.append(withUnsafeBytes(of: numChannels.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: sampleRate.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: bytesPerSecond.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: bytesPerFrame.littleEndian) { Data($0) })
        wavData.append(withUnsafeBytes(of: bitsPerSample.littleEndian) { Data($0) })
        
        // data chunk
        wavData.append("data".data(using: .ascii)!)
        wavData.append(withUnsafeBytes(of: audioDataSize.littleEndian) { Data($0) })
        wavData.append(rawAudioData)
        
        return wavData
    }
    
    func isListening() -> Bool {
        return isRecording
    }

    func cleanup() {
        // Stop any active recording
        if isRecording {
            if isStreamingMode {
                stopStreamingListening()
            } else {
                stopListening()
            }
        }

        // Cancel any active transcription to clean up whisper resources synchronously
        // This must complete before the app terminates to properly free Metal resources
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                TranscriptionStore.shared.cancelRecording()
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    TranscriptionStore.shared.cancelRecording()
                }
            }
        }

        // Ensure audio engine is stopped
        audioEngine.stop()
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        isStreamingMode = false
    }
}

// WhisperResponse struct removed - no longer needed for local implementation 