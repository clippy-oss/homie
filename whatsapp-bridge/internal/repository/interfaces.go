package repository

import (
	"context"
	"time"

	"github.com/clippy-oss/homie/whatsapp-bridge/internal/domain"
)

type MessageRepository interface {
	Create(ctx context.Context, msg *domain.Message) error
	CreateOrIgnore(ctx context.Context, msg *domain.Message) error
	GetByID(ctx context.Context, id string) (*domain.Message, error)
	GetByChatJID(ctx context.Context, chatJID domain.JID, limit, offset int) ([]*domain.Message, error)
	GetByChatJIDSince(ctx context.Context, chatJID domain.JID, since time.Time, limit int) ([]*domain.Message, error)
	UpdateReadStatus(ctx context.Context, ids []string, isRead bool) error
	Search(ctx context.Context, query string, limit int) ([]*domain.Message, error)
	DeleteByChatJID(ctx context.Context, chatJID domain.JID) error
}

type ChatRepository interface {
	Upsert(ctx context.Context, chat *domain.Chat) error
	GetByJID(ctx context.Context, jid domain.JID) (*domain.Chat, error)
	GetAll(ctx context.Context, limit, offset int) ([]*domain.Chat, error)
	UpdateLastMessage(ctx context.Context, jid domain.JID, text, sender string, timestamp time.Time) error
	UpdateUnreadCount(ctx context.Context, jid domain.JID, count int) error
	IncrementUnreadCount(ctx context.Context, jid domain.JID) error
	Delete(ctx context.Context, jid domain.JID) error
}

type ContactRepository interface {
	Upsert(ctx context.Context, contact *domain.Contact) error
	GetByJID(ctx context.Context, jid domain.JID) (*domain.Contact, error)
	GetAll(ctx context.Context) ([]*domain.Contact, error)
	Search(ctx context.Context, query string) ([]*domain.Contact, error)
	Delete(ctx context.Context, jid domain.JID) error
}
