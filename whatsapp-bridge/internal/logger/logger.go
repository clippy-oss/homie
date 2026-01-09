package logger

import (
	"os"
	"time"

	"github.com/rs/zerolog"
	waLog "go.mau.fi/whatsmeow/util/log"
)

var Log zerolog.Logger

// Init initializes the global logger with the specified level.
// Valid levels: debug, info, warn, error
func Init(level string) {
	zerolog.TimeFieldFormat = time.RFC3339Nano
	lvl, err := zerolog.ParseLevel(level)
	if err != nil {
		lvl = zerolog.InfoLevel
	}
	Log = zerolog.New(os.Stdout).
		Level(lvl).
		With().
		Timestamp().
		Logger()
}

// Module returns a logger with a module field for scoped logging.
func Module(name string) zerolog.Logger {
	return Log.With().Str("module", name).Logger()
}

// WALogger adapts zerolog to whatsmeow's Logger interface.
type WALogger struct {
	zlog zerolog.Logger
}

// NewWALogger creates a new whatsmeow-compatible logger for the given module.
func NewWALogger(module string) waLog.Logger {
	return &WALogger{zlog: Module(module)}
}

func (l *WALogger) Debugf(msg string, args ...interface{}) {
	l.zlog.Debug().Msgf(msg, args...)
}

func (l *WALogger) Infof(msg string, args ...interface{}) {
	l.zlog.Info().Msgf(msg, args...)
}

func (l *WALogger) Warnf(msg string, args ...interface{}) {
	l.zlog.Warn().Msgf(msg, args...)
}

func (l *WALogger) Errorf(msg string, args ...interface{}) {
	l.zlog.Error().Msgf(msg, args...)
}

func (l *WALogger) Sub(module string) waLog.Logger {
	return &WALogger{zlog: l.zlog.With().Str("sub", module).Logger()}
}
