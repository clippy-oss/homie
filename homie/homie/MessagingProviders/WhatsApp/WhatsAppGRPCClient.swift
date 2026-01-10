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
        guard case .ready = transportState.state else { return false }
        return true
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
                    Logger.info("gRPC: calling getPairingQR - sending request to server...", module: "WhatsApp")
                    let request = Whatsapp_V1_GetPairingQRRequest()

                    let result = try await self.serviceClient.getPairingQR(request) { response in
                        Logger.info("gRPC: getPairingQR - server accepted request, stream opened", module: "WhatsApp")

                        // Check for immediate error in response metadata
                        if case .failure(let error) = response.accepted {
                            Logger.error("gRPC: getPairingQR - server rejected request: \(error)", module: "WhatsApp")
                            continuation.finish(throwing: WhatsAppGRPCError.rpcFailed(String(describing: error)))
                            return
                        }

                        Logger.info("gRPC: getPairingQR - waiting for QR code events...", module: "WhatsApp")
                        var eventCount = 0
                        for try await event in response.messages {
                            eventCount += 1
                            let eventType: String
                            switch event.payload {
                            case .qrCode(let code):
                                eventType = "qrCode"
                                Logger.info("gRPC: QR code received, length: \(code.count), preview: \(code.prefix(50))...", module: "WhatsApp")
                            case .timeout: eventType = "timeout"
                            case .success: eventType = "success"
                            case .error(let msg): eventType = "error(\(msg))"
                            case .none: eventType = "none"
                            }
                            Logger.info("gRPC: getPairingQR - received event #\(eventCount): \(eventType)", module: "WhatsApp")
                            continuation.yield(event)
                        }
                        Logger.info("gRPC: getPairingQR - stream ended after \(eventCount) events", module: "WhatsApp")
                        continuation.finish()
                    }

                    Logger.info("gRPC: getPairingQR - call completed with result: \(type(of: result))", module: "WhatsApp")
                } catch {
                    Logger.error("gRPC: getPairingQR - RPC failed: \(error)", module: "WhatsApp")

                    // Parse the error to provide a user-friendly message
                    let userMessage = Self.parseGRPCError(error)
                    Logger.error("gRPC: getPairingQR - user message: \(userMessage)", module: "WhatsApp")
                    continuation.finish(throwing: WhatsAppGRPCError.rpcFailed(userMessage))
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
            let userMessage = Self.parseGRPCError(error)
            throw WhatsAppGRPCError.rpcFailed(userMessage)
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

    // MARK: - Error Parsing

    /// Converts gRPC errors into user-friendly messages
    static func parseGRPCError(_ error: Error) -> String {
        let errorString = String(describing: error)

        // Check for known error patterns and provide user-friendly messages

        // QR Channel errors - these occur when there's a stored device credential
        if errorString.contains("GetQRChannel must be called before connecting") {
            return "A stale WhatsApp session exists locally. Please restart the app to clear it, or delete the WhatsApp database files."
        }

        if errorString.contains("already logged in") {
            return "A stale WhatsApp session exists locally. Please restart the app to clear it, or delete the WhatsApp database files."
        }

        if errorString.contains("already connected") || errorString.contains("AlreadyConnected") {
            return "WhatsApp is already connected. Disconnect first to pair a new device."
        }

        // Connection errors
        if errorString.contains("connection refused") || errorString.contains("ECONNREFUSED") {
            return "Unable to connect to WhatsApp bridge. Please ensure the service is running."
        }

        if errorString.contains("timeout") || errorString.contains("deadline exceeded") {
            return "Connection timed out. Please check your network and try again."
        }

        if errorString.contains("unavailable") || errorString.contains("UNAVAILABLE") {
            return "WhatsApp service is temporarily unavailable. Please try again later."
        }

        // Authentication errors
        if errorString.contains("not logged in") || errorString.contains("NotLoggedIn") {
            return "Not logged in to WhatsApp. Please complete the pairing process first."
        }

        if errorString.contains("session expired") || errorString.contains("logged out") {
            return "Your WhatsApp session has expired. Please pair your device again."
        }

        // Pairing errors
        if errorString.contains("invalid phone number") || errorString.contains("InvalidPhoneNumber") {
            return "Invalid phone number format. Please enter your phone number with country code (e.g., +1234567890)."
        }

        if errorString.contains("rate limit") || errorString.contains("too many requests") {
            return "Too many pairing attempts. Please wait a few minutes before trying again."
        }

        // gRPC status code patterns
        if errorString.contains("RPCError error 1") || errorString.contains("CANCELLED") {
            return "Request was cancelled. Please try again."
        }

        if errorString.contains("RPCError error 2") || errorString.contains("UNKNOWN") {
            return "An unexpected error occurred. Please try again."
        }

        if errorString.contains("RPCError error 9") || errorString.contains("FAILED_PRECONDITION") ||
           errorString.contains("FailedPrecondition") {
            // Extract the actual message if available
            if let range = errorString.range(of: "failed to get QR channel:") {
                let message = errorString[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if message.contains("must be called before connecting") {
                    return "Device is already connected. Please disconnect first before pairing a new device."
                }
            }
            return "Operation cannot be performed in the current state. Please disconnect and try again."
        }

        if errorString.contains("RPCError error 14") || errorString.contains("UNAVAILABLE") {
            return "WhatsApp bridge service is not available. Please ensure it's running."
        }

        // Network errors
        if errorString.contains("no route to host") || errorString.contains("network unreachable") {
            return "Network error. Please check your internet connection."
        }

        // Default: return a cleaned up version of the error
        // Try to extract meaningful message from the error
        if let detailRange = errorString.range(of: "message: \"") {
            let afterMessage = errorString[detailRange.upperBound...]
            if let endQuote = afterMessage.firstIndex(of: "\"") {
                let extractedMessage = String(afterMessage[..<endQuote])
                if !extractedMessage.isEmpty {
                    return extractedMessage
                }
            }
        }

        // Fallback: provide a generic message with technical details for debugging
        return "Connection error occurred. Please try again. (Technical: \(errorString.prefix(100)))"
    }
}
