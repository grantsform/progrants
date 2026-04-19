package trans

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"syscall"

	"dedvd/internal/logger"
)

// Progress holds live transcode progress info.
type Progress struct {
	Label   string
	Pass    int
	Passes  int
	Percent float64
	FPS     int
	ETA     string
	Done    bool
	Failed  bool
	Error   string
	LogLine string // raw HandBrakeCLI output line (for viewport display)
}

// DiscJob represents one disc directory to transcode.
type DiscJob struct {
	Dir     string
	Name    string
	VTSDir  string
	OutFile string
	Index   int
	Total   int
}

// ScanDiscs finds all VIDEO backup directories that need transcoding.
func ScanDiscs(videoDir string) ([]DiscJob, error) {
	entries, err := os.ReadDir(videoDir)
	if err != nil {
		return nil, fmt.Errorf("read video dir: %w", err)
	}

	var dirs []string
	for _, e := range entries {
		if e.IsDir() {
			dirs = append(dirs, filepath.Join(videoDir, e.Name()))
		}
	}
	sort.Strings(dirs)

	var jobs []DiscJob
	for i, dir := range dirs {
		name := filepath.Base(dir)
		outFile := filepath.Join(filepath.Dir(dir), name+".mkv")

		// Skip already transcoded
		if _, err := os.Stat(outFile); err == nil {
			continue
		}

		// Find VIDEO_TS
		vts := findVTS(dir)
		if vts == "" {
			continue
		}

		jobs = append(jobs, DiscJob{
			Dir:     dir,
			Name:    name,
			VTSDir:  vts,
			OutFile: outFile,
			Index:   i + 1,
			Total:   len(dirs),
		})
	}

	return jobs, nil
}

// Encode runs HandBrakeCLI on a single disc job, sending progress updates to progressCh.
// Returns nil on success.
func Encode(job DiscJob, log *logger.Logger, progressCh chan<- Progress, ctx context.Context) error {
	const maxRetries = 2
	label := fmt.Sprintf("[%d/%d] %s", job.Index, job.Total, job.Name)

	re := regexp.MustCompile(`task (\d+) of (\d+), ([\d.]+) % \(.*, avg ([\d.]+) fps, ETA (\S+)\)`)

	for attempt := 0; attempt <= maxRetries; attempt++ {
		progressCh <- Progress{Label: label, Percent: 0, ETA: "starting..."}

		// Use stdbuf to force line-buffered output — HandBrakeCLI buffers
		// when it detects a non-tty.  Merge stdout+stderr (progress may go
		// to either stream depending on HB version).
		cmd := exec.CommandContext(ctx, "stdbuf", "-oL", "-eL",
			"HandBrakeCLI",
			"--input", job.VTSDir,
			"--main-feature",
			"--preset", "H.264 MKV 720p30",
			"--output", job.OutFile,
		)
		// Create a new process group so we can kill stdbuf + HandBrakeCLI together
		cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
		cmd.Cancel = func() error {
			// Kill the entire process group
			if cmd.Process != nil {
				return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
			}
			return nil
		}
		stdout, err := cmd.StdoutPipe()
		if err != nil {
			return fmt.Errorf("pipe stdout: %w", err)
		}
		cmd.Stderr = cmd.Stdout // merge stderr into the same pipe

		if err := cmd.Start(); err != nil {
			return fmt.Errorf("start handbrake: %w", err)
		}

		var lastErr string
		scanner := bufio.NewScanner(stdout)
		scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
		scanner.Split(scanCRLF)

		for scanner.Scan() {
			line := scanner.Text()
			trimmed := strings.TrimSpace(line)
			if trimmed == "" {
				continue
			}
			log.RawWrite([]byte(trimmed + "\n"))

			// Filter noisy library spam from the viewport (still logged to file above)
			if isNoisyLine(trimmed) {
				continue
			}

			if m := re.FindStringSubmatch(trimmed); len(m) > 5 {
				pass, _ := strconv.Atoi(m[1])
				passes, _ := strconv.Atoi(m[2])
				pct, _ := strconv.ParseFloat(m[3], 64)
				fps, _ := strconv.ParseFloat(m[4], 64)
				progressCh <- Progress{
					Label:   label,
					Pass:    pass,
					Passes:  passes,
					Percent: pct,
					FPS:     int(fps + 0.5),
					ETA:     m[5],
					LogLine: trimmed,
				}
			} else {
				// Emit non-progress lines so the viewport shows scanning/analysis output
				progressCh <- Progress{Label: label, LogLine: trimmed}
			}

			lower := strings.ToLower(trimmed)
			if strings.Contains(lower, "error") || strings.Contains(lower, "failed") ||
				strings.Contains(lower, "cannot") || strings.Contains(lower, "unable") {
				lastErr = trimmed
			}
		}

		err = cmd.Wait()

		// If context was cancelled (user quit), bail immediately — don't retry
		if ctx.Err() != nil {
			progressCh <- Progress{Label: label, Failed: true, Error: "cancelled"}
			return fmt.Errorf("cancelled")
		}

		if err == nil {
			info, statErr := os.Stat(job.OutFile)
			if statErr == nil && info.Size() > 0 {
				progressCh <- Progress{Label: label, Percent: 100, Done: true}
				return nil
			}
		}

		if attempt < maxRetries {
			log.Warnf("Retry %d/%d for %s: %s", attempt+1, maxRetries, job.Name, lastErr)
			progressCh <- Progress{Label: label, Error: fmt.Sprintf("retry %d/%d — %s", attempt+1, maxRetries, lastErr)}
			os.Remove(job.OutFile)
		} else {
			progressCh <- Progress{Label: label, Failed: true, Error: lastErr}
			log.Errorf("FAILED: %s — %s", label, lastErr)
			return fmt.Errorf("transcode failed after %d retries: %s", maxRetries, lastErr)
		}
	}

	return fmt.Errorf("transcode failed")
}

// isNoisyLine returns true for spammy libdvdread / libdvdnav / codec lines
// that add no value in the viewport.
func isNoisyLine(s string) bool {
	for _, pfx := range []string{
		"libdvdread:",
		"libdvdnav:",
		"disc.c:",
		"ifo_read.c:",
		"nav_read.c:",
		"[mp2 @",
		"[av1 @",
		"[h264 @",
		"[mpeg @",
		"Cannot load lib",
		"l_adr_table",
	} {
		if strings.HasPrefix(s, pfx) || strings.Contains(s, pfx) {
			return true
		}
	}
	return false
}

// scanCRLF splits on \n, \r\n, or bare \r (HandBrakeCLI uses \r for progress).
func scanCRLF(data []byte, atEOF bool) (advance int, token []byte, err error) {
	if atEOF && len(data) == 0 {
		return 0, nil, nil
	}
	for i := 0; i < len(data); i++ {
		if data[i] == '\n' {
			return i + 1, data[:i], nil
		}
		if data[i] == '\r' {
			if i+1 < len(data) && data[i+1] == '\n' {
				return i + 2, data[:i], nil
			}
			return i + 1, data[:i], nil
		}
	}
	if atEOF {
		return len(data), data, nil
	}
	return 0, nil, nil
}

func findVTS(dir string) string {
	for _, name := range []string{"VIDEO_TS", "video_ts"} {
		p := filepath.Join(dir, name)
		if info, err := os.Stat(p); err == nil && info.IsDir() {
			return p
		}
	}
	return ""
}
