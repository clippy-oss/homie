import Foundation
import Accelerate
import whisper

class LocalWhisperManager {
    private var context: OpaquePointer?
    private let modelPath: String
    private let sampleRate: Float = 16000.0 // whisper.cpp expects 16kHz
    
    init(modelPath: String) {
        self.modelPath = modelPath
        loadModel()
    }
    
    deinit {
        cleanup()
    }

    func cleanup() {
        if let ctx = context {
            whisper_free(ctx)
            context = nil
        }
    }
    
    private func loadModel() {
        var params = whisper_context_default_params()
        params.use_gpu = true  // Use Metal on Apple Silicon
        params.flash_attn = true
        
        context = whisper_init_from_file_with_params(modelPath, params)
        
        if context == nil {
            Logger.error("Failed to load whisper model from \(modelPath)", module: "Speech")
        } else {
            Logger.info("Successfully loaded whisper model", module: "Speech")
        }
    }
    
    func transcribe(audioData: Data) -> String? {
        guard let context = context else { 
            Logger.info("Whisper context not initialized", module: "Speech")
            return nil 
        }
        
        // Convert Data to Float32 array and resample to 16kHz
        guard let samples = convertToFloat32Samples(audioData) else {
            Logger.error("Failed to convert audio data", module: "Speech")
            return nil
        }
        
        // Set up parameters
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.translate = false
        
        // Set language parameter with proper C string handling
        let language = "en"
        let result = language.withCString { cString in
            params.language = cString
            params.n_threads = min(4, Int32(ProcessInfo.processInfo.processorCount))
            params.offset_ms = 0
            params.no_context = true
            params.single_segment = true
            
            // Run transcription
            return whisper_full(context, params, samples, Int32(samples.count))
        }
        
        if result != 0 {
            Logger.error("Failed to run whisper model", module: "Speech")
            return nil
        }
        
        // Extract text from segments
        var transcription = ""
        let n_segments = whisper_full_n_segments(context)
        
        for i in 0..<n_segments {
            if let segmentText = whisper_full_get_segment_text(context, i) {
                transcription += String(cString: segmentText)
            }
        }
        
        return transcription.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    func convertToFloat32Samples(_ audioData: Data) -> [Float]? {
        Logger.debug("🔍 Parsing WAV data: \(audioData.count) bytes", module: "Speech")
        
        // Parse WAV data to extract audio samples
        guard audioData.count >= 44 else { // Minimum WAV header size
            Logger.error("❌ Audio data too small for WAV format: \(audioData.count) bytes", module: "Speech")
            return nil
        }
        
        // Check for WAV header
        let riffHeader = String(data: audioData.subdata(in: 0..<4), encoding: .ascii) ?? ""
        let waveHeader = String(data: audioData.subdata(in: 8..<12), encoding: .ascii) ?? ""
        
        Logger.debug("🔍 WAV headers - RIFF: '\(riffHeader)', WAVE: '\(waveHeader)'", module: "Speech")
        
        guard riffHeader == "RIFF" && waveHeader == "WAVE" else {
            Logger.error("❌ Invalid WAV format - RIFF: '\(riffHeader)', WAVE: '\(waveHeader)'", module: "Speech")
            return nil
        }
        
        // Parse WAV format chunk to get audio format info
        let fmtChunkSize = audioData.subdata(in: 16..<20).withUnsafeBytes { $0.load(as: UInt32.self) }
        let audioFormat = audioData.subdata(in: 20..<22).withUnsafeBytes { $0.load(as: UInt16.self) }
        let numChannels = audioData.subdata(in: 22..<24).withUnsafeBytes { $0.load(as: UInt16.self) }
        let sampleRate = audioData.subdata(in: 24..<28).withUnsafeBytes { $0.load(as: UInt32.self) }
        let bitsPerSample = audioData.subdata(in: 34..<36).withUnsafeBytes { $0.load(as: UInt16.self) }
        
        Logger.debug("🔍 WAV format - Channels: \(numChannels), Sample Rate: \(sampleRate), Bits: \(bitsPerSample), Format: \(audioFormat)", module: "Speech")
        
        // Find the data chunk
        var dataStart = 20 + Int(fmtChunkSize) // Start after format chunk
        var dataSize = 0
        
        // Align to 2-byte boundary
        if dataStart % 2 != 0 {
            dataStart += 1
        }
        
        Logger.debug("🔍 Looking for data chunk starting at byte \(dataStart)", module: "Speech")
        
        while dataStart < audioData.count - 8 {
            let chunkId = String(data: audioData.subdata(in: dataStart..<dataStart+4), encoding: .ascii) ?? ""
            let chunkSize = audioData.subdata(in: dataStart+4..<dataStart+8).withUnsafeBytes { $0.load(as: UInt32.self) }
            
            Logger.debug("🔍 Found chunk: '\(chunkId)' size: \(chunkSize)", module: "Speech")
            
            if chunkId == "data" {
                dataSize = Int(chunkSize)
                dataStart += 8
                break
            }
            
            dataStart += Int(chunkSize) + 8
            // Align to 2-byte boundary
            if dataStart % 2 != 0 {
                dataStart += 1
            }
        }
        
        guard dataSize > 0 && dataStart + dataSize <= audioData.count else {
            Logger.error("❌ Invalid WAV data chunk - size: \(dataSize), start: \(dataStart), total: \(audioData.count)", module: "Speech")
            return nil
        }
        
        Logger.info("✅ Found data chunk: \(dataSize) bytes starting at \(dataStart)", module: "Speech")
        
        // Extract audio data based on format
        let audioBytes = audioData.subdata(in: dataStart..<dataStart + dataSize)
        var samples: [Float] = []
        
        if audioFormat == 3 && bitsPerSample == 32 {
            // 32-bit float format
            samples = audioBytes.withUnsafeBytes { bytes in
                Array(bytes.bindMemory(to: Float.self))
            }
            Logger.info("✅ Extracted \(samples.count) float32 samples", module: "Speech")
        } else if audioFormat == 1 && bitsPerSample == 16 {
            // 16-bit PCM format
            let int16Samples = audioBytes.withUnsafeBytes { bytes in
                Array(bytes.bindMemory(to: Int16.self))
            }
            samples = int16Samples.map { Float($0) / 32768.0 }
            Logger.info("✅ Extracted \(samples.count) int16 samples, converted to float32", module: "Speech")
        } else {
            Logger.error("❌ Unsupported audio format: \(audioFormat), bits: \(bitsPerSample)", module: "Speech")
            return nil
        }
        
        // Resample from current sample rate to 16kHz
        let currentSampleRate = Float(sampleRate)
        if currentSampleRate != 16000 {
            Logger.info("🔄 Resampling from \(currentSampleRate)Hz to 16000Hz", module: "Speech")
            return resampleAudio(samples, fromSampleRate: currentSampleRate, toSampleRate: 16000)
        } else {
            Logger.info("✅ No resampling needed - already 16kHz", module: "Speech")
            return samples
        }
    }
    
    private func resampleAudio(_ inputSamples: [Float], fromSampleRate: Float, toSampleRate: Float) -> [Float] {
        let ratio = fromSampleRate / toSampleRate
        let outputLength = Int(Float(inputSamples.count) / ratio)
        
        guard outputLength > 0 else { return inputSamples }
        
        var outputSamples = [Float](repeating: 0, count: outputLength)
        
        // Simple linear interpolation resampling
        for i in 0..<outputLength {
            let sourceIndex = Float(i) * ratio
            let index = Int(sourceIndex)
            let fraction = sourceIndex - Float(index)
            
            if index + 1 < inputSamples.count {
                outputSamples[i] = inputSamples[index] * (1.0 - fraction) + inputSamples[index + 1] * fraction
            } else if index < inputSamples.count {
                outputSamples[i] = inputSamples[index]
            }
        }
        
        return outputSamples
    }
    
    func isModelLoaded() -> Bool {
        return context != nil
    }
}
