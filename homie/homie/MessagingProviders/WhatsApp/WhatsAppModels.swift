//
//  WhatsAppModels.swift
//  homie
//
//  Models for WhatsApp chats and messages
//

import Foundation

struct WhatsAppChat: Identifiable {
    let id: String // JID
    let jid: String
    let type: ChatType
    let name: String
    let lastMessageTime: Date
    let lastMessageText: String
    let lastMessageSender: String
    let unreadCount: Int
    let isMuted: Bool
    let isArchived: Bool
    let isPinned: Bool
    
    enum ChatType {
        case `private`
        case group
    }
}

struct WhatsAppMessage: Identifiable {
    let id: String
    let chatJID: String
    let senderJID: String
    let type: WhatsAppMessageType
    let text: String
    let caption: String?
    let mediaURL: String?
    let mediaMimeType: String?
    let mediaFileName: String?
    let mediaFileSize: Int64
    let timestamp: Date
    let isFromMe: Bool
    let isRead: Bool
    let quotedMessageID: String?
    
    enum WhatsAppMessageType: String {
        case text
        case image
        case video
        case audio
        case document
        case sticker
        case reaction
        case location
        case contact
    }
}

