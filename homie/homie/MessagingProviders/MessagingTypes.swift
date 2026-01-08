//
//  MessagingTypes.swift
//  homie
//
//  Provider-agnostic types used by MessagingProviderProtocol.
//  These types enable consistent messaging interfaces across different providers.
//

import Foundation

// MARK: - Connection Status

/// Represents the current connection state of a messaging provider.
enum MessagingConnectionStatus: Equatable {
    /// Not connected to the messaging service
    case disconnected
    /// Attempting to establish connection
    case connecting
    /// Successfully connected and ready
    case connected
    /// Waiting for device pairing (QR code or pairing code)
    case pairing
    /// Connection error with descriptive message
    case error(String)

    /// Whether the provider is currently connected and operational
    var isConnected: Bool {
        if case .connected = self {
            return true
        }
        return false
    }
}

// MARK: - Chat

/// Represents a conversation in the messaging service.
struct MessagingChat: Identifiable {
    /// Type of chat conversation
    enum ChatType {
        /// One-on-one private conversation
        case individual
        /// Group conversation with multiple participants
        case group
    }

    /// Unique identifier for the chat (e.g., JID for WhatsApp)
    let id: String
    /// Display name of the chat (contact name or group name)
    let name: String
    /// Type of chat (individual or group)
    let chatType: ChatType
    /// Timestamp of the most recent message, if any
    let lastMessageTime: Date?
    /// Text content of the most recent message, if any
    let lastMessageText: String?
    /// Name of the sender of the most recent message, if any
    let lastMessageSenderName: String?
    /// Number of unread messages in the chat
    let unreadCount: Int
    /// Whether the chat is archived
    let isArchived: Bool
    /// Whether notifications are muted for this chat
    let isMuted: Bool
}

// MARK: - Message

/// Represents a single message in a chat.
struct MessagingMessage: Identifiable {
    /// Type of message content
    enum MessageType {
        /// Plain text message
        case text
        /// Image attachment
        case image
        /// Video attachment
        case video
        /// Audio message or voice note
        case audio
        /// Document or file attachment
        case document
        /// Sticker
        case sticker
        /// Reaction to another message
        case reaction
        /// Location share
        case location
    }

    /// Unique identifier for the message
    let id: String
    /// Identifier of the chat this message belongs to
    let chatID: String
    /// Identifier of the message sender
    let senderID: String
    /// Display name of the sender, if available
    let senderName: String?
    /// Text content of the message
    let text: String
    /// When the message was sent
    let timestamp: Date
    /// Whether this message was sent by the current user
    let isFromMe: Bool
    /// Whether this message has been read
    let isRead: Bool
    /// Type of message content
    let messageType: MessageType
    /// URL of media attachment, if any
    let mediaURL: String?
    /// MIME type of media attachment, if any
    let mediaMimeType: String?
    /// Filename of media attachment, if any
    let mediaFilename: String?
    /// ID of message being quoted/replied to, if any
    let quotedMessageID: String?
    /// Reaction emoji (applicable when messageType is .reaction)
    let reactionEmoji: String?
}

// MARK: - Events

/// Types of events that can be subscribed to from a messaging provider.
enum MessagingEventType {
    /// A new message was received
    case messageReceived
    /// A message was successfully sent
    case messageSent
    /// Messages were marked as read
    case messageRead
    /// A chat's metadata was updated
    case chatUpdated
    /// Connection status changed
    case connectionStatus
}

/// Real-time events emitted by a messaging provider.
enum MessagingEvent {
    /// A new message was received in a chat
    case messageReceived(MessagingMessage)
    /// A message was successfully sent
    case messageSent(MessagingMessage)
    /// Messages in a chat were marked as read
    case messageRead(chatID: String, messageIDs: [String])
    /// A chat's metadata was updated (name, unread count, etc.)
    case chatUpdated(MessagingChat)
    /// The connection status changed
    case connectionStatus(MessagingConnectionStatus)
}

// MARK: - Pairing

/// Events emitted during the device pairing process.
enum PairingEvent {
    /// QR code data for scanning (base64 or raw data)
    case qrCode(String)
    /// Pairing code to enter on the mobile device
    case pairingCode(String)
    /// Pairing completed successfully
    case success(userID: String, displayName: String)
    /// Pairing timed out without completion
    case timeout
    /// Pairing failed with an error
    case error(String)
}
