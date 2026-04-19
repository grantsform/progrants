// SettingsStore.qml — user preferences and file persistence.
import QtQuick
import Quickshell.Io

QtObject {
    id: store

    // ── Public state ──────────────────────────────────────────────────────────
    property bool use24HourClock:      true
    property bool lockByDefault:       false
    property bool alarmSoundsEnabled:  true
    property bool eventSoundsEnabled:  true
    property string customAlarmSound:  ""  // override path; empty = use builtin
    property string customEventSound:  ""  // override path; empty = use builtin

    // ── Brightness Control ────────────────────────────────────────────────────
    property bool brightnessEnabled:   true       // Enable automatic brightness control
    property string dimStartTime:      "18:00"    // Start dimming at 6 PM
    property string dimEndTime:        "21:00"    // Finish dimming by 9 PM
    property string brightenStartTime: "05:00"    // Start brightening at 5 AM
    property string brightenEndTime:   "07:00"    // Finish brightening by 7 AM
    property int minBrightness:        20         // Minimum brightness percentage
    property int maxBrightness:        100        // Maximum brightness percentage

    // ── Paths (set by AppState) ───────────────────────────────────────────────
    property string settingsFilePath: ""
    property string storageDir:       ""

    // ── Dirty flags ───────────────────────────────────────────────────────────
    property bool updatingFromDisk: false
    property bool writing:          false
    property bool firstLoad:        true   // cleared after first successful load

    // Signals emitted after settings load (so shell can act)
    signal loaded()

    // Auto-save on changes
    onUse24HourClockChanged:      if (!store.updatingFromDisk) store.saveToFile()
    onLockByDefaultChanged:       if (!store.updatingFromDisk) store.saveToFile()
    onAlarmSoundsEnabledChanged:  if (!store.updatingFromDisk) store.saveToFile()
    onEventSoundsEnabledChanged:  if (!store.updatingFromDisk) store.saveToFile()
    onCustomAlarmSoundChanged:    if (!store.updatingFromDisk) store.saveToFile()
    onCustomEventSoundChanged:    if (!store.updatingFromDisk) store.saveToFile()
    onBrightnessEnabledChanged:   if (!store.updatingFromDisk) store.saveToFile()
    onDimStartTimeChanged:        if (!store.updatingFromDisk) store.saveToFile()
    onDimEndTimeChanged:          if (!store.updatingFromDisk) store.saveToFile()
    onBrightenStartTimeChanged:   if (!store.updatingFromDisk) store.saveToFile()
    onBrightenEndTimeChanged:     if (!store.updatingFromDisk) store.saveToFile()
    onMinBrightnessChanged:       if (!store.updatingFromDisk) store.saveToFile()
    onMaxBrightnessChanged:       if (!store.updatingFromDisk) store.saveToFile()

    // ── File I/O ──────────────────────────────────────────────────────────────

    function readFromFile() {
        if (!store.settingsFilePath || store.settingsFilePath === "") return;
        if (store.writing) return;
        store.updatingFromDisk = true;
        var text = "";
        if (settingsFileView.loaded) {
            if (typeof settingsFileView.text === "function") {
                try { text = settingsFileView.text(); } catch (e) { console.warn("settingsFileView.text() failed", e); }
            } else {
                text = settingsFileView.text;
            }
        }
        if (!settingsFileView.loaded || !text) {
            store.updatingFromDisk = false;
            return;
        }
        try {
            var parsed = JSON.parse(text);
            if (parsed && typeof parsed === "object") {
                if (parsed.use24HourClock      !== undefined) store.use24HourClock      = !!parsed.use24HourClock;
                if (parsed.lockByDefault       !== undefined) store.lockByDefault       = !!parsed.lockByDefault;
                if (parsed.alarmSoundsEnabled  !== undefined) store.alarmSoundsEnabled  = !!parsed.alarmSoundsEnabled;
                if (parsed.eventSoundsEnabled  !== undefined) store.eventSoundsEnabled  = !!parsed.eventSoundsEnabled;
                if (parsed.customAlarmSound    !== undefined) store.customAlarmSound    = parsed.customAlarmSound || "";
                if (parsed.customEventSound    !== undefined) store.customEventSound    = parsed.customEventSound || "";
                console.log("settings loaded", JSON.stringify(parsed));
            }
        } catch (e) {
            console.warn("Failed to parse settings.json", e);
        }
        store.updatingFromDisk = false;
        store.loaded();
        store.firstLoad = false;
    }

    function saveToFile() {
        if (!store.settingsFilePath || store.settingsFilePath === "" || store.updatingFromDisk) return;
        try {
            _ensureDir.exec({ command: ["mkdir", "-p", store.storageDir] });
            var payload = {
                use24HourClock:      store.use24HourClock,
                lockByDefault:       store.lockByDefault,
                alarmSoundsEnabled:  store.alarmSoundsEnabled,
                eventSoundsEnabled:  store.eventSoundsEnabled,
                customAlarmSound:    store.customAlarmSound,
                customEventSound:    store.customEventSound
            };
            store.writing = true;
            settingsFileView.setText(JSON.stringify(payload, null, 2));
            try { settingsFileView.waitForJob(); } catch (e) { console.warn("settingsFileView waitForJob failed", e); }
        } catch (e) {
            console.warn("Failed to save settings.json", e);
        }
    }

    // ── Internal objects ──────────────────────────────────────────────────────

    property Process _ensureDir: Process { id: _ensureDir }

    property FileView _fileView: FileView {
        id: settingsFileView
        path: store.settingsFilePath !== "" ? ("file://" + store.settingsFilePath) : ""
        preload: true
        blockLoading: true
        watchChanges: true
        onSaved:      store.writing = false
        onSaveFailed: function(e) { console.warn("settings.json save failed", e); }
        onLoaded:     store.readFromFile()
        onFileChanged: {
            if (store.writing) {
                store.writing = false;
            } else {
                _reloadTimer.restart();
            }
        }
        onLoadFailed: function(e) { console.warn("settings.json load failed", e); }
    }

    property Timer _reloadTimer: Timer {
        id: _reloadTimer
        interval: 150; repeat: false
        onTriggered: settingsFileView.reload()
    }
}
