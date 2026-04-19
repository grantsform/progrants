package cmd

import (
	"fmt"
	"os"
	"os/exec"

	"dedvd/internal/disc"

	"github.com/spf13/cobra"
)

var rescueCmd = &cobra.Command{
	Use:   "rescue [device]",
	Short: "Recover files from a damaged disc using PhotoRec",
	Long: `Launches PhotoRec (from the testdisk package) to recover files from a
damaged or unreadable disc. PhotoRec handles its own interactive TUI and
is far more robust than any custom wrapper.

Scans for optical drives (/dev/sr0, /dev/sr1, ...). If multiple drives
are found you will be prompted to choose one. PhotoRec's own TUI takes
over from there — use it to select the output directory and file types.

Examples:
  dedvd rescue              # auto-detect optical drive
  dedvd rescue /dev/sr1    # specific device`,
	RunE: func(cmd *cobra.Command, args []string) error {
		resolveBackupDir(cmd)

		if _, err := exec.LookPath("photorec"); err != nil {
			return fmt.Errorf("photorec not found — install with: nix-shell -p testdisk (or apt install testdisk)")
		}

		var dev string
		if len(args) > 0 {
			dev = args[0]
		} else {
			devs := disc.ListOpticalDevices()
			switch len(devs) {
			case 0:
				return fmt.Errorf("no optical drives found (expected /dev/sr0, /dev/sr1, ...)")
			case 1:
				dev = devs[0]
			default:
				fmt.Println("Multiple optical drives found:")
				for i, d := range devs {
					fmt.Printf("  [%d] %s\n", i, d)
				}
				fmt.Print("Select drive number [0]: ")
				var n int
				if _, err := fmt.Scan(&n); err != nil || n < 0 || n >= len(devs) {
					n = 0
				}
				dev = devs[n]
			}
		}

		if _, err := os.Stat(dev); err != nil {
			return fmt.Errorf("device not found: %s", dev)
		}

		fmt.Printf("Launching PhotoRec for %s\n\n", dev)

		photorec := exec.Command("photorec", dev)
		photorec.Stdin = os.Stdin
		photorec.Stdout = os.Stdout
		photorec.Stderr = os.Stderr
		return photorec.Run()
	},
}

func init() {
	rescueCmd.Flags().String("to", "", "prefix path for output (appends /DEDVD-BACKUPS)")
	rootCmd.AddCommand(rescueCmd)
}
