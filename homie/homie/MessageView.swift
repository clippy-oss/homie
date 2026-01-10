//
//  MessageView.swift
//  homie
//
//  Created by Maximilian Prokopp on 16.07.25.
//

import SwiftUI
import AppKit

enum LeftPanelView {
    case messages
    case list
}

struct MessageView: View {
    @StateObject private var viewModel = MessageViewModel()
    @State private var selectedLeftPanelView: LeftPanelView = .messages
    @ObservedObject private var authStore = AuthSessionStore.shared
    @State private var messageText: String = ""
    
    var body: some View {
        NavigationSplitView {
            // Left panel
            leftPanelView
                .navigationSplitViewColumnWidth(min: 200, ideal: 280, max: 350)
        } detail: {
            // Main panel
            mainPanelView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 600)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            viewModel.refreshChats()
            // Auto-generate summaries for unread chats
            Task {
                await viewModel.generateSummariesForUnreadChats()
            }
        }
    }
    
    // MARK: - Left Panel
    
    private var firstName: String {
        // Get name from AuthSessionStore or UserDefaults
        let fullName = authStore.userName ?? UserDefaults.standard.string(forKey: "personalize_name") ?? "there"
        
        // Extract first name (everything before the first space)
        if let firstSpaceIndex = fullName.firstIndex(of: " ") {
            return String(fullName[..<firstSpaceIndex])
        }
        return fullName.isEmpty ? "there" : fullName
    }
    
    private var unreadChats: [WhatsAppChat] {
        Array(viewModel.chats
            .filter { $0.unreadCount > 0 }
            .sorted { $0.lastMessageTime > $1.lastMessageTime }
            .prefix(3))
    }
    
    private var leftPanelView: some View {
        VStack(spacing: 0) {
            // Header with refresh button
            HStack {
                Text(selectedLeftPanelView == .messages ? "Message list" : "Peek list")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.primary)
                
                Spacer()
                
                Button(action: {
                    viewModel.refreshChats()
                }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Refresh chats")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                Divider(),
                alignment: .bottom
            )
            
            // Content area
            ZStack {
                // Sidebar background
                Color(NSColor.controlBackgroundColor)
                    .ignoresSafeArea()
                
                if selectedLeftPanelView == .messages {
                    // Message list (all chats)
                    if viewModel.chats.isEmpty {
                        VStack {
                            Text("No chats")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(viewModel.chats) { chat in
                                    ChatRowView(chat: chat, isSelected: viewModel.selectedChat?.id == chat.id)
                                        .onTapGesture {
                                            viewModel.selectChat(chat)
                                        }
                                }
                            }
                        }
                    }
                } else {
                    // Peek list (unread chats only)
                    if unreadChats.isEmpty {
                        VStack {
                            Text("No unread messages")
                                .foregroundColor(.secondary)
                        }
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(unreadChats) { chat in
                                    ChatRowView(chat: chat, isSelected: false)
                                }
                            }
                        }
                    }
                }
            }
            
            // Bottom icon bar
            HStack(spacing: 0) {
                // Peek list icon
                Button(action: {
                    withAnimation {
                        selectedLeftPanelView = .list
                        // Clear selected chat when switching to peek list
                        viewModel.selectedChat = nil
                    }
                }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 18))
                        .foregroundColor(selectedLeftPanelView == .list ? .accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
                
                Divider()
                    .frame(height: 20)
                
                // Message list icon
                Button(action: {
                    withAnimation {
                        selectedLeftPanelView = .messages
                    }
                }) {
                    Image(systemName: "message")
                        .font(.system(size: 18))
                        .foregroundColor(selectedLeftPanelView == .messages ? .accentColor : .secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
            .background(Color(NSColor.controlBackgroundColor))
            .overlay(
                Divider(),
                alignment: .top
            )
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    // Detect rightward swipe (left to right)
                    if value.translation.width > 50 && abs(value.translation.height) < abs(value.translation.width) {
                        withAnimation {
                            selectedLeftPanelView = .list
                            // Clear selected chat when switching to peek list
                            viewModel.selectedChat = nil
                        }
                    }
                }
        )
    }
    
    // MARK: - Main Panel
    
    private func sendMessage() {
        let text = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        
        messageText = ""
        
        Task {
            do {
                try await viewModel.sendMessage(text)
            } catch {
                Logger.error("Failed to send message: \(error.localizedDescription)", module: "MessageView")
                // Restore the text if sending failed
                messageText = text
            }
        }
    }
    
    private var mainPanelView: some View {
        ZStack {
            // Background material
            ContentBackgroundMaterial()
                .ignoresSafeArea()
            
            if let selectedChat = viewModel.selectedChat {
                NavigationStack {
                    // Messages scroll view
                    ScrollViewReader { proxy in
                        ScrollView {
                            if viewModel.messages.isEmpty {
                                VStack {
                                    Spacer()
                                    Text("No messages")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 14))
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else {
                                LazyVStack(alignment: .leading, spacing: 4) {
                                    ForEach(viewModel.messages) { message in
                                        MessageBubbleView(message: message)
                                            .id(message.id)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .onChange(of: viewModel.messages.count) { count in
                            // Scroll to bottom when messages load
                            if count > 0, let lastMessage = viewModel.messages.last {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation {
                                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                        .onAppear {
                            // Also scroll on appear if messages are already loaded
                            if !viewModel.messages.isEmpty, let lastMessage = viewModel.messages.last {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                    withAnimation {
                                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                    .safeAreaInset(edge: .bottom) {
                        MessageInputBar(messageText: $messageText, onSend: sendMessage)
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigation) {
                            HStack(spacing: 12) {
                                // Avatar
                                Circle()
                                    .fill(Color.blue.opacity(0.3))
                                    .frame(width: 50, height: 50)
                                    .overlay(
                                        Text(String(selectedChat.name.prefix(1)))
                                            .font(.system(size: 20, weight: .medium))
                                            .foregroundColor(.blue)
                                    )
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(selectedChat.name)
                                        .font(.system(size: 18, weight: .semibold))
                                    
                                    if selectedChat.type == .group {
                                        Text(selectedChat.lastMessageSender)
                                            .font(.system(size: 13))
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        
                        ToolbarItem(placement: .primaryAction) {
                            Button(action: {
                                viewModel.refreshChats()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14))
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Refresh messages")
                        }
                    }
                }
            } else {
                // Centered container with unread chats list
                VStack(spacing: 0) {
                    GeometryReader { geometry in
                        VStack {
                            Spacer()
                            
                            // Vertically centered container
                            VStack(alignment: .leading, spacing: 12) {
                                if !unreadChats.isEmpty {
                                    // Title - centered horizontally, 90% width
                                    HStack {
                                        Spacer()
                                        Text("Here are your updates, \(firstName)")
                                            .font(.custom("EB Garamond", size: 28))
                                            .fontWeight(.regular)
                                            .foregroundColor(.primary)
                                            .frame(width: geometry.size.width * 0.9, alignment: .center)
                                        Spacer()
                                    }
                                    .padding(.bottom, 12)
                                }
                                
                                // Summaries - centered horizontally, 60% width
                                HStack {
                                    Spacer()
                                    VStack(alignment: .leading, spacing: 12) {
                                        if unreadChats.isEmpty {
                                            Text("No unread messages")
                                                .foregroundColor(.secondary)
                                                .font(.system(size: 16))
                                        } else {
                                            ForEach(unreadChats) { chat in
                                                if let summary = viewModel.chatSummaries[chat.jid] {
                                                    // Show AI-generated summary with chat name in semibold
                                                    StyledSummaryText(summary: summary, chatName: chat.name)
                                                        .font(.system(size: 14))
                                                        .foregroundColor(.secondary)
                                                        .fixedSize(horizontal: false, vertical: true)
                                                } else {
                                                    // Show last message text
                                                    Text(chat.lastMessageText)
                                                        .font(.system(size: 14))
                                                        .foregroundColor(.secondary)
                                                        .lineLimit(2)
                                                }
                                            }
                                            .padding(.vertical, 4)
                                        }
                                    }
                                    .frame(width: geometry.size.width * 0.6, alignment: .leading)
                                    .padding(.horizontal, 20)
                                    Spacer()
                                }
                            }
                            
                            Spacer()
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                    
                    // Message input bar at the bottom
                    MessageInputBar(messageText: $messageText, onSend: sendMessage)
                }
            }
        }
    }
}

// MARK: - Chat Row View

struct ChatRowView: View {
    let chat: WhatsAppChat
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color.blue.opacity(0.3))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(String(chat.name.prefix(1)))
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.blue)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(chat.name)
                        .font(.system(size: 15, weight: .medium))
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Text(timeString(from: chat.lastMessageTime))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                HStack {
                    Text(chat.lastMessageText)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    if chat.unreadCount > 0 {
                        Text("\(chat.unreadCount)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
    }
    
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        let calendar = Calendar.current
        let now = Date()
        
        // Check if date is today
        if calendar.isDate(date, inSameDayAs: now) {
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
                  calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        } else if let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now),
                  weekInterval.contains(date) {
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date)
        } else {
            formatter.dateFormat = "MM/dd"
            return formatter.string(from: date)
        }
    }
}

// MARK: - Message Bubble View

struct MessageBubbleView: View {
    let message: WhatsAppMessage
    
    var body: some View {
        HStack {
            if message.isFromMe {
                Spacer(minLength: 60)
            }
            
            VStack(alignment: message.isFromMe ? .trailing : .leading, spacing: 4) {
                if !message.isFromMe {
                    Text(senderName)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                        .padding(.leading, 4)
                }
                
                messageContent
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        message.isFromMe
                            ? Color.blue
                            : Color(NSColor.controlBackgroundColor)
                    )
                    .foregroundColor(
                        message.isFromMe ? .white : .primary
                    )
                    .clipShape(
                        RoundedRectangle(cornerRadius: 18)
                    )
                
                Text(timeString(from: message.timestamp))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
            }
            
            if !message.isFromMe {
                Spacer(minLength: 60)
            }
        }
    }
    
    private var senderName: String {
        // Extract name from JID or use a default
        if let phoneNumber = message.senderJID.components(separatedBy: "@").first {
            return phoneNumber
        }
        return "Unknown"
    }
    
    private var messageContent: some View {
        Group {
            switch message.type {
            case .text:
                Text(message.text)
                    .font(.system(size: 15))
            case .image:
                VStack(alignment: .leading, spacing: 4) {
                    if let caption = message.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: 15))
                    }
                    HStack {
                        Image(systemName: "photo")
                        Text("Image")
                            .font(.system(size: 13))
                    }
                }
            case .video:
                VStack(alignment: .leading, spacing: 4) {
                    if let caption = message.caption, !caption.isEmpty {
                        Text(caption)
                            .font(.system(size: 15))
                    }
                    HStack {
                        Image(systemName: "video.fill")
                        Text("Video")
                            .font(.system(size: 13))
                    }
                }
            case .document:
                HStack {
                    Image(systemName: "doc.fill")
                    if let fileName = message.mediaFileName {
                        Text(fileName)
                            .font(.system(size: 13))
                    } else {
                        Text("Document")
                            .font(.system(size: 13))
                    }
                }
            default:
                Text(message.text.isEmpty ? "\(message.type.rawValue.capitalized)" : message.text)
                    .font(.system(size: 15))
            }
        }
    }
    
    private func timeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: - Styled Summary Text

struct StyledSummaryText: View {
    let summary: String
    let chatName: String
    
    var body: some View {
        buildStyledText(from: summary, highlighting: chatName)
    }
    
    private func buildStyledText(from text: String, highlighting name: String) -> Text {
        // Use AttributedString for better control over styling
        var attributedString = AttributedString(text)
        
        // Find all occurrences of the chat name in the summary (case-insensitive)
        var searchRange = text.startIndex..<text.endIndex
        
        while let range = text.range(of: name, options: [.caseInsensitive], range: searchRange) {
            // Apply semibold and black color to this occurrence
            if let attributedRange = Range(range, in: attributedString) {
                attributedString[attributedRange].font = .system(size: 14, weight: .semibold)
                attributedString[attributedRange].foregroundColor = .primary
            }
            
            // Continue searching after this occurrence
            searchRange = range.upperBound..<text.endIndex
        }
        
        return Text(attributedString)
    }
}

// MARK: - Message Input Bar

struct MessageInputBar: View {
    @Binding var messageText: String
    let onSend: () -> Void
    
    var body: some View {
        // Bottom input area with native macOS 26 Liquid Glass styling
        HStack(spacing: 8) {
            // TextField container with glass effect
            HStack {
                TextField("Type a message...", text: $messageText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .onSubmit {
                        onSend()
                    }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(in: .rect(cornerRadius: 18))
            
            Spacer()
            
            Button(action: {
                onSend()
            }) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 20))
            }
            .buttonStyle(.glass)
            .clipShape(Circle())
            .disabled(messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

#Preview {
    MessageView()
        .frame(width: 1000, height: 700)
}

