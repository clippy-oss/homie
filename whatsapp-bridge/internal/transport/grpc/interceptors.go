package grpc

import (
	"context"
	"runtime/debug"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"

	"github.com/clippy-oss/homie/whatsapp-bridge/internal/logger"
)

var grpcLog = logger.Module("grpc")

func LoggingInterceptor() grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (interface{}, error) {
		start := time.Now()
		resp, err := handler(ctx, req)
		duration := time.Since(start)

		code := codes.OK
		if err != nil {
			if st, ok := status.FromError(err); ok {
				code = st.Code()
			}
		}

		grpcLog.Info().
			Str("method", info.FullMethod).
			Str("code", code.String()).
			Int64("duration_ms", duration.Milliseconds()).
			Msg("gRPC request completed")

		return resp, err
	}
}

func RecoveryInterceptor() grpc.UnaryServerInterceptor {
	return func(ctx context.Context, req interface{}, info *grpc.UnaryServerInfo, handler grpc.UnaryHandler) (resp interface{}, err error) {
		defer func() {
			if r := recover(); r != nil {
				grpcLog.Error().
					Str("method", info.FullMethod).
					Interface("panic", r).
					Str("stack", string(debug.Stack())).
					Msg("Panic recovered")
				err = status.Errorf(codes.Internal, "internal server error")
			}
		}()
		return handler(ctx, req)
	}
}

func StreamLoggingInterceptor() grpc.StreamServerInterceptor {
	return func(srv interface{}, ss grpc.ServerStream, info *grpc.StreamServerInfo, handler grpc.StreamHandler) error {
		start := time.Now()
		err := handler(srv, ss)
		duration := time.Since(start)

		code := codes.OK
		if err != nil {
			if st, ok := status.FromError(err); ok {
				code = st.Code()
			}
		}

		grpcLog.Info().
			Str("method", info.FullMethod).
			Str("code", code.String()).
			Int64("duration_ms", duration.Milliseconds()).
			Msg("gRPC stream completed")

		return err
	}
}

func StreamRecoveryInterceptor() grpc.StreamServerInterceptor {
	return func(srv interface{}, ss grpc.ServerStream, info *grpc.StreamServerInfo, handler grpc.StreamHandler) (err error) {
		defer func() {
			if r := recover(); r != nil {
				grpcLog.Error().
					Str("method", info.FullMethod).
					Interface("panic", r).
					Str("stack", string(debug.Stack())).
					Msg("Panic recovered in stream")
				err = status.Errorf(codes.Internal, "internal server error")
			}
		}()
		return handler(srv, ss)
	}
}
