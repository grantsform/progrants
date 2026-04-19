package tui

import (
	"context"
	"fmt"
	"path/filepath"
	"strings"
	"time"

	"dedvd/internal/combine"
	"dedvd/internal/logger"

	"github.com/charmbracelet/bubbles/progress"
	"github.com/charmbracelet/bubbles/spinner"
	"github.com/charmbracelet/bubbles/viewport"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ── Messages ────────────────────────────────────────────────────────────────

type combineProgressMsg struct{ p combine.Progress }
type combineDoneMsg struct{ err error }
type combineScanDoneMsg struct {
	files []string
	err   error
}

// ── Model ────────────────────────────────────────────────────────────────────

type CombineModel struct {
	dir     string
	ext     string
	outFile string
	log     *logger.Logger

	spinner  spinner.Model
	progress progress.Model
	vp       viewport.Model
	ready    bool
	width    int
	height   int

	state      string // "scanning", "running", "done", "error"
	files      []string
	curPhase   string
	curLabel   string
	curPct     float64
	progressCh chan combine.Progress
	err        error

	activities  []activity
	cancel      context.CancelFunc
	confirmQuit bool
}

func NewCombineModel(dir, ext, outFile string, log *logger.Logger) CombineModel {
	s := spinner.New()
	s.Spinner = spinner.Dot
	s.Style = lipgloss.NewStyle().Foreground(lipgloss.Color("12"))

	p := progress.New(
		progress.WithDefaultGradient(),
		progress.WithWidth(50),
	)

	vp := viewport.New(80, 14)
	vp.Style = vpBorderStyle

	return CombineModel{
		dir:        dir,
		ext:        ext,
		outFile:    outFile,
		log:        log,
		spinner:    s,
		progress:   p,
		vp:         vp,
		state:      "scanning",
		activities: []activity{},
	}
}

func (m CombineModel) Init() tea.Cmd {
	return tea.Batch(m.spinner.Tick, m.scanCmd())
}

func (m CombineModel) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
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
		m.syncCombineViewport()

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
		pm, cmd := m.progress.Update(msg)
		m.progress = pm.(progress.Model)
		cmds = append(cmds, cmd)

	case combineScanDoneMsg:
		if msg.err != nil {
			m.state = "error"
			m.err = msg.err
			m.addCombineActivity("✗", "Scan failed: "+msg.err.Error(), errStyle)
			m.syncCombineViewport()
			cmds = append(cmds, flashCmd(&m.vp, m.vp.Width, vpFlashError))
			return m, tea.Batch(cmds...)
		}
		m.files = msg.files
		if len(m.files) == 0 {
			m.state = "error"
			m.err = fmt.Errorf("no .%s files found in %s", m.ext, m.dir)
			m.addCombineActivity("✗", m.err.Error(), errStyle)
			m.syncCombineViewport()
			cmds = append(cmds, flashCmd(&m.vp, m.vp.Width, vpFlashError))
			return m, tea.Batch(cmds...)
		}
		m.addCombineActivity("🔍", fmt.Sprintf("Found %d .%s file(s) — combining in order:", len(m.files), m.ext), labelStyle)
		for _, f := range m.files {
			m.addCombineActivity(" ", filepath.Base(f), fileStyle)
		}
		m.addCombineActivity("→", "Output: "+filepath.Base(m.outFile), labelStyle)
		m.syncCombineViewport()
		m.state = "running"
		m.progressCh = make(chan combine.Progress, 64)
		cmds = append(cmds, m.runCmd())

	case combineProgressMsg:
		p := msg.p
		m.curPhase = p.Phase
		if p.Label != "" {
			m.curLabel = p.Label
		}
		if p.Percent > 0 {
			m.curPct = p.Percent
			cmds = append(cmds, m.progress.SetPercent(p.Percent/100.0))
		}
		if p.LogLine != "" {
			m.addCombineActivity(" ", p.LogLine, dimStyle)
		}
		if p.Error != "" {
			m.addCombineActivity("⚠", p.Error, warnStyle)
		}
		m.syncCombineViewport()
		cmds = append(cmds, m.waitProgressCmd())

	case combineDoneMsg:
		if msg.err != nil {
			m.state = "error"
			m.err = msg.err
			m.addCombineActivity("✗", "FAILED: "+msg.err.Error(), errStyle)
			cmds = append(cmds, flashCmd(&m.vp, m.vp.Width, vpFlashError))
		} else {
			m.state = "done"
			m.addCombineActivity("✓", "Combined → "+filepath.Base(m.outFile), successStyle)
			cmds = append(cmds, flashCmd(&m.vp, m.vp.Width, vpFlashSuccess))
		}
		m.syncCombineViewport()

	case flashResetMsg:
		if m.width > 0 {
			m.vp.Style = vpBorderStyle.Width(m.vp.Width)
		} else {
			m.vp.Style = vpBorderStyle
		}
	}

	return m, tea.Batch(cmds...)
}

func (m CombineModel) View() string {
	if !m.ready {
		return "Initializing..."
	}

	var b strings.Builder

	title := titleStyle.Render("dedvd combine")
	b.WriteString(title + "  " + dimStyle.Render(m.dir) + "\n\n")

	switch m.state {
	case "scanning":
		b.WriteString(m.spinner.View() + " Scanning for ." + m.ext + " files...\n")

	case "running":
		phase := strings.ToUpper(m.curPhase)
		if phase == "" {
			phase = "WORKING"
		}
		b.WriteString(m.spinner.View() + " " + phaseStyle.Render(phase))
		if m.curLabel != "" {
			b.WriteString("  " + m.curLabel)
		}
		b.WriteString("\n")
		if m.curPhase == "encode" && m.curPct > 0 {
			b.WriteString("  " + m.progress.View() + "\n")
		}

	case "done":
		b.WriteString(successStyle.Render("✓ Combine complete → "+filepath.Base(m.outFile)) + "\n")

	case "error":
		b.WriteString(errStyle.Render("✗ "+m.err.Error()) + "\n")
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

func (m *CombineModel) addCombineActivity(icon, text string, style lipgloss.Style) {
	m.activities = append(m.activities, activity{
		ts:    time.Now().Format("15:04:05"),
		icon:  icon,
		text:  text,
		style: style,
	})
}

func (m *CombineModel) syncCombineViewport() {
	var b strings.Builder
	for _, a := range m.activities {
		ts := dimStyle.Render(a.ts)
		b.WriteString(fmt.Sprintf(" %s %s %s\n", ts, a.icon, a.style.Render(a.text)))
	}
	m.vp.SetContent(b.String())
	m.vp.GotoBottom()
}

// ── Commands ─────────────────────────────────────────────────────────────────

func (m CombineModel) scanCmd() tea.Cmd {
	dir, ext := m.dir, m.ext
	return func() tea.Msg {
		files, err := combine.ScanDir(dir, ext)
		return combineScanDoneMsg{files: files, err: err}
	}
}

func (m *CombineModel) runCmd() tea.Cmd {
	files := m.files
	outFile := m.outFile
	log := m.log
	ch := m.progressCh

	ctx, cancel := context.WithCancel(context.Background())
	m.cancel = cancel

	go func() {
		err := combine.Run(files, outFile, log, ch, ctx)
		ch <- combine.Progress{Done: err == nil, Failed: err != nil, Error: func() string {
			if err != nil {
				return err.Error()
			}
			return ""
		}()}
		close(ch)
	}()

	return m.waitProgressCmd()
}

func (m CombineModel) waitProgressCmd() tea.Cmd {
	ch := m.progressCh
	return func() tea.Msg {
		p, ok := <-ch
		if !ok {
			return combineDoneMsg{}
		}
		if p.Done {
			return combineDoneMsg{}
		}
		if p.Failed {
			return combineDoneMsg{err: fmt.Errorf("%s", p.Error)}
		}
		return combineProgressMsg{p: p}
	}
}
