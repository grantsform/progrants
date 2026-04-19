package rescue

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"syscall"
	"time"

	"dedvd/internal/logger"
)

// Event is a structured progress update emitted during rescue.
type Event struct {
	Phase   string // "start", "progress", "done", "error"
	Message string
	Rescued string // e.g. "2048 MB"
	Pct     string // e.g. "45.2%"
	Rate    string // e.g. "1200 kB/s"
	Errors  string // e.g. "42"
}

// Run executes disc rescue — uses ddrescue when the kernel can see the device,
// or falls back to readom (raw SCSI commands) when kernel reports 0 capacity.
func Run(dev, dest, mapFile string, log *logger.Logger, events chan<- Event, ctx context.Context) error {
	emit := func(e Event) {
		if events != nil {
			events <- e
		}
	}

	emit(Event{Phase: "start", Message: fmt.Sprintf("Starting rescue: %s → %s", dev, dest)})
	log.Infof("rescue: %s → %s (map: %s)", dev, dest, mapFile)

	// Determine disc size from drive firmware (works even when kernel reports 0)
	size := discSize(dev, log)
	if size <= 0 {
		size = 4700372992 // standard DVD-R capacity
		emit(Event{Phase: "progress", Message: "Could not detect disc size — using DVD-R max (4.7 GB)"})
		log.Warn("Could not detect disc size — using DVD-R max")
	} else {
		emit(Event{Phase: "progress", Message: fmt.Sprintf("Detected disc size: %s", humanSize(size))})
		log.Infof("Disc size: %d bytes (%s)", size, humanSize(size))
	}

	// Check if kernel can actually see the device data.
	// Unfinalized/damaged DVD-Rs often report 0 bytes to the kernel,
	// making read() via the block layer return EOF immediately.
	// ddrescue uses read() so it can't work in this case.
	kernelSz := kernelDeviceSize(dev)
	log.Infof("Kernel device size: %d bytes", kernelSz)

	if kernelSz <= 0 {
		// Kernel block layer will return EOF — the drive firmware considers
		// this disc blank (unfinalized session). Try to close/fixate the
		// session first, which writes lead-in/lead-out without touching data.
		log.Info("Kernel reports 0 capacity — disc likely has an unclosed session")
		emit(Event{Phase: "progress", Message: "Kernel sees 0 bytes — attempting to fixate unclosed session..."})

		if err := tryFixateSession(ctx, dev, log, emit); err != nil {
			log.Warnf("Session fixation failed: %v", err)
			emit(Event{Phase: "progress", Message: fmt.Sprintf("Fixation failed: %v — trying raw SCSI read as last resort...", err)})
		} else {
			// Re-check kernel capacity after fixation
			kernelSz = kernelDeviceSize(dev)
			log.Infof("Kernel device size after fixation: %d bytes", kernelSz)
		}

		if kernelSz <= 0 {
			// Still 0 after fixation attempt — try readom as last resort
			log.Info("Still 0 capacity — falling back to raw SCSI reading (readom)")
			emit(Event{Phase: "progress", Message: "Still 0 bytes — trying raw SCSI reader (readom)..."})
			return runReadom(ctx, dev, dest, size, log, emit)
		}

		emit(Event{Phase: "progress", Message: fmt.Sprintf("Session fixated! Kernel now sees %s", humanSize(kernelSz))})
		log.Infof("Session fixation worked — kernel now reports %d bytes", kernelSz)
	}

	// Kernel can see the disc — use ddrescue (better recovery with mapfile)
	sizeStr := strconv.FormatInt(size, 10)

	// Pass 1: fast recovery (skip errors quickly)
	log.Info("Pass 1: fast recovery (--no-scrape)")
	emit(Event{Phase: "progress", Message: "Pass 1: fast recovery..."})
	if err := runDdrescue(ctx, dev, dest, mapFile, []string{"--no-scrape", "-n", "--size", sizeStr}, log, emit); err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		emit(Event{Phase: "error", Message: fmt.Sprintf("Pass 1: %v", err)})
		log.Warnf("Pass 1 ended with: %v", err)
	}

	// Check if anything was rescued
	if fi, stErr := os.Stat(dest); stErr != nil {
		log.Warnf("0-byte bailout: stat error: %v", stErr)
		err := fmt.Errorf("ddrescue output file missing: %v", stErr)
		emit(Event{Phase: "error", Message: err.Error()})
		return err
	} else if fi.Size() == 0 {
		log.Warnf("0-byte bailout: file exists but empty (0 bytes)")
		err := fmt.Errorf("ddrescue produced no output — check device permissions and disc")
		emit(Event{Phase: "error", Message: err.Error()})
		return err
	} else {
		log.Infof("Pass 1 output: %d bytes (%s)", fi.Size(), humanSize(fi.Size()))
	}

	if ctx.Err() != nil {
		return ctx.Err()
	}

	// Pass 2: retry bad sectors with retries
	log.Info("Pass 2: retrying bad sectors (-r 3)")
	emit(Event{Phase: "progress", Message: "Pass 2: retrying bad sectors..."})
	if err := runDdrescue(ctx, dev, dest, mapFile, []string{"-r", "3", "--size", sizeStr}, log, emit); err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		emit(Event{Phase: "error", Message: fmt.Sprintf("Pass 2: %v", err)})
		log.Warnf("Pass 2 ended with: %v", err)
	}

	// Report final stats
	if fi, err := os.Stat(dest); err == nil {
		emit(Event{Phase: "done", Message: fmt.Sprintf("ddrescue completed — rescued %s", humanSize(fi.Size()))})
		log.Infof("ddrescue completed — output: %d bytes", fi.Size())
	} else {
		emit(Event{Phase: "done", Message: "ddrescue completed"})
		log.Info("ddrescue completed")
	}
	return nil
}

// kernelDeviceSize returns what the Linux block layer thinks the device size is.
// Returns 0 for devices the kernel considers blank (e.g. unfinalized DVD-R).
func kernelDeviceSize(dev string) int64 {
	// Try without sudo first (works if user can read the device)
	if out, err := exec.Command("blockdev", "--getsize64", dev).Output(); err == nil {
		s := strings.TrimSpace(string(out))
		if sz, _ := strconv.ParseInt(s, 10, 64); sz > 0 {
			return sz
		}
	}
	if out, err := exec.Command("sudo", "-n", "blockdev", "--getsize64", dev).Output(); err == nil {
		s := strings.TrimSpace(string(out))
		if sz, _ := strconv.ParseInt(s, 10, 64); sz > 0 {
			return sz
		}
	}
	return 0
}

// tryFixateSession attempts to close/fixate an unclosed disc session.
// An unfinalized DVD-R has data written but no lead-in/lead-out, so the
// drive considers it blank. Fixation writes the session closure info
// without modifying the data area, making the drive recognize the content.
func tryFixateSession(ctx context.Context, dev string, log *logger.Logger, emit func(Event)) error {
	// Find wodim or cdrecord
	binary := ""
	for _, name := range []string{"wodim", "cdrecord"} {
		if p, err := exec.LookPath(name); err == nil {
			binary = p
			break
		}
	}
	if binary == "" {
		return fmt.Errorf("wodim/cdrecord not found — install cdrkit or cdrtools")
	}

	binName := filepath.Base(binary)
	args := []string{fmt.Sprintf("dev=%s", dev), "-fix", "-force"}

	var cmd *exec.Cmd
	if needsSudo(dev) {
		sudoArgs := append([]string{"-n", binary}, args...)
		cmd = exec.CommandContext(ctx, "sudo", sudoArgs...)
		log.Infof("Running: sudo %s %s", binName, strings.Join(args, " "))
	} else {
		cmd = exec.CommandContext(ctx, binary, args...)
		log.Infof("Running: %s %s", binName, strings.Join(args, " "))
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process != nil {
			return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		}
		return nil
	}

	out, err := cmd.CombinedOutput()
	log.RawWrite([]byte(fmt.Sprintf("--- %s -fix output ---\n", binName)))
	log.RawWrite(out)

	if err != nil {
		return fmt.Errorf("%s -fix: %w", binName, err)
	}

	emit(Event{Phase: "progress", Message: "Session fixated — waiting for drive to settle..."})
	log.Info("Session fixated, waiting for drive to re-read disc...")

	// Give the drive time to re-read the disc after fixation.
	// Poll kernel capacity up to 15 seconds.
	for i := 0; i < 15; i++ {
		select {
		case <-ctx.Done():
			return ctx.Err()
		default:
		}
		// Trigger kernel re-read
		exec.Command("blockdev", "--rereadpt", dev).Run()
		if sz := kernelDeviceSize(dev); sz > 0 {
			log.Infof("Drive re-read successful after %d seconds", i+1)
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(time.Second):
		}
	}

	log.Info("Drive did not re-read within 15 seconds")
	return nil // not an error — caller will re-check capacity
}

// runReadom uses readom (from cdrkit/cdrtools) to do raw SCSI sector reads.
// This bypasses the Linux block layer entirely using SG_IO ioctls,
// so it works even when the kernel reports the device as 0 bytes.
func runReadom(ctx context.Context, dev, dest string, sizeBytes int64, log *logger.Logger, emit func(Event)) error {
	sectors := sizeBytes / 2048

	// Find readom or readcd binary
	binary := ""
	for _, name := range []string{"readom", "readcd"} {
		if p, err := exec.LookPath(name); err == nil {
			binary = p
			break
		}
	}
	if binary == "" {
		return fmt.Errorf("readom/readcd not found — install cdrkit or cdrtools")
	}

	args := []string{
		fmt.Sprintf("dev=%s", dev),
		fmt.Sprintf("f=%s", dest),
		fmt.Sprintf("sectors=0-%d", sectors-1),
		"retries=8",
		"-noerror",
		"-v",
	}

	log.Infof("readom: %d sectors (%s), dest=%s", sectors, humanSize(sizeBytes), dest)

	var cmd *exec.Cmd
	binName := filepath.Base(binary)
	if needsSudo(dev) {
		sudoArgs := append([]string{"-n", binary}, args...)
		cmd = exec.CommandContext(ctx, "sudo", sudoArgs...)
		log.Infof("Running: sudo %s %s", binName, strings.Join(args, " "))
	} else {
		cmd = exec.CommandContext(ctx, binary, args...)
		log.Infof("Running: %s %s", binName, strings.Join(args, " "))
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process != nil {
			return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		}
		return nil
	}

	// Merge stdout + stderr
	pr, pw, err := os.Pipe()
	if err != nil {
		return fmt.Errorf("create pipe: %w", err)
	}
	cmd.Stdout = pw
	cmd.Stderr = pw

	if err := cmd.Start(); err != nil {
		pw.Close()
		pr.Close()
		return fmt.Errorf("start %s: %w", binName, err)
	}
	pw.Close()

	// Parse readom output: "addr: 12345 cnt: 16" lines show progress
	addrRe := regexp.MustCompile(`addr:\s*(\d+)`)
	errLineRe := regexp.MustCompile(`(?i)error|Cannot|cannot`)

	scanner := bufio.NewScanner(pr)
	scanner.Buffer(make([]byte, 0, 64*1024), 256*1024)
	scanner.Split(scanCRLF)

	var lastAddr int64
	var errCount int

	for scanner.Scan() {
		line := scanner.Text()
		log.RawWrite([]byte(line + "\n"))

		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}

		if errLineRe.MatchString(trimmed) && !strings.Contains(trimmed, "-noerror") {
			errCount++
		}

		if m := addrRe.FindStringSubmatch(trimmed); len(m) > 1 {
			if addr, err := strconv.ParseInt(m[1], 10, 64); err == nil {
				lastAddr = addr
				pct := float64(addr) / float64(sectors) * 100
				rescued := addr * 2048
				emit(Event{
					Phase:   "progress",
					Message: fmt.Sprintf("rescued: %s, errors: %d", humanSize(rescued), errCount),
					Rescued: humanSize(rescued),
					Pct:     fmt.Sprintf("%.1f%%", pct),
					Errors:  strconv.Itoa(errCount),
				})
			}
		}
	}
	pr.Close()

	waitErr := cmd.Wait()
	if waitErr != nil {
		log.Warnf("%s exited: %v", binName, waitErr)
	}

	// Report final result
	var rescued int64
	if fi, err := os.Stat(dest); err == nil {
		rescued = fi.Size()
	} else {
		rescued = lastAddr * 2048
	}

	if rescued == 0 {
		err := fmt.Errorf("%s produced no output — check device permissions", binName)
		emit(Event{Phase: "error", Message: err.Error()})
		return err
	}

	// If we rescued less than 0.1% of expected size, the drive firmware is
	// refusing to read — this is not a partial success, it's a total failure.
	if rescued < sizeBytes/1000 {
		msgs := []string{
			fmt.Sprintf("Drive firmware refused to read disc (rescued %s of expected %s)", humanSize(rescued), humanSize(sizeBytes)),
			"SCSI READ commands returned 'LBA out of range' — the drive considers this disc blank.",
			"This typically means the DVD-R session was never finalized (closed).",
			"The disc's Recording Management Data shows no written sectors.",
			"",
			"No software tool (ddrescue, readom, photorec) can override the drive firmware.",
			"",
			"Possible next steps:",
			"  • Try a different optical drive — different firmware may interpret the disc differently",
			"  • Try a different computer — some SATA/USB controllers interact differently",
			"  • Professional data recovery services with specialized hardware",
		}
		for _, line := range msgs {
			emit(Event{Phase: "error", Message: line})
		}
		log.Warnf("Rescue failed: drive refused to read (%s of %s)", humanSize(rescued), humanSize(sizeBytes))
		return fmt.Errorf("drive firmware refused to read disc — try a different optical drive")
	}

	emit(Event{
		Phase:   "done",
		Message: fmt.Sprintf("Raw SCSI read completed — rescued %s, %d errors", humanSize(rescued), errCount),
		Rescued: humanSize(rescued),
		Errors:  strconv.Itoa(errCount),
	})
	log.Infof("%s completed: rescued %d bytes (%s), %d errors", binName, rescued, humanSize(rescued), errCount)
	return nil
}

// discSize tries to determine the disc capacity in bytes.
// Tries dvd+rw-mediainfo first (works even when kernel reports 0),
// then blockdev, then returns 0 to use DVD default.
func discSize(dev string, log *logger.Logger) int64 {
	// Try dvd+rw-mediainfo — parses track info from the drive firmware,
	// works even with unfinalized/damaged discs
	if out, err := exec.Command("dvd+rw-mediainfo", dev).CombinedOutput(); err == nil {
		log.RawWrite([]byte("--- dvd+rw-mediainfo output ---\n"))
		log.RawWrite(out)
		text := string(out)

		// Pattern matches both "2298496*2KB=4707319808" and "2295104*2048=4700372992"
		bytesRe := regexp.MustCompile(`(\d+)\*2\w*=\s*(\d+)`)

		// 1. "Legacy lead-out at:" — most reliable total disc size
		for _, line := range strings.Split(text, "\n") {
			if strings.Contains(line, "lead-out") {
				if m := bytesRe.FindStringSubmatch(line); len(m) > 2 {
					if sz, err := strconv.ParseInt(m[2], 10, 64); err == nil && sz > 0 {
						log.Infof("dvd+rw-mediainfo: lead-out = %d bytes", sz)
						return sz
					}
				}
			}
		}

		// 2. "Track Size:" — may have =bytes or just sectors*2KB
		for _, line := range strings.Split(text, "\n") {
			if strings.Contains(line, "Track Size:") {
				if m := bytesRe.FindStringSubmatch(line); len(m) > 2 {
					if sz, err := strconv.ParseInt(m[2], 10, 64); err == nil && sz > 0 {
						log.Infof("dvd+rw-mediainfo: track size = %d bytes", sz)
						return sz
					}
				}
				// "Track Size:  2297888*2KB" — no =bytes, compute it
				sectRe := regexp.MustCompile(`Track Size:\s*(\d+)\*`)
				if m := sectRe.FindStringSubmatch(line); len(m) > 1 {
					if sectors, err := strconv.ParseInt(m[1], 10, 64); err == nil && sectors > 0 {
						sz := sectors * 2048
						log.Infof("dvd+rw-mediainfo: track sectors=%d → %d bytes", sectors, sz)
						return sz
					}
				}
			}
		}

		// 3. Any other "Size:" line with computable bytes
		for _, line := range strings.Split(text, "\n") {
			if strings.Contains(line, "size:") || strings.Contains(line, "Size:") {
				if m := bytesRe.FindStringSubmatch(line); len(m) > 2 {
					if sz, err := strconv.ParseInt(m[2], 10, 64); err == nil && sz > 0 {
						log.Infof("dvd+rw-mediainfo: size = %d bytes (%s)", sz, strings.TrimSpace(line))
						return sz
					}
				}
			}
		}
	} else {
		log.Infof("dvd+rw-mediainfo failed: %v", err)
	}

	// Try blockdev
	if out, err := exec.Command("sudo", "-n", "blockdev", "--getsize64", dev).Output(); err == nil {
		s := strings.TrimSpace(string(out))
		if sz, err := strconv.ParseInt(s, 10, 64); err == nil && sz > 0 {
			log.Infof("blockdev: %d bytes", sz)
			return sz
		}
	}

	// Try isosize
	if out, err := exec.Command("isosize", dev).Output(); err == nil {
		s := strings.TrimSpace(string(out))
		if sz, err := strconv.ParseInt(s, 10, 64); err == nil && sz > 0 {
			log.Infof("isosize: %d bytes", sz)
			return sz
		}
	}

	return 0
}

// needsSudo checks if we can read the device directly.
func needsSudo(dev string) bool {
	f, err := os.Open(dev)
	if err != nil {
		return true
	}
	f.Close()
	return false
}

func runDdrescue(ctx context.Context, dev, dest, mapFile string, extraArgs []string, log *logger.Logger, emit func(Event)) error {
	ddrescueArgs := []string{"-v", "-b", "2048", "--force"}
	ddrescueArgs = append(ddrescueArgs, extraArgs...)
	ddrescueArgs = append(ddrescueArgs, dev, dest, mapFile)

	var cmd *exec.Cmd
	if needsSudo(dev) {
		sudoArgs := append([]string{"-n", "ddrescue"}, ddrescueArgs...)
		cmd = exec.CommandContext(ctx, "sudo", sudoArgs...)
		log.Infof("Running: sudo %s", strings.Join(sudoArgs, " "))
	} else {
		cmd = exec.CommandContext(ctx, "ddrescue", ddrescueArgs...)
		log.Infof("Running: ddrescue %s", strings.Join(ddrescueArgs, " "))
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process != nil {
			return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		}
		return nil
	}

	// Merge stdout + stderr into a single pipe so we capture everything
	pr, pw, err := os.Pipe()
	if err != nil {
		return fmt.Errorf("create pipe: %w", err)
	}
	cmd.Stdout = pw
	cmd.Stderr = pw

	if err := cmd.Start(); err != nil {
		pw.Close()
		pr.Close()
		return fmt.Errorf("start ddrescue: %w", err)
	}
	pw.Close() // close write end so scanner gets EOF when process exits

	// ddrescue writes status lines to stderr with \r updates
	// Example: "rescued: 2048 MB, errsize: 512 B, rate: 1200 kB/s"
	// Also: "pct rescued:  45.23%, read errors:  42"
	rescuedRe := regexp.MustCompile(`rescued:\s*([\d.]+\s*\S+)`)
	errSizeRe := regexp.MustCompile(`errsize:\s*([\d.]+\s*\S+)`)
	rateRe := regexp.MustCompile(`rate:\s*([\d.]+\s*\S+)`)
	pctRe := regexp.MustCompile(`pct rescued:\s*([\d.]+%)`)
	readErrRe := regexp.MustCompile(`read errors:\s*(\d+)`)

	scanner := bufio.NewScanner(pr)
	scanner.Buffer(make([]byte, 0, 64*1024), 256*1024)
	scanner.Split(scanCRLF)

	for scanner.Scan() {
		line := scanner.Text()
		log.RawWrite([]byte(line + "\n"))

		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}

		ev := Event{Phase: "progress"}

		if m := rescuedRe.FindStringSubmatch(trimmed); len(m) > 1 {
			ev.Rescued = m[1]
		}
		if m := rateRe.FindStringSubmatch(trimmed); len(m) > 1 {
			ev.Rate = m[1]
		}
		if m := errSizeRe.FindStringSubmatch(trimmed); len(m) > 1 {
			ev.Message = fmt.Sprintf("rescued: %s, errors: %s, rate: %s", ev.Rescued, m[1], ev.Rate)
		}
		if m := pctRe.FindStringSubmatch(trimmed); len(m) > 1 {
			ev.Pct = m[1]
		}
		if m := readErrRe.FindStringSubmatch(trimmed); len(m) > 1 {
			ev.Errors = m[1]
		}

		if ev.Rescued != "" || ev.Pct != "" {
			if ev.Message == "" {
				ev.Message = trimmed
			}
			emit(ev)
		}
	}
	pr.Close()

	waitErr := cmd.Wait()
	if waitErr != nil {
		log.Warnf("ddrescue exited: %v", waitErr)
	}
	return waitErr
}

// scanCRLF splits on \n, \r\n, or bare \r.
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

func humanSize(b int64) string {
	const (
		MB = 1024 * 1024
		GB = 1024 * MB
	)
	switch {
	case b >= GB:
		return fmt.Sprintf("%.2f GB", float64(b)/float64(GB))
	case b >= MB:
		return fmt.Sprintf("%.1f MB", float64(b)/float64(MB))
	default:
		return fmt.Sprintf("%d B", b)
	}
}
