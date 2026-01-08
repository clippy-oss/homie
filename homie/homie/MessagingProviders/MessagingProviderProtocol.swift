//
//  MessagingProviderProtocol.swift
//  homie
//
//  Protocol defining the interface for messaging provider implementations.
//  Enables future providers (Telegram, Signal, etc.) without changing core architecture.
//

import Foundation
import Combine

/// Protocol that all messaging provider implementations must conform to.
/// Provides a provider-agnostic interface for messaging capabilities.
protocol MessagingProviderProtocol: AnyObject {
    /// Unique identifier for this provider (e.g., "whatsapp", "telegram")
    var providerID: String { get }

    /// Display name for UI (e.g., "WhatsApp", "Telegram")
    var displayName: String { get }

    /// Current connection status to the messaging service
    var connectionStatus: MessagingConnectionStatus { get }

    /// Publisher for connection status changes
    var connectionStatusPublisher: AnyPublisher<MessagingConnectionStatus, Never> { get }

    /// Whether the provider is currently connected to the messaging service
    var isConnected: Bool { get }

    /// Whether the user is logged in / device is paired
    var isLoggedIn: Bool { get }

    // MARK: - Lifecycle (Subprocess Management)

    /// Start the provider (spawn subprocess if needed, initialize connections)
    func start() async throws

    /// Stop the provider (cleanup subprocess, close connections)
    func stop() async

    // MARK: - Connection (To Messaging Service)

    /// Connect to the messaging service servers
    func connect() async throws

    /// Disconnect from the messaging service servers
    func disconnect() async

    // MARK: - Authentication & Pairing

    /// Stream QR codes for device pairing.
    /// Yields new QR codes on timeout/refresh until pairing succeeds or is cancelled.
    /// - Returns: AsyncThrowingStream of pairing events (QR codes, success, timeout, error)
    func startQRPairing() -> AsyncThrowingStream<PairingEvent, Error>

    /// Pair using phone number.
    /// - Parameter phoneNumber: Phone number in international format (e.g., "+1234567890")
    /// - Returns: Pairing code to enter on the mobile device
    func startCodePairing(phoneNumber: String) async throws -> String

    /// Logout and clear device pairing.
    /// After logout, re-pairing is required to use the provider again.
    func logout() async throws

    // MARK: - Repository (Read Operations)

    /// Get list of chats sorted by most recent activity.
    /// - Parameters:
    ///   - limit: Maximum number of chats to return
    ///   - offset: Number of chats to skip (for pagination)
    /// - Returns: Array of chats
    func getChats(limit: Int, offset: Int) async throws -> [MessagingChat]

    /// Get messages from a specific chat.
    /// - Parameters:
    ///   - chatID: The chat identifier (JID format for WhatsApp)
    ///   - limit: Maximum number of messages to return
    ///   - beforeID: Return messages before this message ID (for pagination)
    /// - Returns: Array of messages, sorted by timestamp descending
    func getMessages(chatID: String, limit: Int, beforeID: String?) async throws -> [MessagingMessage]

    // MARK: - Service Adapter (Write Operations)

    /// Send a text message to a chat.
    /// - Parameters:
    ///   - chatID: The chat identifier
    ///   - text: The message text
    ///   - quotedMessageID: Optional message ID to quote/reply to
    /// - Returns: The sent message
    func sendMessage(chatID: String, text: String, quotedMessageID: String?) async throws -> MessagingMessage

    /// Send a reaction to a message.
    /// - Parameters:
    ///   - chatID: The chat identifier
    ///   - messageID: The message ID to react to
    ///   - emoji: The reaction emoji (e.g., "👍", "❤️")
    func sendReaction(chatID: String, messageID: String, emoji: String) async throws

    /// Mark messages as read.
    /// - Parameters:
    ///   - chatID: The chat identifier
    ///   - messageIDs: Array of message IDs to mark as read
    func markAsRead(chatID: String, messageIDs: [String]) async throws

    // MARK: - Real-time Events

    /// Subscribe to real-time events from the messaging service.
    /// - Parameter types: Event types to subscribe to (empty for all events)
    /// - Returns: AsyncStream of messaging events
    func subscribeToEvents(types: [MessagingEventType]) -> AsyncStream<MessagingEvent>
}

// MARK: - Default Implementations

extension MessagingProviderProtocol {
    var isConnected: Bool {
        connectionStatus.isConnected
    }
}

// MARK: - Error Types

/// Errors that can occur in messaging provider operations
enum MessagingProviderError: LocalizedError {
    case notConnected
    case notLoggedIn
    case processNotRunning
    case connectionFailed(String)
    case pairingFailed(String)
    case sendFailed(String)
    case invalidChatID(String)
    case operationCancelled

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to messaging service"
        case .notLoggedIn:
            return "Not logged in - device pairing required"
        case .processNotRunning:
            return "Messaging bridge process is not running"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .pairingFailed(let message):
            return "Pairing failed: \(message)"
        case .sendFailed(let message):
            return "Send failed: \(message)"
        case .invalidChatID(let id):
            return "Invalid chat ID: \(id)"
        case .operationCancelled:
            return "Operation was cancelled"
        }
    }
}
