package upload

import (
	"bufio"
	"context"
	"fmt"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"syscall"

	"dedvd/internal/logger"
)

// Target holds the parsed user@host:/path destination.
type Target struct {
	User     string
	Host     string
	Path     string
	Password string // set at runtime via prompt; never from flags
}

// ParseTarget parses "user@host:/path" into a Target.
func ParseTarget(s string) (Target, error) {
	// Expected format: USER@HOST:/remote/path
	at := strings.Index(s, "@")
	if at < 1 {
		return Target{}, fmt.Errorf("invalid target %q — expected USER@HOST:/path", s)
	}
	rest := s[at+1:]
	colon := strings.Index(rest, ":")
	if colon < 1 {
		return Target{}, fmt.Errorf("invalid target %q — expected USER@HOST:/path", s)
	}
	return Target{
		User: s[:at],
		Host: rest[:colon],
		Path: rest[colon+1:],
	}, nil
}

func (t Target) String() string {
	return fmt.Sprintf("%s@%s:%s", t.User, t.Host, t.Path)
}

// Event is a structured progress update emitted during upload.
type Event struct {
	Phase   string // "scan", "item-start", "item-progress", "item-done", "item-skip", "item-fail", "done"
	Message string
	Name    string
	File    string // current file being transferred by rsync
	Percent int
	Current int
	Total   int
}

// ItemStatus represents the result of uploading a single item.
type ItemStatus struct {
	Name     string
	Category string // "DATA", "VIDEO", or "AUDIO"
	Skipped  bool
	Failed   bool
	Error    string
}

// Summary holds the results of an upload run.
type Summary struct {
	Items    []ItemStatus
	Uploaded int
	Failed   int
	Skipped  int
}

// Run uploads the entire backupDir to the remote host via rsync over SSH.
// Progress events are sent to events channel if non-nil.
func Run(backupDir string, target Target, log *logger.Logger, events chan<- Event, ctx context.Context) Summary {
	emit := func(e Event) {
		if events != nil {
			events <- e
		}
	}

	var summary Summary
	name := filepath.Base(backupDir)

	emit(Event{Phase: "scan", Message: "Uploading " + backupDir, Total: 1})
	emit(Event{Phase: "item-start", Name: name, Current: 1, Total: 1,
		Message: "Uploading " + backupDir})

	var currentFile string
	status := rsyncPush(backupDir+"/", target.Path+"/", name, "", true, target, log, ctx,
		func(pct int) {
			emit(Event{Phase: "item-progress", Name: name, File: currentFile, Percent: pct, Current: 1, Total: 1,
				Message: fmt.Sprintf("rsync %d%%", pct)})
		},
		func(file string) {
			currentFile = file
			emit(Event{Phase: "item-progress", Name: name, File: file, Percent: 0, Current: 1, Total: 1,
				Message: "rsync " + file})
		},
	)

	summary.Items = append(summary.Items, status)
	if status.Failed {
		summary.Failed++
		emit(Event{Phase: "item-fail", Name: name, Current: 1, Total: 1,
			Message: "FAILED: " + status.Error})
	} else if status.Skipped {
		summary.Skipped++
		emit(Event{Phase: "item-skip", Name: name, Current: 1, Total: 1,
			Message: "skip (up to date)"})
	} else {
		summary.Uploaded++
		emit(Event{Phase: "item-done", Name: name, Current: 1, Total: 1,
			Message: "✓ " + name})
	}

	log.Infof("Upload complete — %d uploaded, %d failed, %d skipped.",
		summary.Uploaded, summary.Failed, summary.Skipped)
	emit(Event{Phase: "done", Message: fmt.Sprintf("Upload complete — %d uploaded, %d failed, %d skipped",
		summary.Uploaded, summary.Failed, summary.Skipped), Total: 1})
	return summary
}

var pctRe = regexp.MustCompile(`(\d+)%`)

func rsyncPush(src, dest, name, category string, isDir bool, target Target, log *logger.Logger, ctx context.Context, onProgress func(int), onFile func(string)) ItemStatus {
	log.Infof("upload: rsync %s/%s → %s:%s", category, name, target.Host, dest)

	remoteDest := fmt.Sprintf("%s@%s:%s", target.User, target.Host, dest)

	// Ensure remote directory exists
	remoteDir := dest
	if !isDir {
		remoteDir = filepath.Dir(dest)
	}
	mkdirArgs := []string{
		"ssh", "-o", "StrictHostKeyChecking=no",
		fmt.Sprintf("%s@%s", target.User, target.Host),
		"mkdir", "-p", remoteDir,
	}
	rsyncArgs := []string{
		"rsync", "--archive", "--compress", "--partial",
		"--ignore-existing",
		"-v", "--info=progress2",
		"-e", "ssh -o StrictHostKeyChecking=no",
		src, remoteDest,
	}

	// If password is set, use sshpass
	var mkdirCmd, rsyncCmd *exec.Cmd
	if target.Password != "" {
		mkdirCmd = exec.CommandContext(ctx, "sshpass", append([]string{"-p", target.Password}, mkdirArgs...)...)
		rsyncCmd = exec.CommandContext(ctx, "sshpass", append([]string{"-p", target.Password}, rsyncArgs...)...)
	} else {
		mkdirCmd = exec.CommandContext(ctx, mkdirArgs[0], mkdirArgs[1:]...)
		rsyncCmd = exec.CommandContext(ctx, rsyncArgs[0], rsyncArgs[1:]...)
	}
	// Kill entire process group on cancel
	rsyncCmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	rsyncCmd.Cancel = func() error {
		if rsyncCmd.Process != nil {
			return syscall.Kill(-rsyncCmd.Process.Pid, syscall.SIGKILL)
		}
		return nil
	}

	status := ItemStatus{Name: name, Category: category}

	// Create remote directory
	if out, err := mkdirCmd.CombinedOutput(); err != nil {
		status.Failed = true
		status.Error = fmt.Sprintf("mkdir remote: %v — %s", err, strings.TrimSpace(string(out)))
		log.Errorf("upload FAILED mkdir: %s/%s — %v", category, name, err)
		return status
	}

	// Run rsync with progress parsing
	stdout, err := rsyncCmd.StdoutPipe()
	if err != nil {
		status.Failed = true
		status.Error = fmt.Sprintf("pipe: %v", err)
		return status
	}
	rsyncCmd.Stderr = rsyncCmd.Stdout

	if err := rsyncCmd.Start(); err != nil {
		status.Failed = true
		status.Error = fmt.Sprintf("start rsync: %v", err)
		log.Errorf("upload FAILED: %s/%s — %v", category, name, err)
		return status
	}

	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 0, 64*1024), 256*1024)
	scanner.Split(scanCRLF)
	transferred := false
	lastPct := -1
	lastFile := ""

	for scanner.Scan() {
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)
		if trimmed == "" {
			continue
		}

		if m := pctRe.FindStringSubmatch(trimmed); len(m) > 1 {
			var pct int
			fmt.Sscanf(m[1], "%d", &pct)
			if pct != lastPct {
				lastPct = pct
				if onProgress != nil {
					onProgress(pct)
				}
			}
			if pct > 0 {
				transferred = true
			}
		} else if !strings.HasPrefix(trimmed, "sent ") && !strings.HasPrefix(trimmed, "total size") {
			// Non-progress, non-summary line = filename being transferred
			if trimmed != lastFile {
				lastFile = trimmed
				if onFile != nil {
					onFile(trimmed)
				}
			}
		}
	}

	if err := rsyncCmd.Wait(); err != nil {
		status.Failed = true
		status.Error = fmt.Sprintf("rsync: %v", err)
		log.Errorf("upload FAILED: %s/%s — %v", category, name, err)
		return status
	}

	if !transferred {
		status.Skipped = true
	} else {
		log.Infof("upload: %s/%s → %s", category, name, remoteDest)
	}
	return status
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
