package combine

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

// Progress reports combine+encode progress to the TUI.
type Progress struct {
	Phase   string // "concat", "encode"
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

// ScanDir lists all files in dir (non-recursive) with the given extension,
// sorted by filename.
func ScanDir(dir, ext string) ([]string, error) {
	if !strings.HasPrefix(ext, ".") {
		ext = "." + ext
	}
	ext = strings.ToLower(ext)

	entries, err := os.ReadDir(dir)
	if err != nil {
		return nil, fmt.Errorf("read dir %s: %w", dir, err)
	}

	var files []string
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		if strings.ToLower(filepath.Ext(e.Name())) == ext {
			files = append(files, filepath.Join(dir, e.Name()))
		}
	}
	sort.Strings(files)
	return files, nil
}

// Run concatenates files via ffmpeg then transcodes the result with
// HandBrakeCLI into outFile (which should end in .mkv).
// Progress is streamed to progressCh.
func Run(files []string, outFile string, log *logger.Logger, progressCh chan<- Progress, ctx context.Context) error {
	emit := func(p Progress) {
		if progressCh != nil {
			progressCh <- p
		}
	}

	if len(files) == 0 {
		return fmt.Errorf("no input files")
	}

	// ── Step 1: ffmpeg concat into a temp file ───────────────────────────
	tmpFile := outFile + ".dedvd-combine-tmp.ts"
	defer os.Remove(tmpFile)

	emit(Progress{Phase: "concat", Label: fmt.Sprintf("Concatenating %d files...", len(files))})
	log.Infof("combine: concatenating %d files → %s", len(files), tmpFile)

	if err := ffmpegConcat(ctx, files, tmpFile, log, emit); err != nil {
		return fmt.Errorf("concat: %w", err)
	}

	if ctx.Err() != nil {
		return ctx.Err()
	}

	// ── Step 2: HandBrakeCLI transcode ───────────────────────────────────
	emit(Progress{Phase: "encode", Label: "Transcoding to MKV..."})
	log.Infof("combine: transcoding %s → %s", tmpFile, outFile)

	if err := handbrakeEncode(ctx, tmpFile, outFile, log, emit); err != nil {
		os.Remove(outFile)
		return fmt.Errorf("encode: %w", err)
	}

	return nil
}

func ffmpegConcat(ctx context.Context, files []string, out string, log *logger.Logger, emit func(Progress)) error {
	// Write a concat list file for ffmpeg.
	listFile := out + ".concat-list.txt"
	defer os.Remove(listFile)

	f, err := os.Create(listFile)
	if err != nil {
		return fmt.Errorf("create concat list: %w", err)
	}
	for _, path := range files {
		// ffmpeg concat demuxer requires absolute paths and escaped single-quotes.
		abs, _ := filepath.Abs(path)
		escaped := strings.ReplaceAll(abs, "'", "'\\''")
		fmt.Fprintf(f, "file '%s'\n", escaped)
		log.Infof("  + %s", filepath.Base(path))
		emit(Progress{Phase: "concat", LogLine: "+ " + filepath.Base(path)})
	}
	f.Close()

	cmd := exec.CommandContext(ctx, "ffmpeg",
		"-y",
		"-f", "concat",
		"-safe", "0",
		"-i", listFile,
		"-c", "copy",
		out,
	)
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process != nil {
			return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		}
		return nil
	}

	combined, err := cmd.CombinedOutput()
	log.RawWrite(combined)
	if err != nil {
		return fmt.Errorf("ffmpeg: %w", err)
	}

	info, err := os.Stat(out)
	if err != nil || info.Size() == 0 {
		return fmt.Errorf("ffmpeg produced empty output")
	}
	emit(Progress{Phase: "concat", Label: fmt.Sprintf("Concatenated → %s", humanSize(info.Size()))})
	return nil
}

func handbrakeEncode(ctx context.Context, in, out string, log *logger.Logger, emit func(Progress)) error {
	re := regexp.MustCompile(`task (\d+) of (\d+), ([\d.]+) % \(.*, avg ([\d.]+) fps, ETA (\S+)\)`)

	cmd := exec.CommandContext(ctx, "stdbuf", "-oL", "-eL",
		"HandBrakeCLI",
		"--input", in,
		"--preset", "H.264 MKV 720p30",
		"--output", out,
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

	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 0, 64*1024), 1024*1024)
	scanner.Split(scanCRLF)

	var lastErr string
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if line == "" {
			continue
		}
		log.RawWrite([]byte(line + "\n"))

		if isNoisyLine(line) {
			continue
		}

		if m := re.FindStringSubmatch(line); len(m) > 5 {
			pass, _ := strconv.Atoi(m[1])
			passes, _ := strconv.Atoi(m[2])
			pct, _ := strconv.ParseFloat(m[3], 64)
			fps, _ := strconv.ParseFloat(m[4], 64)
			emit(Progress{
				Phase:   "encode",
				Label:   fmt.Sprintf("pass %d/%d", pass, passes),
				Pass:    pass,
				Passes:  passes,
				Percent: pct,
				FPS:     int(fps + 0.5),
				ETA:     m[5],
			})
		} else {
			emit(Progress{Phase: "encode", LogLine: line})
			lower := strings.ToLower(line)
			if strings.Contains(lower, "error") || strings.Contains(lower, "failed") {
				lastErr = line
			}
		}
	}

	if err := cmd.Wait(); err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		return fmt.Errorf("handbrake: %w — %s", err, lastErr)
	}

	info, err := os.Stat(out)
	if err != nil || info.Size() == 0 {
		return fmt.Errorf("handbrake produced empty output")
	}
	emit(Progress{Phase: "encode", Percent: 100, Done: true, Label: fmt.Sprintf("Done → %s", humanSize(info.Size()))})
	return nil
}

func humanSize(b int64) string {
	switch {
	case b >= 1<<30:
		return fmt.Sprintf("%.2f GB", float64(b)/float64(1<<30))
	case b >= 1<<20:
		return fmt.Sprintf("%.1f MB", float64(b)/float64(1<<20))
	case b >= 1<<10:
		return fmt.Sprintf("%.0f KB", float64(b)/float64(1<<10))
	default:
		return fmt.Sprintf("%d B", b)
	}
}

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
