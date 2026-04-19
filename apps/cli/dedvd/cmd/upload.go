package cmd

import (
	"fmt"

	"dedvd/internal/tui"
	"dedvd/internal/upload"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"
)

var uploadCmd = &cobra.Command{
	Use:   "upload",
	Short: "Upload backups to remote host via rsync+ssh",
	Long: `Uploads DATA directories and transcoded VIDEO .mkv files to a remote host
via rsync over SSH. Specify the destination as USER@HOST:/path with --to.

Examples:
  dedvd upload --from /drv/dedvd --to GRANTOR@SERVOR-PERSONAL-5050:/drv/data/_DEDVD-SORT_`,
	RunE: func(cmd *cobra.Command, args []string) error {
		resolveBackupDir(cmd)

		toFlag, _ := cmd.Flags().GetString("to")
		if toFlag == "" {
			toFlag = cfg.Remote
		}

		target, err := upload.ParseTarget(toFlag)
		if err != nil {
			return fmt.Errorf("invalid --to: %w", err)
		}

		log, err := newLogger()
		if err != nil {
			return fmt.Errorf("init logger: %w", err)
		}
		defer log.Close()
		log.SessionStart(cfg.BackupDir)

		model := tui.NewUploadModel(cfg, log, target)
		p := tea.NewProgram(model, tea.WithAltScreen())
		if _, err := p.Run(); err != nil {
			return err
		}
		return nil
	},
}

func init() {
	uploadCmd.Flags().String("from", "", "prefix path for reads (appends /DEDVD-BACKUPS)")
	uploadCmd.Flags().String("to", "", "remote destination as USER@HOST:/path")
	rootCmd.AddCommand(uploadCmd)
}
