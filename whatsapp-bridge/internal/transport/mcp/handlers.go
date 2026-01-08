package mcp

import (
	"context"
	"fmt"
	"strings"

	"github.com/mark3labs/mcp-go/mcp"

	"github.com/clippy-oss/homie/whatsapp-bridge/internal/domain"
)

func (s *Server) handleListChats(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	limit := request.GetInt("limit", 20)
	if limit > 100 {
		limit = 100
	}
	if limit <= 0 {
		limit = 20
	}

	chats, err := s.msgSvc.GetChats(ctx, limit, 0)
	if err != nil {
		return mcp.NewToolResultError(fmt.Sprintf("Failed to get chats: %v", err)), nil
	}

	if len(chats) == 0 {
		return mcp.NewToolResultText("No chats found. Make sure WhatsApp is connected and has synced."), nil
	}

	var result strings.Builder
	result.WriteString(fmt.Sprintf("Found %d chat(s):\n\n", len(chats)))

	for i, chat := range chats {
		chatType := "Private"
		if chat.Type == domain.ChatTypeGroup {
			chatType = "Group"
		}

		result.WriteString(fmt.Sprintf("%d. %s (%s)\n", i+1, chat.Name, chatType))
		result.WriteString(fmt.Sprintf("   ID: %s\n", chat.JID.String()))

		if chat.UnreadCount > 0 {
			result.WriteString(fmt.Sprintf("   Unread: %d message(s)\n", chat.UnreadCount))
		}

		if chat.LastMessageText != "" {
			preview := chat.LastMessageText
			if len(preview) > 60 {
				preview = preview[:60] + "..."
			}
			result.WriteString(fmt.Sprintf("   Last: %s\n", preview))
			if !chat.LastMessageTime.IsZero() {
				result.WriteString(fmt.Sprintf("   Time: %s\n", chat.LastMessageTime.Format("2006-01-02 15:04")))
			}
		}
		result.WriteString("\n")
	}

	return mcp.NewToolResultText(result.String()), nil
}

func (s *Server) handleGetMessages(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	chatID := request.GetString("chat_id", "")
	if chatID == "" {
		return mcp.NewToolResultError("chat_id is required"), nil
	}

	chatJID, err := domain.ParseJID(chatID)
	if err != nil {
		return mcp.NewToolResultError(fmt.Sprintf("Invalid chat_id format: %v", err)), nil
	}

	limit := request.GetInt("limit", 50)
	if limit > 200 {
		limit = 200
	}
	if limit <= 0 {
		limit = 50
	}

	messages, err := s.msgSvc.GetMessages(ctx, chatJID, limit, 0)
	if err != nil {
		return mcp.NewToolResultError(fmt.Sprintf("Failed to get messages: %v", err)), nil
	}

	if len(messages) == 0 {
		return mcp.NewToolResultText(fmt.Sprintf("No messages found in chat %s", chatID)), nil
	}

	var result strings.Builder
	result.WriteString(fmt.Sprintf("Messages from %s (%d):\n\n", chatID, len(messages)))

	for _, msg := range messages {
		sender := "Me"
		if !msg.IsFromMe {
			sender = msg.SenderJID.User
			if sender == "" {
				sender = msg.SenderJID.String()
			}
		}

		timestamp := msg.Timestamp.Format("2006-01-02 15:04")
		readStatus := ""
		if msg.IsRead {
			readStatus = " [check mark]"
		}

		result.WriteString(fmt.Sprintf("[%s] %s%s:\n", timestamp, sender, readStatus))

		switch msg.Type {
		case domain.MessageTypeText:
			result.WriteString(fmt.Sprintf("  %s\n", msg.Text))
		case domain.MessageTypeImage:
			caption := msg.Caption
			if caption == "" {
				caption = "(no caption)"
			}
			result.WriteString(fmt.Sprintf("  [Image] %s\n", caption))
		case domain.MessageTypeVideo:
			caption := msg.Caption
			if caption == "" {
				caption = "(no caption)"
			}
			result.WriteString(fmt.Sprintf("  [Video] %s\n", caption))
		case domain.MessageTypeAudio:
			result.WriteString("  [Audio message]\n")
		case domain.MessageTypeDocument:
			result.WriteString(fmt.Sprintf("  [Document: %s]\n", msg.MediaFileName))
		case domain.MessageTypeSticker:
			result.WriteString("  [Sticker]\n")
		case domain.MessageTypeReaction:
			if msg.Reaction != nil {
				result.WriteString(fmt.Sprintf("  Reacted with %s to message %s\n", msg.Reaction.Emoji, msg.Reaction.TargetMessageID))
			}
		case domain.MessageTypeLocation:
			if msg.Location != nil {
				result.WriteString(fmt.Sprintf("  [Location: %s]\n", msg.Location.Name))
			}
		default:
			result.WriteString(fmt.Sprintf("  [%s]\n", msg.Type))
		}

		result.WriteString(fmt.Sprintf("  ID: %s\n\n", msg.ID))
	}

	return mcp.NewToolResultText(result.String()), nil
}

func (s *Server) handleSendMessage(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	chatID := request.GetString("chat_id", "")
	if chatID == "" {
		return mcp.NewToolResultError("chat_id is required"), nil
	}

	text := request.GetString("text", "")
	if text == "" {
		return mcp.NewToolResultError("text is required"), nil
	}

	chatJID, err := domain.ParseJID(chatID)
	if err != nil {
		return mcp.NewToolResultError(fmt.Sprintf("Invalid chat_id format: %v", err)), nil
	}

	msg, err := s.msgSvc.SendTextMessage(ctx, chatJID, text)
	if err != nil {
		return mcp.NewToolResultError(fmt.Sprintf("Failed to send message: %v", err)), nil
	}

	return mcp.NewToolResultText(fmt.Sprintf("Message sent successfully!\nID: %s\nTimestamp: %s\nTo: %s",
		msg.ID, msg.Timestamp.Format("2006-01-02 15:04:05"), chatID)), nil
}

func (s *Server) handleSendReaction(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	chatID := request.GetString("chat_id", "")
	messageID := request.GetString("message_id", "")
	emoji := request.GetString("emoji", "")

	if chatID == "" {
		return mcp.NewToolResultError("chat_id is required"), nil
	}
	if messageID == "" {
		return mcp.NewToolResultError("message_id is required"), nil
	}
	if emoji == "" {
		return mcp.NewToolResultError("emoji is required"), nil
	}

	chatJID, err := domain.ParseJID(chatID)
	if err != nil {
		return mcp.NewToolResultError(fmt.Sprintf("Invalid chat_id format: %v", err)), nil
	}

	err = s.msgSvc.SendReaction(ctx, chatJID, messageID, "", emoji)
	if err != nil {
		return mcp.NewToolResultError(fmt.Sprintf("Failed to send reaction: %v", err)), nil
	}

	return mcp.NewToolResultText(fmt.Sprintf("Reaction %s sent to message %s", emoji, messageID)), nil
}

func (s *Server) handleMarkRead(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	chatID := request.GetString("chat_id", "")
	messageIDsStr := request.GetString("message_ids", "")

	if chatID == "" {
		return mcp.NewToolResultError("chat_id is required"), nil
	}
	if messageIDsStr == "" {
		return mcp.NewToolResultError("message_ids is required"), nil
	}

	chatJID, err := domain.ParseJID(chatID)
	if err != nil {
		return mcp.NewToolResultError(fmt.Sprintf("Invalid chat_id format: %v", err)), nil
	}

	messageIDs := strings.Split(messageIDsStr, ",")
	for i := range messageIDs {
		messageIDs[i] = strings.TrimSpace(messageIDs[i])
	}

	err = s.msgSvc.MarkAsRead(ctx, chatJID, messageIDs)
	if err != nil {
		return mcp.NewToolResultError(fmt.Sprintf("Failed to mark as read: %v", err)), nil
	}

	return mcp.NewToolResultText(fmt.Sprintf("Marked %d message(s) as read in chat %s", len(messageIDs), chatID)), nil
}

func (s *Server) handleSearchMessages(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	query := request.GetString("query", "")
	if query == "" {
		return mcp.NewToolResultError("query is required"), nil
	}

	limit := request.GetInt("limit", 20)
	if limit > 100 {
		limit = 100
	}
	if limit <= 0 {
		limit = 20
	}

	messages, err := s.msgSvc.SearchMessages(ctx, query, limit)
	if err != nil {
		return mcp.NewToolResultError(fmt.Sprintf("Search failed: %v", err)), nil
	}

	if len(messages) == 0 {
		return mcp.NewToolResultText(fmt.Sprintf("No messages found matching '%s'", query)), nil
	}

	var result strings.Builder
	result.WriteString(fmt.Sprintf("Search results for '%s' (%d found):\n\n", query, len(messages)))

	for i, msg := range messages {
		sender := "Me"
		if !msg.IsFromMe {
			sender = msg.SenderJID.User
		}

		result.WriteString(fmt.Sprintf("%d. [%s] %s:\n", i+1, msg.Timestamp.Format("2006-01-02 15:04"), sender))
		result.WriteString(fmt.Sprintf("   Chat: %s\n", msg.ChatJID.String()))

		text := msg.Text
		if text == "" {
			text = msg.Caption
		}
		if len(text) > 100 {
			text = text[:100] + "..."
		}
		result.WriteString(fmt.Sprintf("   %s\n", text))
		result.WriteString(fmt.Sprintf("   ID: %s\n\n", msg.ID))
	}

	return mcp.NewToolResultText(result.String()), nil
}

func (s *Server) handleConnectionStatus(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	connected := s.waSvc.IsConnected()
	loggedIn := s.waSvc.IsLoggedIn()

	var status string
	if connected {
		status = "Connected"
	} else if loggedIn {
		status = "Logged in but disconnected"
	} else {
		status = "Not logged in"
	}

	return mcp.NewToolResultText(fmt.Sprintf("WhatsApp Status: %s\nConnected: %v\nLogged In: %v",
		status, connected, loggedIn)), nil
}

func (s *Server) handleConnect(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	if !s.waSvc.IsLoggedIn() {
		return mcp.NewToolResultError("Not logged in. Please pair your device first using the mobile app."), nil
	}

	err := s.waSvc.Connect(ctx)
	if err != nil {
		return mcp.NewToolResultError(fmt.Sprintf("Failed to connect: %v", err)), nil
	}

	return mcp.NewToolResultText("Successfully connected to WhatsApp"), nil
}

func (s *Server) handleDisconnect(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	s.waSvc.Disconnect()
	return mcp.NewToolResultText("Disconnected from WhatsApp"), nil
}

func (s *Server) handleLogout(ctx context.Context, request mcp.CallToolRequest) (*mcp.CallToolResult, error) {
	err := s.waSvc.Logout(ctx)
	if err != nil {
		return mcp.NewToolResultError(fmt.Sprintf("Failed to logout: %v", err)), nil
	}
	return mcp.NewToolResultText("Successfully logged out from WhatsApp. Device pairing has been removed."), nil
}
