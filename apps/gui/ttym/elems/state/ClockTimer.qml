// ClockTimer.qml — 1-second clock tick, auto-reload, hold/quit timers.
// Receives store references via required properties; emits signals for ring
// repaints and alarm triggers.
import QtQuick

QtObject {
    id: clock

    // ── Store references (set by AppState) ────────────────────────────────────
    required property QtObject eventStore
    required property QtObject alarmStore

    // ── Live time (mirrored out for binding) ──────────────────────────────────
    property var  now:          new Date()
    property int  year:         now.getFullYear()
    property int  month:        now.getMonth()
    property int  day:          now.getDate()
    property int  daySeconds:   now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()
    property real dayProgress:  daySeconds / 86400.0

    // ── Lock hold state ───────────────────────────────────────────────────────
    property bool lockHoldActive:     false
    property bool lockUnlockCooldown: false
    property real lockHoldProgress:   0.0

    // ── Quit hold state ───────────────────────────────────────────────────────
    property bool quitHoldActive:   false
    property real quitHoldProgress: 0.0

    // ── Signals ───────────────────────────────────────────────────────────────
    signal sigRepaintRing()
    signal sigAlarmTriggered()
    signal sigUnlocked()

    // ── Public hold API ───────────────────────────────────────────────────────

    function startUnlockHold() {
        clock.lockHoldActive   = true;
        clock.lockHoldProgress = 0.0;
        _unlockHoldTimer.start();
    }
    function stopUnlockHold() {
        clock.lockHoldActive   = false;
        clock.lockHoldProgress = 0.0;
        _unlockHoldTimer.stop();
    }
    function startQuitHold() {
        clock.quitHoldActive   = true;
        clock.quitHoldProgress = 0.0;
        _quitHoldTimer.start();
    }
    function stopQuitHold() {
        clock.quitHoldActive   = false;
        clock.quitHoldProgress = 0.0;
        _quitHoldTimer.stop();
    }

    // ── Timers ────────────────────────────────────────────────────────────────

    property Timer _clockTimer: Timer {
        id: _clockTimer
        running:  true
        repeat:   true
        interval: 1000
        onTriggered: {
            clock.now         = new Date();
            clock.year        = clock.now.getFullYear();
            clock.month       = clock.now.getMonth();
            clock.day         = clock.now.getDate();
            clock.daySeconds  = clock.now.getHours() * 3600 + clock.now.getMinutes() * 60 + clock.now.getSeconds();
            clock.dayProgress = clock.daySeconds / 86400.0;

            alarmStore.updateProgress();
            clock.sigRepaintRing();
            eventStore.refresh(clock.now);
            eventStore.checkEventAlerts(clock.now);
            alarmStore.updateRecurringState(clock.now, clock.daySeconds);

            if (alarmStore.alarmEnabled && !alarmStore.alarmFiredToday
                    && alarmStore.timeReached(clock.now)) {
                alarmStore.alarmFiredToday = true;
                clock.sigAlarmTriggered();
            }
            if (!alarmStore.alarmEnabled) alarmStore.alarmFiredToday = false;
            if (Qt.formatTime(clock.now, "hh:mm:ss") === "00:00:00") {
                alarmStore.alarmFiredToday    = false;
                alarmStore.alarmDismissedFlag = false;
                alarmStore.saveToFile();
            }
        }
    }


    property Timer _unlockHoldTimer: Timer {
        id: _unlockHoldTimer
        interval: 30
        repeat:   true
        onTriggered: {
            if (!clock.lockHoldActive) return;
            clock.lockHoldProgress += 0.03;
            if (clock.lockHoldProgress >= 1.0) {
                clock.lockHoldProgress = 0.0;
                clock.lockHoldActive   = false;
                _unlockHoldTimer.stop();
                clock.lockUnlockCooldown = true;
                _cooldownTimer.restart();
                clock.sigUnlocked();
            }
        }
    }

    property Timer _cooldownTimer: Timer {
        id: _cooldownTimer
        interval: 1000
        repeat:   false
        onTriggered: clock.lockUnlockCooldown = false
    }

    property Timer _quitHoldTimer: Timer {
        id: _quitHoldTimer
        interval: 100
        repeat:   true
        onTriggered: {
            if (!clock.quitHoldActive) return;
            clock.quitHoldProgress += 0.1;
            if (clock.quitHoldProgress >= 1.0) {
                clock.quitHoldProgress = 1.0;
                _quitHoldTimer.stop();
                Qt.quit();
            }
        }
    }
}
