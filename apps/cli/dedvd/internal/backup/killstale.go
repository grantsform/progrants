package backup

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"syscall"

	"dedvd/internal/logger"
)

// KillStale finds and kills lingering rsync or dedvd backup processes from
// prior runs. It looks for rsync processes whose command line references an
// optical mount path (e.g. /run/media/*/dedvd-*). Returns the number of
// processes killed.
func KillStale(log *logger.Logger) int {
	killed := 0

	// Find rsync processes reading from optical disc mounts
	killed += killMatchingProcs("rsync", []string{"/run/media/", "dedvd-"}, log)

	// Find any lingering dedvd processes (excluding ourselves)
	killed += killMatchingProcs("dedvd", []string{"watch"}, log)

	return killed
}

// killMatchingProcs finds processes whose comm matches procName and whose
// cmdline contains ALL of the given substrings, then sends SIGTERM followed
// by SIGKILL if needed. Skips our own PID.
func killMatchingProcs(procName string, needles []string, log *logger.Logger) int {
	killed := 0
	myPID := os.Getpid()

	entries, err := filepath.Glob("/proc/[0-9]*/comm")
	if err != nil {
		return 0
	}

	for _, commPath := range entries {
		commBytes, err := os.ReadFile(commPath)
		if err != nil {
			continue
		}
		comm := strings.TrimSpace(string(commBytes))
		if comm != procName {
			continue
		}

		pidDir := filepath.Dir(commPath)
		pidStr := filepath.Base(pidDir)
		pid, err := strconv.Atoi(pidStr)
		if err != nil || pid == myPID {
			continue
		}

		cmdlineBytes, err := os.ReadFile(filepath.Join(pidDir, "cmdline"))
		if err != nil {
			continue
		}
		// /proc/PID/cmdline uses null bytes as separators
		cmdline := strings.ReplaceAll(string(cmdlineBytes), "\x00", " ")

		match := true
		for _, needle := range needles {
			if !strings.Contains(cmdline, needle) {
				match = false
				break
			}
		}
		if !match {
			continue
		}

		log.Infof("Killing stale %s process (PID %d): %s", procName, pid, strings.TrimSpace(cmdline))

		// Try graceful SIGTERM first
		proc, err := os.FindProcess(pid)
		if err != nil {
			continue
		}
		_ = proc.Signal(syscall.SIGTERM)

		// Check if it's still alive, send SIGKILL if needed
		if isAlive(pid) {
			_ = proc.Signal(syscall.SIGKILL)
		}
		killed++
	}

	return killed
}

// isAlive checks if a process is still running by sending signal 0.
func isAlive(pid int) bool {
	// Use a quick kill -0 check via /proc existence
	_, err := os.Stat(fmt.Sprintf("/proc/%d", pid))
	return err == nil
}

// KillStaleRsyncForSource kills any rsync process that references the given
// source path in its command line (more targeted than KillStale).
func KillStaleRsyncForSource(src string, log *logger.Logger) int {
	killed := 0
	myPID := os.Getpid()

	// Use pgrep for a quick targeted lookup
	out, err := exec.Command("pgrep", "-f", "rsync.*"+src).Output()
	if err != nil {
		return 0
	}

	for _, line := range strings.Split(strings.TrimSpace(string(out)), "\n") {
		pid, err := strconv.Atoi(strings.TrimSpace(line))
		if err != nil || pid == myPID {
			continue
		}

		log.Infof("Killing stale rsync for %s (PID %d)", src, pid)
		proc, err := os.FindProcess(pid)
		if err != nil {
			continue
		}
		_ = proc.Signal(syscall.SIGTERM)
		if isAlive(pid) {
			_ = proc.Signal(syscall.SIGKILL)
		}
		killed++
	}

	return killed
}
