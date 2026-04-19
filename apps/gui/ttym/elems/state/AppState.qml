// AppState.qml — thin coordinator that owns the three stores + clock timer
// and re-exposes all their properties as aliases so the rest of the UI sees
// a single flat QtObject, exactly as before.
import QtQuick
import Qt.labs.platform
import Quickshell.Io
import Quickshell.Wayland

QtObject {
    id: appState

    // ── Storage paths ─────────────────────────────────────────────────────────
    // StandardPaths returns a file:// URL — strip the scheme to get a plain path.
    property string _homeUrl:         StandardPaths.writableLocation(StandardPaths.HomeLocation)
    property string storageDir:       _homeUrl.replace(/^file:\/\//, "") + "/.ttym"
    property string eventsFilePath:   storageDir + "/events.json"
    property string alarmsFilePath:   storageDir + "/alarms.json"
    property string settingsFilePath: storageDir + "/settings.json"
    property string todosFilePath:    storageDir + "/todos.json"
    // ── Input lock (needs to survive settings reload) ──────────────────────
    property bool inputLocked: false

    // ── Signals (re-exposed from sub-objects) ─────────────────────────────────
    signal sigAlarmTriggered()
    signal sigRepaintRing()
    signal sigEventsRefreshed()
    signal sigEventAlertTriggered(var ev)
    signal sigAlarmDismissed()
    signal sigEventAlertDismissed(string eventId)

    // ── Calendar view navigation (calendar-only, not persisted) ──────────────
    property int viewYear:  _clock.year
    property int viewMonth: _clock.month
    property int viewMonthFirstWeekday: new Date(viewYear, viewMonth, 1).getDay()
    property int viewMonthDaysCount:    new Date(viewYear, viewMonth + 1, 0).getDate()

    // ── Time aliases (from ClockTimer) ────────────────────────────────────────
    property var  now:         _clock.now
    property int  year:        _clock.year
    property int  month:       _clock.month
    property int  day:         _clock.day
    property int  daySeconds:  _clock.daySeconds
    property real dayProgress: _clock.dayProgress

    // ── Lock/quit hold aliases (from ClockTimer) ──────────────────────────────
    property bool lockHoldActive:     _clock.lockHoldActive
    property bool lockUnlockCooldown: _clock.lockUnlockCooldown
    property real lockHoldProgress:   _clock.lockHoldProgress
    property bool quitHoldActive:     _clock.quitHoldActive
    property real quitHoldProgress:   _clock.quitHoldProgress

    // ── Alarm aliases (from AlarmStore) ───────────────────────────────────────
    property bool   alarmEnabled:    _alarmStore.alarmEnabled
    property string alarmTime:       _alarmStore.alarmTime
    property var    alarmWeekdays:   _alarmStore.alarmWeekdays
    property bool   alarmFiredToday: _alarmStore.alarmFiredToday
    property int    alarmSeconds:    _alarmStore.alarmSeconds
    property real   alarmProgress:   _alarmStore.alarmProgress
    property bool   alarmSilent:          _alarmStore.alarmSilent
    property string alarmSound:           _alarmStore.alarmSound
    property bool   alarmAutoTimeout:     _alarmStore.alarmAutoTimeout
    property real   alarmTimeoutMinutes:  _alarmStore.alarmTimeoutMinutes

    onAlarmEnabledChanged:        _alarmStore.alarmEnabled         = alarmEnabled
    onAlarmTimeChanged:           _alarmStore.alarmTime            = alarmTime
    onAlarmWeekdaysChanged:       _alarmStore.alarmWeekdays        = alarmWeekdays
    onAlarmSilentChanged:         _alarmStore.alarmSilent          = alarmSilent
    onAlarmSoundChanged:          _alarmStore.alarmSound           = alarmSound
    onAlarmAutoTimeoutChanged:    _alarmStore.alarmAutoTimeout     = alarmAutoTimeout
    onAlarmTimeoutMinutesChanged: _alarmStore.alarmTimeoutMinutes  = alarmTimeoutMinutes

    // ── Settings aliases (from SettingsStore) ─────────────────────────────────
    property bool use24HourClock:      _settingsStore.use24HourClock
    property bool lockByDefault:       _settingsStore.lockByDefault
    property bool alarmSoundsEnabled:  _settingsStore.alarmSoundsEnabled
    property bool eventSoundsEnabled:  _settingsStore.eventSoundsEnabled
    property string customAlarmSound:  _settingsStore.customAlarmSound
    property string customEventSound:  _settingsStore.customEventSound

    // ── Brightness control properties ─────────────────────────────────────────
    property bool brightnessEnabled:   _settingsStore.brightnessEnabled
    property string dimStartTime:      _settingsStore.dimStartTime
    property string dimEndTime:        _settingsStore.dimEndTime
    property string brightenStartTime: _settingsStore.brightenStartTime
    property string brightenEndTime:   _settingsStore.brightenEndTime
    property int minBrightness:        _settingsStore.minBrightness
    property int maxBrightness:        _settingsStore.maxBrightness

    onUse24HourClockChanged:      _settingsStore.use24HourClock      = use24HourClock
    onLockByDefaultChanged:       _settingsStore.lockByDefault       = lockByDefault
    onAlarmSoundsEnabledChanged:  _settingsStore.alarmSoundsEnabled  = alarmSoundsEnabled
    onEventSoundsEnabledChanged:  _settingsStore.eventSoundsEnabled  = eventSoundsEnabled
    onCustomAlarmSoundChanged:    _settingsStore.customAlarmSound    = customAlarmSound
    onCustomEventSoundChanged:    _settingsStore.customEventSound    = customEventSound

    onBrightnessEnabledChanged: {
        _settingsStore.brightnessEnabled = brightnessEnabled;
        if (_brightnessManager && _brightnessManager.setBrightness) {
            if (!brightnessEnabled) {
                _brightnessManager.setBrightness(100);
            } else if (_brightnessManager.updateBrightness) {
                _brightnessManager.updateBrightness();
            }
        }
    }
    onDimStartTimeChanged:        _settingsStore.dimStartTime        = dimStartTime
    onDimEndTimeChanged:          _settingsStore.dimEndTime          = dimEndTime
    onBrightenStartTimeChanged:   _settingsStore.brightenStartTime   = brightenStartTime
    onBrightenEndTimeChanged:     _settingsStore.brightenEndTime     = brightenEndTime
    onMinBrightnessChanged:       _settingsStore.minBrightness       = minBrightness
    onMaxBrightnessChanged:       _settingsStore.maxBrightness       = maxBrightness

    // ── Events aliases (from EventStore) ──────────────────────────────────────
    property var       events:         _eventStore.events
    property int       eventsRevision: _eventStore.eventsRevision
    property ListModel eventModel:          _eventStore.eventModel
    property ListModel allDayModel:         _eventStore.allDayModel
    property ListModel recurringTodayModel: _eventStore.recurringTodayModel
    property ListModel todoModel:      _todoStore.todoModel
    property int       todoRevision:   _todoStore.todoRevision

    onEventsChanged: _eventStore.events = events

    // ── Hold API (delegated to ClockTimer) ────────────────────────────────────

    function startUnlockHold() { _clock.startUnlockHold(); }
    function stopUnlockHold()  { _clock.stopUnlockHold();  }
    function startQuitHold()   { _clock.startQuitHold();   }
    function stopQuitHold()    { _clock.stopQuitHold();    }

    // ── Event CRUD (delegated to EventStore) ──────────────────────────────────

    function addEvent(title, time, allDay, month, year, day, comment, alert, recurring, recurringWeeks, recurringDays, recurringEndDate, alertSilent, alertSound, alertAutoTimeout, alertTimeoutMinutes, endTime) {
        _eventStore.add(title, time, allDay, month, year, day, comment, alert, recurring, recurringWeeks, recurringDays, recurringEndDate, alertSilent, alertSound, alertAutoTimeout, alertTimeoutMinutes, endTime);
    }
    function updateEventByEventId(eventId, title, time, allDay, month, year, day, comment, alert, recurring, recurringWeeks, recurringDays, recurringEndDate, alertSilent, alertSound, alertAutoTimeout, alertTimeoutMinutes, endTime) {
        _eventStore.update(eventId, title, time, allDay, month, year, day, comment, alert, recurring, recurringWeeks, recurringDays, recurringEndDate, alertSilent, alertSound, alertAutoTimeout, alertTimeoutMinutes, endTime);
    }
    function removeEventByEventId(eventId) {
        _eventStore.remove(eventId);
    }
    function hideEventById(eventId) {
        _eventStore.hideEvent(eventId);
    }
    function unhideEventById(eventId) {
        _eventStore.unhideEvent(eventId);
    }
    function toggleAllDayDoneById(eventId) {
        _eventStore.toggleAllDayDone(eventId);
    }
    function toggleTodoDoneById(todoId) {
        var todayStr = Qt.formatDate(_clock.now, "yyyy-MM-dd");
        _todoStore.toggleDone(todoId, todayStr);
    }
    function addTodo(title, comment) {
        _todoStore.add(title, comment);
    }
    function updateTodo(todoId, title, comment) {
        _todoStore.update(todoId, title, comment);
    }
    function removeTodo(todoId) {
        _todoStore.remove(todoId);
    }
    function isTodoDoneOnDate(todoId, dateStr) {
        return _todoStore.isTodoDoneOnDate(todoId, dateStr);
    }
    function toggleTodoDoneForDate(todoId, dateStr) {
        _todoStore.toggleDone(todoId, dateStr);
    }
    function dismissEventAlertById(eventId) {
        _eventStore.dismissEventAlert(eventId);
    }
    function dismissAlarm() {
        _alarmStore.dismissAlarm();
    }
    function refreshEventModel() {
        _eventStore.refresh(_clock.now);
    }
    function nextEvents() {
        return _eventStore.nextUpcoming(_clock.now, 7, true);
    }
    function eventsForDay(year, month, day) {
        return _eventStore.eventsOnDay(year, month, day);
    }
    function getEventTypesForDay(year, month, day) {
        return _eventStore.getEventTypesOnDay(year, month, day);
    }
    function secondsToNextEvent() {
        var upcoming = _eventStore.nextUpcoming(_clock.now, 1, "selective");
        if (!upcoming || upcoming.length === 0) return -1;
        var diff = (upcoming[0]._timeKey || 0) - _clock.now.getTime();
        return diff > 0 ? Math.floor(diff / 1000) : -1;
    }
    // Like secondsToNextEvent but uses endTime when inside an event window
    function secondsToNextEventTarget() {
        var targetMs = _eventStore.nextEventTarget(_clock.now);
        if (targetMs < 0) return -1;
        var diff = targetMs - _clock.now.getTime();
        return diff > 0 ? Math.floor(diff / 1000) : -1;
    }
    function secondsToNextRecurringEvent() {
        var targetMs = _eventStore.nextRecurringEventTarget(_clock.now);
        if (targetMs < 0) return -1;
        var diff = targetMs - _clock.now.getTime();
        return diff > 0 ? Math.floor(diff / 1000) : -1;
    }
    function eventTimeLeftString(ev, nowDate) {
        return _eventStore.timeLeftString(ev, nowDate || _clock.now);
    }
    function hasEventsOnDay(day) {
        return _eventStore.countOnDay(appState.viewYear, appState.viewMonth, day, appState.viewMonthDaysCount) > 0;
    }
    function eventCountOnDay(day) {
        return _eventStore.countOnDay(appState.viewYear, appState.viewMonth, day, appState.viewMonthDaysCount);
    }

    // ── Calendar helpers ──────────────────────────────────────────────────────

    function monthName() {
        return Qt.formatDate(new Date(appState.viewYear, appState.viewMonth, 1), "MMMM");
    }
    function jumpCalendarMonth(delta) {
        var d = new Date(appState.viewYear, appState.viewMonth + delta, 1);
        appState.viewYear  = d.getFullYear();
        appState.viewMonth = d.getMonth();
    }
    function goToCurrentMonth() {
        appState.viewYear  = _clock.year;
        appState.viewMonth = _clock.month;
    }
    function weekdayName(index) {
        return ["Sun","Mon","Tue","Wed","Thu","Fri","Sat"][index % 7];
    }

    // ── Alarm helpers (delegated to AlarmStore) ───────────────────────────────

    function isRecurringAlarmActive()            { return _alarmStore.isRecurringActive(); }
    function isAlarmDayToday()                   { return _alarmStore.isDayToday(_clock.now); }
    function nextAlarmDayOffset()                { return _alarmStore.nextDayOffset(_clock.now, _clock.daySeconds); }
    function alarmWeekdaysLabel()                { return _alarmStore.weekdaysLabel(); }
    function secondsToNextAlarm()                { return _alarmStore.secondsToNext(_clock.now, _clock.daySeconds); }
    function updateRecurringAlarmState()         { _alarmStore.updateRecurringState(_clock.now, _clock.daySeconds); }
    function updateAlarmProgress()               { _alarmStore.updateProgress(); }
    function alarmCountdownString()              { return _alarmStore.countdownString(_clock.now, _clock.daySeconds); }
    function alarmTimeReached()                  { return _alarmStore.timeReached(_clock.now); }
    function updatePendingTime(h, m, s)          { return _alarmStore.pendingTimeFromBoxes(h, m, s); }
    function saveAlarmsToFile()                  { _alarmStore.saveToFile(); }
    function readAlarmsFromFile()                { _alarmStore.readFromFile(); }
    function saveSettingsToFile()                { _settingsStore.saveToFile(); }
    function readSettingsFromFile()              { _settingsStore.readFromFile(); }
    function saveEventsToFile()                  { _eventStore.saveToFile(); }
    function readEventsFromFile()                { _eventStore.readFromFile(); }

    // ── Init ──────────────────────────────────────────────────────────────────

    function init(wlrLayershell) {
        _initSoundManager();
        if (wlrLayershell != null)
            wlrLayershell.keyboardFocus = WlrKeyboardFocus.OnDemand;
        _ensureStorageDirProcess.exec({ command: ["mkdir", "-p", storageDir] });
        console.debug("storageDir " + storageDir + " eventsFilePath " + eventsFilePath);
        _settingsStore.readFromFile();
        _alarmStore.readFromFile();
        _eventStore.readFromFile();
        _eventStore.refresh(_clock.now);
        _todoStore.readFromFile();
    }

    // ── Sub-objects ───────────────────────────────────────────────────────────

    property Process _ensureStorageDirProcess: Process { id: _ensureStorageDirProcess }

    property EventStore _eventStore: EventStore {
        id: _eventStore
        eventsFilePath: appState.eventsFilePath
        storageDir:     appState.storageDir
        onEventsRefreshed:      appState.sigEventsRefreshed()
        onRequestRepaintRing:   appState.sigRepaintRing()
        onEventAlertTriggered:  function(ev) { appState.sigEventAlertTriggered(ev); }
        onEventAlertDismissed:  function(id) { appState.sigEventAlertDismissed(id); }
    }

    property AlarmStore _alarmStore: AlarmStore {
        id: _alarmStore
        alarmsFilePath: appState.alarmsFilePath
        storageDir:     appState.storageDir
        onRequestRepaintRing: appState.sigRepaintRing()
        onAlarmDismissed:     appState.sigAlarmDismissed()
    }

    property SettingsStore _settingsStore: SettingsStore {
        id: _settingsStore
        settingsFilePath: appState.settingsFilePath
        storageDir:       appState.storageDir
        onLoaded: {
            // Apply lock-by-default only at startup (first file load)
            if (_settingsStore.firstLoad && _settingsStore.lockByDefault)
                appState.inputLocked = true;
        }
    }

    property ClockTimer _clock: ClockTimer {
        id: _clock
        eventStore: _eventStore
        alarmStore: _alarmStore
        onSigRepaintRing:    appState.sigRepaintRing()
        onSigAlarmTriggered: appState.sigAlarmTriggered()
        onSigUnlocked:       appState.inputLocked = false
    }

    property QtObject _soundManager: SfxManager {
        settingsStore: _settingsStore
    }
    property bool _soundManagerReady: true

    function _initSoundManager() { /* no-op, instantiated declaratively */ }

    property BrightnessManager _brightnessManager: BrightnessManager {
        id: _brightnessManager
        settingsStore: _settingsStore
    }

    property TodoStore _todoStore: TodoStore {
        id: _todoStore
        todosFilePath: appState.todosFilePath
        storageDir:    appState.storageDir
    }

    // Sound functions
    function playAlarmSound(soundPath) {
        if (_soundManagerReady && _soundManager.playAlarmSound) _soundManager.playAlarmSound(soundPath || "");
    }
    function playEventSound(soundPath) {
        if (_soundManagerReady && _soundManager.playEventSound) _soundManager.playEventSound(soundPath || "");
    }
    function testAlarmSound() {
        if (_soundManagerReady && _soundManager.testAlarmSound) _soundManager.testAlarmSound();
    }
    function testEventSound() {
        if (_soundManagerReady && _soundManager.testEventSound) _soundManager.testEventSound();
    }

    function stopAlarmSound() {
        _soundManager.stopAlarmSound();
    }

    function stopEventSound() {
        _soundManager.stopEventSound();
    }

    // Brightness functions
    function setBrightness(percentage) {
        _brightnessManager.setBrightnessManual(percentage);
    }
    function updateBrightness() {
        _brightnessManager.updateBrightness();
    }
}
