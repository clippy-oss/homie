//
//  MessageViewModel.swift
//  homie
//
//  View model for managing message view state
//

import Foundation
import SwiftUI
import Combine

@MainActor
class MessageViewModel: ObservableObject {
    @Published var selectedChat: WhatsAppChat?
    @Published var chats: [WhatsAppChat] = []
    @Published var messages: [WhatsAppMessage] = []
    @Published var chatSummaries: [String: String] = [:] // Keyed by chat JID
    @Published var isGeneratingSummaries: Bool = false
    
    private let dbManager = WhatsAppDatabaseManager.shared
    
    init() {
        // Observe database manager's chats
        dbManager.$chats
            .assign(to: &$chats)
    }
    
    func selectChat(_ chat: WhatsAppChat) {
        selectedChat = chat
        // Always load fresh messages from database
        reloadMessages()
    }
    
    func reloadMessages() {
        guard let chat = selectedChat else { return }
        // Clear cache for this chat to force fresh load
        dbManager.clearMessageCache()
        let loadedMessages = dbManager.loadMessages(for: chat.jid)
        messages = loadedMessages
        Logger.info("Loaded \(loadedMessages.count) messages for chat \(chat.name)", module: "MessageView")
    }
    
    func refreshChats() {
        dbManager.loadChats()
        // Also reload messages if a chat is selected
        if selectedChat != nil {
            reloadMessages()
        }
    }
    
    func sendMessage(_ text: String) async throws {
        guard let chat = selectedChat else {
            throw NSError(domain: "MessageViewModel", code: 1, userInfo: [NSLocalizedDescriptionKey: "No chat selected"])
        }
        
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return // Don't send empty messages
        }
        
        let provider = MessagingService.shared.provider(.whatsapp)
        
        do {
            _ = try await provider.sendMessage(chatID: chat.jid, text: text, quotedMessageID: nil as String?)
            Logger.info("Message sent successfully to \(chat.name)", module: "MessageView")
            
            // Reload messages to show the sent message
            reloadMessages()
            // Also refresh chats to update last message
            refreshChats()
        } catch {
            Logger.error("Failed to send message: \(error.localizedDescription)", module: "MessageView")
            throw error
        }
    }
    
    func generateSummariesForUnreadChats() async {
        guard !isGeneratingSummaries else {
            Logger.info("Summary generation already in progress", module: "MessageView")
            return
        }
        
        isGeneratingSummaries = true
        chatSummaries.removeAll()
        
        let unreadChats = chats.filter { $0.unreadCount > 0 }
        Logger.info("📝 Starting summary generation for \(unreadChats.count) unread chats", module: "MessageView")
        
        for (index, chat) in unreadChats.enumerated() {
            Logger.info("📝 Processing chat \(index + 1)/\(unreadChats.count): \(chat.name) (JID: \(chat.jid))", module: "MessageView")
            
            // Load unread messages for this chat
            let allMessages = dbManager.loadMessages(for: chat.jid)
            let unreadMessages = allMessages.filter { !$0.isRead && !$0.isFromMe }
                .sorted { $0.timestamp < $1.timestamp }
            
            Logger.info("📝 Found \(unreadMessages.count) unread messages in chat \(chat.name)", module: "MessageView")
            
            guard !unreadMessages.isEmpty else {
                Logger.info("📝 Skipping chat \(chat.name) - no unread messages", module: "MessageView")
                continue
            }
            
            // Build context from unread messages
            var messageContext = "Unread messages from \(chat.name):\n\n"
            for message in unreadMessages {
                let sender = message.isFromMe ? "Me" : extractSenderName(from: message.senderJID)
                let timestamp = formatMessageTimestamp(message.timestamp)
                let messageText = message.text.isEmpty ? "[\(message.type.rawValue.capitalized)]" : message.text
                messageContext += "[\(timestamp)] \(sender): \(messageText)\n"
            }
            
            Logger.info("📝 Sending context to Foundation Model for chat \(chat.name) (context length: \(messageContext.count) chars)", module: "MessageView")
            
            // Determine the appropriate prompt based on chat type and conditions
            let prompt: String
            if chat.type == .private {
                // One-on-one chat
                if hasSignificantTimeGap(in: unreadMessages) {
                    // Time gap detected - use prompt that includes time context
                    prompt = buildOneOnOneTimeGapPrompt(personName: chat.name)
                } else {
                    // No significant time gap - use simple prompt
                    prompt = buildOneOnOneSimplePrompt(personName: chat.name)
                }
            } else {
                // Group chat
                let uniqueSenders = getUniqueSenders(from: unreadMessages)
                if uniqueSenders.count > 5 {
                    // More than 5 senders - use bullet point format
                    prompt = buildGroupBulletPointPrompt(groupName: chat.name, senderNames: uniqueSenders)
                } else {
                    // 5 or fewer senders - use simple group format
                    prompt = buildGroupSimplePrompt(groupName: chat.name, senderNames: uniqueSenders)
                }
            }
            
            do {
                let summaryText = try await FoundationModelsManager.shared.processText(
                    prompt,
                    context: messageContext
                )
                
                // Store the summary directly (prompt already includes formatting instructions)
                chatSummaries[chat.jid] = summaryText.trimmingCharacters(in: .whitespacesAndNewlines)
                Logger.info("✅ Generated summary for chat \(chat.name): \(summaryText.prefix(100))...", module: "MessageView")
            } catch {
                Logger.error("❌ Failed to generate summary for chat \(chat.name): \(error.localizedDescription)", module: "MessageView")
                chatSummaries[chat.jid] = "Failed to generate summary: \(error.localizedDescription)"
            }
        }
        
        Logger.info("📝 Completed summary generation for all unread chats", module: "MessageView")
        isGeneratingSummaries = false
    }
    
    private func formatMessageTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    // MARK: - Helper Functions for Dynamic Prompts
    
    /// Checks if there's a significant time gap (> 1 hour) between unread messages
    private func hasSignificantTimeGap(in messages: [WhatsAppMessage]) -> Bool {
        guard messages.count > 1 else { return false }
        
        for i in 0..<messages.count - 1 {
            let timeDifference = messages[i + 1].timestamp.timeIntervalSince(messages[i].timestamp)
            if timeDifference > 3600 { // More than 1 hour (3600 seconds)
                return true
            }
        }
        return false
    }
    
    /// Extracts sender name from JID
    private func extractSenderName(from jid: String) -> String {
        return jid.components(separatedBy: "@").first ?? "Unknown"
    }
    
    /// Gets unique sender names from messages
    private func getUniqueSenders(from messages: [WhatsAppMessage]) -> [String] {
        let uniqueJIDs = Set(messages.map { $0.senderJID })
        return uniqueJIDs.map { extractSenderName(from: $0) }
    }
    
    // MARK: - Prompt Builders
    
    /// Builds a simple prompt for one-on-one chats without time gaps
    private func buildOneOnOneSimplePrompt(personName: String) -> String {
        return """
        Summarize the unread messages in a natural, conversational way. Your response should start with "\(personName) texted" or "\(personName) asked you" or "\(personName) sent a message" (use natural variations like these), followed by "about [topic]" or what they asked.
        
        Examples:
        - "\(personName) texted about the project deadline and asked if you could review the document."
        - "\(personName) asked you about the meeting time and sent a message with the agenda."
        - "\(personName) sent a message about the weekend plans and wanted to know your availability."
        
        Keep it concise (1-2 sentences) and focus on the main topic or question. Do not include timestamps or other metadata.
        """
    }
    
    /// Builds a prompt for one-on-one chats with time gaps between messages
    private func buildOneOnOneTimeGapPrompt(personName: String) -> String {
        return """
        Summarize the unread messages, noting the time differences between them when there are gaps of more than 1 hour. Your response should start with "\(personName) texted" or "\(personName) asked you" or "\(personName) sent a message" (use natural variations), followed by what they said, and then mention the time gap before the next message.
        
        Examples:
        - "\(personName) texted about xyz and an hour later asked if abc."
        - "\(personName) sent a message about the meeting, then 2 hours later asked about the location."
        - "\(personName) asked about the report, and a few hours later sent another message with updates."
        
        Use natural time descriptions (e.g., "an hour later", "2 hours later", "a few hours later", "later that day"). Only mention time gaps when they are significant (more than 1 hour).
        
        Keep it concise (2-3 sentences) and maintain the chronological flow with time references.
        """
    }
    
    /// Builds a simple prompt for group chats with 5 or fewer senders
    private func buildGroupSimplePrompt(groupName: String, senderNames: [String]) -> String {
        let namesList = senderNames.joined(separator: ", ")
        return """
        Summarize the unread messages from this group chat. Your response must start with "In the \(groupName) group," and then mention the names of the people who sent messages (\(namesList)).
        
        Examples:
        - "In the \(groupName) group, \(namesList) were discussing the project timeline and upcoming deadlines."
        - "In the \(groupName) group, \(namesList) were planning the team lunch and coordinating schedules."
        
        Keep it concise (1-2 sentences) and focus on the main discussion topic. Always start with "In the [group name] group," and include the actual sender names.
        """
    }
    
    /// Builds a bullet point prompt for group chats with more than 5 senders
    private func buildGroupBulletPointPrompt(groupName: String, senderNames: [String]) -> String {
        let namesList = senderNames.joined(separator: ", ")
        return """
        Summarize the unread messages from this group chat using a bullet point format. Your response must start with "In the \(groupName) group:" on its own line, then list each point with a dash on a new line.
        
        Group related messages together. Use the actual sender names from the messages: \(namesList)
        
        Example format:
        In the \(groupName) group:
        - Alice mentioned the project deadline
        - Bob and Charlie were discussing the technical requirements
        - Alice and David made plans for the team meeting
        
        Keep each bullet point concise (1 sentence) and focus on the key points or discussions. Always start with "In the [group name] group:" on its own line.
        """
    }
}

