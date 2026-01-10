package cli

import "time"

// Mode represents the CLI operation mode
type Mode string

const (
	ModeInteractive Mode = "interactive"
	ModeHeadless    Mode = "headless"
)

// Request represents a JSON request in headless mode
type Request struct {
	ID      string                 `json:"id,omitempty"`
	Command string                 `json:"command"`
	Params  map[string]interface{} `json:"params,omitempty"`
}

// Response represents a JSON response in headless mode
type Response struct {
	ID      string      `json:"id,omitempty"`
	Success bool        `json:"success"`
	Data    interface{} `json:"data,omitempty"`
	Error   string      `json:"error,omitempty"`
}

// Event represents a real-time event in headless mode
type Event struct {
	Type      string      `json:"type"`
	Timestamp time.Time   `json:"timestamp"`
	Data      interface{} `json:"data"`
}

// ChatInfo represents chat information for responses
type ChatInfo struct {
	JID             string    `json:"jid"`
	Name            string    `json:"name"`
	Type            string    `json:"type"`
	UnreadCount     int       `json:"unread_count"`
	LastMessageText string    `json:"last_message_text,omitempty"`
	LastMessageTime time.Time `json:"last_message_time,omitempty"`
}

// MessageInfo represents message information for responses
type MessageInfo struct {
	ID        string    `json:"id"`
	ChatJID   string    `json:"chat_jid"`
	SenderJID string    `json:"sender_jid"`
	Type      string    `json:"type"`
	Text      string    `json:"text,omitempty"`
	Caption   string    `json:"caption,omitempty"`
	Timestamp time.Time `json:"timestamp"`
	IsFromMe  bool      `json:"is_from_me"`
	IsRead    bool      `json:"is_read"`
}

// ConnectionStatus represents connection status for responses
type ConnectionStatus struct {
	Connected bool   `json:"connected"`
	LoggedIn  bool   `json:"logged_in"`
	Status    string `json:"status"`
}

// PairingInfo represents pairing information
type PairingInfo struct {
	Code    string `json:"code,omitempty"`
	QRCode  string `json:"qr_code,omitempty"`
	Success bool   `json:"success"`
	Error   string `json:"error,omitempty"`
}
