package logger

// FilePath returns the path to the underlying log file.
func (l *Logger) FilePath() string {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.file != nil {
		return l.file.Name()
	}
	return ""
}
