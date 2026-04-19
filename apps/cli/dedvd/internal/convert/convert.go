package convert

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

const indexFile = ".dedvd-convert-index"

// Progress mirrors trans.Progress for HandBrakeCLI output.
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
	LogLine string
}

// Job represents a single video file to convert.
type Job struct {
	InFile  string
	OutFile string
	Name    string
	Index   int
	Total   int
}

// ScanDir walks dir top-down and collects video files (.m4v, .mp4, .mpg, .avi)
// that have not yet been successfully converted (checked via the index file +
// .mkv existence).
func ScanDir(dir string) ([]Job, error) {
	done := readIndex(dir)

	var sources []string
	err := filepath.Walk(dir, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return nil
		}
		ext := strings.ToLower(filepath.Ext(path))
		if ext == ".m4v" || ext == ".mp4" || ext == ".mpg" || ext == ".mpeg" || ext == ".avi" {
			sources = append(sources, path)
		}
		return nil
	})
	if err != nil {
		return nil, fmt.Errorf("walk %s: %w", dir, err)
	}
	sort.Strings(sources)

	var jobs []Job
	for _, in := range sources {
		rel, _ := filepath.Rel(dir, in)
		out := strings.TrimSuffix(in, filepath.Ext(in)) + ".mkv"

		// Skip if index says done AND the .mkv still exists.
		if done[rel] {
			if _, err := os.Stat(out); err == nil {
				continue
			}
		}

		jobs = append(jobs, Job{
			InFile:  in,
			OutFile: out,
			Name:    rel,
		})
	}

	// Fill in numbering after filtering.
	for i := range jobs {
		jobs[i].Index = i + 1
		jobs[i].Total = len(jobs)
	}
	return jobs, nil
}

// Encode converts a single video file to .mkv using HandBrakeCLI at 720p HQ.
// On success it appends to the index. Progress is streamed to progressCh.
func Encode(job Job, dir string, log *logger.Logger, progressCh chan<- Progress, ctx context.Context) error {
	const maxRetries = 2
	label := fmt.Sprintf("[%d/%d] %s", job.Index, job.Total, job.Name)

	re := regexp.MustCompile(`task (\d+) of (\d+), ([\d.]+) % \(.*, avg ([\d.]+) fps, ETA (\S+)\)`)

	for attempt := 0; attempt <= maxRetries; attempt++ {
		progressCh <- Progress{Label: label, Percent: 0, ETA: "starting..."}

		cmd := exec.CommandContext(ctx, "stdbuf", "-oL", "-eL",
			"HandBrakeCLI",
			"--input", job.InFile,
			"--preset", "H.264 MKV 720p30",
			"--output", job.OutFile,
		)
		cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
		cmd.Cancel = func() error {
			if cmd.Process != nil {
				return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
			}
			return nil
		}
		stdout, err := cmd.StdoutPipe()
		if err != nil {
			return fmt.Errorf("pipe stdout: %w", err)
		}
		cmd.Stderr = cmd.Stdout

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
				progressCh <- Progress{Label: label, LogLine: trimmed}
			}

			lower := strings.ToLower(trimmed)
			if strings.Contains(lower, "error") || strings.Contains(lower, "failed") ||
				strings.Contains(lower, "cannot") || strings.Contains(lower, "unable") {
				lastErr = trimmed
			}
		}

		err = cmd.Wait()

		if ctx.Err() != nil {
			progressCh <- Progress{Label: label, Failed: true, Error: "cancelled"}
			return fmt.Errorf("cancelled")
		}

		if err == nil {
			info, statErr := os.Stat(job.OutFile)
			if statErr == nil && info.Size() > 0 {
				appendIndex(dir, job.Name)
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
			return fmt.Errorf("convert failed after %d retries: %s", maxRetries, lastErr)
		}
	}
	return fmt.Errorf("convert failed")
}

// ── Index helpers ────────────────────────────────────────────────────────────

// readIndex parses the .dedvd-convert-index file in dir and returns a set of
// relative paths that have been successfully converted.
func readIndex(dir string) map[string]bool {
	m := make(map[string]bool)
	data, err := os.ReadFile(filepath.Join(dir, indexFile))
	if err != nil {
		return m
	}
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(line)
		if line != "" {
			m[line] = true
		}
	}
	return m
}

// appendIndex adds a relative path to the index.
func appendIndex(dir, rel string) {
	f, err := os.OpenFile(filepath.Join(dir, indexFile), os.O_APPEND|os.O_CREATE|os.O_WRONLY, 0o644)
	if err != nil {
		return
	}
	defer f.Close()
	f.WriteString(rel + "\n")
}

// ── Shared helpers ──────────────────────────────────────────────────────────

func isNoisyLine(s string) bool {
	for _, pfx := range []string{
		"libdvdread:", "libdvdnav:", "disc.c:", "ifo_read.c:",
		"nav_read.c:", "[mp2 @", "[av1 @", "[h264 @", "[mpeg @",
		"Cannot load lib", "l_adr_table",
	} {
		if strings.HasPrefix(s, pfx) || strings.Contains(s, pfx) {
			return true
		}
	}
	return false
}

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
