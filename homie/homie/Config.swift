import Foundation

struct Config {
    static let shared = Config()

    private init() {}

    // Supabase configuration - reads from Info.plist
    static var supabaseURL: String {
        guard let url = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String else {
            fatalError("SUPABASE_URL not found in Info.plist")
        }
        return url
    }

    static var supabaseAnonKey: String {
        guard let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String else {
            fatalError("SUPABASE_ANON_KEY not found in Info.plist")
        }
        return key
    }

    // OpenAI API configuration removed - now using local whisper.cpp
    // Foundation Models doesn't require API keys - it runs locally on macOS
    // whisper.cpp also runs locally and doesn't require API keys
    // OpenAI configuration for premium users is now stored in Supabase

    // MARK: - MCP OAuth Configuration
    // OAuth credentials (Client ID and Client Secret) are now stored securely in Supabase Vault
    // and retrieved at runtime via the edge function. No local configuration needed.

    // MARK: - Update Configuration
    static let appcastURL = "https://pub-74e2bbd95fb743b29638f4967a7c5274.r2.dev/appcast.xml"
} 
