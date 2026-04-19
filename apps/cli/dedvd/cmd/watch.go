package cmd

import (
	"dedvd/internal/tui"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"
)

var watchCmd = &cobra.Command{
	Use:   "watch",
	Short: "Watch for disc insertions and auto-backup",
	Long:  "Monitors optical drives for disc insertion, detects DATA/VIDEO type, and performs verified rsync backups.",
	RunE: func(cmd *cobra.Command, args []string) error {
		resolveBackupDir(cmd)
		return runWatch()
	},
}

func init() {
	watchCmd.Flags().String("to", "", "prefix path for backups (appends /DEDVD-BACKUPS)")
	rootCmd.AddCommand(watchCmd)
}

// Keep the standalone watch TUI accessible
var watchStandaloneCmd = &cobra.Command{
	Use:    "watch-headless",
	Short:  "Watch for disc insertions without TUI (log-only mode)",
	Hidden: true,
	RunE: func(cmd *cobra.Command, args []string) error {
		resolveBackupDir(cmd)
		log, err := newLogger()
		if err != nil {
			return err
		}
		defer log.Close()
		log.SessionStart(cfg.BackupDir)

		model := tui.NewWatchModel(cfg, log, true)
		p := tea.NewProgram(model)
		_, err = p.Run()
		return err
	},
}

func init() {
	rootCmd.AddCommand(watchStandaloneCmd)
}
