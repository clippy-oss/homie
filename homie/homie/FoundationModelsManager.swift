import Foundation
import FoundationModels

/// Manager for Apple's Foundation Models integration
class FoundationModelsManager {
    static let shared = FoundationModelsManager()
    
    private var session: LanguageModelSession?
    private var memorySession: LanguageModelSession?
    
    // Cached system instructions with user info embedded
    private var cachedSystemInstructions: String = ""
    
    private init() {
        buildSystemInstructions()
        setupSessions()
    }
    
    /// Build system instructions with user info embedded at the correct location
    private func buildSystemInstructions() {
        let userInfo = UserPersonalizationManager.shared.getUserInformationBlock()
        
        // Base instructions before user info insertion point
        let beforeUserInfo = """
        You are a helpful assistant that processes text content. When the user provides context (the content they're working with) and a request, you should process that content according to their request. The context is the material the user wants you to work with - it could be code, documents, emails, articles, or any other text content. Your job is to help the user with any request using the provided context or even without that if the user has a request without a context.
        Be very direct, you are talking like gen-z. And don't forget, you are not an assistant writing anything like "Sure, here is the output..." or "Feel free to edit it..." No fluff, just the requested output!!!
        Don't add unnecessary explanations or formalities - Just provide the requested content. Always think about the fact that the user has a text box available and only wants to paste there the main text they are working with and no extra text.
        Bad example: User request: "Write a reply to this email" Assitant: "Sure, here is the email..."
        Bad example: User request: "Write a reply to this email" Assitant: "Subject: An email response to..."
        Good example: User request: "Write a reply to this email" Assitant: "Dear xyz,..."
        
        You receive information to the user, so if you need to include anything, like the user's name, email address, or anything that is mentioned, use the info. Always remember that if you sign emails, sign them with the user's name. Always use the Primary email and phone number of the user, unless requested differently.
        """
        
        // Instructions after user info
        let afterUserInfo = """
        
        Use simple formatting without markdown unless specifically requested.
        Your response will be pasted directly into the user's text field and the user will work with that text directly, so under no circumstances use any unnecessary formating!! If the user asks you to summarize a text, don't write "Sure, here is the summary..." but place the summary, and just the summary, diretly in the text field. If the user asks you to write a response to an email, don't or "Here is the email..." but place the email and nothing else.
        For emails format them as an email would be formated, with an adressing of the recipient and at the end a signature, but don't include a subject line. Those belong in a differnt text field.
        
        Always process the user's request using the context they provide and ignore the history. The context is the content they want you to work with, not personal information about them. The personal information is there to give any guidance on what the user's name or so are.
        """
        
        // Combine: before + user info + after
        cachedSystemInstructions = beforeUserInfo + userInfo + afterUserInfo
    }
    
    /// Refresh system instructions when user info changes
    func refreshSystemInstructions() {
        buildSystemInstructions()
        setupSessions()
        Logger.info("🔄 FoundationModelsManager: System instructions refreshed with updated user info", module: "LLM")
    }
    
    /// Get the current system instructions (for logging/debugging)
    func getSystemInstructions() -> String {
        return cachedSystemInstructions
    }
    
    private func setupSessions() {
        // Main session for text processing - use cached instructions
        self.session = LanguageModelSession(instructions: cachedSystemInstructions)
        
        // Memory extraction session
        let memoryInstructions = """
        You are an assistant that analyzes a conversation between a user and an AI, and extracts facts about the USER for long-term memory. You must output ONLY valid JSON in the specified structure.
        """
        
        self.memorySession = LanguageModelSession(instructions: memoryInstructions)
    }
    
    /// Check if Foundation Models is available
    func isAvailable() -> Bool {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return true
        case .unavailable:
            return false
        }
    }
    
    /// Get availability status for user feedback
    func getAvailabilityStatus() -> String {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return "Foundation Models is available and ready to go!"
        case .unavailable(.deviceNotEligible):
            return "The model is not available on this device."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is not enabled in Settings."
        case .unavailable(.modelNotReady):
            return "The model is not ready yet. Please try again later."
        case .unavailable(let other):
            return "The model is unavailable for an unknown reason: \(other)"
        }
    }
    
    /// Process text with Foundation Models (replaces GPT API call)
    func processText(_ text: String, context: String? = nil) async throws -> String {
        guard let session = session else {
            throw FoundationModelsError.sessionNotInitialized
        }
        
        // Build the prompt with context and memory
        // Note: User information is already embedded in the system instructions (session)
        var prompt = Prompt {
            text
        }
        
        if let context = context, !context.isEmpty {
            prompt = Prompt {
                "Content to process:\n\(context)\n\nUser request: \(text)"
            }
        }
        
        // Memory context is stored but not added to prompts
        // (Memory system continues to work for storage but doesn't influence responses)
        
        // Add conversation history
        let memoryTurns = ConversationMemory.shared.getRecentTurns(maxPairs: 6, withinMinutes: 3)
        for turn in memoryTurns {
            prompt = Prompt {
                "User: \(turn.userText)"
                "Assistant: \(turn.assistantText)"
                prompt
            }
        }
        
        let userInfo = UserPersonalizationManager.shared.getUserInformationBlock()
        Logger.debug("🔍 FOUNDATION MODELS MANAGER: About to send prompt to Foundation Models API", module: "LLM")
        Logger.debug("🔍 Prompt structure built with context: \(context != nil ? "YES" : "NO")", module: "LLM")
        Logger.debug("🔍 User information included in system instructions: \(!userInfo.isEmpty ? "YES" : "NO")", module: "LLM")
        Logger.debug("🔍 Memory context included: NO (disabled)", module: "LLM")
        Logger.debug("🔍 Conversation history included: \(!memoryTurns.isEmpty ? "YES (\(memoryTurns.count) turns)" : "NO")", module: "LLM")
        
        do {
            let response = try await session.respond(to: prompt)
            Logger.debug("🔍 FOUNDATION MODELS MANAGER: Received response from Foundation Models API", module: "LLM")
            return response.content
        } catch {
            // Check if this is a context window error
            let errorMessage = error.localizedDescription.lowercased()
            if errorMessage.contains("exceeded model context window size") || errorMessage.contains("context window") {
                Logger.warning("⚠️ Context window exceeded, retrying without conversation history...", module: "LLM")
                return try await processTextWithoutHistory(text, context: context)
            }
            throw error
        }
    }
    
    /// Process text without conversation history (fallback for context window errors)
    private func processTextWithoutHistory(_ text: String, context: String? = nil) async throws -> String {
        guard let session = session else {
            throw FoundationModelsError.sessionNotInitialized
        }
        
        // Build the prompt with context but NO conversation history
        // Note: User information is already embedded in the system instructions (session)
        var prompt = Prompt {
            text
        }
        
        if let context = context, !context.isEmpty {
            prompt = Prompt {
                "Content to process:\n\(context)\n\nUser request: \(text)"
            }
        }
        
        let userInfo = UserPersonalizationManager.shared.getUserInformationBlock()
        Logger.debug("🔍 FOUNDATION MODELS MANAGER: Retrying without conversation history", module: "LLM")
        Logger.debug("🔍 Prompt structure built with context: \(context != nil ? "YES" : "NO")", module: "LLM")
        Logger.debug("🔍 User information included in system instructions: \(!userInfo.isEmpty ? "YES" : "NO")", module: "LLM")
        Logger.debug("🔍 Memory context included: NO (disabled)", module: "LLM")
        Logger.debug("🔍 Conversation history included: NO (0 turns)", module: "LLM")
        
        do {
            let response = try await session.respond(to: prompt)
            Logger.debug("🔍 FOUNDATION MODELS MANAGER: Received response from Foundation Models API (no history)", module: "LLM")
            return response.content
        } catch {
            // If even without history it fails, return the fallback message
            let errorMessage = error.localizedDescription.lowercased()
            if errorMessage.contains("exceeded model context window size") || errorMessage.contains("context window") {
                Logger.error("❌ Even without conversation history, context is too large", module: "LLM")
                return "This context seems too large for me to process. Sorry about that :("
            }
            throw error
        }
    }
    
    /// Extract memory facts using Foundation Models (replaces GPT memory extraction)
    func extractMemoryFacts(from conversationChunk: String) async throws -> ExtractedFacts {
        guard let memorySession = memorySession else {
            throw FoundationModelsError.sessionNotInitialized
        }
        
        let userPrompt = MemoryRetriever.buildExtractionPrompt(withConversation: conversationChunk)
        
        let response = try await memorySession.respond(to: userPrompt, generating: ExtractedFacts.self)
        return response.content
    }
    
    /// Convert Foundation Models facts to the existing memory system format
    func convertToMemoryFacts(_ extractedFacts: ExtractedFacts) -> (bigFacts: [IncomingBigFact], smallFacts: [IncomingSmallFact]) {
        let bigFacts = extractedFacts.new_big_facts.map { fact in
            IncomingBigFact(
                factText: fact.fact,
                importanceScore: 0.8, // Default importance score
                updateConfidence: 0.9 // Default confidence
            )
        }
        
        let smallFacts = extractedFacts.new_small_facts.map { fact in
            IncomingSmallFact(
                factText: fact.fact,
                importanceScore: 0.5 // Default importance score
            )
        }
        
        return (bigFacts, smallFacts)
    }
    
    /// Prewarm the model for better performance
    func prewarm() async {
        // Foundation Models prewarming is handled automatically
        // No explicit prewarm method needed
        Logger.info("🔥 Foundation Models ready for use", module: "LLM")
    }
}

// MARK: - Error Types
enum FoundationModelsError: Error, LocalizedError {
    case sessionNotInitialized
    case modelNotAvailable
    case extractionFailed
    
    var errorDescription: String? {
        switch self {
        case .sessionNotInitialized:
            return "Foundation Models session not initialized"
        case .modelNotAvailable:
            return "Foundation Models is not available on this device"
        case .extractionFailed:
            return "Failed to extract memory facts"
        }
    }
}

// MARK: - Structured Data for Memory Extraction
@Generable
struct ExtractedFacts: Codable {
    @Guide(description: "Important facts about the user that should be remembered long-term")
    let new_big_facts: [FoundationBigFact]
    
    @Guide(description: "Smaller, contextual facts about the user")
    let new_small_facts: [FoundationSmallFact]
}

@Generable
struct FoundationBigFact: Codable {
    @Guide(description: "The fact content")
    let fact: String
    
    @Guide(description: "When this fact was learned")
    let learned_at: String
}

@Generable
struct FoundationSmallFact: Codable {
    @Guide(description: "The fact content")
    let fact: String
    
    @Guide(description: "When this fact was learned")
    let learned_at: String
}
