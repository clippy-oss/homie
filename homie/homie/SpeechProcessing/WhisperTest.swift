import Foundation

class WhisperTest {
    static func testLocalWhisper() {
        Logger.info("🧪 Testing Local Whisper Integration...", module: "Speech")
        
        // Check if model file exists
        let modelPath = Bundle.main.path(forResource: "ggml-base.en", ofType: "bin")
        if let modelPath = modelPath {
            Logger.info("✅ Model file found at: \(modelPath)", module: "Speech")
            
            // Test LocalWhisperManager initialization
            let whisperManager = LocalWhisperManager(modelPath: modelPath)
            if whisperManager.isModelLoaded() {
                Logger.info("✅ Local Whisper model loaded successfully", module: "Speech")
            } else {
                Logger.error("❌ Failed to load Local Whisper model", module: "Speech")
            }
        } else {
            Logger.error("❌ Model file not found in bundle", module: "Speech")
            Logger.info("Make sure to add ggml-base.en.bin to your Xcode project", module: "Speech")
        }
    }
    
    static func testAudioResampling() {
        Logger.info("🧪 Testing Audio Resampling...", module: "Speech")
        
        // Create test audio data (simulate 48kHz audio)
        let sampleCount = 48000 // 1 second of 48kHz audio
        var testSamples = [Float]()
        for i in 0..<sampleCount {
            testSamples.append(sin(Float(i) * 2.0 * Float.pi * 440.0 / 48000.0)) // 440Hz tone
        }
        
        // Convert to Data (simulate WAV format)
        let audioData = testSamples.withUnsafeBytes { Data($0) }
        
        // Test resampling
        let whisperManager = LocalWhisperManager(modelPath: "")
        let resampled = whisperManager.convertToFloat32Samples(audioData)
        
        if let resampled = resampled {
            Logger.info("✅ Audio resampling successful: \(testSamples.count) → \(resampled.count) samples", module: "Speech")
            Logger.info("   Expected ~16000 samples, got \(resampled.count)", module: "Speech")
        } else {
            Logger.error("❌ Audio resampling failed", module: "Speech")
        }
    }
}

// Test completed - no extension needed
