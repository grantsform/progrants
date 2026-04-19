package cmd

import (
	"fmt"
	"os"
	"os/exec"

	"dedvd/internal/config"
	"dedvd/internal/logger"
	"dedvd/internal/tui"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"
)

var cfg config.Config

var rootCmd = &cobra.Command{
	Use:   "dedvd",
	Short: "Optical disc backup tool",
	Long: `dedvd — optical disc backup tool

Watches for CD/DVD/Blu-ray insertion, detects disc type (DATA or VIDEO),
rsync-copies contents with SHA-256 verification, transcodes VIDEO to MKV,
and uploads to remote hosts via rsync+ssh.`,
	RunE: func(cmd *cobra.Command, args []string) error {
		return runWatch()
	},
}

func init() {
	cfg = config.Default()

	rootCmd.PersistentFlags().StringVar(&cfg.BackupDir, "backup-dir", cfg.BackupDir,
		"backup root directory")
	rootCmd.PersistentFlags().StringVar(&cfg.LogFile, "log", cfg.LogFile,
		"log file path")
	rootCmd.PersistentFlags().StringVar(&cfg.Remote, "remote", cfg.Remote,
		"remote destination as USER@HOST:/path")
	rootCmd.PersistentFlags().IntVar(&cfg.PollInterval, "poll-interval", cfg.PollInterval,
		"seconds between disc poll checks")

	// Support --to / --from as aliases for --backup-dir with /DEDVD-BACKUPS suffix
	rootCmd.PersistentFlags().String("to", "", "prefix path for backups (appends /DEDVD-BACKUPS)")
	rootCmd.PersistentFlags().String("from", "", "prefix path for reads (appends /DEDVD-BACKUPS)")
}

func Execute() {
	if err := rootCmd.Execute(); err != nil {
		os.Exit(1)
	}
}

func resolveBackupDir(cmd *cobra.Command) {
	if to, _ := cmd.Flags().GetString("to"); to != "" {
		cfg.BackupDir = to + "/DEDVD-BACKUPS"
	}
	if from, _ := cmd.Flags().GetString("from"); from != "" {
		cfg.BackupDir = from + "/DEDVD-BACKUPS"
	}
}

func newLogger() (*logger.Logger, error) {
	return logger.New(cfg.LogFile)
}

func runWatch() error {
	log, err := newLogger()
	if err != nil {
		return fmt.Errorf("init logger: %w", err)
	}
	defer log.Close()
	log.SessionStart(cfg.BackupDir)

	// Ensure backup dirs exist
	os.MkdirAll(cfg.BackupDir+"/VIDEO", 0o755)
	os.MkdirAll(cfg.BackupDir+"/DATA", 0o755)
	os.MkdirAll(cfg.BackupDir+"/AUDIO", 0o755)

	_, udevErr := exec.LookPath("udevadm")
	useUdev := udevErr == nil

	if !useUdev {
		log.Warn("udevadm not found — falling back to poll mode")
	}

	model := tui.NewWatchModel(cfg, log, useUdev)
	p := tea.NewProgram(model, tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		return err
	}
	return nil
}
