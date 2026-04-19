package tui

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"dedvd/internal/backup"
	"dedvd/internal/config"
	"dedvd/internal/disc"
	"dedvd/internal/logger"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ── Styles ──────────────────────────────────────────────────────────────────

var (
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("12")).
			BorderStyle(lipgloss.RoundedBorder()).
			Padding(0, 1)

	statusStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("10"))

	dimStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("8"))

	warnStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("11"))

	errStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("9"))

	successStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("10")).Bold(true)

	labelStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("14"))

	boxStyle = lipgloss.NewStyle().
			BorderStyle(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("8")).
			Padding(0, 1)

	phaseStyle = lipgloss.NewStyle().
			Bold(true).
			Foreground(lipgloss.Color("13"))

	fileStyle = lipgloss.NewStyle().
			Foreground(lipgloss.Color("6"))

	progressBarFull = lipgloss.NewStyle().
			Foreground(lipgloss.Color("10"))

	progressBarEmpty = lipgloss.NewStyle().
				Foreground(lipgloss.Color("8"))

	vpBorderStyle = lipgloss.NewStyle().
			BorderStyle(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("8"))

	vpFlashSuccess = lipgloss.NewStyle().
			BorderStyle(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("10")).
			Bold(true)

	vpFlashError = lipgloss.NewStyle().
			BorderStyle(lipgloss.RoundedBorder()).
			BorderForeground(lipgloss.Color("9")).
			Bold(true)
)

// ── Messages ────────────────────────────────────────────────────────────────

// flashResetMsg is shared across all TUI models to revert the viewport border.
type flashResetMsg struct{}

// flashCmd sets the viewport border to a flash style and returns a Cmd that
// reverts it after 1.5 s.
func flashCmd(vp *viewport.Model, width int, style lipgloss.Style) tea.Cmd {
	if width > 0 {
		vp.Style = style.Width(width)
	} else {
		vp.Style = style
	}
	return tea.Tick(1500*time.Millisecond, func(time.Time) tea.Msg { return flashResetMsg{} })
}

type discDetectedMsg struct{ info disc.Info }
type discEjectedMsg struct{ dev string }
type backupDoneMsg struct{ result backup.Result }
type backupEventMsg struct{ event backup.Event }
type renameDoneMsg struct {
	oldName, newName string
	err              error
}
type pollTickMsg struct{}
type udevEventMsg struct{ dev string }
type watchErrorMsg struct{ err error }
type staleKilledMsg struct{ count int }
type mountFailedMsg struct {
	dev string
	err error
}
type ejectDoneMsg struct{ err error }

// ── Watch Model ─────────────────────────────────────────────────────────────

type WatchModel struct {
	cfg     config.Config
	log     *logger.Logger
	spinner spinner.Model
	vp      viewport.Model
	input   textinput.Model
	useUdev bool
	done    chan struct{}
	eventCh chan backup.Event
	ready   bool
	width   int
	height  int

	// State
	state       string // "waiting", "naming", "backing-up", "renaming", "mount-failed", "error"
	discInfo    *disc.Info
	backupDone  map[string]bool
	pendingInfo *disc.Info // disc awaiting name confirmation
	failedDev   string     // device that failed to mount

	// Activity log — rendered in viewport
	activities []activity

	// Current phase tracking
	curPhase    string
	curFile     string
	curProgress int
	curTotal    int
	curMessage  string

	// History of completed backups
	backupCount  int
	lastDestPath string // path of last completed backup (for rename)
	err          error

	// Quit confirmation
	confirmQuit bool

	// Process cancellation
	cancel context.CancelFunc
}

type activity struct {
	ts    string
	icon  string
	text  string
	style lipgloss.Style
}

func NewWatchModel(cfg config.Config, log *logger.Logger, useUdev bool) WatchModel {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("12"))

	vp := viewport.New(80, 16)
	vp.Style = vpBorderStyle

	ti := textinput.New()
	ti.Placeholder = "new name"
	ti.Width = 50
	ti.CharLimit = 200

	return WatchModel{
		cfg:        cfg,
		log:        log,
		spinner:    s,
		vp:         vp,
		input:      ti,
		useUdev:    useUdev,
		done:       make(chan struct{}),
		eventCh:    make(chan backup.Event, 64),
		state:      "waiting",
		backupDone: make(map[string]bool),
		activities: []activity{},
	}
}

func (m WatchModel) Init() tea.Cmd {
	cmds := []tea.Cmd{m.spinner.Tick, m.killStaleCmd()}
	if m.useUdev {
		cmds = append(cmds, m.watchUdevCmd())
	} else {
		cmds = append(cmds, m.pollTickCmd())
	}
	cmds = append(cmds, m.checkExistingCmd())
	return tea.Batch(cmds...)
}

func (m WatchModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		headerHeight := 10 // title + status + disc box + padding
		footerHeight := 3  // controls
		vpHeight := m.height - headerHeight - footerHeight
		if vpHeight < 4 {
			vpHeight = 4
		}
		vpWidth := m.width - 4
		if vpWidth < 40 {
			vpWidth = 40
		}
		m.vp.Width = vpWidth
		m.vp.Height = vpHeight
		m.vp.Style = vpBorderStyle.Width(vpWidth)
		m.ready = true
		m.syncViewport()

	case tea.KeyMsg:
		// Handle quit confirmation first
		if m.confirmQuit {
			switch msg.String() {
			case "y", "Y":
				if m.cancel != nil {
					m.cancel()
				}
				close(m.done)
				return m, tea.Quit
			case "n", "N", "esc":
				m.confirmQuit = false
				return m, nil
			}
			return m, nil
		}

		switch msg.String() {
		case "ctrl+c":
			if m.cancel != nil {
				m.cancel()
			}
			close(m.done)
			return m, tea.Quit
		case "q":
			if m.state != "naming" && m.state != "renaming" {
				m.confirmQuit = true
				return m, nil
			}
		case "m":
			if m.state == "mount-failed" && m.failedDev != "" {
				dev := m.failedDev
				m.failedDev = ""
				m.addActivity("🔄", "Retrying mount for "+filepath.Base(dev)+"...", labelStyle)
				m.state = "waiting"
				m.syncViewport()
				cmds = append(cmds, m.mountAndBackupCmd(dev))
				return m, tea.Batch(cmds...)
			}
		case "e":
			if m.state == "waiting" && m.discInfo != nil && m.backupDone[m.discInfo.Device] {
				dev := m.discInfo.Device
				m.addActivity("⏏", "Ejecting "+filepath.Base(dev)+"...", dimStyle)
				m.syncViewport()
				cmds = append(cmds, m.ejectCmd(dev))
				return m, tea.Batch(cmds...)
			}
		case "r":
			if m.state == "waiting" && m.lastDestPath != "" {
				m.state = "renaming"
				m.input.SetValue(filepath.Base(m.lastDestPath))
				m.input.Focus()
				m.input.CursorEnd()
				return m, m.input.Focus()
			}
		case "enter":
			if m.state == "naming" && m.pendingInfo != nil {
				customName := strings.TrimSpace(m.input.Value())
				if customName == "" {
					customName = m.pendingInfo.DestName()
				}
				info := *m.pendingInfo
				m.pendingInfo = nil
				m.state = "backing-up"
				m.curPhase = "init"
				m.curMessage = "Starting backup..."
				m.addActivity("📝", fmt.Sprintf("Backup name: %s", customName), labelStyle)
				m.syncViewport()
				cmds = append(cmds, m.runBackupCmdWithName(info, customName), m.waitForEventCmd())
				return m, tea.Batch(cmds...)
			}
			if m.state == "renaming" {
				newName := strings.TrimSpace(m.input.Value())
				if newName != "" && newName != filepath.Base(m.lastDestPath) {
					cmds = append(cmds, m.renameCmd(m.lastDestPath, newName))
				} else {
					// No change — go back to waiting
					m.state = "waiting"
				}
				return m, tea.Batch(cmds...)
			}
		case "esc":
			if m.state == "naming" && m.pendingInfo != nil {
				// Esc during naming = use default name, start backup
				info := *m.pendingInfo
				customName := info.DestName()
				m.pendingInfo = nil
				m.state = "backing-up"
				m.curPhase = "init"
				m.curMessage = "Starting backup..."
				m.addActivity("📝", fmt.Sprintf("Backup name: %s", customName), labelStyle)
				m.syncViewport()
				cmds = append(cmds, m.runBackupCmdWithName(info, customName), m.waitForEventCmd())
				return m, tea.Batch(cmds...)
			}
			if m.state == "renaming" {
				m.state = "waiting"
				return m, nil
			}
		}

		if m.state == "naming" || m.state == "renaming" {
			var cmd tea.Cmd
			m.input, cmd = m.input.Update(msg)
			cmds = append(cmds, cmd)
		} else {
			// Pass navigation keys to viewport
			var cmd tea.Cmd
			m.vp, cmd = m.vp.Update(msg)
			cmds = append(cmds, cmd)
		}

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		cmds = append(cmds, cmd)
		if m.state == "backing-up" || m.state == "naming" {
			m.syncViewport()
		}

	case pollTickMsg:
		if m.state == "waiting" || m.state == "renaming" {
			cmds = append(cmds, m.checkExistingCmd())
		}
		cmds = append(cmds, m.pollTickCmd())

	case udevEventMsg:
		if msg.dev != "" {
			if m.state == "mount-failed" {
				m.state = "waiting"
				m.failedDev = ""
			}
			cmds = append(cmds, m.mountAndBackupCmd(msg.dev))
		}
		cmds = append(cmds, m.watchUdevCmd())

	case discDetectedMsg:
		// If renaming, abandon rename and use original name
		if m.state == "renaming" {
			m.addActivity("ℹ", "New disc detected — rename abandoned", warnStyle)
			m.state = "waiting"
		}
		// Guard: only accept from waiting state
		if m.state != "waiting" {
			return m, tea.Batch(cmds...)
		}
		m.clearProgress()
		m.backupDone = make(map[string]bool)
		info := msg.info
		m.pendingInfo = &info
		m.discInfo = &info
		m.state = "naming"
		m.log.Infof("Disc detected: %s (%s)", msg.info.Label, msg.info.DiscType)
		m.addActivity("💿", fmt.Sprintf("Disc detected: %s (%s) at %s",
			msg.info.Label, msg.info.DiscType, msg.info.MountPoint), labelStyle)
		m.input.SetValue(info.DestName())
		m.input.Focus()
		m.input.CursorEnd()
		m.syncViewport()
		return m, m.input.Focus()

	case backupEventMsg:
		m.handleBackupEvent(msg.event)
		m.syncViewport()
		// Keep listening for more events
		if m.state == "backing-up" {
			cmds = append(cmds, m.waitForEventCmd())
		}

	case backupDoneMsg:
		if msg.result.Error != nil {
			m.state = "error"
			m.err = msg.result.Error
			m.addActivity("✗", fmt.Sprintf("Backup FAILED: %v", msg.result.Error), errStyle)
			cmds = append(cmds, flashCmd(&m.vp, m.vp.Width, vpFlashError))
		} else {
			m.backupCount++
			m.lastDestPath = msg.result.DestPath
			m.addActivity("✓", fmt.Sprintf("Backup #%d COMPLETE → %s (%d files, verified)",
				m.backupCount, filepath.Base(msg.result.DestPath), msg.result.FileCount), successStyle)
			hints := "r rename"
			if m.discInfo != nil && m.discInfo.Device != "" {
				hints += " • e eject"
			}
			m.addActivity("ℹ", hints+" • "+filepath.Base(msg.result.DestPath), labelStyle)
			// Go straight back to waiting — rename/eject available until next disc
			m.state = "waiting"
			cmds = append(cmds, flashCmd(&m.vp, m.vp.Width, vpFlashSuccess))
		}
		if m.discInfo != nil {
			m.backupDone[m.discInfo.Device] = true
		}
		m.curPhase = "done"
		m.curMessage = ""
		m.syncViewport()

	case renameDoneMsg:
		if msg.err != nil {
			m.addActivity("✗", fmt.Sprintf("Rename failed: %v", msg.err), errStyle)
		} else {
			m.addActivity("✓", fmt.Sprintf("Renamed: %s → %s", msg.oldName, msg.newName), successStyle)
			m.log.Infof("Renamed %s → %s", msg.oldName, msg.newName)
		}
		m.clearProgress()
		m.backupDone = make(map[string]bool)
		m.state = "waiting"
		m.syncViewport()

	case discEjectedMsg:
		if m.backupDone[msg.dev] {
			m.backupDone[msg.dev] = false
			m.addActivity("⏏", "Disc ejected from "+filepath.Base(msg.dev)+" — ready for next disc.", dimStyle)
			m.state = "waiting"
			m.syncViewport()
		}

	case watchErrorMsg:
		m.err = msg.err
		m.addActivity("⚠", "Error: "+msg.err.Error(), errStyle)
		m.syncViewport()

	case mountFailedMsg:
		m.failedDev = msg.dev
		m.state = "mount-failed"
		m.addActivity("⚠", fmt.Sprintf("Mount failed: %v", msg.err), errStyle)
		m.addActivity("ℹ", "Press m to retry mount for "+filepath.Base(msg.dev), labelStyle)
		m.syncViewport()

	case ejectDoneMsg:
		if msg.err != nil {
			m.addActivity("⚠", fmt.Sprintf("Eject failed: %v", msg.err), errStyle)
		} else {
			m.addActivity("⏏", "Disc ejected — ready for next disc.", dimStyle)
			m.discInfo = nil
			m.backupDone = make(map[string]bool)
		}
		m.syncViewport()

	case staleKilledMsg:
		if msg.count > 0 {
			m.addActivity("🧹", fmt.Sprintf("Killed %d stale process(es)", msg.count), warnStyle)
			m.syncViewport()
		}

	case flashResetMsg:
		if m.width > 0 {
			m.vp.Style = vpBorderStyle.Width(m.vp.Width)
		} else {
			m.vp.Style = vpBorderStyle
		}
	}

	return m, tea.Batch(cmds...)
}

func (m *WatchModel) handleBackupEvent(ev backup.Event) {
	m.curPhase = ev.Phase
	m.curMessage = ev.Message
	// Only update the progress counters when the event carries meaningful totals
	// so that activity-log-only events (e.g. rip-track) don't reset the bar.
	if ev.Total > 0 {
		m.curProgress = ev.Current
		m.curTotal = ev.Total
	}
	if ev.File != "" {
		m.curFile = ev.File
	}

	switch ev.Phase {
	case "scan":
		m.addActivity("🔍", ev.Message, labelStyle)
	case "copy":
		m.addActivity("📋", ev.Message, statusStyle)
	case "copy-progress":
		// Don't flood activity log — just update the live status
	case "permissions":
		m.addActivity("🔑", ev.Message, dimStyle)
	case "verify-dst":
		m.addActivity("🔒", "Verifying checksums...", labelStyle)
	case "verify-file":
		// Live status only
	case "verify-done":
		m.addActivity("✓", ev.Message, successStyle)
	case "zip-scan":
		m.addActivity("📦", ev.Message, labelStyle)
	case "zip-extract":
		m.addActivity("📦", ev.Message, warnStyle)
	case "zip-file":
		m.addActivity("  ", fmt.Sprintf("%s: %s", ev.Detail, ev.File), fileStyle)
	case "zip-done":
		m.addActivity("✓", ev.Message, successStyle)
	case "rip":
		m.addActivity("🎵", ev.Message, labelStyle)
	case "rip-track":
		m.addActivity("🎶", ev.Message, statusStyle)
	case "rip-progress":
		// Live status only — don't flood the activity log.
	case "rip-done":
		m.addActivity("✓", ev.Message, successStyle)
	case "error":
		m.addActivity("✗", ev.Message, errStyle)
	case "done":
		m.addActivity("✓", ev.Message, successStyle)
	}
}

func (m WatchModel) View() string {
	if !m.ready {
		return "Initializing..."
	}

	var b strings.Builder

	// ── Title bar ────────────────────────────────────────────────────────
	mode := "poll"
	if m.useUdev {
		mode = "udev"
	}
	title := titleStyle.Render(fmt.Sprintf("dedvd watch (%s)", mode))
	backupDir := dimStyle.Render("→ " + m.cfg.BackupDir)
	b.WriteString(title + "  " + backupDir + "\n")

	// ── Status + disc info ───────────────────────────────────────────────
	switch m.state {
	case "waiting":
		b.WriteString(m.spinner.View() + " Waiting for disc insertion...")
		if m.backupCount > 0 {
			b.WriteString(dimStyle.Render(fmt.Sprintf("  (%d backup(s) completed)", m.backupCount)))
		}
		if m.lastDestPath != "" {
			b.WriteString("\n" + dimStyle.Render("  r to rename "+filepath.Base(m.lastDestPath)))
		}
		b.WriteString("\n")
	case "naming":
		b.WriteString(labelStyle.Render("  Name: ") + m.input.View() + "\n")
		b.WriteString(dimStyle.Render("  Enter to start backup • Esc to use default") + "\n")
	case "backing-up":
		b.WriteString(m.spinner.View() + " " + phaseStyle.Render(phaseLabel(m.curPhase)))
		if m.curMessage != "" {
			b.WriteString("  " + m.curMessage)
		}
		b.WriteString("\n")
	case "renaming":
		b.WriteString(labelStyle.Render("  Rename to: ") + m.input.View() + "\n")
		b.WriteString(dimStyle.Render("  Enter to confirm • Esc to cancel") + "\n")
	case "mount-failed":
		s := "✗ Mount failed"
		if m.failedDev != "" {
			s += " (" + filepath.Base(m.failedDev) + ")"
		}
		b.WriteString(errStyle.Render(s) + "\n")
	case "error":
		b.WriteString(errStyle.Render("✗ Error: "+m.err.Error()) + "\n")
	}

	// ── Live progress section (visible during backup, naming and rename) ─
	if m.state == "backing-up" || m.state == "naming" || m.state == "renaming" {
		b.WriteString(m.renderProgressSection())
	}

	// ── Activity viewport ────────────────────────────────────────────────
	b.WriteString("\n")
	b.WriteString(m.vp.View())
	b.WriteString("\n")

	// ── Footer ───────────────────────────────────────────────────────────
	if m.confirmQuit {
		b.WriteString(warnStyle.Render("  Quit? y/n"))
	} else {
		switch m.state {
		case "naming":
			b.WriteString(dimStyle.Render("  Enter start • Esc default"))
		case "renaming":
			b.WriteString(dimStyle.Render("  Enter confirm • Esc cancel"))
		case "mount-failed":
			b.WriteString(dimStyle.Render("  m retry mount • q quit"))
		default:
			var hints []string
			if m.lastDestPath != "" && m.state == "waiting" {
				hints = append(hints, "r rename")
			}
			if m.discInfo != nil && m.backupDone[m.discInfo.Device] {
				hints = append(hints, "e eject")
			}
			hints = append(hints, "↑/↓ scroll", "q quit")
			b.WriteString(dimStyle.Render("  " + strings.Join(hints, " • ")))
		}
	}
	return b.String()
}

func (m *WatchModel) renderProgressSection() string {
	var b strings.Builder

	if m.discInfo != nil {
		info := labelStyle.Render("  Type ") + string(m.discInfo.DiscType) +
			labelStyle.Render("  Label ") + m.discInfo.Label
		if m.discInfo.MountPoint != "" {
			info += labelStyle.Render("  Mount ") + m.discInfo.MountPoint
		} else if m.discInfo.Device != "" {
			info += labelStyle.Render("  Device ") + m.discInfo.Device
		}
		b.WriteString(info + "\n")
	}

	// Progress bar
	if m.curTotal > 0 {
		bar := renderBar(m.curProgress, m.curTotal, 40)
		pct := float64(m.curProgress) / float64(m.curTotal) * 100
		b.WriteString(fmt.Sprintf("  %s %3.0f%% (%d/%d)", bar, pct, m.curProgress, m.curTotal))
		b.WriteString("\n")
	}

	// Current file
	if m.curFile != "" {
		b.WriteString("  " + fileStyle.Render("→ "+m.curFile) + "\n")
	}

	return b.String()
}

func renderBar(current, total, width int) string {
	if total == 0 {
		return strings.Repeat("░", width)
	}
	filled := current * width / total
	if filled < 0 {
		filled = 0
	}
	if filled > width {
		filled = width
	}
	empty := width - filled
	return progressBarFull.Render(strings.Repeat("█", filled)) +
		progressBarEmpty.Render(strings.Repeat("░", empty))
}

func phaseLabel(phase string) string {
	switch phase {
	case "scan":
		return "SCANNING"
	case "copy", "copy-progress":
		return "COPYING"
	case "permissions":
		return "PERMISSIONS"
	case "verify-src", "verify-dst", "verify-file":
		return "VERIFYING"
	case "verify-done":
		return "VERIFIED"
	case "zip-scan", "zip-extract", "zip-file":
		return "EXTRACTING"
	case "zip-done":
		return "EXTRACTED"
	case "rip", "rip-track", "rip-progress":
		return "RIPPING"
	case "rip-done":
		return "COMPLETE"
	case "done":
		return "COMPLETE"
	case "error":
		return "ERROR"
	default:
		return "WORKING"
	}
}

func (m *WatchModel) addActivity(icon, text string, style lipgloss.Style) {
	m.activities = append(m.activities, activity{
		ts:    time.Now().Format("15:04:05"),
		icon:  icon,
		text:  text,
		style: style,
	})
}

func (m *WatchModel) clearProgress() {
	m.curPhase = ""
	m.curFile = ""
	m.curProgress = 0
	m.curTotal = 0
	m.discInfo = nil
	m.curMessage = ""
}

func (m *WatchModel) syncViewport() {
	var b strings.Builder
	for i, a := range m.activities {
		ts := dimStyle.Render(a.ts)
		isLast := i == len(m.activities)-1
		if isLast && (m.state == "backing-up" || m.state == "naming") {
			b.WriteString(fmt.Sprintf(" %s %s %s %s\n", ts, m.spinner.View(), a.icon, a.style.Render(a.text)))
		} else {
			b.WriteString(fmt.Sprintf(" %s %s %s\n", ts, a.icon, a.style.Render(a.text)))
		}
	}
	content := b.String()
	m.vp.SetContent(content)
	m.vp.GotoBottom()
}

// ── Commands ────────────────────────────────────────────────────────────────

func (m WatchModel) pollTickCmd() tea.Cmd {
	return tea.Tick(time.Duration(m.cfg.PollInterval)*time.Second, func(time.Time) tea.Msg {
		return pollTickMsg{}
	})
}

func (m WatchModel) detectDiscCmd() tea.Cmd {
	return func() tea.Msg {
		mp, err := disc.FindOpticalMount()
		if err != nil || mp == "" {
			return nil
		}
		info := disc.GetInfo(mp)
		return discDetectedMsg{info: info}
	}
}

func (m WatchModel) checkExistingCmd() tea.Cmd {
	return func() tea.Msg {
		for _, dev := range disc.ListOpticalDevices() {
			// Audio CDs cannot be mounted — check before the blkid-based HasMedia.
			if disc.IsAudioCD(dev) {
				info := disc.GetAudioInfo(dev)
				return discDetectedMsg{info: info}
			}
			if disc.HasMedia(dev) {
				mp, err := disc.TryMount(dev, m.log)
				if err == nil && mp != "" {
					info := disc.GetInfo(mp)
					return discDetectedMsg{info: info}
				}
			}
		}
		return nil
	}
}

func (m WatchModel) mountAndBackupCmd(dev string) tea.Cmd {
	return func() tea.Msg {
		// Audio CDs cannot be mounted as a filesystem — detect before HasMedia.
		if disc.IsAudioCD(dev) {
			info := disc.GetAudioInfo(dev)
			return discDetectedMsg{info: info}
		}
		if !disc.HasMedia(dev) {
			return discEjectedMsg{dev: dev}
		}
		mp, err := disc.TryMount(dev, m.log)
		if err != nil {
			return mountFailedMsg{dev: dev, err: err}
		}
		info := disc.GetInfo(mp)
		return discDetectedMsg{info: info}
	}
}

func (m *WatchModel) runBackupCmd(info disc.Info) tea.Cmd {
	return m.runBackupCmdWithName(info, info.DestName())
}

func (m *WatchModel) runBackupCmdWithName(info disc.Info, destName string) tea.Cmd {
	eventCh := m.eventCh
	log := m.log
	cfg := m.cfg

	ctx, cancel := context.WithCancel(context.Background())
	m.cancel = cancel

	return func() tea.Msg {
		// Kill any stale rsync for this source before starting our own
		backup.KillStaleRsyncForSource(info.MountPoint, log)
		result := backup.Run(info, cfg.BackupDir, destName, log, eventCh, ctx)
		return backupDoneMsg{result: result}
	}
}

func (m WatchModel) waitForEventCmd() tea.Cmd {
	ch := m.eventCh
	return func() tea.Msg {
		ev, ok := <-ch
		if !ok {
			return nil
		}
		return backupEventMsg{event: ev}
	}
}

func (m WatchModel) renameCmd(oldPath, newName string) tea.Cmd {
	return func() tea.Msg {
		oldName := filepath.Base(oldPath)
		newPath := filepath.Join(filepath.Dir(oldPath), newName)
		err := os.Rename(oldPath, newPath)
		return renameDoneMsg{oldName: oldName, newName: newName, err: err}
	}
}

func (m WatchModel) killStaleCmd() tea.Cmd {
	log := m.log
	return func() tea.Msg {
		count := backup.KillStale(log)
		return staleKilledMsg{count: count}
	}
}

func (m WatchModel) ejectCmd(dev string) tea.Cmd {
	return func() tea.Msg {
		err := disc.Eject(dev)
		return ejectDoneMsg{err: err}
	}
}

func (m WatchModel) killStaleForSourceCmd(src string) tea.Cmd {
	log := m.log
	return func() tea.Msg {
		count := backup.KillStaleRsyncForSource(src, log)
		return staleKilledMsg{count: count}
	}
}

func (m WatchModel) watchUdevCmd() tea.Cmd {
	return func() tea.Msg {
		ch, err := disc.WatchUdev(m.done)
		if err != nil {
			return watchErrorMsg{err: err}
		}
		select {
		case dev, ok := <-ch:
			if !ok {
				return nil
			}
			return udevEventMsg{dev: dev}
		case <-m.done:
			return nil
		}
	}
}
