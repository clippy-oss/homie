package grpc

import (
	"context"
	"io"

	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/types/known/timestamppb"

	pb "github.com/clippy-oss/homie/whatsapp-bridge/pkg/pb"
	"github.com/clippy-oss/homie/whatsapp-bridge/internal/domain"
	"github.com/clippy-oss/homie/whatsapp-bridge/internal/service"
)

type Handler struct {
	pb.UnimplementedWhatsAppServiceServer

	waSvc  *service.WhatsAppService
	msgSvc *service.MessageService
}

func NewHandler(waSvc *service.WhatsAppService, msgSvc *service.MessageService) *Handler {
	return &Handler{
		waSvc:  waSvc,
		msgSvc: msgSvc,
	}
}

func (h *Handler) Connect(ctx context.Context, req *pb.ConnectRequest) (*pb.ConnectResponse, error) {
	err := h.waSvc.Connect(ctx)
	if err != nil {
		return &pb.ConnectResponse{
			Success:      false,
			ErrorMessage: err.Error(),
		}, nil
	}
	return &pb.ConnectResponse{Success: true}, nil
}

func (h *Handler) Disconnect(ctx context.Context, req *pb.DisconnectRequest) (*pb.DisconnectResponse, error) {
	h.waSvc.Disconnect()
	return &pb.DisconnectResponse{Success: true}, nil
}

func (h *Handler) Logout(ctx context.Context, req *pb.LogoutRequest) (*pb.LogoutResponse, error) {
	err := h.waSvc.Logout(ctx)
	if err != nil {
		return &pb.LogoutResponse{Success: false, ErrorMessage: err.Error()}, nil
	}
	return &pb.LogoutResponse{Success: true}, nil
}

func (h *Handler) GetConnectionStatus(ctx context.Context, req *pb.GetConnectionStatusRequest) (*pb.GetConnectionStatusResponse, error) {
	connStatus := pb.ConnectionStatus_CONNECTION_STATUS_DISCONNECTED
	if h.waSvc.IsConnected() {
		connStatus = pb.ConnectionStatus_CONNECTION_STATUS_CONNECTED
	}

	return &pb.GetConnectionStatusResponse{
		Status:     connStatus,
		IsLoggedIn: h.waSvc.IsLoggedIn(),
	}, nil
}

func (h *Handler) GetPairingQR(req *pb.GetPairingQRRequest, stream pb.WhatsAppService_GetPairingQRServer) error {
	qrChan, err := h.waSvc.GetQRChannel(stream.Context())
	if err != nil {
		return status.Errorf(codes.FailedPrecondition, "failed to get QR channel: %v", err)
	}

	// Connect after getting QR channel
	go func() {
		h.waSvc.Connect(stream.Context())
	}()

	for item := range qrChan {
		var event *pb.PairingQREvent

		switch item.Event {
		case "code":
			event = &pb.PairingQREvent{
				Payload: &pb.PairingQREvent_QrCode{QrCode: item.Code},
			}
		case "timeout":
			event = &pb.PairingQREvent{
				Payload: &pb.PairingQREvent_Timeout{Timeout: true},
			}
		case "success":
			event = &pb.PairingQREvent{
				Payload: &pb.PairingQREvent_Success{
					Success: &pb.PairingSuccess{},
				},
			}
		default:
			if item.Error != nil {
				event = &pb.PairingQREvent{
					Payload: &pb.PairingQREvent_Error{Error: item.Error.Error()},
				}
			} else {
				event = &pb.PairingQREvent{
					Payload: &pb.PairingQREvent_Error{Error: item.Event},
				}
			}
		}

		if err := stream.Send(event); err != nil {
			return err
		}

		if item.Event == "success" || item.Event == "timeout" {
			break
		}
	}

	return nil
}

func (h *Handler) PairWithCode(ctx context.Context, req *pb.PairWithCodeRequest) (*pb.PairWithCodeResponse, error) {
	code, err := h.waSvc.PairWithCode(ctx, req.PhoneNumber)
	if err != nil {
		return &pb.PairWithCodeResponse{ErrorMessage: err.Error()}, nil
	}
	return &pb.PairWithCodeResponse{PairingCode: code}, nil
}

func (h *Handler) GetChats(ctx context.Context, req *pb.GetChatsRequest) (*pb.GetChatsResponse, error) {
	limit := int(req.Limit)
	if limit <= 0 {
		limit = 50
	}

	chats, err := h.msgSvc.GetChats(ctx, limit, int(req.Offset))
	if err != nil {
		return nil, status.Errorf(codes.Internal, "failed to get chats: %v", err)
	}

	pbChats := make([]*pb.Chat, len(chats))
	for i, chat := range chats {
		pbChats[i] = chatToPB(chat)
	}

	return &pb.GetChatsResponse{Chats: pbChats}, nil
}

func (h *Handler) GetChat(ctx context.Context, req *pb.GetChatRequest) (*pb.GetChatResponse, error) {
	jid := jidFromPB(req.Jid)
	chat, err := h.msgSvc.GetChat(ctx, jid)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "failed to get chat: %v", err)
	}
	if chat == nil {
		return nil, status.Errorf(codes.NotFound, "chat not found")
	}

	return &pb.GetChatResponse{Chat: chatToPB(chat)}, nil
}

func (h *Handler) GetMessages(ctx context.Context, req *pb.GetMessagesRequest) (*pb.GetMessagesResponse, error) {
	chatJID := jidFromPB(req.ChatJid)
	limit := int(req.Limit)
	if limit <= 0 {
		limit = 50
	}

	messages, err := h.msgSvc.GetMessages(ctx, chatJID, limit, 0)
	if err != nil {
		return nil, status.Errorf(codes.Internal, "failed to get messages: %v", err)
	}

	pbMessages := make([]*pb.Message, len(messages))
	for i, msg := range messages {
		pbMessages[i] = messageToPB(msg)
	}

	return &pb.GetMessagesResponse{Messages: pbMessages}, nil
}

func (h *Handler) SendMessage(ctx context.Context, req *pb.SendMessageRequest) (*pb.SendMessageResponse, error) {
	chatJID := jidFromPB(req.ChatJid)

	// Check if this is a text message
	if req.Text != "" {
		msg, err := h.msgSvc.SendTextMessage(ctx, chatJID, req.Text)
		if err != nil {
			return &pb.SendMessageResponse{ErrorMessage: err.Error()}, nil
		}
		return &pb.SendMessageResponse{Message: messageToPB(msg)}, nil
	}

	// Check if this is a media message
	if len(req.MediaData) > 0 {
		// TODO: Implement media sending
		return &pb.SendMessageResponse{ErrorMessage: "media sending not yet implemented"}, nil
	}

	return &pb.SendMessageResponse{ErrorMessage: "no content provided"}, nil
}

func (h *Handler) SendReaction(ctx context.Context, req *pb.SendReactionRequest) (*pb.SendReactionResponse, error) {
	chatJID := jidFromPB(req.ChatJid)

	err := h.msgSvc.SendReaction(ctx, chatJID, req.MessageId, "", req.Emoji)
	if err != nil {
		return &pb.SendReactionResponse{Success: false, ErrorMessage: err.Error()}, nil
	}
	return &pb.SendReactionResponse{Success: true}, nil
}

func (h *Handler) MarkAsRead(ctx context.Context, req *pb.MarkAsReadRequest) (*pb.MarkAsReadResponse, error) {
	chatJID := jidFromPB(req.ChatJid)

	err := h.msgSvc.MarkAsRead(ctx, chatJID, req.MessageIds)
	if err != nil {
		return &pb.MarkAsReadResponse{Success: false, ErrorMessage: err.Error()}, nil
	}
	return &pb.MarkAsReadResponse{Success: true}, nil
}

func (h *Handler) StreamEvents(req *pb.StreamEventsRequest, stream pb.WhatsAppService_StreamEventsServer) error {
	eventTypes := make([]domain.EventType, 0)
	for _, t := range req.EventTypes {
		switch t {
		case pb.EventType_EVENT_TYPE_MESSAGE_RECEIVED:
			eventTypes = append(eventTypes, domain.EventTypeMessageReceived)
		case pb.EventType_EVENT_TYPE_MESSAGE_SENT:
			eventTypes = append(eventTypes, domain.EventTypeMessageSent)
		case pb.EventType_EVENT_TYPE_MESSAGE_READ:
			eventTypes = append(eventTypes, domain.EventTypeMessageRead)
		case pb.EventType_EVENT_TYPE_CHAT_UPDATED:
			eventTypes = append(eventTypes, domain.EventTypeChatUpdated)
		case pb.EventType_EVENT_TYPE_CONNECTION_STATUS:
			eventTypes = append(eventTypes, domain.EventTypeConnectionStatus)
		}
	}

	if len(eventTypes) == 0 {
		eventTypes = []domain.EventType{
			domain.EventTypeMessageReceived,
			domain.EventTypeMessageSent,
			domain.EventTypeConnectionStatus,
		}
	}

	eventCh := h.waSvc.GetEventBus().Subscribe(eventTypes)
	defer h.waSvc.GetEventBus().Unsubscribe(eventCh)

	for {
		select {
		case <-stream.Context().Done():
			return nil
		case event, ok := <-eventCh:
			if !ok {
				return nil
			}
			pbEvent := eventToPB(event)
			if pbEvent != nil {
				if err := stream.Send(pbEvent); err != nil {
					if err == io.EOF {
						return nil
					}
					return err
				}
			}
		}
	}
}

// Conversion helpers
func jidFromPB(jid *pb.JID) domain.JID {
	if jid == nil {
		return domain.JID{}
	}
	return domain.JID{User: jid.User, Server: jid.Server}
}

func jidToPB(jid domain.JID) *pb.JID {
	return &pb.JID{User: jid.User, Server: jid.Server}
}

func chatToPB(chat *domain.Chat) *pb.Chat {
	if chat == nil {
		return nil
	}

	var chatType pb.ChatType
	switch chat.Type {
	case domain.ChatTypePrivate:
		chatType = pb.ChatType_CHAT_TYPE_PRIVATE
	case domain.ChatTypeGroup:
		chatType = pb.ChatType_CHAT_TYPE_GROUP
	}

	return &pb.Chat{
		Jid:             jidToPB(chat.JID),
		Name:            chat.Name,
		Type:            chatType,
		LastMessageTime: timestamppb.New(chat.LastMessageTime),
		LastMessageText: chat.LastMessageText,
		UnreadCount:     int32(chat.UnreadCount),
		IsMuted:         chat.IsMuted,
		IsArchived:      chat.IsArchived,
	}
}

func messageToPB(msg *domain.Message) *pb.Message {
	if msg == nil {
		return nil
	}

	var msgType pb.MessageType
	switch msg.Type {
	case domain.MessageTypeText:
		msgType = pb.MessageType_MESSAGE_TYPE_TEXT
	case domain.MessageTypeImage:
		msgType = pb.MessageType_MESSAGE_TYPE_IMAGE
	case domain.MessageTypeVideo:
		msgType = pb.MessageType_MESSAGE_TYPE_VIDEO
	case domain.MessageTypeAudio:
		msgType = pb.MessageType_MESSAGE_TYPE_AUDIO
	case domain.MessageTypeDocument:
		msgType = pb.MessageType_MESSAGE_TYPE_DOCUMENT
	case domain.MessageTypeSticker:
		msgType = pb.MessageType_MESSAGE_TYPE_STICKER
	case domain.MessageTypeReaction:
		msgType = pb.MessageType_MESSAGE_TYPE_REACTION
	case domain.MessageTypeLocation:
		msgType = pb.MessageType_MESSAGE_TYPE_LOCATION
	}

	// Include caption in text if text is empty
	text := msg.Text
	if text == "" && msg.Caption != "" {
		text = msg.Caption
	}

	pbMsg := &pb.Message{
		Id:              msg.ID,
		ChatJid:         jidToPB(msg.ChatJID),
		SenderJid:       jidToPB(msg.SenderJID),
		Type:            msgType,
		Text:            text,
		Timestamp:       timestamppb.New(msg.Timestamp),
		IsFromMe:        msg.IsFromMe,
		IsRead:          msg.IsRead,
		MediaUrl:        msg.MediaURL,
		MediaMimeType:   msg.MediaMimeType,
		MediaFilename:   msg.MediaFileName,
		QuotedMessageId: msg.QuotedMessageID,
	}

	if msg.Reaction != nil {
		pbMsg.Reaction = &pb.Reaction{
			TargetMessageId: msg.Reaction.TargetMessageID,
			Emoji:           msg.Reaction.Emoji,
		}
	}

	return pbMsg
}

func eventToPB(event domain.Event) *pb.WhatsAppEvent {
	switch e := event.(type) {
	case domain.MessageReceivedEvent:
		return &pb.WhatsAppEvent{
			Type:      pb.EventType_EVENT_TYPE_MESSAGE_RECEIVED,
			Timestamp: timestamppb.New(e.Timestamp()),
			Payload: &pb.WhatsAppEvent_MessageEvent{
				MessageEvent: &pb.MessageEvent{
					Message: messageToPB(e.Message),
				},
			},
		}
	case domain.MessageSentEvent:
		return &pb.WhatsAppEvent{
			Type:      pb.EventType_EVENT_TYPE_MESSAGE_SENT,
			Timestamp: timestamppb.New(e.Timestamp()),
			Payload: &pb.WhatsAppEvent_MessageEvent{
				MessageEvent: &pb.MessageEvent{
					Message: messageToPB(e.Message),
				},
			},
		}
	case domain.ConnectionStatusEvent:
		var connStatus pb.ConnectionStatus
		if e.Connected {
			connStatus = pb.ConnectionStatus_CONNECTION_STATUS_CONNECTED
		} else {
			connStatus = pb.ConnectionStatus_CONNECTION_STATUS_DISCONNECTED
		}
		return &pb.WhatsAppEvent{
			Type:      pb.EventType_EVENT_TYPE_CONNECTION_STATUS,
			Timestamp: timestamppb.New(e.Timestamp()),
			Payload: &pb.WhatsAppEvent_ConnectionEvent{
				ConnectionEvent: &pb.ConnectionEvent{
					Status: connStatus,
					Reason: e.Reason,
				},
			},
		}
	case domain.ChatUpdatedEvent:
		return &pb.WhatsAppEvent{
			Type:      pb.EventType_EVENT_TYPE_CHAT_UPDATED,
			Timestamp: timestamppb.New(e.Timestamp()),
			Payload: &pb.WhatsAppEvent_ChatEvent{
				ChatEvent: &pb.ChatEvent{
					Chat: chatToPB(e.Chat),
				},
			},
		}
	}
	return nil
}
