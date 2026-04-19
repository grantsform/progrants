package tui

import (
	"context"
	"fmt"
	"strings"
	"time"

	"dedvd/internal/config"
	"dedvd/internal/logger"
	"dedvd/internal/trans"

	"github.com/charmbracelet/bubbles/progress"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ── Messages ────────────────────────────────────────────────────────────────

type transProgressMsg struct{ p trans.Progress }
type transScanDoneMsg struct {
	jobs []trans.DiscJob
	err  error
}
type transJobDoneMsg struct {
	job trans.DiscJob
	err error
}
type transAllDoneMsg struct{}

// ── Trans Model ─────────────────────────────────────────────────────────────

type TransModel struct {
	cfg      config.Config
	log      *logger.Logger
	spinner  spinner.Model
	progress progress.Model
	vp       viewport.Model
	ready    bool
	width    int
	height   int

	// State
	state   string // "scanning", "transcoding", "done", "error"
	jobs    []trans.DiscJob
	current int
	total   int

	// Current job progress
	curProgress trans.Progress
	progressCh  chan trans.Progress
	completed   []transResult
	err         error

	// Activity log for viewport
	activities []activity

	// Process cancellation
	cancel context.CancelFunc

	// Quit confirmation
	confirmQuit bool
}

type transResult struct {
	name   string
	ok     bool
	detail string
}

func NewTransModel(cfg config.Config, log *logger.Logger) TransModel {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("12"))

	p := progress.New(
		progress.WithDefaultGradient(),
		progress.WithWidth(50),
	)

	vp := viewport.New(80, 14)
	vp.Style = vpBorderStyle

	return TransModel{
		cfg:        cfg,
		log:        log,
		spinner:    s,
		progress:   p,
		vp:         vp,
		state:      "scanning",
		activities: []activity{},
	}
}

func (m TransModel) Init() tea.Cmd {
	return tea.Batch(m.spinner.Tick, m.scanCmd())
}

func (m TransModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
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
		m.syncTransViewport()

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
			m.confirmQuit = true
			return m, nil
		}
		var cmd tea.Cmd
		m.vp, cmd = m.vp.Update(msg)
		cmds = append(cmds, cmd)

	case spinner.TickMsg:
		var cmd tea.Cmd
		m.spinner, cmd = m.spinner.Update(msg)
		cmds = append(cmds, cmd)

	case progress.FrameMsg:
		progressModel, cmd := m.progress.Update(msg)
		m.progress = progressModel.(progress.Model)
		cmds = append(cmds, cmd)

	case transScanDoneMsg:
		if msg.err != nil {
			m.state = "error"
			m.err = msg.err
			m.addActivity("✗", "Scan failed: "+msg.err.Error(), errStyle)
			m.syncTransViewport()
			cmds = append(cmds, flashCmd(&m.vp, m.vp.Width, vpFlashError))
			return m, tea.Batch(cmds...)
		}
		m.jobs = msg.jobs
		m.total = len(msg.jobs)
		if m.total == 0 {
			m.state = "done"
			m.addActivity("—", "No untranscoded discs found.", dimStyle)
			m.syncTransViewport()
			return m, nil
		}
		m.state = "transcoding"
		m.current = 0
		m.addActivity("🔍", fmt.Sprintf("Found %d disc(s) to transcode", m.total), labelStyle)
		for _, j := range m.jobs {
			m.addActivity(" ", fmt.Sprintf("%s → %s", j.Name, j.OutFile), fileStyle)
		}
		m.syncTransViewport()
		m.progressCh = make(chan trans.Progress, 64)
		cmds = append(cmds, m.encodeCmd(m.progressCh))

	case transProgressMsg:
		m.curProgress = msg.p
		if msg.p.Percent > 0 {
			cmds = append(cmds, m.progress.SetPercent(msg.p.Percent/100.0))
		}
		if msg.p.Error != "" {
			m.addActivity("⚠", msg.p.Error, warnStyle)
		}
		// Add raw output lines to the viewport
		if msg.p.LogLine != "" {
			m.addActivity(" ", msg.p.LogLine, dimStyle)
		}
		m.syncTransViewport()
		// Continue listening for more progress
		if m.progressCh != nil && m.current < m.total {
			cmds = append(cmds, waitForProgress(m.progressCh, m.jobs[m.current]))
		}

	case transJobDoneMsg:
		result := transResult{name: msg.job.Name}
		if msg.err != nil {
			result.ok = false
			result.detail = msg.err.Error()
			m.addActivity("✗", fmt.Sprintf("FAILED: %s — %s", msg.job.Name, msg.err.Error()), errStyle)
			cmds = append(cmds, flashCmd(&m.vp, m.vp.Width, vpFlashError))
		} else {
			result.ok = true
			result.detail = "transcoded"
			m.addActivity("✓", fmt.Sprintf("Done: %s", msg.job.Name), successStyle)
			cmds = append(cmds, flashCmd(&m.vp, m.vp.Width, vpFlashSuccess))
		}
		m.completed = append(m.completed, result)
		m.current++
		m.syncTransViewport()
		if m.current < m.total {
			m.progressCh = make(chan trans.Progress, 64)
			cmds = append(cmds, m.encodeCmd(m.progressCh))
		} else {
			m.state = "done"
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

func (m TransModel) View() string {
	if !m.ready {
		return "Initializing..."
	}

	var b strings.Builder

	// ── Title bar ────────────────────────────────────────────────────────
	title := titleStyle.Render("dedvd trans")
	b.WriteString(title + "\n\n")

	switch m.state {
	case "scanning":
		b.WriteString(m.spinner.View() + " Scanning for VIDEO backups...\n")

	case "transcoding":
		b.WriteString(fmt.Sprintf("  Transcoding disc %d of %d\n\n",
			m.current+1, m.total))

		// Current job info
		p := m.curProgress
		if p.Label != "" {
			info := fmt.Sprintf("  %s", p.Label)
			if p.Pass > 0 {
				info += fmt.Sprintf("  pass %d/%d", p.Pass, p.Passes)
			}
			if p.FPS > 0 {
				info += fmt.Sprintf("  %d fps", p.FPS)
			}
			if p.ETA != "" {
				info += fmt.Sprintf("  ETA %s", p.ETA)
			}
			b.WriteString(labelStyle.Render(info) + "\n")
			b.WriteString("  " + m.progress.View() + "\n")
		} else {
			b.WriteString(m.spinner.View() + " Starting encode...\n")
		}

	case "done":
		ok := 0
		fail := 0
		for _, r := range m.completed {
			if r.ok {
				ok++
			} else {
				fail++
			}
		}
		b.WriteString(successStyle.Render(fmt.Sprintf(
			"Transcode complete — %d succeeded, %d failed out of %d disc(s).",
			ok, fail, m.total)) + "\n")
		if m.total == 0 {
			b.WriteString(dimStyle.Render("  No untranscoded discs found.") + "\n")
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

func (m *TransModel) syncTransViewport() {
	var b strings.Builder
	for _, a := range m.activities {
		ts := dimStyle.Render(a.ts)
		b.WriteString(fmt.Sprintf(" %s %s %s\n", ts, a.icon, a.style.Render(a.text)))
	}
	m.vp.SetContent(b.String())
	m.vp.GotoBottom()
}

func (m *TransModel) addActivity(icon, text string, style lipgloss.Style) {
	m.activities = append(m.activities, activity{
		ts:    time.Now().Format("15:04:05"),
		icon:  icon,
		text:  text,
		style: style,
	})
}

// ── Commands ────────────────────────────────────────────────────────────────

func (m TransModel) scanCmd() tea.Cmd {
	return func() tea.Msg {
		jobs, err := trans.ScanDiscs(m.cfg.VideoDir())
		return transScanDoneMsg{jobs: jobs, err: err}
	}
}

func (m *TransModel) encodeCmd(ch chan trans.Progress) tea.Cmd {
	job := m.jobs[m.current]
	log := m.log

	ctx, cancel := context.WithCancel(context.Background())
	m.cancel = cancel

	// Start encode in background goroutine
	go func() {
		err := trans.Encode(job, log, ch, ctx)
		if err != nil {
			ch <- trans.Progress{Label: job.Name, Failed: true, Error: err.Error()}
		}
		close(ch)
	}()

	// Return a Cmd that waits for the first progress update
	return waitForProgress(ch, job)
}

// waitForProgress returns a Cmd that blocks until a progress message arrives.
func waitForProgress(ch <-chan trans.Progress, job trans.DiscJob) tea.Cmd {
	return func() tea.Msg {
		p, ok := <-ch
		if !ok {
			// Channel closed — job done
			return transJobDoneMsg{job: job, err: nil}
		}
		if p.Done {
			return transJobDoneMsg{job: job, err: nil}
		}
		if p.Failed {
			return transJobDoneMsg{job: job, err: fmt.Errorf("%s", p.Error)}
		}
		return transProgressMsg{p: p}
	}
}
