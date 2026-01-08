package cli

import (
	"context"
	"fmt"
	"strconv"
	"strings"
	"time"

	"github.com/clippy-oss/homie/whatsapp-bridge/internal/domain"
	"github.com/clippy-oss/homie/whatsapp-bridge/internal/service"
)

// CommandHandler handles CLI commands
type CommandHandler struct {
	waSvc  *service.WhatsAppService
	msgSvc *service.MessageService
}

// NewCommandHandler creates a new command handler
func NewCommandHandler(waSvc *service.WhatsAppService, msgSvc *service.MessageService) *CommandHandler {
	return &CommandHandler{
		waSvc:  waSvc,
		msgSvc: msgSvc,
	}
}

// Command represents a parsed command
type Command struct {
	Name string
	Args []string
}

// ParseCommand parses a command string (e.g., "/send 123@s.whatsapp.net Hello")
func ParseCommand(input string) (*Command, error) {
	input = strings.TrimSpace(input)
	if input == "" {
		return nil, fmt.Errorf("empty command")
	}

	if !strings.HasPrefix(input, "/") {
		return nil, fmt.Errorf("commands must start with /")
	}

	parts := strings.Fields(input)
	if len(parts) == 0 {
		return nil, fmt.Errorf("empty command")
	}

	name := strings.TrimPrefix(parts[0], "/")
	args := parts[1:]

	return &Command{Name: name, Args: args}, nil
}

// Execute executes a command and returns the result
func (h *CommandHandler) Execute(ctx context.Context, cmd *Command) (interface{}, error) {
	switch cmd.Name {
	case "help", "h":
		return h.cmdHelp()
	case "status", "s":
		return h.cmdStatus()
	case "connect", "c":
		return h.cmdConnect(ctx)
	case "disconnect", "d":
		return h.cmdDisconnect()
	case "logout":
		return h.cmdLogout(ctx)
	case "pair-qr", "qr":
		return h.cmdPairQR(ctx)
	case "pair-phone", "phone":
		return h.cmdPairPhone(ctx, cmd.Args)
	case "chats", "ls":
		return h.cmdChats(ctx, cmd.Args)
	case "messages", "msg":
		return h.cmdMessages(ctx, cmd.Args)
	case "send":
		return h.cmdSend(ctx, cmd.Args)
	case "react":
		return h.cmdReact(ctx, cmd.Args)
	case "read":
		return h.cmdRead(ctx, cmd.Args)
	case "search":
		return h.cmdSearch(ctx, cmd.Args)
	case "quit", "exit", "q":
		return map[string]bool{"quit": true}, nil
	default:
		return nil, fmt.Errorf("unknown command: %s. Type /help for available commands", cmd.Name)
	}
}

func (h *CommandHandler) cmdHelp() (interface{}, error) {
	help := `Available commands:

Connection:
  /status, /s              Show connection status
  /connect, /c             Connect to WhatsApp
  /disconnect, /d          Disconnect from WhatsApp
  /logout                  Logout and remove device pairing

Pairing:
  /pair-qr, /qr            Get QR code for pairing
  /pair-phone, /phone <number>  Pair with phone number (e.g., /phone +1234567890)

Messages:
  /chats, /ls [limit]      List chats (default: 20)
  /messages, /msg <jid> [limit]  Get messages from a chat
  /send <jid> <text>       Send a text message
  /react <jid> <msg_id> <emoji>  React to a message
  /read <jid> <msg_id>     Mark a message as read
  /search <query> [limit]  Search messages

Other:
  /help, /h                Show this help
  /quit, /exit, /q         Exit the CLI`

	return map[string]string{"help": help}, nil
}

func (h *CommandHandler) cmdStatus() (interface{}, error) {
	connected := h.waSvc.IsConnected()
	loggedIn := h.waSvc.IsLoggedIn()

	var status string
	if connected {
		status = "connected"
	} else if loggedIn {
		status = "disconnected (logged in)"
	} else {
		status = "not logged in"
	}

	return ConnectionStatus{
		Connected: connected,
		LoggedIn:  loggedIn,
		Status:    status,
	}, nil
}

func (h *CommandHandler) cmdConnect(ctx context.Context) (interface{}, error) {
	if !h.waSvc.IsLoggedIn() {
		return nil, fmt.Errorf("not logged in. Use /pair-qr or /pair-phone first")
	}

	err := h.waSvc.Connect(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to connect: %w", err)
	}

	return map[string]string{"message": "Connected to WhatsApp"}, nil
}

func (h *CommandHandler) cmdDisconnect() (interface{}, error) {
	h.waSvc.Disconnect()
	return map[string]string{"message": "Disconnected from WhatsApp"}, nil
}

func (h *CommandHandler) cmdLogout(ctx context.Context) (interface{}, error) {
	err := h.waSvc.Logout(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to logout: %w", err)
	}
	return map[string]string{"message": "Logged out from WhatsApp. Device pairing removed."}, nil
}

func (h *CommandHandler) cmdPairQR(ctx context.Context) (interface{}, error) {
	qrChan, err := h.waSvc.GetQRChannel(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get QR channel: %w", err)
	}

	// Start connection in background after QR channel is set up
	go func() {
		time.Sleep(100 * time.Millisecond)
		h.waSvc.Connect(context.Background())
	}()

	// Wait for QR code or result
	for item := range qrChan {
		switch item.Event {
		case "code":
			return PairingInfo{QRCode: item.Code}, nil
		case "success":
			return PairingInfo{Success: true}, nil
		case "timeout":
			return nil, fmt.Errorf("QR code timeout")
		default:
			if item.Error != nil {
				return nil, fmt.Errorf("pairing error: %w", item.Error)
			}
		}
	}

	return nil, fmt.Errorf("QR channel closed unexpectedly")
}

func (h *CommandHandler) cmdPairPhone(ctx context.Context, args []string) (interface{}, error) {
	if len(args) < 1 {
		return nil, fmt.Errorf("usage: /pair-phone <phone_number>")
	}

	phoneNumber := args[0]
	code, err := h.waSvc.PairWithCode(ctx, phoneNumber)
	if err != nil {
		return nil, fmt.Errorf("failed to get pairing code: %w", err)
	}

	return PairingInfo{Code: code}, nil
}

func (h *CommandHandler) cmdChats(ctx context.Context, args []string) (interface{}, error) {
	limit := 20
	if len(args) > 0 {
		if l, err := strconv.Atoi(args[0]); err == nil && l > 0 {
			limit = l
		}
	}

	chats, err := h.msgSvc.GetChats(ctx, limit, 0)
	if err != nil {
		return nil, fmt.Errorf("failed to get chats: %w", err)
	}

	result := make([]ChatInfo, len(chats))
	for i, chat := range chats {
		chatType := "private"
		if chat.Type == domain.ChatTypeGroup {
			chatType = "group"
		}
		result[i] = ChatInfo{
			JID:             chat.JID.String(),
			Name:            chat.Name,
			Type:            chatType,
			UnreadCount:     chat.UnreadCount,
			LastMessageText: chat.LastMessageText,
			LastMessageTime: chat.LastMessageTime,
		}
	}

	return map[string]interface{}{"chats": result, "count": len(result)}, nil
}

func (h *CommandHandler) cmdMessages(ctx context.Context, args []string) (interface{}, error) {
	if len(args) < 1 {
		return nil, fmt.Errorf("usage: /messages <jid> [limit]")
	}

	jid, err := domain.ParseJID(args[0])
	if err != nil {
		return nil, fmt.Errorf("invalid JID: %w", err)
	}

	limit := 50
	if len(args) > 1 {
		if l, err := strconv.Atoi(args[1]); err == nil && l > 0 {
			limit = l
		}
	}

	messages, err := h.msgSvc.GetMessages(ctx, jid, limit, 0)
	if err != nil {
		return nil, fmt.Errorf("failed to get messages: %w", err)
	}

	result := make([]MessageInfo, len(messages))
	for i, msg := range messages {
		result[i] = MessageInfo{
			ID:        msg.ID,
			ChatJID:   msg.ChatJID.String(),
			SenderJID: msg.SenderJID.String(),
			Type:      string(msg.Type),
			Text:      msg.Text,
			Caption:   msg.Caption,
			Timestamp: msg.Timestamp,
			IsFromMe:  msg.IsFromMe,
			IsRead:    msg.IsRead,
		}
	}

	return map[string]interface{}{"messages": result, "count": len(result)}, nil
}

func (h *CommandHandler) cmdSend(ctx context.Context, args []string) (interface{}, error) {
	if len(args) < 2 {
		return nil, fmt.Errorf("usage: /send <jid> <text>")
	}

	jid, err := domain.ParseJID(args[0])
	if err != nil {
		return nil, fmt.Errorf("invalid JID: %w", err)
	}

	text := strings.Join(args[1:], " ")

	msg, err := h.msgSvc.SendTextMessage(ctx, jid, text)
	if err != nil {
		return nil, fmt.Errorf("failed to send message: %w", err)
	}

	return MessageInfo{
		ID:        msg.ID,
		ChatJID:   msg.ChatJID.String(),
		SenderJID: msg.SenderJID.String(),
		Type:      string(msg.Type),
		Text:      msg.Text,
		Timestamp: msg.Timestamp,
		IsFromMe:  msg.IsFromMe,
	}, nil
}

func (h *CommandHandler) cmdReact(ctx context.Context, args []string) (interface{}, error) {
	if len(args) < 3 {
		return nil, fmt.Errorf("usage: /react <jid> <message_id> <emoji>")
	}

	jid, err := domain.ParseJID(args[0])
	if err != nil {
		return nil, fmt.Errorf("invalid JID: %w", err)
	}

	messageID := args[1]
	emoji := args[2]

	err = h.msgSvc.SendReaction(ctx, jid, messageID, "", emoji)
	if err != nil {
		return nil, fmt.Errorf("failed to send reaction: %w", err)
	}

	return map[string]string{
		"message":    "Reaction sent",
		"message_id": messageID,
		"emoji":      emoji,
	}, nil
}

func (h *CommandHandler) cmdRead(ctx context.Context, args []string) (interface{}, error) {
	if len(args) < 2 {
		return nil, fmt.Errorf("usage: /read <jid> <message_id> [message_id2...]")
	}

	jid, err := domain.ParseJID(args[0])
	if err != nil {
		return nil, fmt.Errorf("invalid JID: %w", err)
	}

	messageIDs := args[1:]

	err = h.msgSvc.MarkAsRead(ctx, jid, messageIDs)
	if err != nil {
		return nil, fmt.Errorf("failed to mark as read: %w", err)
	}

	return map[string]interface{}{
		"message":     "Messages marked as read",
		"message_ids": messageIDs,
	}, nil
}

func (h *CommandHandler) cmdSearch(ctx context.Context, args []string) (interface{}, error) {
	if len(args) < 1 {
		return nil, fmt.Errorf("usage: /search <query> [limit]")
	}

	query := args[0]
	limit := 20

	// Check if last arg is a number (limit)
	if len(args) > 1 {
		if l, err := strconv.Atoi(args[len(args)-1]); err == nil && l > 0 {
			limit = l
			query = strings.Join(args[:len(args)-1], " ")
		} else {
			query = strings.Join(args, " ")
		}
	}

	messages, err := h.msgSvc.SearchMessages(ctx, query, limit)
	if err != nil {
		return nil, fmt.Errorf("search failed: %w", err)
	}

	result := make([]MessageInfo, len(messages))
	for i, msg := range messages {
		result[i] = MessageInfo{
			ID:        msg.ID,
			ChatJID:   msg.ChatJID.String(),
			SenderJID: msg.SenderJID.String(),
			Type:      string(msg.Type),
			Text:      msg.Text,
			Caption:   msg.Caption,
			Timestamp: msg.Timestamp,
			IsFromMe:  msg.IsFromMe,
			IsRead:    msg.IsRead,
		}
	}

	return map[string]interface{}{
		"query":    query,
		"messages": result,
		"count":    len(result),
	}, nil
}

// GetQRCodeEvents returns a channel of QR code events for streaming
func (h *CommandHandler) GetQRCodeEvents(ctx context.Context) (<-chan PairingInfo, error) {
	qrChan, err := h.waSvc.GetQRChannel(ctx)
	if err != nil {
		return nil, fmt.Errorf("failed to get QR channel: %w", err)
	}

	resultChan := make(chan PairingInfo)

	// Start connection in background after setting up the channel
	go func() {
		// Small delay to ensure QR channel is ready to receive
		time.Sleep(100 * time.Millisecond)
		h.waSvc.Connect(context.Background())
	}()

	go func() {
		defer close(resultChan)
		for item := range qrChan {
			switch item.Event {
			case "code":
				select {
				case resultChan <- PairingInfo{QRCode: item.Code}:
				case <-ctx.Done():
					return
				}
			case "success":
				select {
				case resultChan <- PairingInfo{Success: true}:
				case <-ctx.Done():
					return
				}
				return
			case "timeout":
				select {
				case resultChan <- PairingInfo{Error: "QR code timeout"}:
				case <-ctx.Done():
					return
				}
				return
			default:
				if item.Error != nil {
					select {
					case resultChan <- PairingInfo{Error: item.Error.Error()}:
					case <-ctx.Done():
						return
					}
					return
				}
			}
		}
	}()

	return resultChan, nil
}

// SubscribeEvents subscribes to WhatsApp events
func (h *CommandHandler) SubscribeEvents(eventTypes []domain.EventType) <-chan Event {
	if len(eventTypes) == 0 {
		eventTypes = []domain.EventType{
			domain.EventTypeMessageReceived,
			domain.EventTypeMessageSent,
			domain.EventTypeConnectionStatus,
		}
	}

	eventBus := h.waSvc.GetEventBus()
	domainChan := eventBus.Subscribe(eventTypes)

	resultChan := make(chan Event)

	go func() {
		defer close(resultChan)
		for evt := range domainChan {
			var eventType string
			var data interface{}

			switch e := evt.(type) {
			case domain.MessageReceivedEvent:
				eventType = "message_received"
				data = MessageInfo{
					ID:        e.Message.ID,
					ChatJID:   e.Message.ChatJID.String(),
					SenderJID: e.Message.SenderJID.String(),
					Type:      string(e.Message.Type),
					Text:      e.Message.Text,
					Caption:   e.Message.Caption,
					Timestamp: e.Message.Timestamp,
					IsFromMe:  e.Message.IsFromMe,
					IsRead:    e.Message.IsRead,
				}
			case domain.MessageSentEvent:
				eventType = "message_sent"
				data = MessageInfo{
					ID:        e.Message.ID,
					ChatJID:   e.Message.ChatJID.String(),
					SenderJID: e.Message.SenderJID.String(),
					Type:      string(e.Message.Type),
					Text:      e.Message.Text,
					Timestamp: e.Message.Timestamp,
					IsFromMe:  e.Message.IsFromMe,
				}
			case domain.ConnectionStatusEvent:
				eventType = "connection_status"
				data = map[string]interface{}{
					"connected": e.Connected,
					"reason":    e.Reason,
				}
			default:
				continue
			}

			resultChan <- Event{
				Type:      eventType,
				Timestamp: time.Now(),
				Data:      data,
			}
		}
	}()

	return resultChan
}

// UnsubscribeEvents unsubscribes from events
func (h *CommandHandler) UnsubscribeEvents(ch <-chan Event) {
	// Note: The actual unsubscription happens when the channel is closed
	// The eventBus handles cleanup
}
