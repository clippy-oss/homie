package domain

import "time"

type MessageType string

const (
	MessageTypeText     MessageType = "text"
	MessageTypeImage    MessageType = "image"
	MessageTypeVideo    MessageType = "video"
	MessageTypeAudio    MessageType = "audio"
	MessageTypeDocument MessageType = "document"
	MessageTypeSticker  MessageType = "sticker"
	MessageTypeReaction MessageType = "reaction"
	MessageTypeLocation MessageType = "location"
	MessageTypeContact  MessageType = "contact"
)

type Message struct {
	ID              string
	ChatJID         JID
	SenderJID       JID
	Type            MessageType
	Text            string
	Caption         string
	MediaURL        string
	MediaMimeType   string
	MediaFileName   string
	MediaFileSize   int64
	Timestamp       time.Time
	IsFromMe        bool
	IsRead          bool
	QuotedMessageID string
	Reaction        *Reaction
	Location        *Location
	ContactCard     *ContactCard
}

type Reaction struct {
	TargetMessageID string
	Emoji           string
	SenderJID       JID
	Timestamp       time.Time
}

type Location struct {
	Latitude  float64
	Longitude float64
	Name      string
	Address   string
}

type ContactCard struct {
	Name        string
	PhoneNumber string
	VCard       string
}

func NewTextMessage(id string, chatJID, senderJID JID, text string, timestamp time.Time, isFromMe bool) *Message {
	return &Message{
		ID:        id,
		ChatJID:   chatJID,
		SenderJID: senderJID,
		Type:      MessageTypeText,
		Text:      text,
		Timestamp: timestamp,
		IsFromMe:  isFromMe,
	}
}

func NewMediaMessage(id string, chatJID, senderJID JID, msgType MessageType, caption, mediaURL, mimeType, fileName string, fileSize int64, timestamp time.Time, isFromMe bool) *Message {
	return &Message{
		ID:            id,
		ChatJID:       chatJID,
		SenderJID:     senderJID,
		Type:          msgType,
		Caption:       caption,
		MediaURL:      mediaURL,
		MediaMimeType: mimeType,
		MediaFileName: fileName,
		MediaFileSize: fileSize,
		Timestamp:     timestamp,
		IsFromMe:      isFromMe,
	}
}
