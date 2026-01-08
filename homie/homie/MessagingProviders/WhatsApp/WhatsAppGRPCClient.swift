//
//  WhatsAppGRPCClient.swift
//  homie
//
//  gRPC client for communicating with the whatsapp-bridge service.
//  Uses grpc-swift 2.x with NIO HTTP/2 transport.
//

import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2Posix

// MARK: - Configuration

struct WhatsAppGRPCConfiguration: Sendable {
    let host: String
    let port: Int

    static var `default`: WhatsAppGRPCConfiguration {
        WhatsAppGRPCConfiguration(host: "127.0.0.1", port: 50051)
    }
}

// MARK: - Transport State

/// Represents the state of the gRPC transport connection
enum GRPCTransportState: Sendable {
    case idle
    case connecting
    case ready
    case failed(String)
}

/// Thread-safe holder for transport state
private final class TransportStateHolder: @unchecked Sendable {
    private var _state: GRPCTransportState = .idle
    private let lock = NSLock()

    var state: GRPCTransportState {
        lock.lock()
        defer { lock.unlock() }
        return _state
    }

    func setState(_ newState: GRPCTransportState) {
        lock.lock()
        defer { lock.unlock() }
        _state = newState
    }
}

// MARK: - Errors

enum WhatsAppGRPCError: Error, LocalizedError {
    case notConnected
    case connectionFailed(String)
    case rpcFailed(String)
    case transportNotReady

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "gRPC client not connected"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .rpcFailed(let message):
            return "RPC failed: \(message)"
        case .transportNotReady:
            return "gRPC transport not ready"
        }
    }
}

// MARK: - Client

@available(macOS 15.0, *)
final class WhatsAppGRPCClient: Sendable {
    private let configuration: WhatsAppGRPCConfiguration
    private let grpcClient: GRPCClient<HTTP2ClientTransport.Posix>
    private let serviceClient: Whatsapp_V1_WhatsAppService.Client<HTTP2ClientTransport.Posix>

    // Transport state management
    private let transportState = TransportStateHolder()

    /// Returns true if the gRPC transport is ready for RPCs
    var isTransportReady: Bool {
        if case .ready = transportState.state { return true }
        return false
    }

    // MARK: - Initialization

    init(configuration: WhatsAppGRPCConfiguration = .default) throws {
        self.configuration = configuration

        let transport = try HTTP2ClientTransport.Posix(
            target: .ipv4(host: configuration.host, port: configuration.port),
            transportSecurity: .plaintext
        )

        self.grpcClient = GRPCClient(transport: transport)
        self.serviceClient = Whatsapp_V1_WhatsAppService.Client(wrapping: grpcClient)
    }

    // MARK: - Lifecycle

    /// Run the client connections (must be called to start processing RPCs)
    ///
    /// This method starts the gRPC transport and runs indefinitely until shutdown.
    /// The Go bridge signals "ready" only after the gRPC server is listening,
    /// so RPCs can be made immediately after this is called.
    func runConnections() async throws {
        transportState.setState(.connecting)
        Logger.info("gRPC: Starting transport connection...", module: "WhatsApp")

        do {
            // grpc-swift 2.x handles connection management internally.
            // RPCs will be queued until the connection is established.
            try await grpcClient.runConnections()
        } catch {
            Logger.error("gRPC: runConnections ended with error: \(error)", module: "WhatsApp")
            transportState.setState(.failed(error.localizedDescription))
            throw error
        }
    }

    /// Verify the connection by making a test RPC
    ///
    /// Since the Go bridge now signals "ready" only after the gRPC server is listening,
    /// this should succeed immediately. Returns the connection status.
    func verifyConnection() async throws -> Whatsapp_V1_GetConnectionStatusResponse {
        Logger.info("gRPC: Verifying connection...", module: "WhatsApp")

        let request = Whatsapp_V1_GetConnectionStatusRequest()
        let response = try await serviceClient.getConnectionStatus(request)

        transportState.setState(.ready)
        Logger.info("gRPC: Connection verified successfully", module: "WhatsApp")
        return response
    }

    /// Begin graceful shutdown of the client
    func beginGracefulShutdown() {
        Logger.info("gRPC: Beginning graceful shutdown", module: "WhatsApp")
        grpcClient.beginGracefulShutdown()
    }

    // MARK: - Connection

    func connectToWhatsApp() async throws -> Whatsapp_V1_ConnectResponse {
        let request = Whatsapp_V1_ConnectRequest()
        return try await serviceClient.connect(request)
    }

    func disconnectFromWhatsApp() async throws -> Whatsapp_V1_DisconnectResponse {
        let request = Whatsapp_V1_DisconnectRequest()
        return try await serviceClient.disconnect(request)
    }

    func getConnectionStatus() async throws -> Whatsapp_V1_GetConnectionStatusResponse {
        let request = Whatsapp_V1_GetConnectionStatusRequest()
        return try await serviceClient.getConnectionStatus(request)
    }

    // MARK: - Pairing & Auth

    func getPairingQR() -> AsyncThrowingStream<Whatsapp_V1_PairingQREvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    Logger.info("gRPC: calling getPairingQR...", module: "WhatsApp")
                    let request = Whatsapp_V1_GetPairingQRRequest()
                    try await self.serviceClient.getPairingQR(request) { response in
                        Logger.info("gRPC: getPairingQR response received, waiting for messages...", module: "WhatsApp")
                        for try await event in response.messages {
                            Logger.info("gRPC: received pairing event", module: "WhatsApp")
                            continuation.yield(event)
                        }
                        Logger.info("gRPC: getPairingQR stream finished", module: "WhatsApp")
                        continuation.finish()
                    }
                    Logger.info("gRPC: getPairingQR call completed", module: "WhatsApp")
                } catch {
                    Logger.error("gRPC: getPairingQR error: \(error)", module: "WhatsApp")
                    continuation.finish(throwing: WhatsAppGRPCError.rpcFailed(error.localizedDescription))
                }
            }
        }
    }

    func pairWithCode(phoneNumber: String) async throws -> Whatsapp_V1_PairWithCodeResponse {
        Logger.info("gRPC: pairWithCode called for phone: \(phoneNumber.prefix(4))****", module: "WhatsApp")

        var request = Whatsapp_V1_PairWithCodeRequest()
        request.phoneNumber = phoneNumber

        do {
            let response = try await serviceClient.pairWithCode(request)
            Logger.info("gRPC: pairWithCode response - code: \(response.pairingCode.isEmpty ? "empty" : "received"), error: \(response.errorMessage.isEmpty ? "none" : response.errorMessage)", module: "WhatsApp")
            return response
        } catch {
            Logger.error("gRPC: pairWithCode failed: \(error)", module: "WhatsApp")
            throw error
        }
    }

    func logout() async throws -> Whatsapp_V1_LogoutResponse {
        let request = Whatsapp_V1_LogoutRequest()
        return try await serviceClient.logout(request)
    }

    // MARK: - Chats

    func getChats(limit: Int, offset: Int, includeArchived: Bool) async throws -> Whatsapp_V1_GetChatsResponse {
        var request = Whatsapp_V1_GetChatsRequest()
        request.limit = Int32(limit)
        request.offset = Int32(offset)
        request.includeArchived = includeArchived
        return try await serviceClient.getChats(request)
    }

    func getChat(jid: Whatsapp_V1_JID) async throws -> Whatsapp_V1_GetChatResponse {
        var request = Whatsapp_V1_GetChatRequest()
        request.jid = jid
        return try await serviceClient.getChat(request)
    }

    // MARK: - Messages

    func getMessages(
        chatJID: Whatsapp_V1_JID,
        limit: Int,
        beforeMessageID: String?,
        afterMessageID: String?
    ) async throws -> Whatsapp_V1_GetMessagesResponse {
        var request = Whatsapp_V1_GetMessagesRequest()
        request.chatJid = chatJID
        request.limit = Int32(limit)
        if let beforeMessageID = beforeMessageID {
            request.beforeMessageID = beforeMessageID
        }
        if let afterMessageID = afterMessageID {
            request.afterMessageID = afterMessageID
        }
        return try await serviceClient.getMessages(request)
    }

    func sendMessage(
        chatJID: Whatsapp_V1_JID,
        text: String,
        quotedMessageID: String?
    ) async throws -> Whatsapp_V1_SendMessageResponse {
        var request = Whatsapp_V1_SendMessageRequest()
        request.chatJid = chatJID
        request.text = text
        if let quotedMessageID = quotedMessageID {
            request.quotedMessageID = quotedMessageID
        }
        return try await serviceClient.sendMessage(request)
    }

    func sendReaction(
        chatJID: Whatsapp_V1_JID,
        messageID: String,
        emoji: String
    ) async throws -> Whatsapp_V1_SendReactionResponse {
        var request = Whatsapp_V1_SendReactionRequest()
        request.chatJid = chatJID
        request.messageID = messageID
        request.emoji = emoji
        return try await serviceClient.sendReaction(request)
    }

    func markAsRead(
        chatJID: Whatsapp_V1_JID,
        messageIDs: [String]
    ) async throws -> Whatsapp_V1_MarkAsReadResponse {
        var request = Whatsapp_V1_MarkAsReadRequest()
        request.chatJid = chatJID
        request.messageIds = messageIDs
        return try await serviceClient.markAsRead(request)
    }

    // MARK: - Events

    func streamEvents(types: [Whatsapp_V1_EventType]) -> AsyncThrowingStream<Whatsapp_V1_WhatsAppEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    var request = Whatsapp_V1_StreamEventsRequest()
                    request.eventTypes = types
                    try await self.serviceClient.streamEvents(request) { response in
                        for try await event in response.messages {
                            continuation.yield(event)
                        }
                        continuation.finish()
                    }
                } catch {
                    continuation.finish(throwing: WhatsAppGRPCError.rpcFailed(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Helpers

    static func makeJID(user: String, server: String = "s.whatsapp.net") -> Whatsapp_V1_JID {
        var jid = Whatsapp_V1_JID()
        jid.user = user
        jid.server = server
        return jid
    }
}
