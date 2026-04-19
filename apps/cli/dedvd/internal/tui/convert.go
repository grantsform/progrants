package tui

import (
	"context"
	"fmt"
	"strings"
	"time"

	"dedvd/internal/convert"
	"dedvd/internal/logger"

	"github.com/charmbracelet/bubbles/progress"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ── Messages ────────────────────────────────────────────────────────────────

type convertProgressMsg struct{ p convert.Progress }
type convertScanDoneMsg struct {
	jobs []convert.Job
	err  error
}
type convertJobDoneMsg struct {
	job convert.Job
	err error
}

// ── Convert Model ───────────────────────────────────────────────────────────

type ConvertModel struct {
	dir      string
	log      *logger.Logger
	spinner  spinner.Model
	progress progress.Model
	vp       viewport.Model
	ready    bool
	width    int
	height   int

	// State
	state   string // "scanning", "converting", "done", "error"
	jobs    []convert.Job
	current int
	total   int

	// Current job progress
	curProgress convert.Progress
	progressCh  chan convert.Progress
	completed   []convertResult
	err         error

	// Activity log for viewport
	activities []activity

	// Process cancellation
	cancel context.CancelFunc

	// Quit confirmation
	confirmQuit bool
}

type convertResult struct {
	name   string
	ok     bool
	detail string
}

func NewConvertModel(dir string, log *logger.Logger) ConvertModel {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("12"))

	p := progress.New(
		progress.WithDefaultGradient(),
		progress.WithWidth(50),
	)

	vp := viewport.New(80, 14)
	vp.Style = vpBorderStyle

	return ConvertModel{
		dir:        dir,
		log:        log,
		spinner:    s,
		progress:   p,
		vp:         vp,
		state:      "scanning",
		activities: []activity{},
	}
}

func (m ConvertModel) Init() tea.Cmd {
	return tea.Batch(m.spinner.Tick, m.scanCmd())
}

func (m ConvertModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
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
		m.syncConvertViewport()

	case tea.KeyMsg:
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
			if m.state == "done" || m.state == "error" {
				return m, tea.Quit
			}
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

	case convertScanDoneMsg:
		if msg.err != nil {
			m.state = "error"
			m.err = msg.err
			m.addConvertActivity("✗", "Scan failed: "+msg.err.Error(), errStyle)
			m.syncConvertViewport()
			cmds = append(cmds, flashCmd(&m.vp, m.vp.Width, vpFlashError))
			return m, tea.Batch(cmds...)
		}
		m.jobs = msg.jobs
		m.total = len(msg.jobs)
		if m.total == 0 {
			m.state = "done"
			m.addConvertActivity("—", "No video files to convert.", dimStyle)
			m.syncConvertViewport()
			return m, nil
		}
		m.state = "converting"
		m.current = 0
		m.addConvertActivity("🔍", fmt.Sprintf("Found %d video file(s) to convert", m.total), labelStyle)
		for _, j := range m.jobs {
			m.addConvertActivity(" ", j.Name, fileStyle)
		}
		m.syncConvertViewport()
		m.progressCh = make(chan convert.Progress, 64)
		cmds = append(cmds, m.encodeConvertCmd(m.progressCh))

	case convertProgressMsg:
		m.curProgress = msg.p
		if msg.p.Percent > 0 {
			cmds = append(cmds, m.progress.SetPercent(msg.p.Percent/100.0))
		}
		if msg.p.Error != "" {
			m.addConvertActivity("⚠", msg.p.Error, warnStyle)
		}
		if msg.p.LogLine != "" {
			m.addConvertActivity(" ", msg.p.LogLine, dimStyle)
		}
		m.syncConvertViewport()
		if m.progressCh != nil && m.current < m.total {
			cmds = append(cmds, waitForConvertProgress(m.progressCh, m.jobs[m.current]))
		}

	case convertJobDoneMsg:
		result := convertResult{name: msg.job.Name}
		if msg.err != nil {
			result.ok = false
			result.detail = msg.err.Error()
			m.addConvertActivity("✗", fmt.Sprintf("FAILED: %s — %s", msg.job.Name, msg.err.Error()), errStyle)
			cmds = append(cmds, flashCmd(&m.vp, m.vp.Width, vpFlashError))
		} else {
			result.ok = true
			result.detail = "converted"
			m.addConvertActivity("✓", fmt.Sprintf("Done: %s → .mkv", msg.job.Name), successStyle)
			cmds = append(cmds, flashCmd(&m.vp, m.vp.Width, vpFlashSuccess))
		}
		m.completed = append(m.completed, result)
		m.current++
		m.syncConvertViewport()
		if m.current < m.total {
			m.progressCh = make(chan convert.Progress, 64)
			cmds = append(cmds, m.encodeConvertCmd(m.progressCh))
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

func (m ConvertModel) View() string {
	if !m.ready {
		return "Initializing..."
	}

	var b strings.Builder

	title := titleStyle.Render("dedvd convert")
	b.WriteString(title + "  " + dimStyle.Render("→ "+m.dir) + "\n\n")

	switch m.state {
	case "scanning":
		b.WriteString(m.spinner.View() + " Scanning for video files...\n")

	case "converting":
		b.WriteString(fmt.Sprintf("  Converting file %d of %d\n\n", m.current+1, m.total))

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
		ok, fail := 0, 0
		for _, r := range m.completed {
			if r.ok {
				ok++
			} else {
				fail++
			}
		}
		b.WriteString(successStyle.Render(fmt.Sprintf(
			"Convert complete — %d succeeded, %d failed out of %d file(s).",
			ok, fail, m.total)) + "\n")
		if m.total == 0 {
			b.WriteString(dimStyle.Render("  No video files found to convert.") + "\n")
		}

	case "error":
		b.WriteString(errStyle.Render("Error: "+m.err.Error()) + "\n")
	}

	b.WriteString("\n")
	b.WriteString(m.vp.View())
	b.WriteString("\n")

	if m.confirmQuit {
		b.WriteString(warnStyle.Render("  Quit? y/n"))
	} else {
		b.WriteString(dimStyle.Render("  ↑/↓ scroll • q quit"))
	}
	return b.String()
}

func (m *ConvertModel) syncConvertViewport() {
	var b strings.Builder
	for _, a := range m.activities {
		ts := dimStyle.Render(a.ts)
		b.WriteString(fmt.Sprintf(" %s %s %s\n", ts, a.icon, a.style.Render(a.text)))
	}
	m.vp.SetContent(b.String())
	m.vp.GotoBottom()
}

func (m *ConvertModel) addConvertActivity(icon, text string, style lipgloss.Style) {
	m.activities = append(m.activities, activity{
		ts:    time.Now().Format("15:04:05"),
		icon:  icon,
		text:  text,
		style: style,
	})
}

// ── Commands ────────────────────────────────────────────────────────────────

func (m ConvertModel) scanCmd() tea.Cmd {
	dir := m.dir
	return func() tea.Msg {
		jobs, err := convert.ScanDir(dir)
		return convertScanDoneMsg{jobs: jobs, err: err}
	}
}

func (m *ConvertModel) encodeConvertCmd(ch chan convert.Progress) tea.Cmd {
	job := m.jobs[m.current]
	log := m.log
	dir := m.dir

	ctx, cancel := context.WithCancel(context.Background())
	m.cancel = cancel

	go func() {
		err := convert.Encode(job, dir, log, ch, ctx)
		if err != nil {
			ch <- convert.Progress{Label: job.Name, Failed: true, Error: err.Error()}
		}
		close(ch)
	}()

	return waitForConvertProgress(ch, job)
}

func waitForConvertProgress(ch <-chan convert.Progress, job convert.Job) tea.Cmd {
	return func() tea.Msg {
		p, ok := <-ch
		if !ok {
			return convertJobDoneMsg{job: job, err: nil}
		}
		if p.Done {
			return convertJobDoneMsg{job: job, err: nil}
		}
		if p.Failed {
			return convertJobDoneMsg{job: job, err: fmt.Errorf("%s", p.Error)}
		}
		return convertProgressMsg{p: p}
	}
}
