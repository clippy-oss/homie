package domain

import (
	"sync"
	"time"
)

type EventType string

const (
	EventTypeMessageReceived  EventType = "message.received"
	EventTypeMessageSent      EventType = "message.sent"
	EventTypeMessageRead      EventType = "message.read"
	EventTypeChatUpdated      EventType = "chat.updated"
	EventTypePresenceUpdated  EventType = "presence.updated"
	EventTypeConnectionStatus EventType = "connection.status"
	EventTypePairingCode      EventType = "pairing.code"
	EventTypePairingQR        EventType = "pairing.qr"
)

type Event interface {
	Type() EventType
	Timestamp() time.Time
}

type MessageReceivedEvent struct {
	Message   *Message
	EventTime time.Time
}

func (e MessageReceivedEvent) Type() EventType      { return EventTypeMessageReceived }
func (e MessageReceivedEvent) Timestamp() time.Time { return e.EventTime }

type MessageSentEvent struct {
	Message   *Message
	EventTime time.Time
}

func (e MessageSentEvent) Type() EventType      { return EventTypeMessageSent }
func (e MessageSentEvent) Timestamp() time.Time { return e.EventTime }

type MessageReadEvent struct {
	ChatJID    JID
	MessageIDs []string
	EventTime  time.Time
}

func (e MessageReadEvent) Type() EventType      { return EventTypeMessageRead }
func (e MessageReadEvent) Timestamp() time.Time { return e.EventTime }

type ChatUpdatedEvent struct {
	Chat      *Chat
	EventTime time.Time
}

func (e ChatUpdatedEvent) Type() EventType      { return EventTypeChatUpdated }
func (e ChatUpdatedEvent) Timestamp() time.Time { return e.EventTime }

type ConnectionStatusEvent struct {
	Connected bool
	Reason    string
	EventTime time.Time
}

func (e ConnectionStatusEvent) Type() EventType      { return EventTypeConnectionStatus }
func (e ConnectionStatusEvent) Timestamp() time.Time { return e.EventTime }

type PairingQREvent struct {
	QRCode    string
	EventTime time.Time
}

func (e PairingQREvent) Type() EventType      { return EventTypePairingQR }
func (e PairingQREvent) Timestamp() time.Time { return e.EventTime }

type PairingCodeEvent struct {
	Code      string
	EventTime time.Time
}

func (e PairingCodeEvent) Type() EventType      { return EventTypePairingCode }
func (e PairingCodeEvent) Timestamp() time.Time { return e.EventTime }

// EventBus provides pub/sub for domain events
type EventBus interface {
	Publish(event Event)
	Subscribe(eventTypes []EventType) <-chan Event
	Unsubscribe(ch <-chan Event)
}

// SimpleEventBus is a basic in-memory implementation of EventBus
type SimpleEventBus struct {
	mu          sync.RWMutex
	subscribers map[<-chan Event]subscription
}

type subscription struct {
	ch         chan Event
	eventTypes map[EventType]bool
}

func NewEventBus() *SimpleEventBus {
	return &SimpleEventBus{
		subscribers: make(map[<-chan Event]subscription),
	}
}

func (b *SimpleEventBus) Publish(event Event) {
	b.mu.RLock()
	defer b.mu.RUnlock()

	for _, sub := range b.subscribers {
		if len(sub.eventTypes) == 0 || sub.eventTypes[event.Type()] {
			select {
			case sub.ch <- event:
			default:
				// Channel full, skip this subscriber
			}
		}
	}
}

func (b *SimpleEventBus) Subscribe(eventTypes []EventType) <-chan Event {
	b.mu.Lock()
	defer b.mu.Unlock()

	ch := make(chan Event, 100)
	typeMap := make(map[EventType]bool)
	for _, t := range eventTypes {
		typeMap[t] = true
	}

	b.subscribers[ch] = subscription{
		ch:         ch,
		eventTypes: typeMap,
	}

	return ch
}

func (b *SimpleEventBus) Unsubscribe(ch <-chan Event) {
	b.mu.Lock()
	defer b.mu.Unlock()

	if sub, ok := b.subscribers[ch]; ok {
		close(sub.ch)
		delete(b.subscribers, ch)
	}
}
