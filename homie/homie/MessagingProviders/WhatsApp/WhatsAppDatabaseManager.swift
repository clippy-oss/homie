//
//  WhatsAppDatabaseManager.swift
//  homie
//
//  Database manager for reading WhatsApp dummy database
//

import Foundation
import SQLite3

// SQLITE_TRANSIENT tells SQLite to copy the string (not available in Swift's SQLite3 module)
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

@MainActor
class WhatsAppDatabaseManager: ObservableObject {
    static let shared = WhatsAppDatabaseManager()
    
    private var db: OpaquePointer?
    private let dbPath: String
    
    @Published var chats: [WhatsAppChat] = []
    @Published var messages: [String: [WhatsAppMessage]] = [:] // Keyed by chat JID
    
    private init() {
        // Look for dummy database in whatsapp-bridge directory
        // Try multiple possible locations
        let fileManager = FileManager.default
        var possiblePaths: [String] = []
        
        // Try relative to current working directory
        let currentDir = fileManager.currentDirectoryPath
        possiblePaths.append("\(currentDir)/whatsapp-bridge/dummy_whatsapp.db")
        
        // Try relative to home directory
        let homeDir = NSHomeDirectory()
        possiblePaths.append("\(homeDir)/CursorProjects/homie_project/whatsapp-bridge/dummy_whatsapp.db")
        
        // Try absolute path
        possiblePaths.append("/Users/maxprokopp/CursorProjects/homie_project/whatsapp-bridge/dummy_whatsapp.db")
        
        // Try relative to executable (for Xcode builds)
        if let execPath = Bundle.main.executablePath {
            let execDir = (execPath as NSString).deletingLastPathComponent
            let projectRoot = (execDir as NSString).deletingLastPathComponent
            possiblePaths.append("\(projectRoot)/whatsapp-bridge/dummy_whatsapp.db")
        }
        
        // Find the first existing path
        var foundPath: String?
        for path in possiblePaths {
            if fileManager.fileExists(atPath: path) {
                foundPath = path
                break
            }
        }
        
        self.dbPath = foundPath ?? possiblePaths.last!
        
        if foundPath != nil {
            openDatabase()
            loadChats()
        } else {
            Logger.warning("Dummy WhatsApp database not found at any expected path. Tried: \(possiblePaths)", module: "WhatsAppDB")
        }
    }
    
    private func openDatabase() {
        guard sqlite3_open(dbPath, &db) == SQLITE_OK else {
            Logger.error("Failed to open database: \(String(cString: sqlite3_errmsg(db)))", module: "WhatsAppDB")
            return
        }
        Logger.info("Opened WhatsApp database at: \(dbPath)", module: "WhatsAppDB")
    }
    
    func loadChats() {
        // If database wasn't opened initially, try to open it now (in case it was created after app start)
        if db == nil {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: dbPath) {
                openDatabase()
            } else {
                Logger.warning("Database still not found at: \(dbPath)", module: "WhatsAppDB")
                return
            }
        }
        
        guard let db = db else { return }
        
        let query = """
            SELECT c.jid, c.type, c.name, c.last_message_time, c.last_message_text, 
                   c.last_message_sender, c.is_muted, c.is_archived, c.is_pinned,
                   c.created_at, c.updated_at,
                   COALESCE(COUNT(CASE WHEN m.is_read = 0 AND m.is_from_me = 0 THEN 1 END), 0) as unread_count
            FROM chats c
            LEFT JOIN messages m ON c.jid = m.chat_jid
            GROUP BY c.jid, c.type, c.name, c.last_message_time, c.last_message_text, 
                     c.last_message_sender, c.is_muted, c.is_archived, c.is_pinned,
                     c.created_at, c.updated_at
            ORDER BY c.last_message_time DESC
        """
        
        var statement: OpaquePointer?
        var chats: [WhatsAppChat] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            while sqlite3_step(statement) == SQLITE_ROW {
                let jid = safeStringColumn(statement, 0) ?? ""
                let type = safeStringColumn(statement, 1) ?? "private"
                let name = safeStringColumn(statement, 2) ?? "Unknown"
                
                let lastMessageTimeString = safeStringColumn(statement, 3) ?? ""
                let lastMessageTime = parseDate(from: lastMessageTimeString) ?? Date()
                let lastMessageText = safeStringColumn(statement, 4) ?? ""
                let lastMessageSender = safeStringColumn(statement, 5) ?? ""
                
                let isMuted = sqlite3_column_int(statement, 6) != 0
                let isArchived = sqlite3_column_int(statement, 7) != 0
                let isPinned = sqlite3_column_int(statement, 8) != 0
                
                // Calculate actual unread count from messages (is_read = 0 AND is_from_me = 0)
                let unreadCount = Int(sqlite3_column_int(statement, 11))
                
                let chat = WhatsAppChat(
                    id: jid,
                    jid: jid,
                    type: type == "group" ? .group : .private,
                    name: name,
                    lastMessageTime: lastMessageTime,
                    lastMessageText: lastMessageText,
                    lastMessageSender: lastMessageSender,
                    unreadCount: unreadCount,
                    isMuted: isMuted,
                    isArchived: isArchived,
                    isPinned: isPinned
                )
                chats.append(chat)
            }
        }
        
        sqlite3_finalize(statement)
        self.chats = chats
        // Clear message cache when chats are refreshed to ensure fresh data
        clearMessageCache()
        Logger.info("Loaded \(chats.count) chats from database", module: "WhatsAppDB")
    }
    
    func loadMessages(for chatJID: String) -> [WhatsAppMessage] {
        guard let db = db else { return [] }
        
        // Always read fresh from database - no caching
        let query = """
            SELECT id, chat_jid, sender_jid, type, text, caption, media_url,
                   media_mime_type, media_file_name, media_file_size,
                   timestamp, is_from_me, is_read, quoted_message_id,
                   reaction_emoji, reaction_target, location_lat, location_lng,
                   location_name, location_address, contact_name, contact_phone,
                   contact_vcard, created_at, updated_at
            FROM messages
            WHERE chat_jid = ?
            ORDER BY timestamp ASC
        """
        
        var statement: OpaquePointer?
        var messageList: [WhatsAppMessage] = []
        
        if sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK {
            let bindResult = chatJID.withCString { cString in
                // SQLITE_TRANSIENT tells SQLite to copy the string
                sqlite3_bind_text(statement, 1, cString, -1, SQLITE_TRANSIENT)
            }
            
            guard bindResult == SQLITE_OK else {
                Logger.error("Failed to bind chatJID parameter: \(String(cString: sqlite3_errmsg(db)))", module: "WhatsAppDB")
                sqlite3_finalize(statement)
                return []
            }
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let id = safeStringColumn(statement, 0) ?? ""
                let chatJID = safeStringColumn(statement, 1) ?? ""
                let senderJID = safeStringColumn(statement, 2) ?? ""
                let type = safeStringColumn(statement, 3) ?? "text"
                let text = safeStringColumn(statement, 4) ?? ""
                let caption = safeStringColumn(statement, 5)
                let mediaURL = safeStringColumn(statement, 6)
                let mediaMimeType = safeStringColumn(statement, 7)
                let mediaFileName = safeStringColumn(statement, 8)
                let mediaFileSize = Int64(sqlite3_column_int64(statement, 9))
                
                let timestampString = safeStringColumn(statement, 10) ?? ""
                let timestamp = parseDate(from: timestampString) ?? Date()
                let isFromMe = sqlite3_column_int(statement, 11) != 0
                let isRead = sqlite3_column_int(statement, 12) != 0
                let quotedMessageID = safeStringColumn(statement, 13)
                
                let message = WhatsAppMessage(
                    id: id,
                    chatJID: chatJID,
                    senderJID: senderJID,
                    type: WhatsAppMessage.WhatsAppMessageType(rawValue: type) ?? .text,
                    text: text,
                    caption: caption?.isEmpty == false ? caption : nil,
                    mediaURL: mediaURL?.isEmpty == false ? mediaURL : nil,
                    mediaMimeType: mediaMimeType?.isEmpty == false ? mediaMimeType : nil,
                    mediaFileName: mediaFileName?.isEmpty == false ? mediaFileName : nil,
                    mediaFileSize: mediaFileSize,
                    timestamp: timestamp,
                    isFromMe: isFromMe,
                    isRead: isRead,
                    quotedMessageID: quotedMessageID?.isEmpty == false ? quotedMessageID : nil
                )
                messageList.append(message)
            }
        }
        
        sqlite3_finalize(statement)
        // Update cache but always return fresh data from DB
        messages[chatJID] = messageList
        Logger.info("Loaded \(messageList.count) messages for chat \(chatJID)", module: "WhatsAppDB")
        return messageList
    }
    
    func clearMessageCache() {
        messages.removeAll()
    }
    
    // Helper to safely get string columns that might be NULL
    private func safeStringColumn(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let text = sqlite3_column_text(statement, index) else {
            return nil
        }
        return String(cString: text)
    }
    
    // Helper to parse dates from SQLite (handles both ISO 8601 strings and Unix timestamps)
    private func parseDate(from string: String) -> Date? {
        // Try ISO 8601 format first (what GORM uses)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: string) {
            return date
        }
        
        // Try without fractional seconds
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: string) {
            return date
        }
        
        // Try as Unix timestamp (double)
        if let timestamp = Double(string) {
            return Date(timeIntervalSince1970: timestamp)
        }
        
        // Try standard date formatter as fallback
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = TimeZone.current
        if let date = formatter.date(from: string) {
            return date
        }
        
        return nil
    }
    
    deinit {
        if let db = db {
            sqlite3_close(db)
        }
    }
}

