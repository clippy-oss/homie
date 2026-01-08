package service

import (
	"context"
	"fmt"
	"sync"
	"time"

	"go.mau.fi/whatsmeow"
	"go.mau.fi/whatsmeow/proto/waE2E"
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
	client      *whatsmeow.Client
	device      *store.Device
	eventBus    domain.EventBus
	msgRepo     repository.MessageRepository
	chatRepo    repository.ChatRepository
	contactRepo repository.ContactRepository
	config      WhatsAppServiceConfig
	logger      waLog.Logger

	mu        sync.RWMutex
	connected bool
}

func NewWhatsAppService(
	device *store.Device,
	eventBus domain.EventBus,
	msgRepo repository.MessageRepository,
	chatRepo repository.ChatRepository,
	contactRepo repository.ContactRepository,
	config WhatsAppServiceConfig,
	logger waLog.Logger,
) *WhatsAppService {
	return &WhatsAppService{
		device:      device,
		eventBus:    eventBus,
		msgRepo:     msgRepo,
		chatRepo:    chatRepo,
		contactRepo: contactRepo,
		config:      config,
		logger:      logger,
	}
}

func (s *WhatsAppService) Connect(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.client != nil && s.client.IsConnected() {
		return nil
	}

	s.client = whatsmeow.NewClient(s.device, s.logger)
	s.client.AddEventHandler(s.handleEvent)

	return s.client.Connect()
}

func (s *WhatsAppService) Disconnect() {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.client != nil {
		s.client.Disconnect()
		s.client = nil
	}
	s.connected = false
}

func (s *WhatsAppService) Logout(ctx context.Context) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.client == nil {
		return fmt.Errorf("not connected")
	}

	// Logout from WhatsApp (removes device from linked devices)
	err := s.client.Logout(ctx)
	if err != nil {
		return fmt.Errorf("failed to logout: %w", err)
	}

	// Disconnect and clear client
	s.client.Disconnect()
	s.client = nil
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

func (s *WhatsAppService) GetQRChannel(ctx context.Context) (<-chan whatsmeow.QRChannelItem, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.client == nil {
		s.client = whatsmeow.NewClient(s.device, s.logger)
		s.client.AddEventHandler(s.handleEvent)
	}

	if s.device.ID != nil {
		return nil, fmt.Errorf("already logged in")
	}

	return s.client.GetQRChannel(ctx)
}

func (s *WhatsAppService) PairWithCode(ctx context.Context, phoneNumber string) (string, error) {
	s.mu.Lock()
	defer s.mu.Unlock()

	if s.client == nil {
		s.client = whatsmeow.NewClient(s.device, s.logger)
		s.client.AddEventHandler(s.handleEvent)
	}

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

	case *events.Message:
		s.handleMessage(v)

	case *events.Receipt:
		s.handleReceipt(v)

	case *events.PushName:
		s.handlePushName(v)
	}
}

func (s *WhatsAppService) handleMessage(evt *events.Message) {
	msg := s.convertMessage(evt)
	if msg == nil {
		return
	}

	ctx := context.Background()

	if err := s.msgRepo.Create(ctx, msg); err != nil {
		s.logger.Warnf("Failed to persist message: %v", err)
	}

	senderName := msg.SenderJID.User
	if !msg.IsFromMe {
		if err := s.chatRepo.IncrementUnreadCount(ctx, msg.ChatJID); err != nil {
			s.logger.Warnf("Failed to increment unread count: %v", err)
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
		s.logger.Warnf("Failed to update chat: %v", err)
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
	ctx := context.Background()
	jid := s.toDomainJID(evt.JID)

	contact := &domain.Contact{
		JID:      jid,
		PushName: evt.NewPushName,
	}

	if err := s.contactRepo.Upsert(ctx, contact); err != nil {
		s.logger.Warnf("Failed to update contact push name: %v", err)
	}
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
