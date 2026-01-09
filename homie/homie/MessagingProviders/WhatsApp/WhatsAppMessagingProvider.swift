//
//  WhatsAppMessagingProvider.swift
//  homie
//
//  Main WhatsApp provider conforming to MessagingProviderProtocol.
//  Manages the whatsapp-bridge subprocess and provides messaging capabilities.
//

import Foundation
import Combine
import SwiftProtobuf

@available(macOS 15.0, *)
class WhatsAppMessagingProvider: MessagingProviderProtocol, ObservableObject {
    // MARK: - Protocol Properties

    let providerID = "whatsapp"
    let displayName = "WhatsApp"

    @Published private(set) var connectionStatus: MessagingConnectionStatus = .disconnected
    @Published private(set) var isLoggedIn: Bool = false

    var connectionStatusPublisher: AnyPublisher<MessagingConnectionStatus, Never> {
        $connectionStatus.eraseToAnyPublisher()
    }

    // MARK: - Dependencies (Injected)

    private let processManager: WhatsAppProcessManager
    private(set) var grpcClient: WhatsAppGRPCClient?
    private let grpcConfiguration: WhatsAppGRPCConfiguration

    /// Returns true if the gRPC client is initialized and ready
    var grpcClientReady: Bool {
        grpcClient?.isTransportReady ?? false
    }

    // MARK: - Private State

    private var grpcRunTask: Task<Void, Error>?
    private var eventStreamTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(processManager: WhatsAppProcessManager, grpcConfiguration: WhatsAppGRPCConfiguration = .default) {
        self.processManager = processManager
        self.grpcConfiguration = grpcConfiguration
    }

    /// Convenience initializer with default configuration
    convenience init() {
        let processConfig = WhatsAppProcessConfiguration.default
        self.init(
            processManager: WhatsAppProcessManager(configuration: processConfig),
            grpcConfiguration: .default
        )
    }

    // MARK: - Lifecycle

    func start() async throws {
        Logger.info("Starting WhatsApp provider", module: "WhatsApp")

        // Start the bridge subprocess (waits for "ready" signal)
        try await processManager.start()

        // Create gRPC client
        let client = try WhatsAppGRPCClient(configuration: grpcConfiguration)
        self.grpcClient = client

        // Run the gRPC client connections in a background task
        grpcRunTask = Task {
            do {
                try await client.runConnections()
            } catch {
                Logger.error("gRPC runConnections ended: \(error)", module: "WhatsApp")
            }
        }

        // The Go bridge now signals "ready" only AFTER the gRPC server is listening.
        // So we can verify the connection immediately - no polling needed.
        do {
            let statusResponse = try await client.verifyConnection()
            isLoggedIn = statusResponse.isLoggedIn
            connectionStatus = convertConnectionStatus(statusResponse.status)
            Logger.info("WhatsApp provider started - logged in: \(isLoggedIn), status: \(connectionStatus)", module: "WhatsApp")

        } catch {
            Logger.error("Failed to verify gRPC connection: \(error.localizedDescription)", module: "WhatsApp")
            // Set error status but don't throw - allow app to continue
            connectionStatus = .error("Bridge connection failed")
        }
    }

    func stop() async {
        Logger.info("Stopping WhatsApp provider", module: "WhatsApp")

        // Cancel event stream
        eventStreamTask?.cancel()
        eventStreamTask = nil

        // Begin graceful shutdown of gRPC client
        grpcClient?.beginGracefulShutdown()
        grpcRunTask?.cancel()
        grpcRunTask = nil
        grpcClient = nil

        // Stop the subprocess
        processManager.stop()

        connectionStatus = .disconnected
    }

    // MARK: - Connection

    func connect() async throws {
        Logger.info("Connecting to WhatsApp", module: "WhatsApp")
        connectionStatus = .connecting

        guard let client = grpcClient else {
            throw MessagingProviderError.notConnected
        }

        do {
            let response = try await client.connectToWhatsApp()
            if response.success {
                connectionStatus = .connected
                Logger.info("Connected to WhatsApp successfully", module: "WhatsApp")
            } else {
                let errorMessage = response.errorMessage.isEmpty ? "Unknown error" : response.errorMessage
                connectionStatus = .error(errorMessage)
                throw MessagingProviderError.connectionFailed(errorMessage)
            }
        } catch let error as MessagingProviderError {
            throw error
        } catch {
            connectionStatus = .error(error.localizedDescription)
            Logger.error("Connection failed: \(error.localizedDescription)", module: "WhatsApp")
            throw MessagingProviderError.connectionFailed(error.localizedDescription)
        }
    }

    func disconnect() async {
        Logger.info("Disconnecting from WhatsApp", module: "WhatsApp")

        guard let client = grpcClient else { return }

        do {
            _ = try await client.disconnectFromWhatsApp()
        } catch {
            Logger.error("Disconnect error: \(error.localizedDescription)", module: "WhatsApp")
        }

        connectionStatus = .disconnected
    }

    // MARK: - Pairing

    func startQRPairing() -> AsyncThrowingStream<PairingEvent, Error> {
        Logger.info("Starting QR pairing", module: "WhatsApp")

        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                guard let self = self else {
                    continuation.finish(throwing: MessagingProviderError.notConnected)
                    return
                }

                // Check if already logged in - QR pairing is not available
                if self.isLoggedIn {
                    Logger.info("QR pairing: already logged in, cannot pair again", module: "WhatsApp")
                    continuation.yield(.error("Already logged in. Please disconnect first to pair a new device."))
                    continuation.finish()
                    return
                }

                guard let client = self.grpcClient else {
                    Logger.error("QR pairing: grpcClient is nil - provider not started?", module: "WhatsApp")
                    continuation.finish(throwing: MessagingProviderError.notConnected)
                    return
                }

                // Check transport readiness (should be instant if start() succeeded)
                guard client.isTransportReady else {
                    Logger.error("QR pairing: gRPC transport not ready", module: "WhatsApp")
                    continuation.yield(.error("WhatsApp bridge not ready. Please try again."))
                    continuation.finish()
                    return
                }

                await MainActor.run {
                    self.connectionStatus = .pairing
                }

                do {
                    Logger.info("QR pairing: calling client.getPairingQR()", module: "WhatsApp")
                    let qrStream = client.getPairingQR()

                    for try await protoEvent in qrStream {
                        let pairingEvent = self.convertPairingQREvent(protoEvent)
                        continuation.yield(pairingEvent)

                        // Check for success to update login status
                        if case .success(let userID, _) = pairingEvent {
                            Logger.info("QR pairing successful for user: \(userID)", module: "WhatsApp")
                            await MainActor.run {
                                self.isLoggedIn = true
                                self.connectionStatus = .connected
                            }
                        }
                    }

                    Logger.info("QR pairing: stream ended", module: "WhatsApp")
                    continuation.finish()
                } catch {
                    Logger.error("QR pairing error: \(error.localizedDescription)", module: "WhatsApp")
                    continuation.finish(throwing: MessagingProviderError.pairingFailed(error.localizedDescription))
                }
            }
        }
    }

    func startCodePairing(phoneNumber: String) async throws -> String {
        Logger.info("Starting code pairing for phone: \(phoneNumber.prefix(4))****", module: "WhatsApp")

        // Check if already logged in
        if isLoggedIn {
            Logger.info("Code pairing: already logged in, cannot pair again", module: "WhatsApp")
            throw MessagingProviderError.pairingFailed("Already logged in. Please disconnect first to pair a new device.")
        }

        guard let client = grpcClient else {
            Logger.error("Code pairing: grpcClient is nil", module: "WhatsApp")
            throw MessagingProviderError.notConnected
        }

        // Check transport readiness
        guard client.isTransportReady else {
            Logger.error("Code pairing: gRPC transport not ready", module: "WhatsApp")
            throw MessagingProviderError.connectionFailed("WhatsApp bridge not ready")
        }

        connectionStatus = .pairing

        do {
            let response = try await client.pairWithCode(phoneNumber: phoneNumber)

            if !response.errorMessage.isEmpty {
                Logger.error("Code pairing: server returned error: \(response.errorMessage)", module: "WhatsApp")
                connectionStatus = .error(response.errorMessage)
                throw MessagingProviderError.pairingFailed(response.errorMessage)
            }

            Logger.info("Code pairing: received pairing code", module: "WhatsApp")
            return response.pairingCode
        } catch let error as MessagingProviderError {
            throw error
        } catch {
            connectionStatus = .error(error.localizedDescription)
            Logger.error("Code pairing failed: \(error.localizedDescription)", module: "WhatsApp")
            throw MessagingProviderError.pairingFailed(error.localizedDescription)
        }
    }

    func logout() async throws {
        Logger.info("Logging out from WhatsApp", module: "WhatsApp")

        guard let client = grpcClient else {
            throw MessagingProviderError.notConnected
        }

        do {
            let response = try await client.logout()

            if !response.success {
                let errorMessage = response.errorMessage.isEmpty ? "Logout failed" : response.errorMessage
                throw MessagingProviderError.sendFailed(errorMessage)
            }

            isLoggedIn = false
            connectionStatus = .disconnected
            Logger.info("Logged out successfully", module: "WhatsApp")
        } catch let error as MessagingProviderError {
            throw error
        } catch {
            Logger.error("Logout failed: \(error.localizedDescription)", module: "WhatsApp")
            throw error
        }
    }

    // MARK: - Repository

    func getChats(limit: Int, offset: Int) async throws -> [MessagingChat] {
        Logger.info("Getting chats (limit: \(limit), offset: \(offset))", module: "WhatsApp")

        guard connectionStatus.isConnected else {
            throw MessagingProviderError.notConnected
        }

        guard isLoggedIn else {
            throw MessagingProviderError.notLoggedIn
        }

        guard let client = grpcClient else {
            throw MessagingProviderError.notConnected
        }

        do {
            let response = try await client.getChats(limit: limit, offset: offset, includeArchived: false)
            let chats = response.chats.map { convertChat($0) }
            Logger.info("Retrieved \(chats.count) chats", module: "WhatsApp")
            return chats
        } catch {
            Logger.error("Failed to get chats: \(error.localizedDescription)", module: "WhatsApp")
            throw error
        }
    }

    func getMessages(chatID: String, limit: Int, beforeID: String?) async throws -> [MessagingMessage] {
        Logger.info("Getting messages for chat: \(chatID) (limit: \(limit))", module: "WhatsApp")

        guard connectionStatus.isConnected else {
            throw MessagingProviderError.notConnected
        }

        guard isLoggedIn else {
            throw MessagingProviderError.notLoggedIn
        }

        guard let client = grpcClient else {
            throw MessagingProviderError.notConnected
        }

        let jid = parseJID(chatID)

        do {
            let response = try await client.getMessages(
                chatJID: jid,
                limit: limit,
                beforeMessageID: beforeID,
                afterMessageID: nil
            )
            let messages = response.messages.map { convertMessage($0) }
            Logger.info("Retrieved \(messages.count) messages", module: "WhatsApp")
            return messages
        } catch {
            Logger.error("Failed to get messages: \(error.localizedDescription)", module: "WhatsApp")
            throw error
        }
    }

    // MARK: - Service Adapter

    func sendMessage(chatID: String, text: String, quotedMessageID: String?) async throws -> MessagingMessage {
        Logger.info("Sending message to chat: \(chatID)", module: "WhatsApp")

        guard connectionStatus.isConnected else {
            throw MessagingProviderError.notConnected
        }

        guard isLoggedIn else {
            throw MessagingProviderError.notLoggedIn
        }

        guard let client = grpcClient else {
            throw MessagingProviderError.notConnected
        }

        let jid = parseJID(chatID)

        do {
            let response = try await client.sendMessage(
                chatJID: jid,
                text: text,
                quotedMessageID: quotedMessageID
            )

            if !response.errorMessage.isEmpty {
                throw MessagingProviderError.sendFailed(response.errorMessage)
            }

            let message = convertMessage(response.message)
            Logger.info("Message sent successfully: \(message.id)", module: "WhatsApp")
            return message
        } catch let error as MessagingProviderError {
            throw error
        } catch {
            Logger.error("Failed to send message: \(error.localizedDescription)", module: "WhatsApp")
            throw MessagingProviderError.sendFailed(error.localizedDescription)
        }
    }

    func sendReaction(chatID: String, messageID: String, emoji: String) async throws {
        Logger.info("Sending reaction '\(emoji)' to message: \(messageID)", module: "WhatsApp")

        guard connectionStatus.isConnected else {
            throw MessagingProviderError.notConnected
        }

        guard isLoggedIn else {
            throw MessagingProviderError.notLoggedIn
        }

        guard let client = grpcClient else {
            throw MessagingProviderError.notConnected
        }

        let jid = parseJID(chatID)

        do {
            let response = try await client.sendReaction(
                chatJID: jid,
                messageID: messageID,
                emoji: emoji
            )

            if !response.success {
                let errorMessage = response.errorMessage.isEmpty ? "Failed to send reaction" : response.errorMessage
                throw MessagingProviderError.sendFailed(errorMessage)
            }

            Logger.info("Reaction sent successfully", module: "WhatsApp")
        } catch let error as MessagingProviderError {
            throw error
        } catch {
            Logger.error("Failed to send reaction: \(error.localizedDescription)", module: "WhatsApp")
            throw MessagingProviderError.sendFailed(error.localizedDescription)
        }
    }

    func markAsRead(chatID: String, messageIDs: [String]) async throws {
        Logger.info("Marking \(messageIDs.count) messages as read in chat: \(chatID)", module: "WhatsApp")

        guard connectionStatus.isConnected else {
            throw MessagingProviderError.notConnected
        }

        guard isLoggedIn else {
            throw MessagingProviderError.notLoggedIn
        }

        guard let client = grpcClient else {
            throw MessagingProviderError.notConnected
        }

        let jid = parseJID(chatID)

        do {
            let response = try await client.markAsRead(chatJID: jid, messageIDs: messageIDs)

            if !response.success {
                let errorMessage = response.errorMessage.isEmpty ? "Failed to mark as read" : response.errorMessage
                throw MessagingProviderError.sendFailed(errorMessage)
            }

            Logger.info("Messages marked as read", module: "WhatsApp")
        } catch let error as MessagingProviderError {
            throw error
        } catch {
            Logger.error("Failed to mark as read: \(error.localizedDescription)", module: "WhatsApp")
            throw error
        }
    }

    // MARK: - Events

    func subscribeToEvents(types: [MessagingEventType]) -> AsyncStream<MessagingEvent> {
        Logger.info("Subscribing to events: \(types)", module: "WhatsApp")

        let protoTypes = types.map { convertToProtoEventType($0) }

        return AsyncStream { continuation in
            eventStreamTask?.cancel()

            eventStreamTask = Task { [weak self] in
                guard let self = self, let client = self.grpcClient else {
                    continuation.finish()
                    return
                }

                do {
                    let eventStream = client.streamEvents(types: protoTypes)

                    for try await protoEvent in eventStream {
                        if Task.isCancelled {
                            break
                        }

                        if let event = self.convertEvent(protoEvent) {
                            // Update internal state for connection status events
                            if case .connectionStatus(let status) = event {
                                await MainActor.run {
                                    self.connectionStatus = status
                                    if status.isConnected {
                                        self.isLoggedIn = true
                                    } else if case .disconnected = status {
                                        self.isLoggedIn = false
                                    }
                                }
                            }
                            continuation.yield(event)
                        }
                    }

                    continuation.finish()
                } catch {
                    Logger.error("Event stream error: \(error.localizedDescription)", module: "WhatsApp")
                    continuation.finish()
                }
            }

            continuation.onTermination = { [weak self] _ in
                self?.eventStreamTask?.cancel()
            }
        }
    }

    // MARK: - Conversion Helpers

    private func convertChat(_ proto: Whatsapp_V1_Chat) -> MessagingChat {
        let chatType: MessagingChat.ChatType
        switch proto.type {
        case .group:
            chatType = .group
        case .private, .unspecified, .UNRECOGNIZED:
            chatType = .individual
        }

        return MessagingChat(
            id: formatJID(proto.jid),
            name: proto.name,
            chatType: chatType,
            lastMessageTime: proto.hasLastMessageTime ? convertTimestamp(proto.lastMessageTime) : nil,
            lastMessageText: proto.lastMessageText.isEmpty ? nil : proto.lastMessageText,
            lastMessageSenderName: nil, // Not available in proto
            unreadCount: Int(proto.unreadCount),
            isArchived: proto.isArchived,
            isMuted: proto.isMuted
        )
    }

    private func convertMessage(_ proto: Whatsapp_V1_Message) -> MessagingMessage {
        let messageType: MessagingMessage.MessageType
        switch proto.type {
        case .text:
            messageType = .text
        case .image:
            messageType = .image
        case .video:
            messageType = .video
        case .audio:
            messageType = .audio
        case .document:
            messageType = .document
        case .sticker:
            messageType = .sticker
        case .reaction:
            messageType = .reaction
        case .location:
            messageType = .location
        case .unspecified, .UNRECOGNIZED:
            messageType = .text
        }

        return MessagingMessage(
            id: proto.id,
            chatID: formatJID(proto.chatJid),
            senderID: formatJID(proto.senderJid),
            senderName: nil, // Would need to resolve from contacts
            text: proto.text,
            timestamp: proto.hasTimestamp ? convertTimestamp(proto.timestamp) : Date(),
            isFromMe: proto.isFromMe,
            isRead: proto.isRead,
            messageType: messageType,
            mediaURL: proto.mediaURL.isEmpty ? nil : proto.mediaURL,
            mediaMimeType: proto.mediaMimeType.isEmpty ? nil : proto.mediaMimeType,
            mediaFilename: proto.mediaFilename.isEmpty ? nil : proto.mediaFilename,
            quotedMessageID: proto.quotedMessageID.isEmpty ? nil : proto.quotedMessageID,
            reactionEmoji: proto.hasReaction ? proto.reaction.emoji : nil
        )
    }

    private func convertEvent(_ proto: Whatsapp_V1_WhatsAppEvent) -> MessagingEvent? {
        switch proto.type {
        case .messageReceived:
            guard case .messageEvent(let msgEvent) = proto.payload else { return nil }
            let message = convertMessage(msgEvent.message)
            return .messageReceived(message)

        case .messageSent:
            guard case .messageEvent(let msgEvent) = proto.payload else { return nil }
            let message = convertMessage(msgEvent.message)
            return .messageSent(message)

        case .messageRead:
            // Message read events don't have a specific payload in our proto
            // Return nil or implement based on actual proto structure
            return nil

        case .chatUpdated:
            guard case .chatEvent(let chatEvent) = proto.payload else { return nil }
            let chat = convertChat(chatEvent.chat)
            return .chatUpdated(chat)

        case .connectionStatus:
            guard case .connectionEvent(let connEvent) = proto.payload else { return nil }
            let status = convertConnectionStatus(connEvent.status)
            return .connectionStatus(status)

        case .unspecified, .UNRECOGNIZED:
            return nil
        }
    }

    private func convertPairingQREvent(_ proto: Whatsapp_V1_PairingQREvent) -> PairingEvent {
        switch proto.payload {
        case .qrCode(let code):
            Logger.info("Provider: Converting QR code, length: \(code.count)", module: "WhatsApp")
            return .qrCode(code)
        case .timeout:
            return .timeout
        case .success(let successInfo):
            let userID = formatJID(successInfo.userJid)
            return .success(userID: userID, displayName: successInfo.pushName)
        case .error(let errorMessage):
            return .error(errorMessage)
        case .none:
            return .error("Unknown pairing event")
        }
    }

    private func convertConnectionStatus(_ proto: Whatsapp_V1_ConnectionStatus) -> MessagingConnectionStatus {
        switch proto {
        case .disconnected:
            return .disconnected
        case .connecting:
            return .connecting
        case .connected:
            return .connected
        case .unspecified, .UNRECOGNIZED:
            return .disconnected
        }
    }

    private func convertToProtoEventType(_ type: MessagingEventType) -> Whatsapp_V1_EventType {
        switch type {
        case .messageReceived:
            return .messageReceived
        case .messageSent:
            return .messageSent
        case .messageRead:
            return .messageRead
        case .chatUpdated:
            return .chatUpdated
        case .connectionStatus:
            return .connectionStatus
        }
    }

    /// Parse a chat ID string in "user@server" format to a JID
    private func parseJID(_ chatID: String) -> Whatsapp_V1_JID {
        let components = chatID.split(separator: "@", maxSplits: 1)

        var jid = Whatsapp_V1_JID()
        jid.user = String(components.first ?? "")
        jid.server = components.count > 1 ? String(components[1]) : "s.whatsapp.net"
        return jid
    }

    /// Format a JID to "user@server" string
    private func formatJID(_ jid: Whatsapp_V1_JID) -> String {
        guard !jid.user.isEmpty else { return "" }
        return "\(jid.user)@\(jid.server)"
    }

    /// Convert SwiftProtobuf.Google_Protobuf_Timestamp to Date
    private func convertTimestamp(_ timestamp: SwiftProtobuf.Google_Protobuf_Timestamp) -> Date {
        let seconds = TimeInterval(timestamp.seconds)
        let nanos = TimeInterval(timestamp.nanos) / 1_000_000_000
        return Date(timeIntervalSince1970: seconds + nanos)
    }
}
