package cmd

import (
	"fmt"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"dedvd/internal/tui"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/spf13/cobra"
)

var combineCmd = &cobra.Command{
	Use:   "combine [directory]",
	Short: "Combine all files of a given type in a directory into one .mkv",
	Long: `Collects all files matching --fmt in the given directory, sorts them by
filename, concatenates them with ffmpeg, then transcodes the result to a
720p H.264 .mkv via HandBrakeCLI. Original files are left untouched.

The output file is placed in the same directory as the inputs, named
after the directory with a timestamp (e.g. MyDisc_20060102_150405.mkv).

Examples:
  dedvd combine /path/to/disc --fmt mpg
  dedvd combine /path/to/disc --fmt avi
  dedvd combine /path/to/disc --fmt mpg --out combined.mkv`,
	Args: cobra.ExactArgs(1),
	RunE: func(cmd *cobra.Command, args []string) error {
		dir := args[0]
		ext, _ := cmd.Flags().GetString("fmt")
		outName, _ := cmd.Flags().GetString("out")

		if ext == "" {
			return fmt.Errorf("--fmt is required (e.g. --fmt mpg)")
		}
		// Normalise extension
		ext = strings.TrimPrefix(strings.ToLower(ext), ".")

		if _, err := exec.LookPath("ffmpeg"); err != nil {
			return fmt.Errorf("ffmpeg not found — required for concatenation")
		}
		if _, err := exec.LookPath("HandBrakeCLI"); err != nil {
			return fmt.Errorf("HandBrakeCLI not found — required for transcoding")
		}

		if outName == "" {
			base := filepath.Base(filepath.Clean(dir))
			ts := time.Now().Format("20060102_150405")
			outName = base + "_" + ts + ".mkv"
		}
		if !strings.HasSuffix(strings.ToLower(outName), ".mkv") {
			outName += ".mkv"
		}
		outFile := filepath.Join(dir, outName)

		log, err := newLogger()
		if err != nil {
			return fmt.Errorf("init logger: %w", err)
		}
		defer log.Close()
		log.SessionStart(dir)

		model := tui.NewCombineModel(dir, ext, outFile, log)
		p := tea.NewProgram(model, tea.WithAltScreen())
		if _, err := p.Run(); err != nil {
			return err
		}
		return nil
	},
}

func init() {
	combineCmd.Flags().String("fmt", "", "file extension to combine (e.g. mpg, avi, mp4)")
	combineCmd.Flags().String("out", "", "output filename (default: <dir>_<timestamp>.mkv)")
	rootCmd.AddCommand(combineCmd)
}
