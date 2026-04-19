package tui

import (
	"context"
	"fmt"
	"strings"
	"time"

	"dedvd/internal/config"
	"dedvd/internal/logger"
	"dedvd/internal/upload"

	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/textinput"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ── Messages ────────────────────────────────────────────────────────────────

type uploadEventMsg struct{ event upload.Event }
type uploadDoneMsg struct{ summary upload.Summary }

// ── Upload Model ────────────────────────────────────────────────────────────

type UploadModel struct {
	cfg     config.Config
	log     *logger.Logger
	spinner spinner.Model
	vp      viewport.Model
	input   textinput.Model
	ready   bool
	width   int
	height  int

	target  upload.Target
	eventCh chan upload.Event

	state      string // "password", "uploading", "done", "error"
	activities []activity
	curName    string
	curPct     int
	curIdx     int
	curTotal   int
	summary    *upload.Summary
	err        error

	// Quit confirmation
	confirmQuit bool

	// Process cancellation
	cancel context.CancelFunc
}

func NewUploadModel(cfg config.Config, log *logger.Logger, target upload.Target) UploadModel {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("12"))

	vp := viewport.New(80, 14)
	vp.Style = vpBorderStyle

	ti := textinput.New()
	ti.Placeholder = "SSH password"
	ti.EchoMode = textinput.EchoPassword
	ti.EchoCharacter = '•'
	ti.Width = 40
	ti.Focus()

	// If password already set (e.g. SSH key auth — skip prompt)
	initialState := "password"
	if target.Password != "" {
		initialState = "uploading"
	}

	return UploadModel{
		cfg:        cfg,
		log:        log,
		spinner:    s,
		vp:         vp,
		input:      ti,
		target:     target,
		eventCh:    make(chan upload.Event, 64),
		state:      initialState,
		activities: []activity{},
	}
}

func (m UploadModel) Init() tea.Cmd {
	cmds := []tea.Cmd{m.spinner.Tick, m.input.Focus()}
	if m.state == "uploading" {
		cmds = append(cmds, m.runUploadCmd(), m.waitForEventCmd())
	}
	return tea.Batch(cmds...)
}

func (m UploadModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	var cmds []tea.Cmd

	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
		headerHeight := 8
		footerHeight := 3
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
		m.syncUploadViewport()

	case tea.KeyMsg:
		// Handle quit confirmation first
		if m.confirmQuit {
			switch msg.String() {
			case "y", "Y":
				if m.cancel != nil {
					m.cancel()
				}
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
			return m, tea.Quit
		case "q":
			if m.state != "password" {
				m.confirmQuit = true
				return m, nil
			}
		case "enter":
			if m.state == "password" {
				m.target.Password = m.input.Value()
				m.state = "uploading"
				m.addActivity("🔑", fmt.Sprintf("Connecting to %s@%s ...", m.target.User, m.target.Host), labelStyle)
				m.syncUploadViewport()
				cmds = append(cmds, m.runUploadCmd(), m.waitForEventCmd())
				return m, tea.Batch(cmds...)
			}
			if m.state == "done" {
				return m, tea.Quit
			}
		case "esc":
			if m.state == "password" {
				return m, tea.Quit
			}
		}

		if m.state == "password" {
			var cmd tea.Cmd
			m.input, cmd = m.input.Update(msg)
			cmds = append(cmds, cmd)
		} else {
			var cmd tea.Cmd
			m.vp, cmd = m.vp.Update(msg)
			cmds = append(cmds, cmd)
		}

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		cmds = append(cmds, cmd)

	case uploadEventMsg:
		m.handleUploadEvent(msg.event)
		m.syncUploadViewport()
		if m.state == "uploading" {
			cmds = append(cmds, m.waitForEventCmd())
		}

	case uploadDoneMsg:
		m.state = "done"
		m.summary = &msg.summary
		if msg.summary.Failed > 0 {
			cmds = append(cmds, flashCmd(&m.vp, m.vp.Width, vpFlashError))
		} else {
			cmds = append(cmds, flashCmd(&m.vp, m.vp.Width, vpFlashSuccess))
		}
		m.syncUploadViewport()

	case flashResetMsg:
		if m.width > 0 {
			m.vp.Style = vpBorderStyle.Width(m.vp.Width)
		} else {
			m.vp.Style = vpBorderStyle
		}
	}

	return m, tea.Batch(cmds...)
}

func (m *UploadModel) handleUploadEvent(ev upload.Event) {
	m.curIdx = ev.Current
	m.curTotal = ev.Total

	switch ev.Phase {
	case "scan":
		m.addActivity("🔍", ev.Message, labelStyle)
	case "item-start":
		m.curName = ev.Name
		m.curPct = 0
		m.addActivity("📤", ev.Message, statusStyle)
	case "item-progress":
		m.curPct = ev.Percent
		if ev.File != "" {
			m.curName = ev.File
		}
	case "item-done":
		m.addActivity("✓", ev.Message, successStyle)
	case "item-skip":
		m.addActivity("—", ev.Message, warnStyle)
	case "item-fail":
		m.addActivity("✗", ev.Message, errStyle)
	case "done":
		m.addActivity("✓", ev.Message, successStyle)
	}
}

func (m UploadModel) View() string {
	if !m.ready && m.state != "password" {
		return "Initializing..."
	}

	var b strings.Builder

	// ── Title bar ────────────────────────────────────────────────────────
	title := titleStyle.Render("dedvd upload")
	dest := dimStyle.Render("→ " + m.target.String())
	b.WriteString(title + "  " + dest + "\n\n")

	switch m.state {
	case "password":
		b.WriteString(fmt.Sprintf("  SSH password for %s@%s\n\n", m.target.User, m.target.Host))
		b.WriteString("  " + m.input.View() + "\n\n")
		b.WriteString(dimStyle.Render("  Enter to connect • Esc to cancel"))
		return b.String()

	case "uploading":
		b.WriteString(m.spinner.View() + " " + phaseStyle.Render("UPLOADING"))
		if m.curName != "" {
			b.WriteString("  " + m.curName)
		}
		b.WriteString("\n")
		bar := renderBar(m.curPct, 100, 40)
		b.WriteString(fmt.Sprintf("  %s %3d%%\n", bar, m.curPct))

	case "done":
		if m.summary != nil {
			b.WriteString(successStyle.Render(fmt.Sprintf(
				"Upload complete — %d uploaded, %d failed, %d skipped.",
				m.summary.Uploaded, m.summary.Failed, m.summary.Skipped)) + "\n")
		}

	case "error":
		b.WriteString(errStyle.Render("Error: "+m.err.Error()) + "\n")
	}

	// ── Activity viewport ────────────────────────────────────────────────
	b.WriteString("\n")
	b.WriteString(m.vp.View())
	b.WriteString("\n")

	// ── Footer ───────────────────────────────────────────────────────────
	if m.confirmQuit {
		b.WriteString(warnStyle.Render("  Quit? y/n"))
	} else {
		b.WriteString(dimStyle.Render("  ↑/↓ scroll • q quit"))
	}
	return b.String()
}

func (m *UploadModel) addActivity(icon, text string, style lipgloss.Style) {
	m.activities = append(m.activities, activity{
		ts:    time.Now().Format("15:04:05"),
		icon:  icon,
		text:  text,
		style: style,
	})
}

func (m *UploadModel) syncUploadViewport() {
	var b strings.Builder
	for _, a := range m.activities {
		ts := dimStyle.Render(a.ts)
		b.WriteString(fmt.Sprintf(" %s %s %s\n", ts, a.icon, a.style.Render(a.text)))
	}
	m.vp.SetContent(b.String())
	m.vp.GotoBottom()
}

// ── Commands ────────────────────────────────────────────────────────────────

func (m *UploadModel) runUploadCmd() tea.Cmd {
	cfg := m.cfg
	log := m.log
	target := m.target
	eventCh := m.eventCh

	ctx, cancel := context.WithCancel(context.Background())
	m.cancel = cancel

	return func() tea.Msg {
		summary := upload.Run(cfg.BackupDir, target, log, eventCh, ctx)
		return uploadDoneMsg{summary: summary}
	}
}

func (m UploadModel) waitForEventCmd() tea.Cmd {
	ch := m.eventCh
	return func() tea.Msg {
		ev, ok := <-ch
		if !ok {
			return nil
		}
		return uploadEventMsg{event: ev}
	}
}
