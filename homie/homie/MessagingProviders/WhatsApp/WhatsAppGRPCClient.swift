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

// MARK: - Errors

enum WhatsAppGRPCError: Error, LocalizedError {
    case notConnected
    case connectionFailed(String)
    case rpcFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "gRPC client not connected"
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .rpcFailed(let message):
            return "RPC failed: \(message)"
        }
    }
}

// MARK: - Client

@available(macOS 15.0, *)
final class WhatsAppGRPCClient: Sendable {
    private let configuration: WhatsAppGRPCConfiguration
    private let grpcClient: GRPCClient<HTTP2ClientTransport.Posix>
    private let serviceClient: Whatsapp_V1_WhatsAppService.Client<HTTP2ClientTransport.Posix>

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
    func runConnections() async throws {
        try await grpcClient.runConnections()
    }

    /// Begin graceful shutdown of the client
    func beginGracefulShutdown() {
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
                    let request = Whatsapp_V1_GetPairingQRRequest()
                    try await self.serviceClient.getPairingQR(request) { response in
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

    func pairWithCode(phoneNumber: String) async throws -> Whatsapp_V1_PairWithCodeResponse {
        var request = Whatsapp_V1_PairWithCodeRequest()
        request.phoneNumber = phoneNumber
        return try await serviceClient.pairWithCode(request)
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
