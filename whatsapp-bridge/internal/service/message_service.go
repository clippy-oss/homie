package service

import (
	"context"
	"time"

	"github.com/clippy-oss/homie/whatsapp-bridge/internal/domain"
	"github.com/clippy-oss/homie/whatsapp-bridge/internal/repository"
)

type MessageService struct {
	msgRepo  repository.MessageRepository
	chatRepo repository.ChatRepository
	waSvc    *WhatsAppService
}

func NewMessageService(
	msgRepo repository.MessageRepository,
	chatRepo repository.ChatRepository,
	waSvc *WhatsAppService,
) *MessageService {
	return &MessageService{
		msgRepo:  msgRepo,
		chatRepo: chatRepo,
		waSvc:    waSvc,
	}
}

func (s *MessageService) GetMessages(ctx context.Context, chatJID domain.JID, limit, offset int) ([]*domain.Message, error) {
	return s.msgRepo.GetByChatJID(ctx, chatJID, limit, offset)
}

func (s *MessageService) GetMessagesSince(ctx context.Context, chatJID domain.JID, since time.Time, limit int) ([]*domain.Message, error) {
	return s.msgRepo.GetByChatJIDSince(ctx, chatJID, since, limit)
}

func (s *MessageService) GetMessage(ctx context.Context, id string) (*domain.Message, error) {
	return s.msgRepo.GetByID(ctx, id)
}

func (s *MessageService) SendTextMessage(ctx context.Context, chatJID domain.JID, text string) (*domain.Message, error) {
	return s.waSvc.SendTextMessage(ctx, chatJID, text)
}

func (s *MessageService) SendReaction(ctx context.Context, chatJID domain.JID, targetMessageID, senderJID, emoji string) error {
	return s.waSvc.SendReaction(ctx, chatJID, targetMessageID, senderJID, emoji)
}

func (s *MessageService) MarkAsRead(ctx context.Context, chatJID domain.JID, messageIDs []string) error {
	return s.waSvc.MarkAsRead(ctx, chatJID, messageIDs)
}

func (s *MessageService) SearchMessages(ctx context.Context, query string, limit int) ([]*domain.Message, error) {
	return s.msgRepo.Search(ctx, query, limit)
}

func (s *MessageService) GetChats(ctx context.Context, limit, offset int) ([]*domain.Chat, error) {
	return s.chatRepo.GetAll(ctx, limit, offset)
}

func (s *MessageService) GetChat(ctx context.Context, jid domain.JID) (*domain.Chat, error) {
	return s.chatRepo.GetByJID(ctx, jid)
}
