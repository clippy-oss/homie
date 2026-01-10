package domain

import "time"

type ChatType string

const (
	ChatTypePrivate ChatType = "private"
	ChatTypeGroup   ChatType = "group"
)

type Chat struct {
	JID               JID
	Type              ChatType
	Name              string
	LastMessageTime   time.Time
	LastMessageText   string
	LastMessageSender string
	UnreadCount       int
	IsMuted           bool
	IsArchived        bool
	IsPinned          bool
	GroupParticipants []JID
}

func NewPrivateChat(jid JID, name string) *Chat {
	return &Chat{
		JID:  jid,
		Type: ChatTypePrivate,
		Name: name,
	}
}

func NewGroupChat(jid JID, name string, participants []JID) *Chat {
	return &Chat{
		JID:               jid,
		Type:              ChatTypeGroup,
		Name:              name,
		GroupParticipants: participants,
	}
}
