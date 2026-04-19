package config

import (
	"os"
	"path/filepath"
)

const (
	DefaultPollInterval = 3
	DefaultLogFile      = "/tios/logs/DEDVD-LOG.txt"
	DefaultRemote       = "GRANTOR@SERVOR-FAMILIAL-5050:/drv/dada/_DEDVD-SORT_"
)

type Config struct {
	BackupDir    string
	LogFile      string
	Remote       string
	PollInterval int
}

func Default() Config {
	home, _ := os.UserHomeDir()
	return Config{
		BackupDir:    filepath.Join(home, "DEDVD-BACKUPS"),
		LogFile:      DefaultLogFile,
		Remote:       DefaultRemote,
		PollInterval: DefaultPollInterval,
	}
}

func (c Config) VideoDir() string { return filepath.Join(c.BackupDir, "VIDEO") }
func (c Config) DataDir() string  { return filepath.Join(c.BackupDir, "DATA") }
