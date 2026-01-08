package repository

import (
	"time"

	"github.com/clippy-oss/homie/whatsapp-bridge/internal/domain"
)

type MessageModel struct {
	ID              string `gorm:"primaryKey"`
	ChatJID         string `gorm:"index:idx_chat_timestamp"`
	SenderJID       string
	Type            string
	Text            string
	Caption         string
	MediaURL        string
	MediaMimeType   string
	MediaFileName   string
	MediaFileSize   int64
	Timestamp       time.Time `gorm:"index:idx_chat_timestamp"`
	IsFromMe        bool
	IsRead          bool `gorm:"index"`
	QuotedMessageID string
	ReactionEmoji   string
	ReactionTarget  string
	LocationLat     float64
	LocationLng     float64
	LocationName    string
	LocationAddress string
	ContactName     string
	ContactPhone    string
	ContactVCard    string
	CreatedAt       time.Time
	UpdatedAt       time.Time
}

func (MessageModel) TableName() string { return "messages" }

type ChatModel struct {
	JID               string `gorm:"primaryKey"`
	Type              string
	Name              string
	LastMessageTime   time.Time `gorm:"index"`
	LastMessageText   string
	LastMessageSender string
	UnreadCount       int
	IsMuted           bool
	IsArchived        bool
	IsPinned          bool
	CreatedAt         time.Time
	UpdatedAt         time.Time
}

func (ChatModel) TableName() string { return "chats" }

type ContactModel struct {
	JID          string `gorm:"primaryKey"`
	Name         string
	PushName     string
	BusinessName string
	PhoneNumber  string `gorm:"index"`
	AvatarURL    string
	CreatedAt    time.Time
	UpdatedAt    time.Time
}

func (ContactModel) TableName() string { return "contacts" }

// Conversion functions
func MessageModelToDomain(m *MessageModel) *domain.Message {
	if m == nil {
		return nil
	}

	chatJID, _ := domain.ParseJID(m.ChatJID)
	senderJID, _ := domain.ParseJID(m.SenderJID)

	msg := &domain.Message{
		ID:              m.ID,
		ChatJID:         chatJID,
		SenderJID:       senderJID,
		Type:            domain.MessageType(m.Type),
		Text:            m.Text,
		Caption:         m.Caption,
		MediaURL:        m.MediaURL,
		MediaMimeType:   m.MediaMimeType,
		MediaFileName:   m.MediaFileName,
		MediaFileSize:   m.MediaFileSize,
		Timestamp:       m.Timestamp,
		IsFromMe:        m.IsFromMe,
		IsRead:          m.IsRead,
		QuotedMessageID: m.QuotedMessageID,
	}

	if m.ReactionEmoji != "" {
		reactionSenderJID, _ := domain.ParseJID(m.SenderJID)
		msg.Reaction = &domain.Reaction{
			TargetMessageID: m.ReactionTarget,
			Emoji:           m.ReactionEmoji,
			SenderJID:       reactionSenderJID,
		}
	}

	if m.LocationLat != 0 || m.LocationLng != 0 {
		msg.Location = &domain.Location{
			Latitude:  m.LocationLat,
			Longitude: m.LocationLng,
			Name:      m.LocationName,
			Address:   m.LocationAddress,
		}
	}

	if m.ContactName != "" || m.ContactPhone != "" {
		msg.ContactCard = &domain.ContactCard{
			Name:        m.ContactName,
			PhoneNumber: m.ContactPhone,
			VCard:       m.ContactVCard,
		}
	}

	return msg
}

func MessageDomainToModel(msg *domain.Message) *MessageModel {
	if msg == nil {
		return nil
	}

	model := &MessageModel{
		ID:              msg.ID,
		ChatJID:         msg.ChatJID.String(),
		SenderJID:       msg.SenderJID.String(),
		Type:            string(msg.Type),
		Text:            msg.Text,
		Caption:         msg.Caption,
		MediaURL:        msg.MediaURL,
		MediaMimeType:   msg.MediaMimeType,
		MediaFileName:   msg.MediaFileName,
		MediaFileSize:   msg.MediaFileSize,
		Timestamp:       msg.Timestamp,
		IsFromMe:        msg.IsFromMe,
		IsRead:          msg.IsRead,
		QuotedMessageID: msg.QuotedMessageID,
	}

	if msg.Reaction != nil {
		model.ReactionEmoji = msg.Reaction.Emoji
		model.ReactionTarget = msg.Reaction.TargetMessageID
	}

	if msg.Location != nil {
		model.LocationLat = msg.Location.Latitude
		model.LocationLng = msg.Location.Longitude
		model.LocationName = msg.Location.Name
		model.LocationAddress = msg.Location.Address
	}

	if msg.ContactCard != nil {
		model.ContactName = msg.ContactCard.Name
		model.ContactPhone = msg.ContactCard.PhoneNumber
		model.ContactVCard = msg.ContactCard.VCard
	}

	return model
}

func ChatModelToDomain(m *ChatModel) *domain.Chat {
	if m == nil {
		return nil
	}

	jid, _ := domain.ParseJID(m.JID)

	return &domain.Chat{
		JID:               jid,
		Type:              domain.ChatType(m.Type),
		Name:              m.Name,
		LastMessageTime:   m.LastMessageTime,
		LastMessageText:   m.LastMessageText,
		LastMessageSender: m.LastMessageSender,
		UnreadCount:       m.UnreadCount,
		IsMuted:           m.IsMuted,
		IsArchived:        m.IsArchived,
		IsPinned:          m.IsPinned,
	}
}

func ChatDomainToModel(chat *domain.Chat) *ChatModel {
	if chat == nil {
		return nil
	}

	return &ChatModel{
		JID:               chat.JID.String(),
		Type:              string(chat.Type),
		Name:              chat.Name,
		LastMessageTime:   chat.LastMessageTime,
		LastMessageText:   chat.LastMessageText,
		LastMessageSender: chat.LastMessageSender,
		UnreadCount:       chat.UnreadCount,
		IsMuted:           chat.IsMuted,
		IsArchived:        chat.IsArchived,
		IsPinned:          chat.IsPinned,
	}
}

func ContactModelToDomain(m *ContactModel) *domain.Contact {
	if m == nil {
		return nil
	}

	jid, _ := domain.ParseJID(m.JID)

	return &domain.Contact{
		JID:          jid,
		Name:         m.Name,
		PushName:     m.PushName,
		BusinessName: m.BusinessName,
		PhoneNumber:  m.PhoneNumber,
		AvatarURL:    m.AvatarURL,
	}
}

func ContactDomainToModel(contact *domain.Contact) *ContactModel {
	if contact == nil {
		return nil
	}

	return &ContactModel{
		JID:          contact.JID.String(),
		Name:         contact.Name,
		PushName:     contact.PushName,
		BusinessName: contact.BusinessName,
		PhoneNumber:  contact.PhoneNumber,
		AvatarURL:    contact.AvatarURL,
	}
}
