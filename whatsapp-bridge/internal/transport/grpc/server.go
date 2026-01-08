package grpc

import (
	"net"

	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"

	pb "github.com/clippy-oss/homie/whatsapp-bridge/pkg/pb"
	"github.com/clippy-oss/homie/whatsapp-bridge/internal/service"
)

type ServerConfig struct {
	Address string
}

type Server struct {
	server  *grpc.Server
	handler *Handler
	config  ServerConfig
}

func NewServer(
	waSvc *service.WhatsAppService,
	msgSvc *service.MessageService,
	config ServerConfig,
) *Server {
	handler := NewHandler(waSvc, msgSvc)

	server := grpc.NewServer(
		grpc.ChainUnaryInterceptor(
			LoggingInterceptor(),
			RecoveryInterceptor(),
		),
		grpc.ChainStreamInterceptor(
			StreamLoggingInterceptor(),
			StreamRecoveryInterceptor(),
		),
	)

	pb.RegisterWhatsAppServiceServer(server, handler)
	reflection.Register(server)

	return &Server{
		server:  server,
		handler: handler,
		config:  config,
	}
}

func (s *Server) Start() error {
	lis, err := net.Listen("tcp", s.config.Address)
	if err != nil {
		return err
	}

	return s.server.Serve(lis)
}

func (s *Server) Stop() {
	s.server.GracefulStop()
}
