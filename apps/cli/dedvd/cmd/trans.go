package cmd

import (
	"fmt"

	"dedvd/internal/tui"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"
)

var transCmd = &cobra.Command{
	Use:   "trans",
	Short: "Transcode VIDEO backups to MKV via HandBrakeCLI",
	Long:  "Scans VIDEO backup directories for untranscoded discs and encodes them to H.264 MKV 720p30 using HandBrakeCLI.",
	RunE: func(cmd *cobra.Command, args []string) error {
		resolveBackupDir(cmd)
		log, err := newLogger()
		if err != nil {
			return fmt.Errorf("init logger: %w", err)
		}
		defer log.Close()
		log.SessionStart(cfg.BackupDir)

		model := tui.NewTransModel(cfg, log)
		p := tea.NewProgram(model, tea.WithAltScreen())
		if _, err := p.Run(); err != nil {
			return err
		}
		return nil
	},
}

func init() {
	transCmd.Flags().String("from", "", "prefix path for reads (appends /DEDVD-BACKUPS)")
	rootCmd.AddCommand(transCmd)
}
