package cli

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"sync"

	"github.com/clippy-oss/homie/whatsapp-bridge/internal/domain"
)

// HeadlessCLI handles JSON-based headless operation
type HeadlessCLI struct {
	handler *CommandHandler
	reader  *bufio.Reader
	writer  io.Writer
	mu      sync.Mutex
}

// NewHeadlessCLI creates a new headless CLI
func NewHeadlessCLI(handler *CommandHandler) *HeadlessCLI {
	return &HeadlessCLI{
		handler: handler,
		reader:  bufio.NewReader(os.Stdin),
		writer:  os.Stdout,
	}
}

// Run starts the headless JSON processing loop
func (cli *HeadlessCLI) Run(ctx context.Context) error {
	// Send ready message
	cli.sendResponse(Response{
		Success: true,
		Data:    map[string]string{"status": "ready", "mode": "headless"},
	})

	// Subscribe to events in background
	eventChan := cli.handler.SubscribeEvents([]domain.EventType{
		domain.EventTypeMessageReceived,
		domain.EventTypeMessageSent,
		domain.EventTypeConnectionStatus,
	})

	go cli.streamEvents(eventChan)

	// Process incoming JSON requests
	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			line, err := cli.reader.ReadString('\n')
			if err != nil {
				if err == io.EOF {
					return nil
				}
				cli.sendError("", fmt.Sprintf("read error: %v", err))
				continue
			}

			cli.processRequest(ctx, line)
		}
	}
}

func (cli *HeadlessCLI) processRequest(ctx context.Context, line string) {
	var req Request
	if err := json.Unmarshal([]byte(line), &req); err != nil {
		cli.sendError("", fmt.Sprintf("invalid JSON: %v", err))
		return
	}

	if req.Command == "" {
		cli.sendError(req.ID, "missing command field")
		return
	}

	// Convert params to args for command handler
	args := cli.paramsToArgs(req.Command, req.Params)

	cmd := &Command{
		Name: req.Command,
		Args: args,
	}

	// Special handling for streaming commands
	switch req.Command {
	case "pair-qr", "qr":
		cli.handleQRPairingStream(ctx, req.ID)
		return
	case "subscribe":
		// Already subscribed, just acknowledge
		cli.sendResponse(Response{
			ID:      req.ID,
			Success: true,
			Data:    map[string]string{"message": "subscribed to events"},
		})
		return
	case "quit", "exit":
		cli.sendResponse(Response{
			ID:      req.ID,
			Success: true,
			Data:    map[string]string{"message": "goodbye"},
		})
		os.Exit(0)
		return
	}

	result, err := cli.handler.Execute(ctx, cmd)
	if err != nil {
		cli.sendError(req.ID, err.Error())
		return
	}

	cli.sendResponse(Response{
		ID:      req.ID,
		Success: true,
		Data:    result,
	})
}

func (cli *HeadlessCLI) paramsToArgs(command string, params map[string]interface{}) []string {
	if params == nil {
		return nil
	}

	var args []string

	switch command {
	case "pair-phone", "phone":
		if phone, ok := params["phone"].(string); ok {
			args = append(args, phone)
		}

	case "chats", "ls":
		if limit, ok := params["limit"].(float64); ok {
			args = append(args, fmt.Sprintf("%d", int(limit)))
		}

	case "messages", "msg":
		if jid, ok := params["jid"].(string); ok {
			args = append(args, jid)
		}
		if limit, ok := params["limit"].(float64); ok {
			args = append(args, fmt.Sprintf("%d", int(limit)))
		}

	case "send":
		if jid, ok := params["jid"].(string); ok {
			args = append(args, jid)
		}
		if text, ok := params["text"].(string); ok {
			args = append(args, text)
		}

	case "react":
		if jid, ok := params["jid"].(string); ok {
			args = append(args, jid)
		}
		if msgID, ok := params["message_id"].(string); ok {
			args = append(args, msgID)
		}
		if emoji, ok := params["emoji"].(string); ok {
			args = append(args, emoji)
		}

	case "read":
		if jid, ok := params["jid"].(string); ok {
			args = append(args, jid)
		}
		if msgID, ok := params["message_id"].(string); ok {
			args = append(args, msgID)
		}
		if msgIDs, ok := params["message_ids"].([]interface{}); ok {
			for _, id := range msgIDs {
				if s, ok := id.(string); ok {
					args = append(args, s)
				}
			}
		}

	case "search":
		if query, ok := params["query"].(string); ok {
			args = append(args, query)
		}
		if limit, ok := params["limit"].(float64); ok {
			args = append(args, fmt.Sprintf("%d", int(limit)))
		}
	}

	return args
}

func (cli *HeadlessCLI) handleQRPairingStream(ctx context.Context, reqID string) {
	qrChan, err := cli.handler.GetQRCodeEvents(ctx)
	if err != nil {
		cli.sendError(reqID, err.Error())
		return
	}

	for info := range qrChan {
		if info.Error != "" {
			cli.sendError(reqID, info.Error)
			return
		}
		if info.Success {
			cli.sendResponse(Response{
				ID:      reqID,
				Success: true,
				Data: map[string]interface{}{
					"event":   "pairing_success",
					"success": true,
				},
			})
			return
		}
		if info.QRCode != "" {
			cli.sendResponse(Response{
				ID:      reqID,
				Success: true,
				Data: map[string]interface{}{
					"event":   "qr_code",
					"qr_code": info.QRCode,
				},
			})
		}
	}
}

func (cli *HeadlessCLI) streamEvents(eventChan <-chan Event) {
	for event := range eventChan {
		cli.sendEvent(event)
	}
}

func (cli *HeadlessCLI) sendResponse(resp Response) {
	cli.mu.Lock()
	defer cli.mu.Unlock()

	data, _ := json.Marshal(resp)
	fmt.Fprintln(cli.writer, string(data))
}

func (cli *HeadlessCLI) sendError(id, message string) {
	cli.sendResponse(Response{
		ID:      id,
		Success: false,
		Error:   message,
	})
}

func (cli *HeadlessCLI) sendEvent(event Event) {
	cli.mu.Lock()
	defer cli.mu.Unlock()

	data, _ := json.Marshal(map[string]interface{}{
		"type":      "event",
		"event":     event.Type,
		"timestamp": event.Timestamp,
		"data":      event.Data,
	})
	fmt.Fprintln(cli.writer, string(data))
}
