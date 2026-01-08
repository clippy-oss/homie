package repository

import (
	"time"

	"github.com/clippy-oss/homie/whatsapp-bridge/internal/domain"
)

type MessageModel struct {
	ID              string    `gorm:"primaryKey;column:id"`
	ChatJID         string    `gorm:"column:chat_jid;index:idx_chat_timestamp"`
	SenderJID       string    `gorm:"column:sender_jid"`
	Type            string    `gorm:"column:type"`
	Text            string    `gorm:"column:text"`
	Caption         string    `gorm:"column:caption"`
	MediaURL        string    `gorm:"column:media_url"`
	MediaMimeType   string    `gorm:"column:media_mime_type"`
	MediaFileName   string    `gorm:"column:media_file_name"`
	MediaFileSize   int64     `gorm:"column:media_file_size"`
	Timestamp       time.Time `gorm:"column:timestamp;index:idx_chat_timestamp"`
	IsFromMe        bool      `gorm:"column:is_from_me"`
	IsRead          bool      `gorm:"column:is_read;index"`
	QuotedMessageID string    `gorm:"column:quoted_message_id"`
	ReactionEmoji   string    `gorm:"column:reaction_emoji"`
	ReactionTarget  string    `gorm:"column:reaction_target"`
	LocationLat     float64   `gorm:"column:location_lat"`
	LocationLng     float64   `gorm:"column:location_lng"`
	LocationName    string    `gorm:"column:location_name"`
	LocationAddress string    `gorm:"column:location_address"`
	ContactName     string    `gorm:"column:contact_name"`
	ContactPhone    string    `gorm:"column:contact_phone"`
	ContactVCard    string    `gorm:"column:contact_vcard"`
	CreatedAt       time.Time `gorm:"column:created_at"`
	UpdatedAt       time.Time `gorm:"column:updated_at"`
}

func (MessageModel) TableName() string { return "messages" }

type ChatModel struct {
	JID               string    `gorm:"primaryKey;column:jid"`
	Type              string    `gorm:"column:type"`
	Name              string    `gorm:"column:name"`
	LastMessageTime   time.Time `gorm:"column:last_message_time;index"`
	LastMessageText   string    `gorm:"column:last_message_text"`
	LastMessageSender string    `gorm:"column:last_message_sender"`
	UnreadCount       int       `gorm:"column:unread_count"`
	IsMuted           bool      `gorm:"column:is_muted"`
	IsArchived        bool      `gorm:"column:is_archived"`
	IsPinned          bool      `gorm:"column:is_pinned"`
	CreatedAt         time.Time `gorm:"column:created_at"`
	UpdatedAt         time.Time `gorm:"column:updated_at"`
}

func (ChatModel) TableName() string { return "chats" }

// ContactModel is no longer used - contacts are stored by whatsmeow's built-in
// ContactStore (whatsmeow_contacts table). Use WhatsAppService.GetContacts() instead.

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

// Contact conversion functions removed - contacts are stored by whatsmeow's
// built-in ContactStore. Use WhatsAppService.GetContacts() instead.
