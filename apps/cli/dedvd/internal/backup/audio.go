package backup

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

	"dedvd/internal/disc"
	"dedvd/internal/logger"
)

// queryAudioTracks runs cdparanoia -Q to read the disc's table of contents.
// Returns the number of audio tracks and their per-track sector lengths.
// On failure, trackCount == 0.
func queryAudioTracks(dev string, ctx context.Context) (trackCount int, sectors []int64) {
	out, _ := exec.CommandContext(ctx, "cdparanoia", "-Q", "-d", dev).CombinedOutput()
	// Track lines: "  1.    16341 [03:37.91]   0 [00:00.00]  ..."
	trackRe := regexp.MustCompile(`^\s+(\d+)\.\s+(\d+)`)
	for _, line := range strings.Split(string(out), "\n") {
		if m := trackRe.FindStringSubmatch(line); len(m) > 2 {
			n, _ := strconv.ParseInt(m[2], 10, 64)
			sectors = append(sectors, n)
		}
	}
	trackCount = len(sectors)
	return
}

// ripAudio rips all tracks from a CDDA audio disc to WAV files using
// cdparanoia, streaming per-track and per-sector progress events.
func ripAudio(info disc.Info, dest string, log *logger.Logger, emit func(Event), ctx context.Context) Result {
	log.Infof("Disc type : %s", info.DiscType)
	log.Infof("Label     : %s", info.Label)
	log.Infof("Device    : %s", info.Device)
	log.Infof("Dest      : %s", dest)

	// Query TOC first for smooth sector-based progress.
	trackCount, trackSectors := queryAudioTracks(info.Device, ctx)
	var totalSectors int64
	for _, s := range trackSectors {
		totalSectors += s
	}

	startMsg := "Starting audio CD rip..."
	if trackCount > 0 {
		startMsg = fmt.Sprintf("Found %d audio tracks — starting rip...", trackCount)
	}
	emit(Event{Phase: "rip", Message: startMsg, Total: trackCount})
	log.Infof("%s", startMsg)

	if err := os.MkdirAll(dest, 0o755); err != nil {
		return Result{DestPath: dest, Error: fmt.Errorf("create dest: %w", err)}
	}

	cmd := exec.CommandContext(ctx, "cdparanoia", "-B", "-d", info.Device)
	cmd.Dir = dest
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process != nil {
			return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		}
		return nil
	}

	stderr, err := cmd.StderrPipe()
	if err != nil {
		return Result{DestPath: dest, Error: fmt.Errorf("pipe: %w", err)}
	}
	if err := cmd.Start(); err != nil {
		return Result{DestPath: dest, Error: fmt.Errorf("cdparanoia: %w", err)}
	}

	trackStartRe := regexp.MustCompile(`Ripping track\s+(\d+)(?:\s+of\s+(\d+))?`)
	// cdparanoia outputs "outputting to track04.cdda.wav" — track number is in the filename.
	outputFileRe := regexp.MustCompile(`(?i)outputting to\s+(track(\d+)\S*\.wav)`)
	// cdparanoia progress lines (via \r): "(== PROGRESS == [... | 044 00 ] ... =="
	progressRe := regexp.MustCompile(`\|\s*(\d+)\s+\d+\s*\]`)

	var (
		curTrack  int // 1-based index of track currently being ripped
		curFile   string
		curSector int64
	)

	emitTrackStart := func() {
		if curTrack == 0 {
			return
		}
		trackMsg := fmt.Sprintf("Ripping track %d", curTrack)
		if trackCount > 0 {
			trackMsg = fmt.Sprintf("Ripping track %d of %d", curTrack, trackCount)
		}
		// Current = tracks already completed (0-based), so bar fills as each track starts.
		emit(Event{
			Phase:   "rip-track",
			Message: trackMsg,
			File:    curFile,
			Current: curTrack - 1,
			Total:   trackCount,
		})
	}

	emitSectorProgress := func() {
		if curTrack == 0 {
			return
		}
		msg := fmt.Sprintf("track %d of %d", curTrack, trackCount)
		if trackCount == 0 {
			msg = fmt.Sprintf("track %d", curTrack)
		}
		if totalSectors > 0 && len(trackSectors) >= curTrack {
			trackTotal := trackSectors[curTrack-1]
			msg += fmt.Sprintf(" — sector %d/%d", curSector, trackTotal)
		}
		// Total=0 so handleBackupEvent skips overwriting the track-level bar.
		emit(Event{
			Phase:   "rip-progress",
			Message: msg,
			File:    curFile,
		})
	}

	scanner := bufio.NewScanner(stderr)
	scanner.Buffer(make([]byte, 0, 64*1024), 256*1024)
	scanner.Split(scanCRLF)

	for scanner.Scan() {
		line := scanner.Text()
		log.Infof("[cdparanoia] %s", line)

		switch {
		case outputFileRe.MatchString(line):
			// "outputting to track04.cdda.wav" — derive track number from filename.
			m := outputFileRe.FindStringSubmatch(line)
			curFile = m[1]
			curSector = 0
			if n, _ := strconv.Atoi(m[2]); n > 0 {
				curTrack = n
			}
			emitTrackStart()

		case trackStartRe.MatchString(line):
			// Fallback: "Ripping track N [of M]" when outputting-to line is absent/different.
			m := trackStartRe.FindStringSubmatch(line)
			if n, _ := strconv.Atoi(m[1]); n > 0 {
				curTrack = n
			}
			curSector = 0
			if m[2] != "" {
				if tc, _ := strconv.Atoi(m[2]); tc > 0 && trackCount == 0 {
					trackCount = tc
				}
			}
			if curFile == "" {
				emitTrackStart()
			}

		case progressRe.MatchString(line):
			m := progressRe.FindStringSubmatch(line)
			s, _ := strconv.ParseInt(m[1], 10, 64)
			curSector = s
			emitSectorProgress()
		}
	}

	if err := cmd.Wait(); err != nil {
		if ctx.Err() != nil {
			return Result{DestPath: dest, Error: ctx.Err()}
		}
		return Result{DestPath: dest, Error: fmt.Errorf("cdparanoia: %w", err)}
	}

	wavFiles, _ := filepath.Glob(filepath.Join(dest, "*.wav"))
	fileCount := len(wavFiles)

	log.Infof("Audio rip COMPLETE → %s (%d tracks)", dest, fileCount)
	emit(Event{
		Phase:   "rip-done",
		Message: fmt.Sprintf("Rip COMPLETE → %s (%d tracks)", filepath.Base(dest), fileCount),
		Current: fileCount,
		Total:   fileCount,
	})

	return Result{DestPath: dest, FileCount: fileCount, Verified: true}
}
