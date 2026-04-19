package logger

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// Logger writes timestamped messages to both an io.Writer (for TUI consumption)
// and a persistent log file on disk.
type Logger struct {
	mu      sync.Mutex
	file    *os.File
	writers []io.Writer
}

func New(logPath string) (*Logger, error) {
	if err := os.MkdirAll(filepath.Dir(logPath), 0o755); err != nil {
		return nil, fmt.Errorf("create log dir: %w", err)
	}
	f, err := os.OpenFile(logPath, os.O_CREATE|os.O_APPEND|os.O_WRONLY, 0o644)
	if err != nil {
		return nil, fmt.Errorf("open log file: %w", err)
	}
	l := &Logger{file: f}
	l.writers = []io.Writer{f}
	return l, nil
}

func (l *Logger) AddWriter(w io.Writer) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.writers = append(l.writers, w)
}

func (l *Logger) Close() error {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.file != nil {
		return l.file.Close()
	}
	return nil
}

func (l *Logger) timestamp() string {
	return time.Now().Format("15:04:05")
}

func (l *Logger) write(prefix, msg string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	line := fmt.Sprintf("[dedvd %s] %s%s\n", l.timestamp(), prefix, msg)
	for _, w := range l.writers {
		fmt.Fprint(w, line)
	}
}

func (l *Logger) Info(msg string)           { l.write("", msg) }
func (l *Logger) Infof(f string, a ...any)  { l.write("", fmt.Sprintf(f, a...)) }
func (l *Logger) Warn(msg string)           { l.write("WARN: ", msg) }
func (l *Logger) Warnf(f string, a ...any)  { l.write("WARN: ", fmt.Sprintf(f, a...)) }
func (l *Logger) Error(msg string)          { l.write("ERROR: ", msg) }
func (l *Logger) Errorf(f string, a ...any) { l.write("ERROR: ", fmt.Sprintf(f, a...)) }
func (l *Logger) Banner(msg string)         { l.write("", msg) }
func (l *Logger) Separator() {
	l.write("", "=================================================================")
}

func (l *Logger) SessionStart(backupDir string) {
	l.Separator()
	l.Infof("dedvd session started  %s", time.Now().Format("2006-01-02 15:04:05"))
	l.Infof("Log file   : %s", l.file.Name())
	l.Infof("Backup root: %s", backupDir)
	l.Separator()
}

// RawWrite writes directly to the log file only (for rsync/handbrake output).
func (l *Logger) RawWrite(data []byte) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.file != nil {
		l.file.Write(data)
	}
}
