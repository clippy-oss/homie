package service

import (
	"context"
	"fmt"
	"sync"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waE2E"
	"go.mau.fi/whatsmeow/proto/waWeb"
	"go.mau.fi/whatsmeow/store"
	"go.mau.fi/whatsmeow/types"
	"go.mau.fi/whatsmeow/types/events"
	waLog "go.mau.fi/whatsmeow/util/log"
	"google.golang.org/protobuf/proto"

	"github.com/clippy-oss/homie/whatsapp-bridge/internal/domain"
	"github.com/clippy-oss/homie/whatsapp-bridge/internal/repository"
)

type WhatsAppServiceConfig struct {
	MediaDownloadPath string
}

type WhatsAppService struct {
	client   *whatsmeow.Client
	device   *store.Device
	eventBus domain.EventBus
	msgRepo  repository.MessageRepository
	chatRepo repository.ChatRepository
	config   WhatsAppServiceConfig
	logger   waLog.Logger

	mu        sync.RWMutex
	connected bool
}

func NewWhatsAppService(
	device *store.Device,
	eventBus domain.EventBus,
	msgRepo repository.MessageRepository,
	chatRepo repository.ChatRepository,
	config WhatsAppServiceConfig,
	logger waLog.Logger,
) *WhatsAppService {
	client := whatsmeow.NewClient(device, logger)

	svc := &WhatsAppService{
		client:   client,
		device:   device,
		eventBus: eventBus,
		msgRepo:  msgRepo,
		chatRepo: chatRepo,
		config:   config,
		logger:   logger,
	}

	client.AddEventHandler(svc.handleEvent)
	return svc
}

func (s *WhatsAppService) Connect(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.client.IsConnected() {
		return nil
	}

	return s.client.Connect()
}

func (s *WhatsAppService) Disconnect() {
	s.mu.Lock()
	defer s.mu.Unlock()

	s.client.Disconnect()
	s.connected = false
}

func (s *WhatsAppService) Logout(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	// Logout from WhatsApp (removes device from linked devices)
	err := s.client.Logout(ctx)
	if err != nil {
		return fmt.Errorf("failed to logout: %w", err)
	}

	// Disconnect after logout
	s.client.Disconnect()
	s.connected = false

	return nil
}

func (s *WhatsAppService) IsConnected() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.connected && s.client != nil && s.client.IsConnected()
}

func (s *WhatsAppService) IsLoggedIn() bool {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.device != nil && s.device.ID != nil
}

// GetContacts returns all contacts from whatsmeow's built-in ContactStore as domain types
func (s *WhatsAppService) GetContacts(ctx context.Context) ([]*domain.Contact, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if s.client == nil {
		return nil, fmt.Errorf("client not initialized")
	}

	waContacts, err := s.client.Store.Contacts.GetAllContacts(ctx)
	if err != nil {
		return nil, err
	}

	contacts := make([]*domain.Contact, 0, len(waContacts))
	for jid, info := range waContacts {
		contacts = append(contacts, s.contactInfoToDomain(jid, info))
	}
	return contacts, nil
}

// GetContact returns a specific contact from whatsmeow's built-in ContactStore as domain type
func (s *WhatsAppService) GetContact(ctx context.Context, jid domain.JID) (*domain.Contact, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	if s.client == nil {
		return nil, fmt.Errorf("client not initialized")
	}

	waJID := s.toWhatsmeowJID(jid)
	info, err := s.client.Store.Contacts.GetContact(ctx, waJID)
	if err != nil {
		return nil, err
	}

	return s.contactInfoToDomain(waJID, info), nil
}

// contactInfoToDomain converts whatsmeow ContactInfo to domain Contact
func (s *WhatsAppService) contactInfoToDomain(jid types.JID, info types.ContactInfo) *domain.Contact {
	return &domain.Contact{
		JID:          s.toDomainJID(jid),
		Name:         info.FullName,
		PushName:     info.PushName,
		BusinessName: info.BusinessName,
		PhoneNumber:  jid.User,
	}
}

func (s *WhatsAppService) GetQRChannel(ctx context.Context) (<-chan whatsmeow.QRChannelItem, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.device.ID != nil {
		return nil, fmt.Errorf("already logged in")
	}

	return s.client.GetQRChannel(ctx)
}

func (s *WhatsAppService) PairWithCode(ctx context.Context, phoneNumber string) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	// PairPhone requires an active websocket connection
	if !s.client.IsConnected() {
		if err := s.client.Connect(); err != nil {
			return "", fmt.Errorf("failed to connect: %w", err)
		}
	}

	return s.client.PairPhone(ctx, phoneNumber, true, whatsmeow.PairClientChrome, "Chrome (Mac)")
}

func (s *WhatsAppService) SendTextMessage(ctx context.Context, chatJID domain.JID, text string) (*domain.Message, error) {
	if !s.IsConnected() {
		return nil, fmt.Errorf("not connected to WhatsApp")
	}

	waJID := s.toWhatsmeowJID(chatJID)

	msg := &waE2E.Message{
		Conversation: proto.String(text),
	}

	resp, err := s.client.SendMessage(ctx, waJID, msg)
	if err != nil {
		return nil, fmt.Errorf("failed to send message: %w", err)
	}

	domainMsg := domain.NewTextMessage(
		resp.ID,
		chatJID,
		s.getOwnJID(),
		text,
		resp.Timestamp,
		true,
	)

	if err := s.msgRepo.Create(ctx, domainMsg); err != nil {
		s.logger.Warnf("Failed to persist sent message: %v", err)
	}

	if err := s.chatRepo.UpdateLastMessage(ctx, chatJID, text, "me", resp.Timestamp); err != nil {
		s.logger.Warnf("Failed to update chat: %v", err)
	}

	s.eventBus.Publish(domain.MessageSentEvent{
		Message:   domainMsg,
		EventTime: time.Now(),
	})

	return domainMsg, nil
}

func (s *WhatsAppService) SendReaction(ctx context.Context, chatJID domain.JID, targetMessageID, senderJID, emoji string) error {
	if !s.IsConnected() {
		return fmt.Errorf("not connected to WhatsApp")
	}

	waJID := s.toWhatsmeowJID(chatJID)
	senderWAJID, err := types.ParseJID(senderJID)
	if err != nil {
		senderWAJID = *s.client.Store.ID
	}

	msg := s.client.BuildReaction(waJID, senderWAJID, targetMessageID, emoji)
	_, err = s.client.SendMessage(ctx, waJID, msg)
	return err
}

func (s *WhatsAppService) MarkAsRead(ctx context.Context, chatJID domain.JID, messageIDs []string) error {
	if !s.IsConnected() {
		return fmt.Errorf("not connected to WhatsApp")
	}

	waJID := s.toWhatsmeowJID(chatJID)

	ids := make([]types.MessageID, len(messageIDs))
	for i, id := range messageIDs {
		ids[i] = types.MessageID(id)
	}

	err := s.client.MarkRead(ctx, ids, time.Now(), waJID, s.client.Store.ID.ToNonAD())
	if err != nil {
		return err
	}

	if err := s.msgRepo.UpdateReadStatus(ctx, messageIDs, true); err != nil {
		s.logger.Warnf("Failed to update read status in db: %v", err)
	}

	if err := s.chatRepo.UpdateUnreadCount(ctx, chatJID, 0); err != nil {
		s.logger.Warnf("Failed to update unread count: %v", err)
	}

	s.eventBus.Publish(domain.MessageReadEvent{
		ChatJID:    chatJID,
		MessageIDs: messageIDs,
		EventTime:  time.Now(),
	})

	return nil
}

func (s *WhatsAppService) handleEvent(evt interface{}) {
	switch v := evt.(type) {
	case *events.Connected:
		s.mu.Lock()
		s.connected = true
		s.mu.Unlock()
		s.eventBus.Publish(domain.ConnectionStatusEvent{
			Connected: true,
			EventTime: time.Now(),
		})

	case *events.Disconnected:
		s.mu.Lock()
		s.connected = false
		s.mu.Unlock()
		s.eventBus.Publish(domain.ConnectionStatusEvent{
			Connected: false,
			Reason:    "disconnected",
			EventTime: time.Now(),
		})

	case *events.LoggedOut:
		s.logger.Warnf("Device logged out remotely (OnConnect: %v, Reason: %v)", v.OnConnect, v.Reason)
		s.mu.Lock()
		s.connected = false
		// Note: whatsmeow automatically calls Store.Delete() which clears device.ID
		// Keep client reference - it can be reused for re-pairing after logout
		s.mu.Unlock()
		s.eventBus.Publish(domain.ConnectionStatusEvent{
			Connected: false,
			Reason:    "logged_out",
			EventTime: time.Now(),
		})

	case *events.Message:
		s.handleMessage(v)

	case *events.Receipt:
		s.handleReceipt(v)

	case *events.PushName:
		s.handlePushName(v)

	case *events.HistorySync:
		s.handleHistorySync(v)

	case *events.MarkChatAsRead:
		s.handleMarkChatAsRead(v)

	case *events.Archive:
		s.handleArchive(v)
	}
}

func (s *WhatsAppService) handleMessage(evt *events.Message) {
	msg := s.convertMessage(evt)
	if msg == nil {
		return
	}

	ctx := context.Background()

	if err := s.msgRepo.Create(ctx, msg); err != nil {
		s.logger.Warnf("Failed to persist message %s in chat %s: %v", msg.ID, msg.ChatJID.String(), err)
	}

	senderName := msg.SenderJID.User
	if !msg.IsFromMe {
		if err := s.chatRepo.IncrementUnreadCount(ctx, msg.ChatJID); err != nil {
			s.logger.Warnf("Failed to increment unread count for chat %s: %v", msg.ChatJID.String(), err)
		}
	} else {
		senderName = "me"
	}

	text := msg.Text
	if text == "" && msg.Caption != "" {
		text = msg.Caption
	}
	if text == "" {
		text = "[" + string(msg.Type) + "]"
	}

	if err := s.chatRepo.UpdateLastMessage(ctx, msg.ChatJID, text, senderName, msg.Timestamp); err != nil {
		s.logger.Warnf("Failed to update chat %s with message %s: %v", msg.ChatJID.String(), msg.ID, err)
	}

	s.eventBus.Publish(domain.MessageReceivedEvent{
		Message:   msg,
		EventTime: time.Now(),
	})
}

func (s *WhatsAppService) handleReceipt(evt *events.Receipt) {
	if evt.Type != types.ReceiptTypeRead && evt.Type != types.ReceiptTypeReadSelf {
		return
	}

	messageIDs := make([]string, len(evt.MessageIDs))
	for i, id := range evt.MessageIDs {
		messageIDs[i] = string(id)
	}

	ctx := context.Background()
	if err := s.msgRepo.UpdateReadStatus(ctx, messageIDs, true); err != nil {
		s.logger.Warnf("Failed to update read status: %v", err)
	}
}

func (s *WhatsAppService) handlePushName(evt *events.PushName) {
	// Push names are automatically stored by whatsmeow's ContactStore
	// We just log them for debugging purposes
	s.logger.Debugf("Push name update: %s -> %s", evt.JID.String(), evt.NewPushName)
}

func (s *WhatsAppService) handleHistorySync(evt *events.HistorySync) {
	ctx := context.Background()
	data := evt.Data
	syncType := data.GetSyncType()

	s.logger.Infof("Received history sync: type=%s, conversations=%d, progress=%d%%",
		syncType.String(),
		len(data.GetConversations()),
		data.GetProgress())

	// Only INITIAL_BOOTSTRAP has reliable conversation metadata
	// RECENT and other types have empty/null metadata
	isInitialSync := syncType.String() == "INITIAL_BOOTSTRAP"

	// Process each conversation
	for _, conv := range data.GetConversations() {
		chatJID, err := types.ParseJID(conv.GetID())
		if err != nil {
			s.logger.Warnf("Failed to parse chat JID %s: %v", conv.GetID(), err)
			continue
		}

		domainChatJID := s.toDomainJID(chatJID)

		// Only upsert chat metadata for initial bootstrap sync
		if isInitialSync {
			// Determine chat type
			chatType := domain.ChatTypePrivate
			if chatJID.Server == types.GroupServer {
				chatType = domain.ChatTypeGroup
			}

			// Get or create chat
			chatName := conv.GetName()
			if chatName == "" {
				chatName = conv.GetID()
			}

			chat := &domain.Chat{
				JID:         domainChatJID,
				Type:        chatType,
				Name:        chatName,
				UnreadCount: int(conv.GetUnreadCount()),
				IsArchived:  conv.GetArchived(),
			}

			if err := s.chatRepo.Upsert(ctx, chat); err != nil {
				s.logger.Warnf("Failed to upsert chat %s: %v", conv.GetID(), err)
			}
		}

		// Process messages in this conversation
		for _, historyMsg := range conv.GetMessages() {
			webMsg := historyMsg.GetMessage()
			if webMsg == nil || webMsg.Message == nil {
				continue
			}

			msg := s.convertHistorySyncMessage(webMsg, domainChatJID)
			if msg == nil {
				continue
			}

			// Use CreateOrIgnore to avoid duplicates
			if err := s.msgRepo.CreateOrIgnore(ctx, msg); err != nil {
				s.logger.Warnf("Failed to persist history message: %v", err)
			}

			// For non-initial syncs, ensure the chat exists (create if not)
			if !isInitialSync {
				s.ensureChatExists(ctx, domainChatJID, chatJID)
			}
		}

		// Update chat with last message info if available (only for initial sync)
		if isInitialSync && len(conv.GetMessages()) > 0 {
			lastMsg := conv.GetMessages()[0].GetMessage()
			if lastMsg != nil && lastMsg.Message != nil {
				text := s.extractMessageText(lastMsg.Message)
				senderName := "unknown"
				if lastMsg.GetKey().GetFromMe() {
					senderName = "me"
				} else if lastMsg.GetParticipant() != "" {
					senderName = lastMsg.GetParticipant()
				}
				timestamp := time.Unix(int64(lastMsg.GetMessageTimestamp()), 0)
				if err := s.chatRepo.UpdateLastMessage(ctx, domainChatJID, text, senderName, timestamp); err != nil {
					s.logger.Warnf("Failed to update chat last message: %v", err)
				}
			}
		}
	}

	s.logger.Infof("History sync processing complete")
}

func (s *WhatsAppService) ensureChatExists(ctx context.Context, domainChatJID domain.JID, chatJID types.JID) {
	// Check if chat exists, create minimal entry if not
	existing, err := s.chatRepo.GetByJID(ctx, domainChatJID)
	if err != nil {
		s.logger.Warnf("Failed to check chat existence: %v", err)
		return
	}
	if existing != nil {
		return // Chat already exists
	}

	// Create minimal chat entry
	chatType := domain.ChatTypePrivate
	if chatJID.Server == types.GroupServer {
		chatType = domain.ChatTypeGroup
	}

	chat := &domain.Chat{
		JID:  domainChatJID,
		Type: chatType,
		Name: chatJID.User, // Use user part as fallback name
	}

	if err := s.chatRepo.Upsert(ctx, chat); err != nil {
		s.logger.Warnf("Failed to create chat %s: %v", chatJID.String(), err)
	}
}

func (s *WhatsAppService) handleMarkChatAsRead(evt *events.MarkChatAsRead) {
	ctx := context.Background()
	chatJID := s.toDomainJID(evt.JID)

	// When a chat is marked as read from another device, reset unread count to 0
	if evt.Action.GetRead() {
		if err := s.chatRepo.UpdateUnreadCount(ctx, chatJID, 0); err != nil {
			s.logger.Warnf("Failed to update unread count for %s: %v", evt.JID.String(), err)
		} else {
			s.logger.Infof("Chat %s marked as read from another device", evt.JID.String())
		}
	}
}

func (s *WhatsAppService) handleArchive(evt *events.Archive) {
	ctx := context.Background()
	chatJID := s.toDomainJID(evt.JID)

	archived := evt.Action.GetArchived()
	if err := s.chatRepo.UpdateArchived(ctx, chatJID, archived); err != nil {
		s.logger.Warnf("Failed to update archived status for %s: %v", evt.JID.String(), err)
	} else {
		if archived {
			s.logger.Infof("Chat %s archived from another device", evt.JID.String())
		} else {
			s.logger.Infof("Chat %s unarchived from another device", evt.JID.String())
		}
	}
}

func (s *WhatsAppService) convertHistorySyncMessage(webMsg *waWeb.WebMessageInfo, chatJID domain.JID) *domain.Message {
	if webMsg == nil || webMsg.Message == nil {
		return nil
	}

	msgKey := webMsg.GetKey()
	senderJIDStr := msgKey.GetParticipant()
	if senderJIDStr == "" {
		if msgKey.GetFromMe() {
			// Use own JID for messages from self
			if s.client != nil && s.client.Store.ID != nil {
				senderJIDStr = s.client.Store.ID.String()
			}
		} else {
			senderJIDStr = msgKey.GetRemoteJID()
		}
	}

	senderJID, _ := types.ParseJID(senderJIDStr)
	domainSenderJID := s.toDomainJID(senderJID)

	var msgType domain.MessageType
	var text, caption, mimeType, fileName string

	waMsg := webMsg.Message
	if waMsg.GetConversation() != "" {
		msgType = domain.MessageTypeText
		text = waMsg.GetConversation()
	} else if waMsg.GetExtendedTextMessage() != nil {
		msgType = domain.MessageTypeText
		text = waMsg.GetExtendedTextMessage().GetText()
	} else if waMsg.GetImageMessage() != nil {
		msgType = domain.MessageTypeImage
		caption = waMsg.GetImageMessage().GetCaption()
		mimeType = waMsg.GetImageMessage().GetMimetype()
	} else if waMsg.GetVideoMessage() != nil {
		msgType = domain.MessageTypeVideo
		caption = waMsg.GetVideoMessage().GetCaption()
		mimeType = waMsg.GetVideoMessage().GetMimetype()
	} else if waMsg.GetAudioMessage() != nil {
		msgType = domain.MessageTypeAudio
		mimeType = waMsg.GetAudioMessage().GetMimetype()
	} else if waMsg.GetDocumentMessage() != nil {
		msgType = domain.MessageTypeDocument
		caption = waMsg.GetDocumentMessage().GetCaption()
		mimeType = waMsg.GetDocumentMessage().GetMimetype()
		fileName = waMsg.GetDocumentMessage().GetFileName()
	} else if waMsg.GetStickerMessage() != nil {
		msgType = domain.MessageTypeSticker
		mimeType = waMsg.GetStickerMessage().GetMimetype()
	} else {
		// Skip unsupported message types
		return nil
	}

	timestamp := time.Unix(int64(webMsg.GetMessageTimestamp()), 0)

	return &domain.Message{
		ID:            msgKey.GetID(),
		ChatJID:       chatJID,
		SenderJID:     domainSenderJID,
		Type:          msgType,
		Text:          text,
		Caption:       caption,
		MediaMimeType: mimeType,
		MediaFileName: fileName,
		Timestamp:     timestamp,
		IsFromMe:      msgKey.GetFromMe(),
		IsRead:        true, // Historical messages are considered read
	}
}

func (s *WhatsAppService) extractMessageText(msg *waE2E.Message) string {
	if msg.GetConversation() != "" {
		return msg.GetConversation()
	}
	if msg.GetExtendedTextMessage() != nil {
		return msg.GetExtendedTextMessage().GetText()
	}
	if msg.GetImageMessage() != nil && msg.GetImageMessage().GetCaption() != "" {
		return msg.GetImageMessage().GetCaption()
	}
	if msg.GetVideoMessage() != nil && msg.GetVideoMessage().GetCaption() != "" {
		return msg.GetVideoMessage().GetCaption()
	}
	if msg.GetDocumentMessage() != nil && msg.GetDocumentMessage().GetCaption() != "" {
		return msg.GetDocumentMessage().GetCaption()
	}
	return "[media]"
}

func (s *WhatsAppService) convertMessage(evt *events.Message) *domain.Message {
	chatJID := s.toDomainJID(evt.Info.Chat)
	senderJID := s.toDomainJID(evt.Info.Sender)

	var msgType domain.MessageType
	var text, caption, mediaURL, mimeType, fileName string

	if evt.Message.GetConversation() != "" {
		msgType = domain.MessageTypeText
		text = evt.Message.GetConversation()
	} else if evt.Message.GetExtendedTextMessage() != nil {
		msgType = domain.MessageTypeText
		text = evt.Message.GetExtendedTextMessage().GetText()
	} else if evt.Message.GetImageMessage() != nil {
		msgType = domain.MessageTypeImage
		caption = evt.Message.GetImageMessage().GetCaption()
		mimeType = evt.Message.GetImageMessage().GetMimetype()
	} else if evt.Message.GetVideoMessage() != nil {
		msgType = domain.MessageTypeVideo
		caption = evt.Message.GetVideoMessage().GetCaption()
		mimeType = evt.Message.GetVideoMessage().GetMimetype()
	} else if evt.Message.GetAudioMessage() != nil {
		msgType = domain.MessageTypeAudio
		mimeType = evt.Message.GetAudioMessage().GetMimetype()
	} else if evt.Message.GetDocumentMessage() != nil {
		msgType = domain.MessageTypeDocument
		caption = evt.Message.GetDocumentMessage().GetCaption()
		mimeType = evt.Message.GetDocumentMessage().GetMimetype()
		fileName = evt.Message.GetDocumentMessage().GetFileName()
	} else if evt.Message.GetStickerMessage() != nil {
		msgType = domain.MessageTypeSticker
		mimeType = evt.Message.GetStickerMessage().GetMimetype()
	} else if evt.Message.GetReactionMessage() != nil {
		msgType = domain.MessageTypeReaction
		text = evt.Message.GetReactionMessage().GetText()
	} else if evt.Message.GetLocationMessage() != nil {
		msgType = domain.MessageTypeLocation
	} else {
		return nil
	}

	msg := &domain.Message{
		ID:            evt.Info.ID,
		ChatJID:       chatJID,
		SenderJID:     senderJID,
		Type:          msgType,
		Text:          text,
		Caption:       caption,
		MediaURL:      mediaURL,
		MediaMimeType: mimeType,
		MediaFileName: fileName,
		Timestamp:     evt.Info.Timestamp,
		IsFromMe:      evt.Info.IsFromMe,
		IsRead:        false,
	}

	if evt.Message.GetReactionMessage() != nil {
		msg.Reaction = &domain.Reaction{
			TargetMessageID: evt.Message.GetReactionMessage().GetKey().GetID(),
			Emoji:           evt.Message.GetReactionMessage().GetText(),
			SenderJID:       senderJID,
			Timestamp:       evt.Info.Timestamp,
		}
	}

	if evt.Message.GetLocationMessage() != nil {
		loc := evt.Message.GetLocationMessage()
		msg.Location = &domain.Location{
			Latitude:  float64(loc.GetDegreesLatitude()),
			Longitude: float64(loc.GetDegreesLongitude()),
			Name:      loc.GetName(),
			Address:   loc.GetAddress(),
		}
	}

	return msg
}

func (s *WhatsAppService) toWhatsmeowJID(jid domain.JID) types.JID {
	return types.JID{
		User:   jid.User,
		Server: jid.Server,
		Device: jid.Device,
	}
}

func (s *WhatsAppService) toDomainJID(jid types.JID) domain.JID {
	return domain.JID{
		User:   jid.User,
		Server: jid.Server,
		Device: jid.Device,
	}
}

func (s *WhatsAppService) getOwnJID() domain.JID {
	if s.client != nil && s.client.Store.ID != nil {
		return s.toDomainJID(*s.client.Store.ID)
	}
	return domain.JID{}
}

func (s *WhatsAppService) GetEventBus() domain.EventBus {
	return s.eventBus
}
