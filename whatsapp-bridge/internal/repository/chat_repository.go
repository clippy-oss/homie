package repository

import (
	"context"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"github.com/clippy-oss/homie/whatsapp-bridge/internal/domain"
)

type gormChatRepository struct {
	db *gorm.DB
}

func NewChatRepository(db *gorm.DB) ChatRepository {
	return &gormChatRepository{db: db}
}

func (r *gormChatRepository) Upsert(ctx context.Context, chat *domain.Chat) error {
	model := ChatDomainToModel(chat)
	return r.db.WithContext(ctx).Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "jid"}},
		UpdateAll: true,
	}).Create(model).Error
}

func (r *gormChatRepository) GetByJID(ctx context.Context, jid domain.JID) (*domain.Chat, error) {
	var model ChatModel
	if err := r.db.WithContext(ctx).First(&model, "jid = ?", jid.String()).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, nil
		}
		return nil, err
	}
	return ChatModelToDomain(&model), nil
}

func (r *gormChatRepository) GetAll(ctx context.Context, limit, offset int) ([]*domain.Chat, error) {
	var models []ChatModel
	query := r.db.WithContext(ctx).Order("last_message_time DESC")

	if limit > 0 {
		query = query.Limit(limit).Offset(offset)
	}

	if err := query.Find(&models).Error; err != nil {
		return nil, err
	}

	chats := make([]*domain.Chat, len(models))
	for i := range models {
		chats[i] = ChatModelToDomain(&models[i])
	}
	return chats, nil
}

func (r *gormChatRepository) UpdateLastMessage(ctx context.Context, jid domain.JID, text, sender string, timestamp time.Time) error {
	return r.db.WithContext(ctx).
		Model(&ChatModel{}).
		Where("jid = ?", jid.String()).
		Updates(map[string]interface{}{
			"last_message_text":   text,
			"last_message_sender": sender,
			"last_message_time":   timestamp,
		}).Error
}

func (r *gormChatRepository) UpdateUnreadCount(ctx context.Context, jid domain.JID, count int) error {
	return r.db.WithContext(ctx).
		Model(&ChatModel{}).
		Where("jid = ?", jid.String()).
		Update("unread_count", count).Error
}

func (r *gormChatRepository) IncrementUnreadCount(ctx context.Context, jid domain.JID) error {
	return r.db.WithContext(ctx).
		Model(&ChatModel{}).
		Where("jid = ?", jid.String()).
		UpdateColumn("unread_count", gorm.Expr("unread_count + ?", 1)).Error
}

func (r *gormChatRepository) Delete(ctx context.Context, jid domain.JID) error {
	return r.db.WithContext(ctx).
		Where("jid = ?", jid.String()).
		Delete(&ChatModel{}).Error
}
