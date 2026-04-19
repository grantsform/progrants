package cmd

import (
	"fmt"

	"dedvd/internal/tui"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"
)

var convertCmd = &cobra.Command{
	Use:   "convert [directory]",
	Short: "Convert video files to 720p HQ .mkv via HandBrakeCLI",
	Long: `Recursively scans a directory for .m4v, .mp4, .mpg, and .avi files and converts each to an
identically-named .mkv using HandBrakeCLI (H.264 MKV 720p30 preset).

Successfully converted files are recorded in a top-level
.dedvd-convert-index file. On subsequent runs, any entry in the index
whose .mkv still exists on disk is skipped.`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		dir := args[0]

		log, err := newLogger()
		if err != nil {
			return fmt.Errorf("init logger: %w", err)
		}
		defer log.Close()
		log.SessionStart(dir)

		model := tui.NewConvertModel(dir, log)
		p := tea.NewProgram(model, tea.WithAltScreen())
		if _, err := p.Run(); err != nil {
			return err
		}
		return nil
	},
}

func init() {
	rootCmd.AddCommand(convertCmd)
}
