// AlarmStore.qml — alarm configuration, helpers, and file persistence.
import QtQuick
import Quickshell.Io

QtObject {
    id: store

    // ── Public state ──────────────────────────────────────────────────────────
    property bool   alarmEnabled:    false
    property string alarmTime:       "07:00:00"
    property var    alarmWeekdays:   [true, true, true, true, true, true, true]
    property bool   alarmFiredToday: false
    property int    alarmSeconds:    7 * 3600
    property real   alarmProgress:   alarmSeconds / 86400.0
    property bool   alarmSilent:       false  // no sound when alarm fires
    property string alarmSound:        ""     // custom sfx path; empty = builtin
    property bool   alarmAutoTimeout:  true   // auto-dismiss after timeout
    property real   alarmTimeoutMinutes: 15   // minutes before auto-dismiss (supports 0.25=15s, 0.5=30s)

    // ── Paths (set by AppState) ───────────────────────────────────────────────
    property string alarmsFilePath: ""
    property string storageDir:     ""

    // ── Dirty flags ───────────────────────────────────────────────────────────
    property bool updatingFromDisk: false
    property bool writing:          false

    // ── Signals ──────────────────────────────────────────────────────────────
    signal requestRepaintRing()
    signal alarmDismissed()

    // Tracks whether the alarm popup was dismissed via the JSON flag
    property bool alarmDismissedFlag: false

    // Auto-save on changes
    onAlarmEnabledChanged:  if (!store.updatingFromDisk) store.saveToFile()
    onAlarmTimeChanged:     if (!store.updatingFromDisk) store.saveToFile()
    onAlarmWeekdaysChanged: if (!store.updatingFromDisk) store.saveToFile()
    onAlarmSilentChanged:         if (!store.updatingFromDisk) store.saveToFile()
    onAlarmSoundChanged:          if (!store.updatingFromDisk) store.saveToFile()
    onAlarmAutoTimeoutChanged:    if (!store.updatingFromDisk) store.saveToFile()
    onAlarmTimeoutMinutesChanged: if (!store.updatingFromDisk) store.saveToFile()

    // ── File I/O ──────────────────────────────────────────────────────────────

    function readFromFile() {
        if (!store.alarmsFilePath || store.alarmsFilePath === "") return;
        store.writing = false;
        store.updatingFromDisk = true;
        var text = "";
        if (alarmsFileView.loaded) {
            if (typeof alarmsFileView.text === "function") {
                try { text = alarmsFileView.text(); } catch (e) { console.warn("alarmsFileView.text() failed", e); }
            } else {
                text = alarmsFileView.text;
            }
        }
        if (!alarmsFileView.loaded || !text) {
            store.updatingFromDisk = false;
            return;
        }
        try {
            var parsed = JSON.parse(text);
            if (parsed && typeof parsed === "object") {
                if (parsed.alarmEnabled !== undefined)   store.alarmEnabled  = !!parsed.alarmEnabled;
                if (parsed.alarmTime    !== undefined)   store.alarmTime     = parsed.alarmTime;
                if (parsed.alarmWeekdays instanceof Array && parsed.alarmWeekdays.length === 7)
                    store.alarmWeekdays = parsed.alarmWeekdays.slice(0);
                if (parsed.alarmSilent  !== undefined)   store.alarmSilent   = !!parsed.alarmSilent;
                if (parsed.alarmSound   !== undefined)   store.alarmSound    = parsed.alarmSound || "";
                if (parsed.alarmAutoTimeout !== undefined)     store.alarmAutoTimeout    = !!parsed.alarmAutoTimeout;
                if (parsed.alarmTimeoutMinutes !== undefined)  store.alarmTimeoutMinutes = parseFloat(parsed.alarmTimeoutMinutes) || 15;
                // If dismissed flag arrives from disk while alarm was active, close it
                if (parsed.dismissed && !store.alarmDismissedFlag) {
                    store.alarmDismissedFlag = true;
                    store.alarmDismissed();
                } else if (!parsed.dismissed) {
                    store.alarmDismissedFlag = false;
                }
                store.updateProgress();
                store.updateRecurringState();
                store.requestRepaintRing();
            }
        } catch (e) {
            console.warn("Failed to parse alarms.json", e);
        }
        store.updatingFromDisk = false;
    }

    function saveToFile() {
        if (!store.alarmsFilePath || store.alarmsFilePath === "" || store.updatingFromDisk) return;
        try {
            _ensureDir.exec({ command: ["mkdir", "-p", store.storageDir] });
            var payload = {
                alarmEnabled:        store.alarmEnabled,
                alarmTime:           store.alarmTime,
                alarmWeekdays:       store.alarmWeekdays,
                alarmSilent:         store.alarmSilent,
                alarmSound:          store.alarmSound,
                alarmAutoTimeout:    store.alarmAutoTimeout,
                alarmTimeoutMinutes: store.alarmTimeoutMinutes,
                dismissed:           store.alarmDismissedFlag
            };
            store.writing = true;
            alarmsFileView.setText(JSON.stringify(payload, null, 2));
            try { alarmsFileView.waitForJob(); } catch (e) { console.warn("alarmsFileView waitForJob failed", e); }
        } catch (e) {
            console.warn("Failed to save alarms.json", e);
        }
    }

    // ── Alarm helpers ─────────────────────────────────────────────────────────

    function isRecurringActive() {
        for (var i = 0; i < store.alarmWeekdays.length; ++i)
            if (store.alarmWeekdays[i]) return true;
        return false;
    }

    function isDayToday(nowDate) {
        if (!store.isRecurringActive()) return true;
        return store.alarmWeekdays[nowDate.getDay()];
    }

    function nextDayOffset(nowDate, daySeconds) {
        if (!store.alarmEnabled) return 0;
        if (!store.isRecurringActive()) return 0;
        var nowDay = nowDate.getDay();
        for (var offset = 0; offset < 7; ++offset) {
            var day = (nowDay + offset) % 7;
            if (store.alarmWeekdays[day]) {
                if (offset === 0) {
                    if (daySeconds <= store.alarmSeconds) return 0;
                } else {
                    return offset;
                }
            }
        }
        return 0;
    }

    function weekdaysLabel() {
        if (!store.isRecurringActive()) return "Every day";
        var labels = ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"];
        var selected = [];
        for (var i = 0; i < store.alarmWeekdays.length; ++i)
            if (store.alarmWeekdays[i]) selected.push(labels[i]);
        return selected.length ? selected.join(" ") : "No days";
    }

    function secondsToNext(nowDate, daySeconds) {
        if (!store.alarmEnabled) return -1;
        var nowSeconds = daySeconds;
        var nowDay = nowDate.getDay();
        var recurring = store.isRecurringActive();
        if (!recurring) {
            var delta = store.alarmSeconds - nowSeconds;
            return delta >= 0 ? delta : -1;
        }
        for (var offset = 0; offset < 7; offset++) {
            var day = (nowDay + offset) % 7;
            if (!store.alarmWeekdays[day]) continue;
            if (offset === 0) {
                if (nowSeconds <= store.alarmSeconds) return store.alarmSeconds - nowSeconds;
                continue;
            }
            return (offset * 86400) + store.alarmSeconds - nowSeconds;
        }
        return -1;
    }

    function updateRecurringState(nowDate, daySeconds) {
        if (!store.alarmEnabled) { store.alarmFiredToday = false; store.alarmDismissedFlag = false; return; }
        if (!store.isDayToday(nowDate || new Date())) { store.alarmFiredToday = false; store.alarmDismissedFlag = false; return; }
        var nowSec = daySeconds !== undefined ? daySeconds
                     : ((nowDate || new Date()).getHours() * 3600 + (nowDate || new Date()).getMinutes() * 60 + (nowDate || new Date()).getSeconds());
        if (nowSec < store.alarmSeconds)      { store.alarmFiredToday = false; store.alarmDismissedFlag = false; }
        else if (nowSec > store.alarmSeconds)   store.alarmFiredToday = true;
    }

    function updateProgress() {
        var parts = store.alarmTime.split(":");
        if (parts.length < 2 || parts.length > 3) return;
        var h = parseInt(parts[0], 10);
        var m = parseInt(parts[1], 10);
        var s = parts.length > 2 ? parseInt(parts[2], 10) : 0;
        if (isNaN(h) || isNaN(m) || h < 0 || h > 23 || m < 0 || m > 59) return;
        if (isNaN(s) || s < 0 || s > 59) s = 0;
        store.alarmSeconds  = h * 3600 + m * 60 + s;
        store.alarmProgress = store.alarmSeconds / 86400.0;
    }

    function countdownString(nowDate, daySeconds) {
        if (!store.alarmEnabled) return "";
        var secondsNext = store.secondsToNext(nowDate || new Date(), daySeconds || 0);
        if (secondsNext >= 0) {
            var h = Math.floor(secondsNext / 3600);
            var m = Math.floor((secondsNext % 3600) / 60);
            var s = secondsNext % 60;
            return "Next Alarm In: " + h.toString().padStart(2,'0') + ":"
                 + m.toString().padStart(2,'0') + ":" + s.toString().padStart(2,'0');
        }
        if (store.isRecurringActive()) return "Alarm Not Scheduled";
        var nowSec = daySeconds || 0;
        var delta = store.alarmSeconds - nowSec;
        if (delta < 0)                 return "Alarm Passed";
        if (store.alarmFiredToday)     return "Alarm Fired";
        var h2 = Math.floor(delta / 3600);
        var m2 = Math.floor((delta % 3600) / 60);
        var s2 = delta % 60;
        return "Until Alarm: " + h2.toString().padStart(2,'0') + ":"
             + m2.toString().padStart(2,'0') + ":" + s2.toString().padStart(2,'0');
    }

    function timeReached(nowDate) {
        var nowText = Qt.formatTime(nowDate || new Date(), "hh:mm:ss");
        var alarm   = store.alarmTime;
        if (alarm.length === 5) alarm += ":00";
        return nowText === alarm;
    }

    function pendingTimeFromBoxes(hourBox, minuteBox, secondBox) {
        var hh = hourBox   && hourBox.currentIndex   >= 0 ? hourBox.model[hourBox.currentIndex]     : "00";
        var mm = minuteBox && minuteBox.currentIndex >= 0 ? minuteBox.model[minuteBox.currentIndex] : "00";
        var ss = secondBox && secondBox.currentIndex >= 0 ? secondBox.model[secondBox.currentIndex] : "00";
        return hh + ":" + mm + ":" + ss;
    }

    function dismissAlarm() {
        store.alarmFiredToday    = true;
        store.alarmDismissedFlag = true;
        store.saveToFile();
        store.alarmDismissed();
    }

    // ── Internal objects ──────────────────────────────────────────────────────

    property Process _ensureDir: Process { id: _ensureDir }

    property FileView _fileView: FileView {
        id: alarmsFileView
        path: store.alarmsFilePath !== "" ? ("file://" + store.alarmsFilePath) : ""
        preload: true
        blockLoading: true
        watchChanges: true
        onSaved:      store.writing = false
        onSaveFailed: function(e) { console.warn("alarms.json save failed", e); }
        onLoaded:     store.readFromFile()
        onFileChanged: {
            if (store.writing) {
                store.writing = false;
            } else {
                _reloadTimer.restart();
            }
        }
        onLoadFailed: function(e) { console.log("alarms.json load failed", e); }
    }

    property Timer _reloadTimer: Timer {
        id: _reloadTimer
        interval: 150; repeat: false
        onTriggered: alarmsFileView.reload()
    }
}
