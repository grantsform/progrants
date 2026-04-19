package backup

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"syscall"

	"dedvd/internal/disc"
	"dedvd/internal/logger"
)

// Result represents the outcome of a backup operation.
type Result struct {
	DestPath  string
	FileCount int
	Verified  bool
	Error     error
}

// Event is a structured progress update emitted during backup.
type Event struct {
	Phase   string // "scan", "copy", "copy-progress", "permissions", "verify-dst", "verify-file", "verify-done", "zip-scan", "zip-extract", "zip-file", "zip-done", "done", "error"
	Message string // human-readable description
	File    string // current file being processed (if applicable)
	Current int    // progress numerator
	Total   int    // progress denominator
	Bytes   int64  // bytes transferred / total (for copy)
	Detail  string // extra detail (hash, size, etc.)
}

// Run performs a backup of a disc.  For AUDIO discs cdparanoia is used to rip
// tracks to WAV; for DATA/VIDEO discs rsync copies the mounted filesystem.
// Progress events are sent to the events channel if non-nil.
func Run(info disc.Info, backupDir string, destName string, log *logger.Logger, events chan<- Event, ctx context.Context) Result {
	emit := func(e Event) {
		if events != nil {
			events <- e
		}
	}

	dest := filepath.Join(backupDir, string(info.DiscType), destName)

	if info.DiscType == disc.TypeAudio {
		return ripAudio(info, dest, log, emit, ctx)
	}

	log.Infof("Disc type : %s", info.DiscType)
	log.Infof("Label     : %s", info.Label)
	log.Infof("Source    : %s", info.MountPoint)
	log.Infof("Dest      : %s", dest)

	if err := os.MkdirAll(dest, 0o755); err != nil {
		return Result{DestPath: dest, Error: fmt.Errorf("create dest: %w", err)}
	}

	// Scan source files
	emit(Event{Phase: "scan", Message: "Scanning disc contents..."})
	fileList := listFiles(info.MountPoint)
	var totalBytes int64
	for _, f := range fileList {
		totalBytes += f.size
	}
	emit(Event{Phase: "scan", Message: fmt.Sprintf("Found %d files (%s)", len(fileList), humanBytes(totalBytes)), Total: len(fileList), Bytes: totalBytes})
	logFileListingFromEntries(fileList, info.MountPoint, log)

	// rsync copy
	emit(Event{Phase: "copy", Message: "Copying disc contents via rsync...", Total: len(fileList), Bytes: totalBytes})
	log.Infof("Copying contents of %s ...", info.MountPoint)
	if err := rsyncCopy(info.MountPoint, dest, log, ctx, func(pct string, xfr, _ int, curFile string) {
		total := len(fileList)
		if xfr > total {
			xfr = total
		}
		msg := fmt.Sprintf("rsync %s - %d/%d files", pct, xfr, total)
		if curFile != "" {
			msg += ", " + curFile
		}
		emit(Event{Phase: "copy-progress", Message: msg, File: curFile, Current: xfr, Total: total})
	}); err != nil {
		emit(Event{Phase: "error", Message: fmt.Sprintf("rsync failed: %v", err)})
		return Result{DestPath: dest, Error: fmt.Errorf("rsync: %w", err)}
	}
	emit(Event{Phase: "copy", Message: "Copy complete", Total: len(fileList), Current: len(fileList)})

	// Fix permissions
	emit(Event{Phase: "permissions", Message: "Fixing read-only permissions..."})
	log.Infof("Fixing permissions on %s ...", dest)
	_ = exec.Command("chmod", "-R", "u+rwX", dest).Run()

	// Verify: compare file count & sizes against source scan, then hash destination
	destFiles := listFiles(dest)
	srcByRel := make(map[string]int64, len(fileList))
	for _, f := range fileList {
		srcByRel[f.rel] = f.size
	}
	var missingFiles, sizeMismatch []string
	for _, f := range fileList {
		found := false
		for _, d := range destFiles {
			if d.rel == f.rel {
				found = true
				if d.size != f.size {
					sizeMismatch = append(sizeMismatch, fmt.Sprintf("%s: src=%d dst=%d", f.rel, f.size, d.size))
				}
				break
			}
		}
		if !found {
			missingFiles = append(missingFiles, f.rel)
		}
	}
	if len(missingFiles) > 0 || len(sizeMismatch) > 0 {
		for _, m := range missingFiles {
			log.Warnf("MISSING in dest: %s", m)
		}
		for _, m := range sizeMismatch {
			log.Warnf("SIZE MISMATCH: %s", m)
		}
		emit(Event{Phase: "error", Message: fmt.Sprintf("Verification FAILED — %d missing, %d size mismatches", len(missingFiles), len(sizeMismatch))})
		return Result{DestPath: dest, FileCount: len(fileList), Verified: false, Error: fmt.Errorf("post-copy verification failed")}
	}
	log.Infof("File count & size check PASSED — %d files match", len(fileList))

	// Hash destination only (SSD — fast) for archival checksums
	emit(Event{Phase: "verify-dst", Message: "Computing SHA-256 checksums (destination)...", Total: len(destFiles)})
	log.Info("Computing SHA-256 checksums of destination files ...")
	destSums, err := checksumTreeWithProgress(dest, func(i int, path string) {
		emit(Event{Phase: "verify-file", Message: fmt.Sprintf("Hashing %d/%d", i+1, len(destFiles)), File: path, Current: i + 1, Total: len(destFiles)})
	})
	if err != nil {
		log.Warnf("Dest checksum failed: %v", err)
		emit(Event{Phase: "error", Message: fmt.Sprintf("Dest checksum failed: %v", err)})
		return Result{DestPath: dest, Error: err}
	}

	// Write checksums to log
	log.RawWrite([]byte(fmt.Sprintf("\n--- CHECKSUMS (%s) ---\n", dest)))
	for _, e := range destSums {
		log.RawWrite([]byte(fmt.Sprintf("%s  %s\n", e.Hash, e.Path)))
	}

	log.Infof("Verification PASSED — %d files, checksums recorded.", len(destSums))
	emit(Event{Phase: "verify-done", Message: fmt.Sprintf("Verification PASSED — %d files, checksums recorded", len(destSums)), Current: len(destSums), Total: len(destSums)})

	// Extract ZIPs
	extractZipsWithEvents(dest, log, emit)

	log.Infof("Backup COMPLETE → %s", dest)
	emit(Event{Phase: "done", Message: fmt.Sprintf("Backup COMPLETE → %s (%d files)", filepath.Base(dest), len(destSums)), Current: len(destSums), Total: len(destSums)})

	return Result{DestPath: dest, FileCount: len(destSums), Verified: true}
}

func rsyncCopy(src, dest string, log *logger.Logger, ctx context.Context, progressFn func(pct string, xfr, total int, curFile string)) error {
	cmd := exec.CommandContext(ctx, "rsync",
		"--archive",
		"--recursive",
		"--info=progress2,name1",
		"--stats",
		"--human-readable",
		"--no-specials",
		"--no-devices",
		"--log-file="+log.FilePath(),
		"--", src+"/", dest+"/",
	)
	// Create a new process group so cancellation kills rsync and all children
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error {
		if cmd.Process != nil {
			return syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		}
		return nil
	}

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return err
	}
	cmd.Stderr = cmd.Stdout

	if err := cmd.Start(); err != nil {
		return err
	}

	// Parse rsync progress2 output for live updates.
	// progress2 uses \r to overwrite lines in-place, so we need a custom
	// split function that splits on both \r and \n.
	progressRe := regexp.MustCompile(`(\d+)%`)
	xfrRe := regexp.MustCompile(`xfr#(\d+),\s*to-chk=(\d+)/(\d+)`)

	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 0, 64*1024), 256*1024)
	scanner.Split(scanCRLF)
	var lastFile string
	var lastXfr, lastTotal int
	for scanner.Scan() {
		line := scanner.Text()
		log.RawWrite([]byte(line + "\n"))

		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}

		// Detect file names (lines that don't start with numbers/spaces are filenames)
		if len(trimmed) > 0 && trimmed[0] != ' ' && !strings.Contains(trimmed, "%") && !strings.HasPrefix(trimmed, "Number") && !strings.HasPrefix(trimmed, "Total") && !strings.HasPrefix(trimmed, "Literal") && !strings.HasPrefix(trimmed, "Matched") && !strings.HasPrefix(trimmed, "File list") && !strings.HasPrefix(trimmed, "sent ") && !strings.HasPrefix(trimmed, "total ") {
			lastFile = trimmed
		}

		if progressFn != nil {
			pct := ""
			if m := progressRe.FindStringSubmatch(line); len(m) > 1 {
				pct = m[1] + "%"
			}
			if m := xfrRe.FindStringSubmatch(line); len(m) > 2 {
				var xfr int
				fmt.Sscanf(m[1], "%d", &xfr)
				lastXfr = xfr
			}
			if pct != "" || lastXfr > 0 {
				progressFn(pct, lastXfr, lastTotal, lastFile)
			}
		}
	}

	return cmd.Wait()
}

// scanCRLF is a bufio.Scanner split function that tokenises on \n, \r\n, or
// bare \r (which rsync --info=progress2 uses for in-place updates).
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

type checksumEntry struct {
	Path string
	Hash string
}

func checksumTreeWithProgress(root string, onFile func(idx int, relPath string)) ([]checksumEntry, error) {
	var entries []checksumEntry
	idx := 0
	err := filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil {
			return err
		}
		if info.IsDir() {
			return nil
		}
		rel, _ := filepath.Rel(root, path)
		if onFile != nil {
			onFile(idx, rel)
		}
		h, err := sha256File(path)
		if err != nil {
			return fmt.Errorf("hash %s: %w", rel, err)
		}
		entries = append(entries, checksumEntry{Path: rel, Hash: h})
		idx++
		return nil
	})
	if err != nil {
		return nil, err
	}
	sort.Slice(entries, func(i, j int) bool { return entries[i].Path < entries[j].Path })
	return entries, nil
}

func sha256File(path string) (string, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", err
	}
	defer f.Close()
	h := sha256.New()
	if _, err := io.Copy(h, f); err != nil {
		return "", err
	}
	return hex.EncodeToString(h.Sum(nil)), nil
}

type fileEntry struct {
	rel  string
	size int64
}

func listFiles(root string) []fileEntry {
	var entries []fileEntry
	_ = filepath.Walk(root, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return nil
		}
		rel, _ := filepath.Rel(root, path)
		entries = append(entries, fileEntry{rel: rel, size: info.Size()})
		return nil
	})
	return entries
}

func logFileListingFromEntries(files []fileEntry, root string, log *logger.Logger) {
	log.Infof("Disc file listing (source: %s):", root)
	for _, f := range files {
		log.RawWrite([]byte(fmt.Sprintf("  %10d  %s\n", f.size, f.rel)))
	}
}

func extractZipsWithEvents(dest string, log *logger.Logger, emit func(Event)) {
	var zips []string
	_ = filepath.Walk(dest, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return nil
		}
		if strings.HasSuffix(strings.ToLower(path), ".zip") {
			zips = append(zips, path)
		}
		return nil
	})

	if len(zips) == 0 {
		log.Info("No ZIP files found — nothing to extract.")
		emit(Event{Phase: "zip-done", Message: "No ZIP files found"})
		return
	}

	emit(Event{Phase: "zip-scan", Message: fmt.Sprintf("Found %d ZIP archive(s)", len(zips)), Total: len(zips)})

	totalExtracted := 0
	for zi, zf := range zips {
		zipDir := filepath.Dir(zf)
		zipName := filepath.Base(zf)
		log.Infof("Extracting %s ...", zipName)
		emit(Event{Phase: "zip-extract", Message: fmt.Sprintf("Extracting %s (%d/%d)", zipName, zi+1, len(zips)), File: zipName, Current: zi + 1, Total: len(zips)})

		tmpDir, err := os.MkdirTemp("", "dedvd-zip-*")
		if err != nil {
			log.Warnf("Failed to create temp dir for %s: %v", zipName, err)
			continue
		}

		cmd := exec.Command("7z", "x", "-o"+tmpDir, "-y", zf)
		if out, err := cmd.CombinedOutput(); err != nil {
			log.Warnf("7z failed for %s, trying unzip: %v\n%s", zf, err, string(out))
			cmd2 := exec.Command("unzip", "-q", zf, "-d", tmpDir)
			if out2, err2 := cmd2.CombinedOutput(); err2 != nil {
				log.Warnf("Failed to extract %s: %v\n%s", zf, err2, string(out2))
				emit(Event{Phase: "error", Message: fmt.Sprintf("Failed to extract %s: %v", zipName, err2)})
				os.RemoveAll(tmpDir)
				continue
			}
		}

		count := 0
		_ = filepath.Walk(tmpDir, func(path string, info os.FileInfo, err error) error {
			if err != nil || info.IsDir() {
				return nil
			}
			rel, _ := filepath.Rel(tmpDir, path)
			target := filepath.Join(zipDir, rel)

			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return nil
			}

			action := "extracted"
			if _, err := os.Stat(target); os.IsNotExist(err) {
				if err := moveFile(path, target); err != nil {
					log.Warnf("Failed to move %s → %s: %v", rel, target, err)
					return nil
				}
			} else {
				srcInfo, _ := os.Stat(path)
				destInfo, _ := os.Stat(target)
				if srcInfo != nil && destInfo != nil && srcInfo.Size() == destInfo.Size() {
					if err := moveFile(path, target); err != nil {
						log.Warnf("Failed to move %s → %s: %v", rel, target, err)
						return nil
					}
					action = "overwrite"
				} else {
					ext := filepath.Ext(rel)
					base := strings.TrimSuffix(filepath.Base(rel), ext)
					altTarget := filepath.Join(filepath.Dir(target), base+"-alt"+ext)
					if err := moveFile(path, altTarget); err != nil {
						log.Warnf("Failed to move %s → %s: %v", rel, altTarget, err)
						return nil
					}
					action = "conflict→" + filepath.Base(altTarget)
				}
			}
			log.Infof("  %s: %s", action, rel)
			emit(Event{Phase: "zip-file", Message: fmt.Sprintf("%s: %s", action, rel), File: rel, Detail: action})
			count++
			return nil
		})

		os.RemoveAll(tmpDir)
		if count > 0 {
			os.Remove(zf)
			log.Infof("Removing zip: %s (%d files extracted)", zipName, count)
		} else {
			log.Warnf("ZIP extraction produced 0 files — keeping %s", zipName)
			emit(Event{Phase: "error", Message: fmt.Sprintf("Extraction produced 0 files — keeping %s", zipName)})
		}
		totalExtracted += count
	}

	log.Infof("ZIP extraction complete — %d archive(s), %d file(s) placed.", len(zips), totalExtracted)
	emit(Event{Phase: "zip-done", Message: fmt.Sprintf("ZIP extraction — %d archive(s), %d file(s)", len(zips), totalExtracted), Current: len(zips), Total: len(zips)})
}

// moveFile moves src to dst, falling back to copy+delete when os.Rename
// fails (e.g. cross-device moves from /tmp to another filesystem).
func moveFile(src, dst string) error {
	if err := os.Rename(src, dst); err == nil {
		return nil
	}
	// Fallback: copy then remove
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()

	out, err := os.Create(dst)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		os.Remove(dst)
		return err
	}
	if err := out.Close(); err != nil {
		os.Remove(dst)
		return err
	}
	return os.Remove(src)
}

func humanBytes(b int64) string {
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
