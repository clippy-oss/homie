package cli

import (
	"bufio"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"strings"

	"github.com/clippy-oss/homie/whatsapp-bridge/internal/domain"
	"github.com/skip2/go-qrcode"
)

// InteractiveCLI handles interactive command-line interface
type InteractiveCLI struct {
	handler *CommandHandler
	reader  *bufio.Reader
	writer  io.Writer
}

// NewInteractiveCLI creates a new interactive CLI
func NewInteractiveCLI(handler *CommandHandler) *InteractiveCLI {
	return &InteractiveCLI{
		handler: handler,
		reader:  bufio.NewReader(os.Stdin),
		writer:  os.Stdout,
	}
}

// Run starts the interactive CLI loop
func (cli *InteractiveCLI) Run(ctx context.Context) error {
	cli.printWelcome()

	// Subscribe to events in background
	eventChan := cli.handler.SubscribeEvents([]domain.EventType{
		domain.EventTypeMessageReceived,
		domain.EventTypeConnectionStatus,
	})

	go cli.handleEvents(eventChan)

	for {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
			cli.print("\n> ")
			line, err := cli.reader.ReadString('\n')
			if err != nil {
				if err == io.EOF {
					return nil
				}
				return err
			}

			line = strings.TrimSpace(line)
			if line == "" {
				continue
			}

			if err := cli.processCommand(ctx, line); err != nil {
				if err.Error() == "quit" {
					cli.println("Goodbye!")
					return nil
				}
				cli.printf("Error: %s\n", err)
			}
		}
	}
}

func (cli *InteractiveCLI) printWelcome() {
	cli.println("===========================================")
	cli.println("  WhatsApp Bridge CLI")
	cli.println("===========================================")
	cli.println("Type /help for available commands")
	cli.println("")

	// Show current status
	status, _ := cli.handler.cmdStatus()
	if s, ok := status.(ConnectionStatus); ok {
		cli.printf("Status: %s\n", s.Status)
	}
}

func (cli *InteractiveCLI) processCommand(ctx context.Context, input string) error {
	cmd, err := ParseCommand(input)
	if err != nil {
		return err
	}

	// Special handling for QR pairing (streaming)
	if cmd.Name == "pair-qr" || cmd.Name == "qr" {
		return cli.handleQRPairing(ctx)
	}

	result, err := cli.handler.Execute(ctx, cmd)
	if err != nil {
		return err
	}

	// Check for quit command
	if m, ok := result.(map[string]bool); ok && m["quit"] {
		return fmt.Errorf("quit")
	}

	// Format and display result
	cli.displayResult(cmd.Name, result)
	return nil
}

func (cli *InteractiveCLI) handleQRPairing(ctx context.Context) error {
	cli.println("Generating QR code for pairing...")
	cli.println("Scan this QR code with your WhatsApp app (Settings > Linked Devices > Link a Device)")
	cli.println("")

	qrChan, err := cli.handler.GetQRCodeEvents(ctx)
	if err != nil {
		return err
	}

	for info := range qrChan {
		if info.Error != "" {
			return fmt.Errorf(info.Error)
		}
		if info.Success {
			cli.println("\nPairing successful! You are now connected.")
			return nil
		}
		if info.QRCode != "" {
			// Generate ASCII QR code
			qr, err := qrcode.New(info.QRCode, qrcode.Medium)
			if err != nil {
				cli.printf("QR Code data: %s\n", info.QRCode)
			} else {
				cli.println(qr.ToSmallString(false))
			}
			cli.println("Waiting for scan... (QR code will refresh)")
		}
	}

	return nil
}

func (cli *InteractiveCLI) displayResult(cmdName string, result interface{}) {
	switch cmdName {
	case "help", "h":
		if m, ok := result.(map[string]string); ok {
			cli.println(m["help"])
		}

	case "status", "s":
		if s, ok := result.(ConnectionStatus); ok {
			cli.printf("Connection Status: %s\n", s.Status)
			cli.printf("  Connected: %v\n", s.Connected)
			cli.printf("  Logged In: %v\n", s.LoggedIn)
		}

	case "chats", "ls":
		if m, ok := result.(map[string]interface{}); ok {
			chats, _ := m["chats"].([]ChatInfo)
			cli.printf("Found %d chat(s):\n\n", len(chats))
			for i, chat := range chats {
				unread := ""
				if chat.UnreadCount > 0 {
					unread = fmt.Sprintf(" [%d unread]", chat.UnreadCount)
				}
				cli.printf("%d. %s (%s)%s\n", i+1, chat.Name, chat.Type, unread)
				cli.printf("   JID: %s\n", chat.JID)
				if chat.LastMessageText != "" {
					preview := chat.LastMessageText
					if len(preview) > 50 {
						preview = preview[:50] + "..."
					}
					cli.printf("   Last: %s\n", preview)
				}
			}
		}

	case "messages", "msg":
		if m, ok := result.(map[string]interface{}); ok {
			messages, _ := m["messages"].([]MessageInfo)
			cli.printf("Found %d message(s):\n\n", len(messages))
			for _, msg := range messages {
				sender := "Me"
				if !msg.IsFromMe {
					sender = msg.SenderJID
				}
				timestamp := msg.Timestamp.Format("2006-01-02 15:04")
				cli.printf("[%s] %s:\n", timestamp, sender)
				if msg.Text != "" {
					cli.printf("  %s\n", msg.Text)
				} else if msg.Caption != "" {
					cli.printf("  [%s] %s\n", msg.Type, msg.Caption)
				} else {
					cli.printf("  [%s]\n", msg.Type)
				}
				cli.printf("  ID: %s\n\n", msg.ID)
			}
		}

	case "send":
		if msg, ok := result.(MessageInfo); ok {
			cli.printf("Message sent!\n")
			cli.printf("  ID: %s\n", msg.ID)
			cli.printf("  Time: %s\n", msg.Timestamp.Format("2006-01-02 15:04:05"))
		}

	case "search":
		if m, ok := result.(map[string]interface{}); ok {
			query, _ := m["query"].(string)
			messages, _ := m["messages"].([]MessageInfo)
			cli.printf("Search results for '%s' (%d found):\n\n", query, len(messages))
			for i, msg := range messages {
				sender := "Me"
				if !msg.IsFromMe {
					sender = msg.SenderJID
				}
				cli.printf("%d. [%s] %s:\n", i+1, msg.Timestamp.Format("2006-01-02 15:04"), sender)
				text := msg.Text
				if text == "" {
					text = msg.Caption
				}
				if len(text) > 80 {
					text = text[:80] + "..."
				}
				cli.printf("   %s\n", text)
				cli.printf("   Chat: %s | ID: %s\n\n", msg.ChatJID, msg.ID)
			}
		}

	case "pair-phone", "phone":
		if info, ok := result.(PairingInfo); ok {
			if info.Code != "" {
				cli.println("Pairing code generated!")
				cli.printf("Enter this code in WhatsApp: %s\n", info.Code)
				cli.println("Go to WhatsApp > Settings > Linked Devices > Link a Device > Link with phone number")
			}
		}

	default:
		// Generic JSON output for other commands
		if m, ok := result.(map[string]string); ok {
			if msg, exists := m["message"]; exists {
				cli.println(msg)
				return
			}
		}
		// Pretty print JSON
		data, _ := json.MarshalIndent(result, "", "  ")
		cli.println(string(data))
	}
}

func (cli *InteractiveCLI) handleEvents(eventChan <-chan Event) {
	for event := range eventChan {
		switch event.Type {
		case "message_received":
			if msg, ok := event.Data.(MessageInfo); ok {
				cli.printf("\n[New Message] From %s:\n", msg.SenderJID)
				if msg.Text != "" {
					cli.printf("  %s\n", msg.Text)
				} else {
					cli.printf("  [%s]\n", msg.Type)
				}
				cli.print("> ")
			}
		case "connection_status":
			if data, ok := event.Data.(map[string]interface{}); ok {
				connected, _ := data["connected"].(bool)
				if connected {
					cli.println("\n[Connected to WhatsApp]")
				} else {
					reason, _ := data["reason"].(string)
					cli.printf("\n[Disconnected: %s]\n", reason)
				}
				cli.print("> ")
			}
		}
	}
}

func (cli *InteractiveCLI) print(s string) {
	fmt.Fprint(cli.writer, s)
}

func (cli *InteractiveCLI) println(s string) {
	fmt.Fprintln(cli.writer, s)
}

func (cli *InteractiveCLI) printf(format string, args ...interface{}) {
	fmt.Fprintf(cli.writer, format, args...)
}
