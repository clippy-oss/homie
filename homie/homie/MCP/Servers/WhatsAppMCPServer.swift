//
//  WhatsAppMCPServer.swift
//  homie
//
//  MCP server implementation for WhatsApp messaging
//

import Foundation
import Combine

@available(macOS 15.0, *)
class WhatsAppMCPServer: MCPServerProtocol, ObservableObject {
    let serverID = "whatsapp"
    let config: MCPServerConfig

    @Published private(set) var connectionStatus: MCPConnectionStatus = .disconnected

    var connectionStatusPublisher: AnyPublisher<MCPConnectionStatus, Never> {
        $connectionStatus.eraseToAnyPublisher()
    }

    var isConnected: Bool {
        connectionStatus.isConnected
    }

    // MARK: - Dependencies (Injected)
    private let messagingProvider: MessagingProviderProtocol
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization
    init(messagingProvider: MessagingProviderProtocol) {
        self.messagingProvider = messagingProvider
        self.config = MCPServerConfig(
            id: "whatsapp",
            name: "WhatsApp",
            description: "Send and receive WhatsApp messages",
            iconName: "message.fill",
            authType: .devicePairing,
            authURL: "",
            tokenURL: "",
            scopes: [],
            redirectPath: ""
        )

        // Sync connection status with provider
        setupStatusSync()
    }

    private func setupStatusSync() {
        messagingProvider.connectionStatusPublisher
            .map { status -> MCPConnectionStatus in
                switch status {
                case .connected: return .connected(email: nil)
                case .disconnected: return .disconnected
                case .pairing: return .pairing
                case .connecting: return .connecting
                case .error(let msg): return .error(msg)
                }
            }
            .assign(to: &$connectionStatus)
    }

    // MARK: - Tools

    var tools: [MCPTool] {
        return [
            MCPTool(
                name: "whatsapp_list_chats",
                description: "List WhatsApp chats sorted by most recent activity.",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [
                        "limit": MCPToolProperty(
                            type: "integer",
                            description: "Maximum number of chats to return (default 20)",
                            enumValues: nil,
                            items: nil
                        )
                    ],
                    required: nil
                ),
                serverID: serverID
            ),
            MCPTool(
                name: "whatsapp_get_messages",
                description: "Get messages from a specific WhatsApp chat.",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [
                        "chat_id": MCPToolProperty(
                            type: "string",
                            description: "The chat identifier (JID format)",
                            enumValues: nil,
                            items: nil
                        ),
                        "limit": MCPToolProperty(
                            type: "integer",
                            description: "Maximum number of messages to return (default 50)",
                            enumValues: nil,
                            items: nil
                        )
                    ],
                    required: ["chat_id"]
                ),
                serverID: serverID
            ),
            MCPTool(
                name: "whatsapp_send_message",
                description: "Send a text message to a WhatsApp chat.",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [
                        "chat_id": MCPToolProperty(
                            type: "string",
                            description: "The chat identifier (JID format)",
                            enumValues: nil,
                            items: nil
                        ),
                        "text": MCPToolProperty(
                            type: "string",
                            description: "The message text to send",
                            enumValues: nil,
                            items: nil
                        )
                    ],
                    required: ["chat_id", "text"]
                ),
                serverID: serverID
            ),
            MCPTool(
                name: "whatsapp_send_reaction",
                description: "React to a WhatsApp message with an emoji.",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [
                        "chat_id": MCPToolProperty(
                            type: "string",
                            description: "The chat identifier (JID format)",
                            enumValues: nil,
                            items: nil
                        ),
                        "message_id": MCPToolProperty(
                            type: "string",
                            description: "The message ID to react to",
                            enumValues: nil,
                            items: nil
                        ),
                        "emoji": MCPToolProperty(
                            type: "string",
                            description: "The reaction emoji (e.g., thumbs up, heart, laughing)",
                            enumValues: nil,
                            items: nil
                        )
                    ],
                    required: ["chat_id", "message_id", "emoji"]
                ),
                serverID: serverID
            ),
            MCPTool(
                name: "whatsapp_mark_read",
                description: "Mark WhatsApp messages as read.",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [
                        "chat_id": MCPToolProperty(
                            type: "string",
                            description: "The chat identifier (JID format)",
                            enumValues: nil,
                            items: nil
                        ),
                        "message_ids": MCPToolProperty(
                            type: "array",
                            description: "Array of message IDs to mark as read",
                            enumValues: nil,
                            items: MCPToolProperty(
                                type: "string",
                                description: nil,
                                enumValues: nil,
                                items: nil
                            )
                        )
                    ],
                    required: ["chat_id", "message_ids"]
                ),
                serverID: serverID
            ),
            MCPTool(
                name: "whatsapp_connection_status",
                description: "Get the current WhatsApp connection status.",
                parameters: MCPToolParameters(
                    type: "object",
                    properties: [:],
                    required: nil
                ),
                serverID: serverID
            )
        ]
    }

    // MARK: - Tool Execution

    func execute(tool toolName: String, arguments: [String: Any]) async throws -> String {
        switch toolName {
        case "whatsapp_list_chats":
            return try await listChats(arguments: arguments)
        case "whatsapp_get_messages":
            return try await getMessages(arguments: arguments)
        case "whatsapp_send_message":
            return try await sendMessage(arguments: arguments)
        case "whatsapp_send_reaction":
            return try await sendReaction(arguments: arguments)
        case "whatsapp_mark_read":
            return try await markAsRead(arguments: arguments)
        case "whatsapp_connection_status":
            return getConnectionStatus()
        default:
            throw MCPError.toolNotFound(toolName)
        }
    }

    // MARK: - Tool Implementations

    private func listChats(arguments: [String: Any]) async throws -> String {
        guard messagingProvider.isLoggedIn else {
            throw MCPError.notConnected(serverID: serverID)
        }

        let limit = arguments["limit"] as? Int ?? 20

        let chats = try await messagingProvider.getChats(limit: limit, offset: 0)
        return formatChatsResponse(chats)
    }

    private func getMessages(arguments: [String: Any]) async throws -> String {
        guard messagingProvider.isLoggedIn else {
            throw MCPError.notConnected(serverID: serverID)
        }

        guard let chatID = arguments["chat_id"] as? String else {
            throw MCPError.executionFailed("Missing required parameter: chat_id")
        }

        let limit = arguments["limit"] as? Int ?? 50

        let messages = try await messagingProvider.getMessages(chatID: chatID, limit: limit, beforeID: nil)
        return formatMessagesResponse(messages)
    }

    private func sendMessage(arguments: [String: Any]) async throws -> String {
        guard messagingProvider.isLoggedIn else {
            throw MCPError.notConnected(serverID: serverID)
        }

        guard let chatID = arguments["chat_id"] as? String else {
            throw MCPError.executionFailed("Missing required parameter: chat_id")
        }

        guard let text = arguments["text"] as? String else {
            throw MCPError.executionFailed("Missing required parameter: text")
        }

        let sentMessage = try await messagingProvider.sendMessage(chatID: chatID, text: text, quotedMessageID: nil)
        return "Message sent successfully.\nMessage ID: \(sentMessage.id)\nTimestamp: \(formatDate(sentMessage.timestamp))"
    }

    private func sendReaction(arguments: [String: Any]) async throws -> String {
        guard messagingProvider.isLoggedIn else {
            throw MCPError.notConnected(serverID: serverID)
        }

        guard let chatID = arguments["chat_id"] as? String else {
            throw MCPError.executionFailed("Missing required parameter: chat_id")
        }

        guard let messageID = arguments["message_id"] as? String else {
            throw MCPError.executionFailed("Missing required parameter: message_id")
        }

        guard let emoji = arguments["emoji"] as? String else {
            throw MCPError.executionFailed("Missing required parameter: emoji")
        }

        try await messagingProvider.sendReaction(chatID: chatID, messageID: messageID, emoji: emoji)
        return "Reaction '\(emoji)' sent to message \(messageID)"
    }

    private func markAsRead(arguments: [String: Any]) async throws -> String {
        guard messagingProvider.isLoggedIn else {
            throw MCPError.notConnected(serverID: serverID)
        }

        guard let chatID = arguments["chat_id"] as? String else {
            throw MCPError.executionFailed("Missing required parameter: chat_id")
        }

        guard let messageIDs = arguments["message_ids"] as? [String] else {
            throw MCPError.executionFailed("Missing required parameter: message_ids")
        }

        try await messagingProvider.markAsRead(chatID: chatID, messageIDs: messageIDs)
        return "Marked \(messageIDs.count) message(s) as read in chat \(chatID)"
    }

    private func getConnectionStatus() -> String {
        let status = messagingProvider.connectionStatus
        let isLoggedIn = messagingProvider.isLoggedIn

        var result = "WhatsApp Connection Status:\n"
        result += "- Status: \(statusDescription(status))\n"
        result += "- Logged In: \(isLoggedIn ? "Yes" : "No")\n"
        result += "- Provider: \(messagingProvider.displayName)"

        return result
    }

    // MARK: - Format Helpers

    private func formatChatsResponse(_ chats: [MessagingChat]) -> String {
        if chats.isEmpty {
            return "No chats found."
        }

        var result = "Found \(chats.count) chat(s):\n\n"

        for chat in chats {
            let chatTypeStr = chat.chatType == .group ? "Group" : "Individual"
            let unreadStr = chat.unreadCount > 0 ? " (\(chat.unreadCount) unread)" : ""
            let archivedStr = chat.isArchived ? " [Archived]" : ""
            let mutedStr = chat.isMuted ? " [Muted]" : ""

            result += "- \(chat.name)\(unreadStr)\(archivedStr)\(mutedStr)\n"
            result += "  ID: \(chat.id)\n"
            result += "  Type: \(chatTypeStr)\n"

            if let lastMessageTime = chat.lastMessageTime {
                result += "  Last message: \(formatDate(lastMessageTime))\n"
            }

            if let lastMessageText = chat.lastMessageText {
                let truncatedText = lastMessageText.count > 50
                    ? String(lastMessageText.prefix(50)) + "..."
                    : lastMessageText
                let senderPrefix = chat.lastMessageSenderName.map { "\($0): " } ?? ""
                result += "  Preview: \(senderPrefix)\(truncatedText)\n"
            }

            result += "\n"
        }

        return result
    }

    private func formatMessagesResponse(_ messages: [MessagingMessage]) -> String {
        if messages.isEmpty {
            return "No messages found."
        }

        var result = "Found \(messages.count) message(s):\n\n"

        for message in messages {
            let senderName = message.isFromMe ? "You" : (message.senderName ?? message.senderID)
            let readStatus = message.isRead ? "" : " [Unread]"
            let messageTypeStr = messageTypeDescription(message.messageType)

            result += "[\(formatDate(message.timestamp))] \(senderName)\(readStatus):\n"

            if message.messageType == .text {
                result += "  \(message.text)\n"
            } else {
                result += "  [\(messageTypeStr)]\n"
                if !message.text.isEmpty {
                    result += "  Caption: \(message.text)\n"
                }
            }

            result += "  ID: \(message.id)\n"

            if let quotedID = message.quotedMessageID {
                result += "  Reply to: \(quotedID)\n"
            }

            result += "\n"
        }

        return result
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func statusDescription(_ status: MessagingConnectionStatus) -> String {
        switch status {
        case .disconnected:
            return "Disconnected"
        case .connecting:
            return "Connecting"
        case .connected:
            return "Connected"
        case .pairing:
            return "Waiting for pairing"
        case .error(let message):
            return "Error: \(message)"
        }
    }

    private func messageTypeDescription(_ type: MessagingMessage.MessageType) -> String {
        switch type {
        case .text: return "Text"
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .document: return "Document"
        case .sticker: return "Sticker"
        case .reaction: return "Reaction"
        case .location: return "Location"
        }
    }

    // MARK: - Protocol Stubs (Not used for WhatsApp)

    func setCredentials(_ credentials: MCPStoredCredentials) {
        // Not used - WhatsApp uses device pairing, not OAuth
    }

    func disconnect() {
        connectionStatus = .disconnected
    }

    func refreshTokenIfNeeded() async throws {
        // Not applicable for WhatsApp
    }
}
