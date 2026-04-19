package disc

import (
	"bufio"
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"

	"dedvd/internal/logger"
)

// Type represents the detected disc content type.
type Type string

const (
	TypeVideo Type = "VIDEO"
	TypeData  Type = "DATA"
	TypeAudio Type = "AUDIO"
)

// Info holds detected disc metadata.
type Info struct {
	MountPoint string
	Device     string
	Label      string
	DiscType   Type
	Timestamp  string
}

// DestName returns the backup directory name: LABEL_TIMESTAMP.
func (d Info) DestName() string {
	return d.Label + "_" + d.Timestamp
}

// FindOpticalMount detects a mounted optical disc.
func FindOpticalMount() (string, error) {
	// Try iso9660/udf via findmnt
	out, err := exec.Command("findmnt", "-n", "-o", "TARGET", "--list", "-t", "iso9660,udf").Output()
	if err == nil {
		mp := firstLine(string(out))
		if mp != "" {
			return mp, nil
		}
	}

	// Check /dev/sr* devices
	matches, _ := filepath.Glob("/dev/sr*")
	for _, dev := range matches {
		info, err := os.Stat(dev)
		if err != nil || info.Mode()&os.ModeDevice == 0 {
			continue
		}
		out, err := exec.Command("findmnt", "-n", "-o", "TARGET", "--list", "-S", dev).Output()
		if err == nil {
			mp := firstLine(string(out))
			if mp != "" {
				return mp, nil
			}
		}
	}

	// Check /run/media
	entries, err := os.ReadDir("/run/media")
	if err == nil {
		for _, userDir := range entries {
			userPath := filepath.Join("/run/media", userDir.Name())
			subEntries, err := os.ReadDir(userPath)
			if err != nil {
				continue
			}
			for _, sub := range subEntries {
				mp := filepath.Join(userPath, sub.Name())
				if err := exec.Command("findmnt", "-n", "-o", "TARGET", mp).Run(); err == nil {
					return mp, nil
				}
			}
		}
	}

	return "", nil
}

// IsAudioCD reports whether dev contains a CDDA audio disc.
// It first queries the udevadm property database (fast, no I/O).  If udevadm
// reports media is present but doesn't flag it as CD_DA, it falls back to
// cdparanoia --query, which reads the TOC directly and exits 0 only for
// audio CDs.
func IsAudioCD(dev string) bool {
	// udevadm info --name= correctly resolves /dev/srN device nodes.
	out, err := exec.Command("udevadm", "info", "--query=property", "--name", dev).Output()
	if err == nil {
		hasMedia := false
		for _, line := range strings.Split(string(out), "\n") {
			line = strings.TrimSpace(line)
			switch {
			case line == "ID_CDROM_MEDIA=1":
				hasMedia = true
			case line == "ID_CDROM_MEDIA_CD_DA=1":
				return true
			case strings.HasPrefix(line, "ID_CDROM_MEDIA_TRACK_COUNT_AUDIO="):
				v := strings.TrimPrefix(line, "ID_CDROM_MEDIA_TRACK_COUNT_AUDIO=")
				if v != "" && v != "0" {
					return true
				}
			}
		}
		// udevadm ran successfully; if it reported no media, trust it.
		if !hasMedia {
			return false
		}
		// Media is present but not flagged CD_DA — fall through to cdparanoia.
	}

	// Fallback: ask cdparanoia to read the TOC with a short timeout.
	// It exits 0 only when audio tracks are found.
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	return exec.CommandContext(ctx, "cdparanoia", "-Q", "-d", dev).Run() == nil
}

// GetAudioInfo returns disc Info for a CDDA audio disc (no mount point).
func GetAudioInfo(dev string) Info {
	ts := time.Now().Format("20060102_150405")
	label := audioLabel(dev)
	return Info{
		Device:     dev,
		MountPoint: "",
		Label:      label,
		DiscType:   TypeAudio,
		Timestamp:  ts,
	}
}

// audioLabel tries to read a CD-TEXT label via udevadm; falls back to
// "AUDIO_DISC".
func audioLabel(dev string) string {
	out, err := exec.Command("udevadm", "info", "--query=property", "--name", dev).Output()
	if err == nil {
		for _, line := range strings.Split(string(out), "\n") {
			if strings.HasPrefix(line, "ID_FS_LABEL=") {
				if label := sanitizeLabel(strings.TrimPrefix(line, "ID_FS_LABEL=")); label != "" {
					return label
				}
			}
		}
	}
	return "AUDIO_DISC"
}

// DetectType determines if a mounted disc is VIDEO or DATA.
func DetectType(mountpoint string) Type {
	for _, name := range []string{"VIDEO_TS", "video_ts", "BDMV", "bdmv"} {
		info, err := os.Stat(filepath.Join(mountpoint, name))
		if err == nil && info.IsDir() {
			return TypeVideo
		}
	}
	return TypeData
}

// GetLabel extracts the disc label via blkid, sanitized.
func GetLabel(mountpoint string) string {
	devOut, err := exec.Command("findmnt", "-n", "-o", "SOURCE", mountpoint).Output()
	if err != nil {
		return "DISC_" + time.Now().Format("20060102_150405")
	}
	dev := firstLine(string(devOut))
	if dev == "" {
		return "DISC_" + time.Now().Format("20060102_150405")
	}

	labelOut, _ := exec.Command("blkid", "-o", "value", "-s", "LABEL", dev).Output()
	label := sanitizeLabel(firstLine(string(labelOut)))
	if label == "" {
		label = "DISC"
	}
	return label
}

// GetLabelForDevice extracts the disc label directly from a block device.
func GetLabelForDevice(dev string) (string, error) {
	out, err := exec.Command("blkid", "-o", "value", "-s", "LABEL", dev).Output()
	if err != nil {
		return "", err
	}
	label := sanitizeLabel(firstLine(string(out)))
	return label, nil
}

// GetInfo returns full disc information for a mountpoint.
func GetInfo(mountpoint string) Info {
	ts := time.Now().Format("20060102_150405")
	label := GetLabel(mountpoint)

	devOut, _ := exec.Command("findmnt", "-n", "-o", "SOURCE", mountpoint).Output()
	dev := firstLine(string(devOut))

	return Info{
		MountPoint: mountpoint,
		Device:     dev,
		Label:      label,
		DiscType:   DetectType(mountpoint),
		Timestamp:  ts,
	}
}

// TryMount attempts to mount the given block device, returning the mountpoint.
func TryMount(dev string, log *logger.Logger) (string, error) {
	// Check if already mounted
	out, err := exec.Command("findmnt", "-n", "-o", "TARGET", "--list", "-S", dev).Output()
	if err == nil {
		mp := firstLine(string(out))
		if mp != "" {
			return mp, nil
		}
	}

	// Wait for the drive to become ready (udev fires before media is readable)
	for i := 0; i < 10; i++ {
		if exec.Command("blkid", dev).Run() == nil {
			break
		}
		time.Sleep(500 * time.Millisecond)
	}

	// Prefer udisksctl (works without root, integrates with KDE/desktop)
	if _, err := exec.LookPath("udisksctl"); err == nil {
		log.Infof("Auto-mounting %s via udisksctl ...", dev)
		out, _ := exec.Command("udisksctl", "mount",
			"--block-device", dev, "--options", "ro", "--no-user-interaction").CombinedOutput()
		re := regexp.MustCompile(`at (.+?)\.?\s*$`)
		if m := re.FindSubmatch(out); len(m) > 1 {
			mp := strings.TrimSpace(string(m[1]))
			if info, err := os.Stat(mp); err == nil && info.IsDir() {
				log.Infof("Mounted %s at %s (udisksctl)", dev, mp)
				return mp, nil
			}
		}
	}

	// Fallback: sudo mount
	if exec.Command("sudo", "-n", "true").Run() == nil {
		devName := filepath.Base(dev)
		user := os.Getenv("USER")
		mnt := filepath.Join("/run/media", user, "dedvd-"+devName)
		log.Infof("Auto-mounting %s at %s via sudo mount ...", dev, mnt)
		_ = exec.Command("sudo", "mkdir", "-p", mnt).Run()
		if err := exec.Command("sudo", "mount", "-t", "auto", "-o", "ro", dev, mnt).Run(); err == nil {
			log.Infof("Mounted %s at %s (sudo mount)", dev, mnt)
			return mnt, nil
		}
		_ = exec.Command("sudo", "rmdir", mnt).Run()
	}

	return "", fmt.Errorf("could not mount %s", dev)
}

// HasMedia checks if a block device has readable media via blkid.
func HasMedia(dev string) bool {
	return exec.Command("blkid", dev).Run() == nil
}

// Unmount unmounts a block device. Tries udisksctl first, then sudo umount.
func Unmount(dev string) error {
	// Try udisksctl
	if _, err := exec.LookPath("udisksctl"); err == nil {
		if err := exec.Command("udisksctl", "unmount", "--block-device", dev, "--no-user-interaction").Run(); err == nil {
			return nil
		}
	}
	// Fallback: sudo umount
	if exec.Command("sudo", "-n", "true").Run() == nil {
		out, err := exec.Command("findmnt", "-n", "-o", "TARGET", "--list", "-S", dev).Output()
		if err == nil {
			mp := firstLine(string(out))
			if mp != "" {
				if err := exec.Command("sudo", "umount", mp).Run(); err == nil {
					return nil
				}
			}
		}
	}
	return fmt.Errorf("could not unmount %s", dev)
}

// Eject unmounts and ejects the disc from the given device.
func Eject(dev string) error {
	_ = Unmount(dev)
	if err := exec.Command("eject", dev).Run(); err != nil {
		return fmt.Errorf("eject %s: %w", dev, err)
	}
	return nil
}

// WatchUdev returns a channel that emits optical drive events.
// Each event is the device path (e.g. /dev/sr0). Close done to stop.
func WatchUdev(done <-chan struct{}) (<-chan string, error) {
	if _, err := exec.LookPath("udevadm"); err != nil {
		return nil, fmt.Errorf("udevadm not found")
	}

	ch := make(chan string, 8)
	cmd := exec.Command("udevadm", "monitor", "--udev", "--subsystem-match=block")
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return nil, err
	}
	if err := cmd.Start(); err != nil {
		return nil, err
	}

	re := regexp.MustCompile(`(change|add).*block.*(sr[0-9]+)`)

	go func() {
		defer close(ch)
		defer cmd.Process.Kill()
		scanner := bufio.NewScanner(stdout)
		for scanner.Scan() {
			select {
			case <-done:
				return
			default:
			}
			line := scanner.Text()
			if m := re.FindStringSubmatch(line); len(m) > 2 {
				ch <- "/dev/" + m[2]
			}
		}
	}()

	return ch, nil
}

// ListOpticalDevices returns all /dev/sr* block devices.
func ListOpticalDevices() []string {
	matches, _ := filepath.Glob("/dev/sr*")
	var devs []string
	for _, m := range matches {
		info, err := os.Stat(m)
		if err == nil && (info.Mode()&os.ModeDevice != 0) {
			devs = append(devs, m)
		}
	}
	return devs
}

func firstLine(s string) string {
	s = strings.TrimSpace(s)
	if i := strings.IndexByte(s, '\n'); i >= 0 {
		return s[:i]
	}
	return s
}

func sanitizeLabel(s string) string {
	s = strings.TrimSpace(s)
	var b strings.Builder
	for i, r := range s {
		if i >= 40 {
			break
		}
		if (r >= 'A' && r <= 'Z') || (r >= 'a' && r <= 'z') || (r >= '0' && r <= '9') || r == '_' || r == '-' {
			b.WriteRune(r)
		}
	}
	return b.String()
}
