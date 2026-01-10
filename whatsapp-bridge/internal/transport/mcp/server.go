package mcp

import (
	"context"
	"net/http"
	"time"

	"github.com/mark3labs/mcp-go/mcp"
	"github.com/mark3labs/mcp-go/server"

	"github.com/clippy-oss/homie/whatsapp-bridge/internal/service"
)

type ServerConfig struct {
	Address string
}

type Server struct {
	mcpServer  *server.MCPServer
	sseServer  *server.SSEServer
	httpServer *http.Server
	msgSvc     *service.MessageService
	waSvc      *service.WhatsAppService
	config     ServerConfig
}

func NewServer(
	msgSvc *service.MessageService,
	waSvc *service.WhatsAppService,
	config ServerConfig,
) *Server {
	s := &Server{
		msgSvc: msgSvc,
		waSvc:  waSvc,
		config: config,
	}

	s.mcpServer = server.NewMCPServer(
		"whatsapp-bridge",
		"1.0.0",
		server.WithToolCapabilities(true),
	)

	s.registerTools()

	s.sseServer = server.NewSSEServer(s.mcpServer,
		server.WithKeepAliveInterval(30*time.Second),
	)

	return s
}

func (s *Server) registerTools() {
	// List chats tool
	s.mcpServer.AddTool(
		mcp.NewTool("whatsapp_list_chats",
			mcp.WithDescription("List WhatsApp chats/conversations sorted by most recent activity"),
			mcp.WithNumber("limit",
				mcp.Description("Maximum number of chats to return (default 20, max 100)"),
			),
		),
		s.handleListChats,
	)

	// Get messages tool
	s.mcpServer.AddTool(
		mcp.NewTool("whatsapp_get_messages",
			mcp.WithDescription("Get messages from a specific WhatsApp chat"),
			mcp.WithString("chat_id",
				mcp.Required(),
				mcp.Description("JID of the chat (e.g., '1234567890@s.whatsapp.net' for users or 'groupid@g.us' for groups)"),
			),
			mcp.WithNumber("limit",
				mcp.Description("Maximum number of messages to return (default 50, max 200)"),
			),
		),
		s.handleGetMessages,
	)

	// Send message tool
	s.mcpServer.AddTool(
		mcp.NewTool("whatsapp_send_message",
			mcp.WithDescription("Send a text message to a WhatsApp chat"),
			mcp.WithString("chat_id",
				mcp.Required(),
				mcp.Description("JID of the chat to send message to"),
			),
			mcp.WithString("text",
				mcp.Required(),
				mcp.Description("Message text to send"),
			),
		),
		s.handleSendMessage,
	)

	// Send reaction tool
	s.mcpServer.AddTool(
		mcp.NewTool("whatsapp_send_reaction",
			mcp.WithDescription("Send a reaction emoji to a specific message"),
			mcp.WithString("chat_id",
				mcp.Required(),
				mcp.Description("JID of the chat containing the message"),
			),
			mcp.WithString("message_id",
				mcp.Required(),
				mcp.Description("ID of the message to react to"),
			),
			mcp.WithString("emoji",
				mcp.Required(),
				mcp.Description("Reaction emoji (e.g., '👍', '❤️', '😂', '😮', '😢', '🙏')"),
			),
		),
		s.handleSendReaction,
	)

	// Mark as read tool
	s.mcpServer.AddTool(
		mcp.NewTool("whatsapp_mark_read",
			mcp.WithDescription("Mark messages as read in a chat"),
			mcp.WithString("chat_id",
				mcp.Required(),
				mcp.Description("JID of the chat"),
			),
			mcp.WithString("message_ids",
				mcp.Required(),
				mcp.Description("Comma-separated list of message IDs to mark as read"),
			),
		),
		s.handleMarkRead,
	)

	// Search messages tool
	s.mcpServer.AddTool(
		mcp.NewTool("whatsapp_search_messages",
			mcp.WithDescription("Search messages across all chats by text content"),
			mcp.WithString("query",
				mcp.Required(),
				mcp.Description("Search query text"),
			),
			mcp.WithNumber("limit",
				mcp.Description("Maximum results to return (default 20, max 100)"),
			),
		),
		s.handleSearchMessages,
	)

	// Connection status tool
	s.mcpServer.AddTool(
		mcp.NewTool("whatsapp_connection_status",
			mcp.WithDescription("Get current WhatsApp connection status"),
		),
		s.handleConnectionStatus,
	)

	// Connect tool
	s.mcpServer.AddTool(
		mcp.NewTool("whatsapp_connect",
			mcp.WithDescription("Connect to WhatsApp (requires prior authentication)"),
		),
		s.handleConnect,
	)

	// Disconnect tool
	s.mcpServer.AddTool(
		mcp.NewTool("whatsapp_disconnect",
			mcp.WithDescription("Disconnect from WhatsApp"),
		),
		s.handleDisconnect,
	)

	// Logout tool
	s.mcpServer.AddTool(
		mcp.NewTool("whatsapp_logout",
			mcp.WithDescription("Logout from WhatsApp and remove device pairing. You will need to pair again after this."),
		),
		s.handleLogout,
	)
}

func (s *Server) Start() error {
	mux := http.NewServeMux()

	mux.Handle("/sse", s.sseServer.SSEHandler())
	mux.Handle("/message", s.sseServer.MessageHandler())

	// Health check endpoint
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("ok"))
	})

	s.httpServer = &http.Server{
		Addr:    s.config.Address,
		Handler: mux,
	}

	return s.httpServer.ListenAndServe()
}

func (s *Server) Stop(ctx context.Context) error {
	return s.httpServer.Shutdown(ctx)
}
