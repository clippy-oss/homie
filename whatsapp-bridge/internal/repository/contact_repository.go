package repository

import (
	"context"

	"gorm.io/gorm"
	"gorm.io/gorm/clause"

	"github.com/clippy-oss/homie/whatsapp-bridge/internal/domain"
)

type gormContactRepository struct {
	db *gorm.DB
}

func NewContactRepository(db *gorm.DB) ContactRepository {
	return &gormContactRepository{db: db}
}

func (r *gormContactRepository) Upsert(ctx context.Context, contact *domain.Contact) error {
	model := ContactDomainToModel(contact)
	return r.db.WithContext(ctx).Clauses(clause.OnConflict{
		Columns:   []clause.Column{{Name: "jid"}},
		UpdateAll: true,
	}).Create(model).Error
}

func (r *gormContactRepository) GetByJID(ctx context.Context, jid domain.JID) (*domain.Contact, error) {
	var model ContactModel
	if err := r.db.WithContext(ctx).First(&model, "jid = ?", jid.String()).Error; err != nil {
		if err == gorm.ErrRecordNotFound {
			return nil, nil
		}
		return nil, err
	}
	return ContactModelToDomain(&model), nil
}

func (r *gormContactRepository) GetAll(ctx context.Context) ([]*domain.Contact, error) {
	var models []ContactModel
	if err := r.db.WithContext(ctx).Order("name ASC").Find(&models).Error; err != nil {
		return nil, err
	}

	contacts := make([]*domain.Contact, len(models))
	for i := range models {
		contacts[i] = ContactModelToDomain(&models[i])
	}
	return contacts, nil
}

func (r *gormContactRepository) Search(ctx context.Context, query string) ([]*domain.Contact, error) {
	var models []ContactModel
	err := r.db.WithContext(ctx).
		Where("name LIKE ? OR push_name LIKE ? OR business_name LIKE ? OR phone_number LIKE ?",
			"%"+query+"%", "%"+query+"%", "%"+query+"%", "%"+query+"%").
		Order("name ASC").
		Find(&models).Error
	if err != nil {
		return nil, err
	}

	contacts := make([]*domain.Contact, len(models))
	for i := range models {
		contacts[i] = ContactModelToDomain(&models[i])
	}
	return contacts, nil
}

func (r *gormContactRepository) Delete(ctx context.Context, jid domain.JID) error {
	return r.db.WithContext(ctx).
		Where("jid = ?", jid.String()).
		Delete(&ContactModel{}).Error
}
