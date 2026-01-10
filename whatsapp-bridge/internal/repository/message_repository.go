package repository

import (
	"context"
	"strings"
	"time"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"github.com/clippy-oss/homie/whatsapp-bridge/internal/domain"
)

type gormMessageRepository struct {
	db *gorm.DB
}

func NewMessageRepository(db *gorm.DB) MessageRepository {
	return &gormMessageRepository{db: db}
}

func (r *gormMessageRepository) Create(ctx context.Context, msg *domain.Message) error {
	model := MessageDomainToModel(msg)
	return r.db.WithContext(ctx).Create(model).Error
}

func (r *gormMessageRepository) CreateOrIgnore(ctx context.Context, msg *domain.Message) error {
	model := MessageDomainToModel(msg)
	// Use INSERT OR IGNORE to skip duplicates (SQLite)
	return r.db.WithContext(ctx).
		Clauses(clause.OnConflict{DoNothing: true}).
		Create(model).Error
}

func (r *gormMessageRepository) GetByID(ctx context.Context, id string) (*domain.Message, error) {
	var model MessageModel
	if err := r.db.WithContext(ctx).First(&model, "id = ?", id).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, nil
		}
		return nil, err
	}
	return MessageModelToDomain(&model), nil
}

func (r *gormMessageRepository) GetByChatJID(ctx context.Context, chatJID domain.JID, limit, offset int) ([]*domain.Message, error) {
	var models []MessageModel
	err := r.db.WithContext(ctx).
		Where("chat_jid = ?", chatJID.String()).
		Order("timestamp DESC").
		Limit(limit).
		Offset(offset).
		Find(&models).Error
	if err != nil {
		return nil, err
	}

	messages := make([]*domain.Message, len(models))
	for i := range models {
		messages[i] = MessageModelToDomain(&models[i])
	}
	return messages, nil
}

func (r *gormMessageRepository) GetByChatJIDSince(ctx context.Context, chatJID domain.JID, since time.Time, limit int) ([]*domain.Message, error) {
	var models []MessageModel
	err := r.db.WithContext(ctx).
		Where("chat_jid = ? AND timestamp > ?", chatJID.String(), since).
		Order("timestamp ASC").
		Limit(limit).
		Find(&models).Error
	if err != nil {
		return nil, err
	}

	messages := make([]*domain.Message, len(models))
	for i := range models {
		messages[i] = MessageModelToDomain(&models[i])
	}
	return messages, nil
}

func (r *gormMessageRepository) UpdateReadStatus(ctx context.Context, ids []string, isRead bool) error {
	return r.db.WithContext(ctx).
		Model(&MessageModel{}).
		Where("id IN ?", ids).
		Update("is_read", isRead).Error
}

func (r *gormMessageRepository) Search(ctx context.Context, query string, limit int) ([]*domain.Message, error) {
	// Escape LIKE special characters to prevent SQL injection
	escapedQuery := strings.ReplaceAll(query, "%", "\\%")
	escapedQuery = strings.ReplaceAll(escapedQuery, "_", "\\_")
	likePattern := "%" + escapedQuery + "%"

	var models []MessageModel
	err := r.db.WithContext(ctx).
		Where("text LIKE ? ESCAPE '\\' OR caption LIKE ? ESCAPE '\\'", likePattern, likePattern).
		Order("timestamp DESC").
		Limit(limit).
		Find(&models).Error
	if err != nil {
		return nil, err
	}

	messages := make([]*domain.Message, len(models))
	for i := range models {
		messages[i] = MessageModelToDomain(&models[i])
	}
	return messages, nil
}

func (r *gormMessageRepository) DeleteByChatJID(ctx context.Context, chatJID domain.JID) error {
	return r.db.WithContext(ctx).
		Where("chat_jid = ?", chatJID.String()).
		Delete(&MessageModel{}).Error
}
