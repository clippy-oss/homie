package domain

import (
	"fmt"
	"strings"
)

// JID represents a WhatsApp user/group identifier
type JID struct {
	User   string
	Server string
	Device uint16
}

func (j JID) String() string {
	if j.User == "" {
		return j.Server
	}
	return fmt.Sprintf("%s@%s", j.User, j.Server)
}

func (j JID) IsGroup() bool {
	return j.Server == "g.us"
}

func (j JID) IsUser() bool {
	return j.Server == "s.whatsapp.net"
}

func (j JID) PhoneNumber() string {
	if j.IsUser() {
		return j.User
	}
	return ""
}

func ParseJID(s string) (JID, error) {
	parts := strings.Split(s, "@")
	if len(parts) != 2 {
		return JID{}, fmt.Errorf("invalid JID format: %s", s)
	}
	return JID{User: parts[0], Server: parts[1]}, nil
}

func MustParseJID(s string) JID {
	jid, err := ParseJID(s)
	if err != nil {
		panic(err)
	}
	return jid
}
